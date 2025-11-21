// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// A pipeline stage for updating PC
//

import BasicTypes::*;
import PipelineTypes::*;
import MemoryMapTypes::*;
import CacheSystemTypes::*;
import FetchUnitTypes::*;

//`define RSD_STOP_FETCH_ON_PRED_MISS

// Detect the cache line boundary in sequential access
function automatic logic StepOverCacheLine (PC_Path pc1, PC_Path pc2);
    return pc1[ICACHE_LINE_BYTE_NUM_BIT_WIDTH] != pc2[ICACHE_LINE_BYTE_NUM_BIT_WIDTH];
endfunction

module NextPCStage(
    NextPCStageIF.ThisStage port,
    FetchStageIF.NextPCStage next,
    RecoveryManagerIF.NextPCStage recovery,
    ControllerIF.NextPCStage ctrl,
    DebugIF.NextPCStage debug
);

`ifdef RSD_STOP_FETCH_ON_PRED_MISS
    typedef enum logic {
        PHASE_FETCH,
        PHASE_WAIT
    } Phase;

    parameter PHASE_DELAY = 2;
    Phase phase[PHASE_DELAY];
    Phase nextPhase;

    // SMT Note: This logic assumes global stall behavior for mispredicts.
    // Ideally duplicated per thread, but kept simple here for compatibility.
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < PHASE_DELAY; i++) begin
                phase[i] <= PHASE_FETCH;
            end
        end
        // Check if ANY thread is recovering or committing
        else if ((| recovery.toRecoveryPhase) || (| recovery.toCommitPhase)) begin
            for (int i = 0; i < PHASE_DELAY; i++) begin
                phase[i] <= PHASE_FETCH;
            end
        end
        else begin
            for (int i = 0; i < PHASE_DELAY - 1; i++) begin
                phase[i+1] <= phase[i];
            end
            phase[0] <= nextPhase;
        end
    end

    always_comb begin
        // Check if ANY thread is recovering
        if ((| recovery.toRecoveryPhase)) begin
            nextPhase = PHASE_FETCH;
        end
        else begin
            nextPhase = phase[0];
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                if (port.brResult[i].valid && port.brResult[i].mispred) begin
                    nextPhase = PHASE_WAIT;
                end
            end
        end
    end
`endif

    // Debug SID
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpSerial curSID, nextSID;
    FlipFlop#( .FF_WIDTH(OP_SERIAL_WIDTH), .RESET_VALUE(1) )
        sidFF(
            .out( curSID ),
            .in ( nextSID ),
            .clk( port.clk ),
            .rst( port.rst )
        );
`endif

    //
    // --- SMT Arbitration (Round Robin)
    //
    ThreadID currentThread;
    logic [THREAD_NUM_BIT_WIDTH-1:0] threadCounter;

    // Pipeline Control
    logic stall, clear;
    logic regStall, beginStall;
    logic writePC_FromOuter;

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            threadCounter <= '0;
            regStall <= FALSE;
        end
        else begin
            regStall <= stall;
            // Only switch threads if we are not stalled.
            // If we stall (e.g. I-Cache miss), we must retry the SAME thread.
            if (!stall) begin
                threadCounter <= threadCounter + 1'b1;
            end
        end
    end

    always_comb begin
        currentThread = threadCounter % NUM_THREADS;
        port.fetchThreadID = currentThread; // Drive interface signal
    end

    // Current PC Selection
    PC_Path currentPC;
    always_comb begin
        // MUX: Select the PC of the active thread
        currentPC = port.pcOut[currentThread];
    end

    PC_Path predNextPC;
    FetchStageRegPath nextStage[ FETCH_WIDTH ];

    // Helper logic to aggregate array signals
    logic isAnyInterrupt;
    logic isAnyRecovery;

    always_comb begin
        // Control
        stall = ctrl.npStage.stall;
        clear = ctrl.npStage.clear;

`ifdef RSD_STOP_FETCH_ON_PRED_MISS
        // Check array for recovery status using reduction
        ctrl.npStageSendBubbleLower =
            (!(| recovery.toRecoveryPhase) && phase[PHASE_DELAY - 1] == PHASE_WAIT);
`else
        ctrl.npStageSendBubbleLower = FALSE;
`endif

        beginStall = !regStall && stall;

        // Check arrays for external triggers
        isAnyInterrupt = FALSE;
        isAnyRecovery = FALSE;
        for(int t=0; t<NUM_THREADS; t++) begin
            if (port.interruptAddrWE[t]) isAnyInterrupt = TRUE;
            if (recovery.toRecoveryPhase[t]) isAnyRecovery = TRUE;
        end

        // Whether PC is written from outside
        if (isAnyRecovery || recovery.recoverFromRename || isAnyInterrupt) begin
            writePC_FromOuter = TRUE;
        end
        else begin
            writePC_FromOuter = FALSE;
        end

        // Note: port.pcWE is now an array, handled in the PC Update block below.
    end


    //
    // Branch Prediction & Next Address Calculation
    //
    always_comb begin

        // Decide the address to input to the branch predictor
        // Priority: Recovery > Interrupt > Rename Recovery > Normal Fetch

        predNextPC = currentPC; // Default

        // If any thread requests recovery, use the shared recovered PC.
        // (This preserves your previous behavior that used recoveredPC_FromRwCommit.)
        if (isAnyRecovery) begin
            predNextPC = recovery.recoveredPC_FromRwCommit;
        end
        else if (recovery.recoverFromRename) begin
            // Detect branch misprediction in decode stage (Rename)
            predNextPC = recovery.recoveredPC_FromRename;
        end
        else begin
            // Normal Fetch Logic
            predNextPC = currentPC;

            for (int i = 0; i < FETCH_WIDTH; i++) begin
                // Process of branch prediction:
                // If BTB is hit, the instruction is predicted to be a branch.
                // In addition, if the branch is predicted as Taken,
                // the address read from BTB is used as next PC.
                if (!regStall && next.fetchStageIsValid[i] &&
                        next.btbHit[i] && next.brPredTaken[i]) begin
                    // Use PC from BTB
                    predNextPC = next.btbOut[i];
                    break;
                end
            end
        end

        // To Branch predictor
        port.predNextPC = predNextPC;
    end


    //
    //  Updating PC
    //
    always_comb begin
        // -----------------------
        // Defaults (prevent inferred latches)
        // -----------------------
        // Default PC input and per-thread write enables
        port.pcIn = '0;
        for (int t = 0; t < NUM_THREADS; t++) begin
            port.pcWE[t] = FALSE;
        end

        // Default next-stage entries
        for (int i = 0; i < FETCH_WIDTH; i++) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].sid = '0;
