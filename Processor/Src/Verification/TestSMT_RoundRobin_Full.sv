`timescale 1ns/1ps

import BasicTypes::*;
import MemoryMapTypes::*;
import PipelineTypes::*;
import FetchUnitTypes::*;
import CacheSystemTypes::*;
import MicroArchConf::*;
import MemoryTypes::*;

parameter STEP  = 8; // 62.5MHz
parameter HOLD  = 2;
parameter SETUP = 2;
parameter WAIT  = STEP*2-HOLD-SETUP;
parameter HOLD_PLUS_WAIT = HOLD + WAIT;

// How long to run
localparam int NUM_CYCLES = 200;

// Instruction buffer entry for accumulating prefetched instructions
typedef struct packed {
    logic valid;
    ThreadID tid;
    PC_Path pc;
    InsnPath insn;
    int cycle;
    logic cacheHit;
} InstrBufferEntry;

module TestSMT_RoundRobin_Full;

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
    PerformanceCounterIF perfCounterIF(clk, rst);
    CacheSystemIF       cacheSystemIF(clk, rst);

    //
    // Memory signals
    //
    MemoryEntryDataPath memReadData;
    logic memReadDataReady;
    logic memAccessReadBusy;
    logic memAccessWriteBusy;
    MemoryEntryDataPath memAccessWriteData;
    PhyAddrPath memAccessAddr;
    logic memAccessRE;
    logic memAccessWE;
    MemAccessSerial nextMemReadSerial;
    MemWriteSerial nextMemWriteSerial;
    MemAccessSerial memReadSerial;
    ThreadID memReadTid;
    MemAccessResponse memAccessResponse;

    //
    // Memory module
    //
    Memory #(
        .INIT_HEX_FILE("")
    ) memory (
        .clk( clk ),
        .rst( rst ),
        .memAccessAddr( memAccessAddr ),
        .memAccessWriteData( memAccessWriteData ),
        .memAccessRE( memAccessRE ),
        .memAccessWE( memAccessWE ),
        .memAccessBusy( memAccessReadBusy ), // Using read busy for both
        .nextMemReadSerial( nextMemReadSerial ),
        .nextMemWriteSerial( nextMemWriteSerial ),
        .memReadDataReady( memReadDataReady ),
        .memReadData( memReadData ),
        .memReadSerial( memReadSerial ),
        .memAccessResponse( memAccessResponse )
    );

    assign memAccessWriteBusy = memAccessReadBusy;
    assign memReadTid = '0; // Memory doesn't preserve tid, but MemoryAccessController should

    //
    // MemoryAccessController
    //
    MemoryAccessController memoryAccessController(
        .port( cacheSystemIF.MemoryAccessController ),
        .memAccessAddr( memAccessAddr ),
        .memAccessWriteData( memAccessWriteData ),
        .memAccessRE( memAccessRE ),
        .memAccessWE( memAccessWE ),
        .memAccessReadBusy( memAccessReadBusy ),
        .memAccessWriteBusy( memAccessWriteBusy ),
        .nextMemReadSerial( nextMemReadSerial ),
        .nextMemWriteSerial( nextMemWriteSerial ),
        .memReadDataReady( memReadDataReady ),
        .memReadData( memReadData ),
        .memReadSerial( memReadSerial ),
        .memReadTid( memReadTid ),
        .memAccessResponse( memAccessResponse )
    );

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

    FetchStage fetch_stage(
        .port    (fetchStageIF.ThisStage),
        .prev    (nextPCStageIF.NextStage),
        .ctrl    (controllerIF.FetchStage),
        .debug   (debugIF.FetchStage),
        .perfCounter(perfCounterIF.FetchStage)
    );

    ICache iCache(
        .port    (nextPCStageIF.ICache),
        .next    (fetchStageIF.ICache),
        .cacheSystem(cacheSystemIF.ICache)
    );

    BTB btb(
        .port(nextPCStageIF.BTB),
        .next(fetchStageIF.BTB)
    );

    BranchPredictor brPred(
        .port(nextPCStageIF.BranchPredictor),
        .next(fetchStageIF.BranchPredictor),
        .ctrl(controllerIF.BranchPredictor)
    );

    //
    // Instruction accumulation buffer
    //
    localparam INSTR_BUFFER_SIZE = 512;
    InstrBufferEntry instrBuffer[INSTR_BUFFER_SIZE];
    int instrBufferWritePtr;
    int instrBufferCount;

    //
    // Tracking variables
    //
    localparam int THREADS = CONF_THREAD_NUM;
    localparam int ADDR_W  = PC_WIDTH;
    localparam int DELTA_BYTES = FETCH_WIDTH * INSN_BYTE_WIDTH;

    // Per-thread tracking
    logic [ADDR_W-1:0] base_pc  [THREADS];
    logic [ADDR_W-1:0] last_pc  [THREADS];
    logic              pc_seen  [THREADS];
    int                visit_cnt[THREADS];
    int                prefetch_cnt[THREADS];
    int                cache_miss_cnt[THREADS];
    int                cache_hit_cnt[THREADS];
    int                icache_access_cnt[THREADS]; // Count ICache accesses per thread

    // ICache access monitoring
    ThreadID last_icache_access_tid;
    ThreadID current_tid_ff;
    logic icache_access_in_progress;
    int concurrent_icache_accesses; // Should never be > 1

    // Cache request monitoring
    int icache_req_cnt;
    int memory_req_cnt;
    int memory_resp_cnt;

    // Convenience: watch what NextPCStage is doing
    PC_Path tb_pcIn;
    PC_Path tb_pcOut;
    ThreadID tb_activeThread;

    assign tb_pcIn  = nextPCStageIF.pcIn;
    assign tb_pcOut = nextPCStageIF.pcOut;
    assign tb_activeThread = fetchStageIF.activeThreadForICache;

    //
    // Initialization
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

        // No stalls from controller (initially)
        controllerIF.npStage.stall    = 1'b0;
        controllerIF.npStage.clear    = 1'b0;
        controllerIF.npStageSendBubbleLower = 1'b0;
        controllerIF.ifStage.stall    = 1'b0;
        controllerIF.ifStage.clear    = 1'b0;

        // Init tracking
        for (int t = 0; t < THREADS; t++) begin
            base_pc[t]   = '0;
            last_pc[t]   = '0;
            pc_seen[t]   = 1'b0;
            visit_cnt[t] = 0;
            prefetch_cnt[t] = 0;
            cache_miss_cnt[t] = 0;
            cache_hit_cnt[t] = 0;
            icache_access_cnt[t] = 0;
        end

        instrBufferWritePtr = 0;
        instrBufferCount = 0;
        icache_req_cnt = 0;
        memory_req_cnt = 0;
        memory_resp_cnt = 0;
        concurrent_icache_accesses = 0;
        icache_access_in_progress = 1'b0;
        last_icache_access_tid = '0;

        for (int i = 0; i < INSTR_BUFFER_SIZE; i++) begin
            instrBuffer[i].valid = 1'b0;
        end
    end

    //
    // Monitor ICache access (ensure only one thread at a time)
    //
    always_ff @(posedge clk) begin
        if (!rst) begin
            // Track concurrent ICache accesses
            if (fetchStageIF.icRE) begin
                current_tid_ff = fetchStageIF.activeThreadForICache;
                
                if (icache_access_in_progress && (last_icache_access_tid != current_tid_ff)) begin
                    concurrent_icache_accesses++;
                    $error("[CYCLE %0d] CONCURRENT ICACHE ACCESS: TID %0d and TID %0d accessing simultaneously!",
                           $time/STEP, last_icache_access_tid, current_tid_ff);
                end
                
                icache_access_in_progress = 1'b1;
                last_icache_access_tid = current_tid_ff;
                icache_access_cnt[current_tid_ff]++;
            end
            else begin
                icache_access_in_progress = 1'b0;
            end
        end
    end

    //
    // Accumulate prefetched instructions
    //
    always_ff @(posedge clk) begin
        if (!rst) begin
            // Monitor FetchStage output to accumulate instructions
            for (int i = 0; i < FETCH_WIDTH; i++) begin
                if (fetchStageIF.nextStage[i].valid && 
                    instrBufferWritePtr < INSTR_BUFFER_SIZE) begin
                    instrBuffer[instrBufferWritePtr].valid = 1'b1;
                    instrBuffer[instrBufferWritePtr].tid = fetchStageIF.nextStage[i].pc.tid;
                    instrBuffer[instrBufferWritePtr].pc = fetchStageIF.nextStage[i].pc;
                    instrBuffer[instrBufferWritePtr].insn = fetchStageIF.nextStage[i].insn;
                    instrBuffer[instrBufferWritePtr].cycle = $time/STEP;
                    // Check if this was a cache hit (instruction is valid and came from cache)
                    instrBuffer[instrBufferWritePtr].cacheHit = fetchStageIF.icReadHit[i];
                    
                    instrBufferWritePtr = (instrBufferWritePtr + 1) % INSTR_BUFFER_SIZE;
                    if (instrBufferCount < INSTR_BUFFER_SIZE) begin
                        instrBufferCount++;
                    end
                end
            end
        end
    end

    //
    // Monitor cache and memory activity
    //
    always_ff @(posedge clk) begin
        if (!rst) begin
            // Monitor ICache requests
            if (cacheSystemIF.icMemAccessReq.valid) begin
                icache_req_cnt++;
            end

            // Monitor memory requests
            if (memAccessRE) begin
                memory_req_cnt++;
            end

            // Monitor memory responses
            if (memReadDataReady) begin
                memory_resp_cnt++;
            end
        end
    end

    //
    // Main test
    //
    initial begin : main_test
        int cycle = 0;
        ThreadID current_tid;
        logic [ADDR_W-1:0] current_pc;
        logic [ADDR_W-1:0] diff;
        ThreadID icache_tid;
        logic cache_hit;
        int sample_count;

        $display("[TB] ========== SMT Round-Robin Prefetch Full System Test ==========");
        $display("[TB] Testing round-robin prefetch with ICache and Memory");
        $display("[TB] Threads: %0d, Fetch Width: %0d", THREADS, FETCH_WIDTH);
        $display("[TB] Waiting for reset to deassert...");
        
        @(negedge rst);
        // Let the design settle (BOOT FSM completes)
        repeat (10) @(posedge clk);

        $display("\n[TB] Starting test for %0d cycles...", NUM_CYCLES);
        $display("[TB] Monitoring round-robin behavior and ICache serialization...\n");

        while (cycle < NUM_CYCLES) begin
            @(posedge clk);

            if (rst) begin
                cycle++;
                continue;
            end

            // Monitor round-robin prefetch behavior
            current_tid = tb_pcIn.tid;
            current_pc = tb_pcIn.addr;

            if (current_tid < THREADS && tb_pcIn.addr != '0) begin
                if (!pc_seen[current_tid]) begin
                    // First time we see this thread: learn its base PC
                    base_pc[current_tid]   = current_pc;
                    last_pc[current_tid]   = current_pc;
                    pc_seen[current_tid]   = 1'b1;
                    visit_cnt[current_tid] = 1;

                    $display("[CYCLE %0d] First prefetch for TID %0d: base_pc=0x%h, activeThreadForICache=%0d",
                             cycle, current_tid, current_pc, tb_activeThread);
                end
                else begin
                    // Subsequent visits: check step size from last_pc
                    diff = current_pc - last_pc[current_tid];

                    if (diff == DELTA_BYTES) begin
                        visit_cnt[current_tid]++;
                        prefetch_cnt[current_tid]++;
                    end
                    else if (diff != 0) begin
                        $display("[CYCLE %0d] TID %0d: pc_prev=0x%h pc_curr=0x%h diff=%0d (non-sequential)",
                                 cycle, current_tid, last_pc[current_tid], current_pc, diff);
                    end

                    last_pc[current_tid] = current_pc;
                end
            end

            // Monitor ICache access
            if (fetchStageIF.icRE) begin
                icache_tid = fetchStageIF.activeThreadForICache;
                cache_hit = fetchStageIF.icReadHit[0];
                
                if (cache_hit) begin
                    cache_hit_cnt[icache_tid]++;
                end
                else begin
                    cache_miss_cnt[icache_tid]++;
                end

                if (cycle % 20 == 0) begin // Print every 20 cycles to reduce verbosity
                    $display("[CYCLE %0d] ICache access: TID=%0d, Addr=0x%h, Hit=%b",
                             cycle, icache_tid, fetchStageIF.icReadAddrIn, cache_hit);
                end
            end

            // Monitor memory activity
            if (memAccessRE && cycle % 10 == 0) begin
                $display("[CYCLE %0d] Memory read request: addr=0x%h, serial=%0d",
                         cycle, memAccessAddr, nextMemReadSerial);
            end

            if (memReadDataReady && cycle % 10 == 0) begin
                $display("[CYCLE %0d] Memory read response: data=0x%h, serial=%0d",
                         cycle, memReadData, memReadSerial);
            end

            cycle++;
        end

        // Final summary
        $display("\n[TB] ========== Test Summary ==========");
        $display("[TB] Total cycles: %0d", NUM_CYCLES);
        $display("[TB] Instructions accumulated: %0d", instrBufferCount);
        $display("[TB] Total ICache requests: %0d", icache_req_cnt);
        $display("[TB] Total memory requests: %0d", memory_req_cnt);
        $display("[TB] Total memory responses: %0d", memory_resp_cnt);
        $display("[TB] Concurrent ICache accesses detected: %0d (should be 0)", concurrent_icache_accesses);
        
        $display("\n[TB] Per-thread statistics:");
        for (int t = 0; t < THREADS; t++) begin
            $display("[TB] Thread %0d:", t);
            $display("[TB]   Visits: %0d", visit_cnt[t]);
            $display("[TB]   Prefetches: %0d", prefetch_cnt[t]);
            $display("[TB]   ICache accesses: %0d", icache_access_cnt[t]);
            $display("[TB]   Cache hits: %0d", cache_hit_cnt[t]);
            $display("[TB]   Cache misses: %0d", cache_miss_cnt[t]);
            if (pc_seen[t]) begin
                $display("[TB]   Base PC: 0x%h", base_pc[t]);
                $display("[TB]   Last PC: 0x%h", last_pc[t]);
            end
        end

        // Check round-robin fairness
        if (THREADS >= 2) begin
            int min_visits;
            int max_visits;
            int imbalance;
            
            min_visits = visit_cnt[0];
            max_visits = visit_cnt[0];
            for (int t = 1; t < THREADS; t++) begin
                if (visit_cnt[t] < min_visits) min_visits = visit_cnt[t];
                if (visit_cnt[t] > max_visits) max_visits = visit_cnt[t];
            end
            imbalance = max_visits - min_visits;
            $display("\n[TB] Round-robin fairness:");
            $display("[TB]   Min visits: %0d, Max visits: %0d, Imbalance: %0d",
                     min_visits, max_visits, imbalance);
            if (imbalance > NUM_CYCLES / 5) begin
                $warning("[TB] Significant round-robin imbalance detected!");
            end
            else begin
                $display("[TB]   Round-robin appears balanced.");
            end
        end

        // Check that threads don't share the same base PC
        if (THREADS >= 2) begin
            if (base_pc[0] == base_pc[1] && pc_seen[0] && pc_seen[1]) begin
                $error("[TB] base_pc[0] == base_pc[1] (0x%h) — threads did not get distinct start PCs",
                       base_pc[0]);
            end
            else if (pc_seen[0] && pc_seen[1]) begin
                $display("[TB] Threads have distinct base PCs: T0=0x%h, T1=0x%h, diff=0x%h",
                         base_pc[0], base_pc[1], base_pc[1] - base_pc[0]);
            end
        end

        // Verify ICache serialization
        if (concurrent_icache_accesses == 0) begin
            $display("\n[TB] ✓ ICache serialization verified: No concurrent accesses detected");
        end
        else begin
            $error("\n[TB] ✗ ICache serialization FAILED: %0d concurrent accesses detected!",
                   concurrent_icache_accesses);
        end

        // Sample accumulated instructions
        $display("\n[TB] Sample of accumulated instructions (first 20):");
        sample_count = 0;
        for (int i = 0; i < INSTR_BUFFER_SIZE && sample_count < 20; i++) begin
            if (instrBuffer[i].valid) begin
                $display("[TB]   [%0d] TID=%0d, PC=0x%h, Insn=0x%h, Hit=%b, Cycle=%0d",
                         sample_count, instrBuffer[i].tid, instrBuffer[i].pc.addr,
                         instrBuffer[i].insn, instrBuffer[i].cacheHit, instrBuffer[i].cycle);
                sample_count++;
            end
        end

        $display("\n[TB] Test complete. Check above logs for any [FAIL] or [ERROR] messages.");
        $finish;
    end

endmodule : TestSMT_RoundRobin_Full

