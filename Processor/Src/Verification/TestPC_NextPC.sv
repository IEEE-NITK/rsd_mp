

`timescale 1ns/1ps

import BasicTypes::*;
import MemoryMapTypes::*;
import PipelineTypes::*;
import FetchUnitTypes::*;
import CacheSystemTypes::*;
import MicroArchConf::*;

parameter STEP  = 8; // 62.5MHz
parameter HOLD  = 2;
parameter SETUP = 2;
parameter WAIT  = STEP*2-HOLD-SETUP;
parameter HOLD_PLUS_WAIT = HOLD + WAIT;

// How long to run
localparam int NUM_CYCLES = 40;

module TestPC_NextPC;

    //
    // Clock and Reset
    //
    logic clk, rst, rstStart;

    TestBenchClockGenerator #(
        .STEP(STEP)
    ) clkgen (
        .clk    (clk),
        .rst    (rst),
        .rstOut (rstStart)
    );

    //
    // Interfaces
    //
    NextPCStageIF    nextPCStageIF(
        .clk     (clk),
        .rst     (rst),
        .rstStart(rstStart)
    );

    FetchStageIF        fetchStageIF(clk, rst, rstStart);
    RecoveryManagerIF   recoveryManagerIF(clk, rst);
    ControllerIF        controllerIF(clk, rst);
    DebugIF             debugIF(clk, rst);

    //
    // DUTs
    //
    PC pc_module(
        .port(nextPCStageIF.PC)
    );

    NextPCStage nextpc_stage(
        .port    (nextPCStageIF.ThisStage),
        .next    (fetchStageIF.NextPCStage),
        .recovery(recoveryManagerIF.NextPCStage),
        .ctrl    (controllerIF.NextPCStage),
        .debug   (debugIF.NextPCStage)
    );

    //
    // Tracking and expected model
    //
    localparam int THREADS = CONF_THREAD_NUM; // expected 2
    localparam int ADDR_W  = PC_WIDTH;
    localparam int DELTA_BYTES = FETCH_WIDTH * INSN_BYTE_WIDTH;

    // Per-thread base PC (learned from first observation)
    logic [ADDR_W-1:0] base_pc  [THREADS];
    logic [ADDR_W-1:0] last_pc  [THREADS];
    logic              pc_seen  [THREADS];
    int                visit_cnt[THREADS];

    // Convenience: watch what NextPCStage is telling PC to write
    PC_Path tb_pcIn;
    PC_Path tb_pcOut;

    assign tb_pcIn  = nextPCStageIF.pcIn;
    assign tb_pcOut = nextPCStageIF.pcOut;

    ThreadID          tid;
    logic [ADDR_W-1:0] pc;
    logic [ADDR_W-1:0] expected;

    //
    // Initialization of control interfaces
    //
    initial begin
        // No recovery / interrupts
        recoveryManagerIF.toRecoveryPhase          = '0;
        recoveryManagerIF.toCommitPhase            = '0;
        recoveryManagerIF.recoverFromRename        = '0;
        recoveryManagerIF.recoveredPC_FromRwCommit = '0;
        recoveryManagerIF.recoveredPC_FromRename   = '0;

        nextPCStageIF.interruptAddrWE  = 1'b0;
        nextPCStageIF.interruptAddrIn  = '0;

        // No stalls from controller
        controllerIF.npStage.stall    = 1'b0;
        controllerIF.npStage.clear    = 1'b0;
        controllerIF.npStageSendBubbleLower = 1'b0;

        // No BTB hits
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            fetchStageIF.fetchStageIsValid[i] = 1'b1;
            fetchStageIF.btbHit[i]            = 1'b0;
            fetchStageIF.brPredTaken[i]       = 1'b0;
            fetchStageIF.btbOut[i]            = '0;
            fetchStageIF.fetchStagePC[i]      = '0;
        end

        // Init tracking
        for (int t = 0; t < THREADS; t++) begin
            base_pc[t]   = '0;
            last_pc[t]   = '0;
            pc_seen[t]   = 1'b0;
            visit_cnt[t] = 0;
        end
    end

    //
    // Main test
    //
    initial begin : main_test
        int cycle = 0;

        $display("[TB] Waiting for reset to deassert...");
        @(negedge rst);
        // Let the design settle a bit (also lets any BOOT FSM finish)
        repeat (5) @(posedge clk);

        $display("\n========== Round-Robin Prefetch Test ==========");

        while (cycle < NUM_CYCLES) begin
            @(posedge clk);

            if (rst) begin
                cycle++;
                continue;
            end

            // Observe what NextPCStage is telling PC to write
            tid = tb_pcIn.tid;
            pc  = tb_pcIn.addr;

            if (tid >= THREADS) begin
                $error("[FAIL] Invalid TID %0d seen on pcIn", tid);
                cycle++;
                continue;
            end

            if (!pc_seen[tid]) begin
                // First time we see this thread: learn its base PC
                base_pc[tid]   = pc;
                last_pc[tid]   = pc;
                pc_seen[tid]   = 1'b1;
                visit_cnt[tid] = 1;

                $display("[CYCLE %0d] First visit of TID %0d: base_pc=%h",
                         cycle, tid, pc);
            end
            else begin
                // Subsequent visits: check step size from last_pc
                logic [ADDR_W-1:0] diff = pc - last_pc[tid];

                $display("[CYCLE %0d] TID %0d: pc_prev=%h pc_curr=%h diff=%0d",
                         cycle, tid, last_pc[tid], pc, diff);

                if (diff != DELTA_BYTES) begin
                    $error("[FAIL] PC increment for TID %0d incorrect: expected %0d, got %0d",
                           tid, DELTA_BYTES, diff);
                end

                last_pc[tid]   = pc;
                visit_cnt[tid] = visit_cnt[tid] + 1;
            end

            cycle++;
        end

        // Check that all threads were visited
        $display("\n[TB] Checking round-robin coverage over %0d cycles...", NUM_CYCLES);
        for (int t = 0; t < THREADS; t++) begin
            if (!pc_seen[t]) begin
                $error("[FAIL] Thread %0d never scheduled!", t);
            end
            else begin
                $display("[INFO] Thread %0d: base_pc=%h visit_cnt=%0d",
                         t, base_pc[t], visit_cnt[t]);
            end
        end

        // Optional: check that threads don’t share the same base PC
        if (THREADS >= 2) begin
            if (base_pc[0] == base_pc[1]) begin
                $error("[FAIL] base_pc[0] == base_pc[1] (%h) — threads did not get distinct start PCs",
                       base_pc[0]);
            end
            else begin
                $display("[INFO] base_pc[1] - base_pc[0] = %0d (0x%h)",
                         base_pc[1] - base_pc[0],
                         base_pc[1] - base_pc[0]);
            end
        end

        $display("\n[TB] Test complete. Check above logs for any [FAIL] messages.");
        $finish;
    end

endmodule : TestPC_NextPC