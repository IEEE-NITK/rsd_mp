// NextPCStage.sv
`timescale 1ns/1ps

import BasicTypes::*;
import PipelineTypes::*;
import MemoryMapTypes::*;
import CacheSystemTypes::*;
import FetchUnitTypes::*;
import MemoryMapTypes::*;
import MicroArchConf::*;

// Detect the cache line boundary in sequential access
function automatic logic StepOverCacheLine (PC_Path pc1, PC_Path pc2);
    return pc1[ICACHE_LINE_BYTE_NUM_BIT_WIDTH] != pc2[ICACHE_LINE_BYTE_NUM_BIT_WIDTH];
endfunction

module NextPCStage(
    NextPCStageIF.ThisStage          port,
    FetchStageIF.NextPCStage         next,
    RecoveryManagerIF.NextPCStage    recovery,
    ControllerIF.NextPCStage         ctrl,
    DebugIF.NextPCStage              debug
);

`ifdef RSD_STOP_FETCH_ON_PRED_MISS
    typedef enum logic {
        PHASE_FETCH,
        PHASE_WAIT
    } Phase;

    parameter PHASE_DELAY = 2;
    Phase phase[PHASE_DELAY];
    Phase nextPhase;

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < PHASE_DELAY; i++) begin
                phase[i] <= PHASE_FETCH;
            end
        end
        else if (recovery.toRecoveryPhase || recovery.toCommitPhase) begin
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
        if (recovery.toRecoveryPhase) begin
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
`endif // RSD_STOP_FETCH_ON_PRED_MISS

    //
    // Round-robin thread selection
    //
    ThreadID currentThread, nextThread;

    FlipFlop #(
        .FF_WIDTH    (THREAD_NUM_BIT_WIDTH),
        .RESET_VALUE (0)
    ) threadFF (
        .out (currentThread),
        .in  (nextThread),
        .clk (port.clk),
        .rst (port.rst)
    );

    // RR "natural" next thread
    always_comb begin
        nextThread = (currentThread + 1) % THREAD_NUM;
    end

    //
    // *** BOOT LOGIC: per-thread initial PC ***
    //
    typedef enum logic [0:0] { BOOT, RUN } boot_state_t;
    boot_state_t boot_state;
    ThreadID     boot_tid;

    // Per-thread initial PCs (example for 2 threads)
    localparam logic [PC_WIDTH-1:0] INIT_PC [CONF_THREAD_NUM] = '{
        32'h0000_1000,   // Thread 0
        32'h0000_2000    // Thread 1
    };

    // Boot FSM: walk over all threads and write INIT_PC[tid]
    always_ff @(posedge port.clk or posedge port.rst) begin
        if (port.rst) begin
            boot_state <= BOOT;
            boot_tid   <= '0;
        end
        else if (boot_state == BOOT) begin
            if (boot_tid == CONF_THREAD_NUM-1) begin
                boot_state <= RUN;
            end
            else begin
                boot_tid <= boot_tid + 1;
            end
        end
    end

    //
    // "Active" thread for this cycle
    // (used for PC read/write, nextStage, branch predictor)
    //
    ThreadID pcThread;

    always_comb begin
        if (boot_state == BOOT) begin
            pcThread = boot_tid; // during BOOT we walk over threads
        end
        else if (recovery.toRecoveryPhase) begin
            pcThread = recovery.recoveredPC_FromRwCommit.tid;
        end
        else if (recovery.recoverFromRename) begin
            pcThread = recovery.recoveredPC_FromRename.tid;
        end
        else if (port.interruptAddrWE) begin
            pcThread = port.interruptAddrIn.tid;
        end
        else begin
            pcThread = nextThread; // normal RR
        end
    end

`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpSerial curSID, nextSID;

    FlipFlop #(
        .FF_WIDTH    (OP_SERIAL_WIDTH),
        .RESET_VALUE (1)
    ) sidFF (
        .out (curSID),
        .in  (nextSID),
        .clk (port.clk),
        .rst (port.rst)
    );