`endif
            nextStage[i].tid   = currentThread;
            nextStage[i].pc    = '0;
            nextStage[i].valid = FALSE;
        end

        // --- PC Input Data Calculation
        if (isAnyInterrupt) begin
            // When an interrupt occurs, use interrupt address.
            // SMT: Mux the correct interrupt address
            if (port.interruptAddrWE[0])
                port.pcIn = port.interruptAddrIn[0];
            else
                port.pcIn = port.interruptAddrIn[1];
        end
        else if (beginStall) begin
            // Update PC based on the branch prediction result accessed
            // immediately before the stall if it is beginning of stall.
            port.pcIn = predNextPC;
        end
        else begin
            // Increment PC
            port.pcIn = predNextPC + FETCH_WIDTH*INSN_BYTE_WIDTH;
            for (int i = 1; i < FETCH_WIDTH; i++) begin
                if (StepOverCacheLine(predNextPC, 
                                    predNextPC + i * INSN_BYTE_WIDTH)) begin
                    // When PC stepped over the border of cache line, stop there
                    port.pcIn = predNextPC + i * INSN_BYTE_WIDTH;
                    break;
                end
            end
        end

        // --- PC Write Enable (Demux per Thread) ---
        for (int t = 0; t < NUM_THREADS; t++) begin
            if (port.rst) begin
                port.pcWE[t] = FALSE;
            end
            else if (recovery.toRecoveryPhase[t]) begin
                // Recovery writes to the specific thread's PC
                port.pcWE[t] = TRUE;
            end
            else if (port.interruptAddrWE[t]) begin
                // Interrupt writes to the specific thread's PC
                port.pcWE[t] = TRUE;
            end
            else if (recovery.recoverFromRename) begin
                 // Safe fallback: Enable for current thread if recovering from rename.
                 port.pcWE[t] = (t == currentThread); 
            end
            else if (t == currentThread) begin
                // Normal Fetch: Only update the current thread's PC
                // NOTE: beginStall and writePC_FromOuter are computed in the other always_comb block
                port.pcWE[t] = (!stall || beginStall) && !writePC_FromOuter;
            end
            else begin
                port.pcWE[t] = FALSE;
            end
        end


        // Build nextStage entries (already initialized above; override fields)
        for (int i = 0; i < FETCH_WIDTH; i++) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
            // Generate serial id for dumping
            nextStage[i].sid = curSID + i;
`endif
            nextStage[i].tid = currentThread; // SMT: Tag instruction
            nextStage[i].pc  = predNextPC + i * INSN_BYTE_WIDTH;

            if (isAnyInterrupt || clear ||
                StepOverCacheLine(predNextPC, nextStage[i].pc)) begin
                nextStage[i].valid = FALSE;
            end
            else begin
                nextStage[i].valid = TRUE;
            end
        end

        // Drive the interface structure
        port.nextStage = nextStage;
    end




    //
    // I-cache Access
    //
    AddrPath fetchAddr;
    always_comb begin
        // Decide input address of I-cache
        if (next.fetchStageIsValid[0] && stall) begin
            // Use the PC of the IF stage
            fetchAddr = ToAddrFromPC(next.fetchStagePC[0]);
        end
        else begin
            // Use the PC of this stage
            fetchAddr = ToAddrFromPC(predNextPC);
        end

        // To I-cache
        port.icNextReadAddrIn = ToPhyAddrFromLogical(fetchAddr);
    end

`ifndef RSD_DISABLE_DEBUG_REGISTER
    logic [FETCH_WIDTH : 0] numValidInsns;
    always_comb begin
        numValidInsns = 0; // Count valid instructions in this stage
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            if (!nextStage[i].valid) begin
                break;
            end
            else begin
                numValidInsns++;
            end
        end

        // Update serial ID.
        nextSID = ( stall || clear) ?
            curSID : (curSID + numValidInsns);

        // --- Debug Register
        for ( int i = 0; i < FETCH_WIDTH; i++ ) begin
            debug.npReg[i].valid = stall ? FALSE : nextStage[i].valid;
            debug.npReg[i].sid = nextStage[i].sid;
        end
    end
`endif

endmodule : NextPCStage
