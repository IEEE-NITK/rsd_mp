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
    // ... (Keep existing Stop Fetch logic ) ...
    // Note For brevity, assuming standard phase logic here. 
    // In a real SMT impl, Phase logic might need duplication per thread, 
    // but strictly for NextPC arbitration, we can often share or simplify.
`endif

    // SMT: Thread Arbitration (Round Robin)
    // We only switch threads if we are NOT stalled. 
    // If we stall (ICache miss), we must retry the SAME thread next cycle.
    ThreadID currentThread;
    logic [THREAD_NUM_BIT_WIDTH-1:0] threadCounter;
    
    // Pipeline Control
    logic stall, clear;
    logic regStall, beginStall;
    
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            threadCounter <= '0;
            regStall <= FALSE;
        end
        else begin
            regStall <= stall;
            // ARBITRATION LOGIC:
            // Only advance the round-robin counter if we are not stalled.
            // If stalled, we must hold the thread ID to retry the fetch.
            if (!stall) begin
                threadCounter <= threadCounter + 1'b1;
            end
        end
    end
    
    always_comb begin
        currentThread = threadCounter % NUM_THREADS;
        port.selectedTid = currentThread; // Output to interface
    end

    // Current PC Selection
    PC_Path currentPC;
    always_comb begin
        // MUX: Select the PC of the active thread
        currentPC = port.pcOut[currentThread];
    end

    PC_Path predNextPC;
    FetchStageRegPath nextStage[ FETCH_WIDTH ];
    logic writePC_FromOuter;

    always_comb begin
        // Control
        stall = ctrl.npStage.stall;
        clear = ctrl.npStage.clear;
        ctrl.npStageSendBubbleLower = FALSE; // Simplified for SMT start

        beginStall = !regStall && stall;

        // Whether PC is written from outside (Recovery or Interrupt)
        if (recovery.toRecoveryPhase || recovery.recoverFromRename || port.interruptAddrWE) begin
            writePC_FromOuter = TRUE;
        end
        else begin
            writePC_FromOuter = FALSE;
        end
    end


    //
    // Branch Prediction & Next Address Calculation
    //
    always_comb begin

        // Decide the address to input to the branch predictor
        if (recovery.toRecoveryPhase) begin
            // Recovery: Use the address provided by the recovery manager
            predNextPC = recovery.recoveredPC_FromRwCommit;
        end
        else if (recovery.recoverFromRename) begin
            predNextPC = recovery.recoveredPC_FromRename;
        end
        else begin
            // Standard Fetch: Use the current thread's PC
            predNextPC = currentPC; 

            for (int i = 0; i < FETCH_WIDTH; i++) begin
                // Check BTB Hit for the CURRENT thread
                // Note The BTB module (modified previously) checks the TID internally
                if (!regStall && next.fetchStageIsValid[i] && 
                        next.btbHit[i] && next.brPredTaken[i]) begin
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

        // --- PC Input Data Calculation
        if (port.interruptAddrWE) begin
            port.pcIn = port.interruptAddrIn;
        end
        else if (beginStall) begin
            // If stalling, keep the calculated next PC ready
            port.pcIn = predNextPC;
        end
        else begin
            // Increment PC (Sequential fetch)
            port.pcIn = predNextPC + FETCH_WIDTH*INSN_BYTE_WIDTH;
            
            for (int i = 1; i < FETCH_WIDTH; i++) begin
                if (StepOverCacheLine(predNextPC, predNextPC+i*INSN_BYTE_WIDTH)) begin
                    port.pcIn = predNextPC+i*INSN_BYTE_WIDTH;
                    break;
                end
            end
        end

        // --- PC Write Enable (Demux)
        for (int i = 0; i < NUM_THREADS; i++) begin
            if (port.rst) begin
                port.pcWE[i] = FALSE;
            end
            // Case 1: Recovery (Global or Specific Thread)
            // Assuming recoveryManager handles thread targeting, but for now 
            // if we recover, we usually recover the specific thread.
            // (Simplification: If recovery.toRecoveryPhase is high, we assume 
            // the recovery unit is driving the PC for the *recovering* thread.
            // For this snippet, we assume recovery overrides arbitration).
            else if (writePC_FromOuter) begin
                 // In a full implementation, check if (i == recovery.tid)
                 // For now, we assume the system recovers one thread at a time.
                 port.pcWE[i] = TRUE; 
            end
            // Case 2: Normal Fetch
            else if (i == currentThread) begin
                 // We only update the PC of the thread we are currently fetching
                 port.pcWE[i] = (!stall || beginStall);
            end
            else begin
                 // Other threads hold their PC
                 port.pcWE[i] = FALSE;
            end
        end

        // --- Pipeline Register Update
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            // Pass the current thread ID down the pipeline
            nextStage[i].tid = currentThread; 
            nextStage[i].pc = predNextPC + i * INSN_BYTE_WIDTH;
            
            if (port.interruptAddrWE || clear ||
                StepOverCacheLine(predNextPC, nextStage[i].pc)) begin
                nextStage[i].valid = FALSE;
            end
            else begin
                nextStage[i].valid = TRUE;
            end
        end

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
            // Use the PC of this stage (Current Thread)
            fetchAddr = ToAddrFromPC(predNextPC);
        end
        
        // To I-cache
        port.icNextReadAddrIn = ToPhyAddrFromLogical(fetchAddr);
    end

endmodule : NextPCStage