`endif

    PC_Path           predNextPC;
    FetchStageRegPath nextStage[FETCH_WIDTH];

    // Pipeline control
    logic stall, clear;
    logic regStall, beginStall;
    logic writePC_FromOuter;

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            regStall <= FALSE;
        end
        else begin
            regStall <= stall;
        end
    end

    //
    // Pipeline control (with BOOT override)
    //
    always_comb begin
        if (boot_state == BOOT) begin
            // During BOOT we force a PC write for each thread
            stall  = 1'b0;
            clear  = 1'b0;

            beginStall        = 1'b0;
            writePC_FromOuter = 1'b0;

            ctrl.npStageSendBubbleLower = 1'b0;
            port.pcWE = !port.rst;
        end
        else begin
            // Normal behavior
            stall = ctrl.npStage.stall;
            clear = ctrl.npStage.clear;

`ifdef RSD_STOP_FETCH_ON_PRED_MISS
            ctrl.npStageSendBubbleLower =
                (!recovery.toRecoveryPhase && phase[PHASE_DELAY - 1] == PHASE_WAIT);
`else
            ctrl.npStageSendBubbleLower = FALSE;
`endif

            beginStall = !regStall && stall;

            if (recovery.toRecoveryPhase || recovery.recoverFromRename
                                         || port.interruptAddrWE) begin
                writePC_FromOuter = TRUE;
            end
            else begin
                writePC_FromOuter = FALSE;
            end

            port.pcWE =
                (writePC_FromOuter || !stall || beginStall) && !port.rst;
        end
    end

    //
    // Branch Prediction
    //
    always_comb begin
        if (recovery.toRecoveryPhase) begin
            predNextPC = recovery.recoveredPC_FromRwCommit;
        end
        else if (recovery.recoverFromRename) begin
            predNextPC = recovery.recoveredPC_FromRename;
        end
        else if (boot_state == BOOT) begin
            // during BOOT, just use INIT_PC[pcThread]
            predNextPC.addr = INIT_PC[pcThread];
            predNextPC.tid  = pcThread;
        end
        else begin
            // Use current PC as seen by PC module
            predNextPC = port.pcOut;
            predNextPC.tid = pcThread;

            // Optional: override with BTB prediction for this thread
            for (int i = 0; i < FETCH_WIDTH; i++) begin
                if (!regStall && next.fetchStageIsValid[i] &&
                    next.btbHit[i] && next.brPredTaken[i]) begin
                    predNextPC = next.btbOut[i];
                    predNextPC.tid = pcThread;
                    break;
                end
            end
        end

        port.predNextPC = predNextPC;
    end

    //
    // Updating PC + generating nextStage
    //
    always_comb begin
        // Default: clear nextStage
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            nextStage[i] = '0;
        end

        if (boot_state == BOOT) begin
            //
            // BOOT: directly write per-thread initial PC
            //
            port.pcIn.tid  = pcThread;                 // = boot_tid
            port.pcIn.addr = INIT_PC[pcThread];

            for (int i = 0; i < FETCH_WIDTH; i++) begin
                nextStage[i].pc.tid  = pcThread;
                nextStage[i].pc.addr = INIT_PC[pcThread];
                nextStage[i].valid   = FALSE; // no real fetch during BOOT
            end
        end
        else begin
            //
            // Normal RUN behavior
            //
            if (port.interruptAddrWE) begin
                // full PC_Path including tid comes from interrupt input
                port.pcIn = port.interruptAddrIn;
            end
            else if (recovery.toRecoveryPhase) begin
                port.pcIn = recovery.recoveredPC_FromRwCommit;
            end
            else if (recovery.recoverFromRename) begin
                port.pcIn = recovery.recoveredPC_FromRename;
            end
            else if (beginStall) begin
                port.pcIn = predNextPC;
            end
            else begin
                // normal sequential increment for pcThread
                port.pcIn.tid  = pcThread;
                port.pcIn.addr = predNextPC.addr + FETCH_WIDTH*INSN_BYTE_WIDTH;

                for (int i = 1; i < FETCH_WIDTH; i++) begin
                    if (StepOverCacheLine(predNextPC,
                                          predNextPC + i*INSN_BYTE_WIDTH)) begin
                        port.pcIn.tid  = pcThread;
                        port.pcIn.addr = predNextPC.addr + i*INSN_BYTE_WIDTH;
                        break;
                    end
                end
            end

            // Build the outgoing "fetch window" PC values
            for (int i = 0; i < FETCH_WIDTH; i++) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
                nextStage[i].sid = curSID + i;
`endif
                nextStage[i].pc.addr = predNextPC.addr + i * INSN_BYTE_WIDTH;
                nextStage[i].pc.tid  = pcThread;

                if (port.interruptAddrWE || clear ||
                    StepOverCacheLine(predNextPC, nextStage[i].pc)) begin
                    nextStage[i].valid = FALSE;
                end
                else begin
                    nextStage[i].valid = TRUE;
                end
            end
        end

        port.nextStage = nextStage;
    end

    //
    // I-cache Access
    // Only allow ICache access for the currently active thread (pcThread)
    // This ensures serialization - only one thread accesses ICache at a time
    //
    AddrPath fetchAddr;
    logic icacheAccessAllowed;
    
    always_comb begin
        // Determine if ICache access is allowed for the active thread
        // ICache access is allowed when:
        // 1. We're not in BOOT (or if in BOOT, only for the current boot_tid)
        // 2. The fetch address corresponds to the active pcThread
        // 3. We're not in a recovery phase that would change the thread
        
        if (boot_state == BOOT) begin
            // During BOOT, allow access for the thread being initialized
            icacheAccessAllowed = TRUE; // BOOT is sequential, so safe
        end
        else if (recovery.toRecoveryPhase || recovery.recoverFromRename || port.interruptAddrWE) begin
            // During recovery/interrupt, allow access for the recovered/interrupted thread
            icacheAccessAllowed = TRUE;
        end
        else begin
            // Normal operation: only allow access for the active pcThread
            // Check if the fetch address belongs to the active thread
            if (next.fetchStageIsValid[0] && stall) begin
                // If FetchStage is stalled, check if the stalled instruction is from active thread
                icacheAccessAllowed = (next.fetchStagePC[0].tid == pcThread);
            end
            else begin
                // Normal prefetch: ensure predNextPC belongs to active thread
                icacheAccessAllowed = (predNextPC.tid == pcThread);
            end
        end
        
        // Calculate fetch address
        if (next.fetchStageIsValid[0] && stall) begin
            fetchAddr = ToAddrFromPC(next.fetchStagePC[0]);
        end
        else begin
            fetchAddr = ToAddrFromPC(predNextPC);
        end

        // Only update ICache address if access is allowed for the active thread
        // This ensures ICache only sees requests from one thread at a time
        if (icacheAccessAllowed) begin
            port.icNextReadAddrIn = ToPhyAddrFromLogical(fetchAddr);
        end
        else begin
            // Keep previous address or set to invalid (depending on ICache implementation)
            // For safety, we can keep the last valid address or set to 0
            // ICache should handle this gracefully (it checks icRE from FetchStage)
            port.icNextReadAddrIn = ToPhyAddrFromLogical(fetchAddr); // Still set it, but FetchStage will gate icRE
        end
        
        // Signal to FetchStage which thread is allowed to access ICache
        // This ensures only one thread accesses ICache at a time
        next.activeThreadForICache = pcThread;
    end

`ifndef RSD_DISABLE_DEBUG_REGISTER
    logic [FETCH_WIDTH : 0] numValidInsns;
    always_comb begin
        numValidInsns = 0;
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            if (!nextStage[i].valid) begin
                break;
            end
            else begin
                numValidInsns++;
            end
        end

        nextSID = (stall || clear) ?
                  curSID : (curSID + numValidInsns);

        for (int i = 0; i < FETCH_WIDTH; i++) begin
            debug.npReg[i].valid = stall ? FALSE : nextStage[i].valid;
            debug.npReg[i].sid   = nextStage[i].sid;
        end
    end
`endif

endmodule : NextPCStage