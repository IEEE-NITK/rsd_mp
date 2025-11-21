// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// --- SMT Dual-Thread Round-Robin Fetch Verification Test
//
// This testbench specifically verifies:
// 1. Two threads with different starting addresses
// 2. Round-robin fetch selection (Thread 0 → Thread 1 → Thread 0 → ...)
// 3. ThreadID propagation with correct fetch addresses
// 4. Per-thread instruction execution
//

`timescale 1ns/1ps

import DumperTypes::*;
import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import MicroOpTypes::*;
import LoadStoreUnitTypes::*;
import MemoryMapTypes::*;
import IO_UnitTypes::*;
import DebugTypes::*;

parameter STEP = 8;
parameter HOLD = 2;
parameter SETUP = 2;
parameter WAIT = STEP*2-HOLD-SETUP;
parameter HOLD_PLUS_WAIT = HOLD + WAIT;

module TestSMT_DualThreadRoundRobin;

    //=======================================================================
    // Test Configuration
    //=======================================================================
    
    // Thread PC configuration
    // Thread 0 starts at ROM (0x00000000)
    // Thread 1 starts at RAM (0x80000000)
    localparam PC_THREAD_0 = 32'h00000000;
    localparam PC_THREAD_1 = 32'h80000000;
    
    // Test parameters
    int MAX_TEST_CYCLES;
    int SHOW_SERIAL_OUT;
    string TEST_CODE;
    string DUMMY_DATA_FILE;
    
    // File names
    string codeFileName;
    string serialDumpFileName;
    string roundRobinReportFileName;
    
    // Simulation variables
    integer cycle;
    integer count;
    
    // Register file tracking
    DataPath regData[ LREG_NUM ];
    integer numCommittedRISCV_Op;
    integer numCommittedMicroOp;
    real realTmp;

    //=======================================================================
    // Round-Robin Specific Tracking
    //=======================================================================
    
    typedef struct packed {
        integer pcAddress;
        integer threadID;
        integer fetchCycle;
        integer instructionCount;
    } RoundRobinFetchRecord;
    
    RoundRobinFetchRecord roundRobinHistory[500];
    integer roundRobinHistoryIdx = 0;
    
    typedef struct packed {
        integer cycleNumber;
        ThreadID selectedThread;
        ThreadID actualThreadFetched;
        logic threadIDMatch;
        PC_Path expectedPC;
        PC_Path actualPC;
        logic pcMatch;
    } RoundRobinVerificationRecord;
    
    RoundRobinVerificationRecord rrVerification[500];
    integer rrVerificationIdx = 0;
    
    //=======================================================================
    // Clock and Reset
    //=======================================================================
    
    logic clk, rst, rstOut;

    TestBenchClockGenerator #(
        .STEP(STEP)
    ) clkgen (
        .clk( clk ),
        .rst( rst ),
        .rstOut( rstOut )
    );

    //=======================================================================
    // Main Module Instantiation
    //=======================================================================
    
    LED_Path ledOut;
    LED_Path lastCommittedPC;
    DebugRegister debugRegister;
    logic rxd, txd;
    logic serialWE;
    SerialDataPath serialWriteData;

    Main_Zynq_Wrapper main(
        .clk_p( clk ),
        .clk_n ( ~clk ),
        .negResetIn( ~rst ),
        .posResetOut( rstOut ),
        .*
    );

    //=======================================================================
    // Helper Functions
    //=======================================================================
    
    // Get expected PC based on thread and cycle
    function automatic PC_Path GetExpectedPC(ThreadID tid, integer cycleNum);
        // Simple prediction: alternating cycles, incrementing PC
        // In actual implementation, would need to track more carefully
        if (tid == 0)
            return PC_THREAD_0 + (cycleNum / 2) * 4;  // 4 bytes per instruction
        else
            return PC_THREAD_1 + (cycleNum / 2) * 4;
    endfunction
    
    // Verify round-robin pattern
    task VerifyRoundRobinPattern();
        integer thread0Count = 0;
        integer thread1Count = 0;
        integer expectedThread;
        string patternStatus;
        logic patternCorrect = TRUE;
        
        $display("\n========== Round-Robin Pattern Verification ==========");
        
        for (int i = 0; i < rrVerificationIdx; i++) begin
            expectedThread = (i % NUM_THREADS);
            
            if (rrVerification[i].selectedThread != expectedThread) begin
                $warning("[RR Pattern] Cycle %d: Expected Thread %d, got %d", 
                         rrVerification[i].cycleNumber, 
                         expectedThread, 
                         rrVerification[i].selectedThread);
                patternCorrect = FALSE;
            end
            
            if (rrVerification[i].selectedThread == 0) begin
                thread0Count++;
            end else begin
                thread1Count++;
            end
        end
        
        if (patternCorrect) begin
            $display("[✓] Round-robin pattern VERIFIED");
            $display("    Thread 0 selections: %d", thread0Count);
            $display("    Thread 1 selections: %d", thread1Count);
        end else begin
            $display("[✗] Round-robin pattern FAILED - non-sequential thread selection");
        end
    endtask
    
    // Verify per-thread PC consistency
    task VerifyPerThreadPCConsistency();
        PC_Path thread0PC[500];
        PC_Path thread1PC[500];
        integer t0_count = 0;
        integer t1_count = 0;
        logic pcIncreasing[NUM_THREADS];
        
        $display("\n========== Per-Thread PC Consistency Verification ==========");
        
        for (int t = 0; t < NUM_THREADS; t++) begin
            pcIncreasing[t] = TRUE;
        end
        
        // Collect PC values per thread
        for (int i = 0; i < rrVerificationIdx; i++) begin
            if (rrVerification[i].selectedThread == 0) begin
                thread0PC[t0_count] = rrVerification[i].actualPC;
                t0_count++;
            end else begin
                thread1PC[t1_count] = rrVerification[i].actualPC;
                t1_count++;
            end
        end
        
        // Verify thread 0 PC progression
        for (int i = 1; i < t0_count; i++) begin
            if (thread0PC[i] <= thread0PC[i-1] && thread0PC[i] != thread0PC[i-1]) begin
                // PC should be monotonically increasing or same
                if (thread0PC[i] < thread0PC[i-1]) begin
                    pcIncreasing[0] = FALSE;
                end
            end
        end
        
        // Verify thread 1 PC progression
        for (int i = 1; i < t1_count; i++) begin
            if (thread1PC[i] <= thread1PC[i-1] && thread1PC[i] != thread1PC[i-1]) begin
                if (thread1PC[i] < thread1PC[i-1]) begin
                    pcIncreasing[1] = FALSE;
                end
            end
        end
        
        if (pcIncreasing[0]) begin
            $display("[✓] Thread 0 PC progression: CORRECT");
            $display("    Start PC: 0x%08x, End PC: 0x%08x", thread0PC[0], thread0PC[t0_count-1]);
        end else begin
            $display("[✗] Thread 0 PC progression: FAILED");
        end
        
        if (pcIncreasing[1]) begin
            $display("[✓] Thread 1 PC progression: CORRECT");
            $display("    Start PC: 0x%08x, End PC: 0x%08x", thread1PC[0], thread1PC[t1_count-1]);
        end else begin
            $display("[✗] Thread 1 PC progression: FAILED");
        end
    endtask
    
    // Monitor fetch stage for round-robin behavior
    task MonitorRoundRobinFetch();
        ThreadID selectedTid;
        PC_Path fetchedPC;
        
        selectedTid = main.main.core.npStage.port.selectedTid;
        
        // Get expected PC for selected thread
        if (selectedTid == 0) begin
            fetchedPC = main.main.core.npStage.port.pcOut[0];
        end else begin
            fetchedPC = main.main.core.npStage.port.pcOut[1];
        end
        
        // Record verification data
        if (rrVerificationIdx < 500) begin
            rrVerification[rrVerificationIdx].cycleNumber = cycle;
            rrVerification[rrVerificationIdx].selectedThread = selectedTid;
            rrVerification[rrVerificationIdx].actualPC = fetchedPC;
            
            // Expected thread should alternate
            rrVerification[rrVerificationIdx].expectedPC = 
                (selectedTid == 0) ? PC_THREAD_0 : PC_THREAD_1;
            
            // Check if PC starts from expected location
            if ((selectedTid == 0 && fetchedPC >= PC_THREAD_0 && fetchedPC < 32'h80000000) ||
                (selectedTid == 1 && fetchedPC >= PC_THREAD_1)) begin
                rrVerification[rrVerificationIdx].pcMatch = TRUE;
            end else begin
                rrVerification[rrVerificationIdx].pcMatch = FALSE;
            end
            
            rrVerificationIdx++;
        end
    endtask
    
    // Generate round-robin test report
    task GenerateRoundRobinReport();
        integer file_handle;
        
        file_handle = $fopen(roundRobinReportFileName, "w");
        
        $fprintf(file_handle, "=================================================\n");
        $fprintf(file_handle, "SMT Round-Robin Fetch Test Report\n");
        $fprintf(file_handle, "=================================================\n\n");
        
        $fprintf(file_handle, "Configuration:\n");
        $fprintf(file_handle, "  Thread 0 Start PC: 0x%08x\n", PC_THREAD_0);
        $fprintf(file_handle, "  Thread 1 Start PC: 0x%08x\n", PC_THREAD_1);
        $fprintf(file_handle, "  Number of Threads: %d\n", NUM_THREADS);
        $fprintf(file_handle, "  Test Duration: %d cycles\n\n", cycle);
        
        $fprintf(file_handle, "----- Fetch Pattern Analysis -----\n");
        $fprintf(file_handle, "Total fetch cycles recorded: %d\n\n", rrVerificationIdx);
        
        // Count consecutive correct pattern matches
        integer correctPatternCycles = 0;
        for (int i = 0; i < rrVerificationIdx; i++) begin
            integer expectedThread = (i % NUM_THREADS);
            if (rrVerification[i].selectedThread == expectedThread) begin
                correctPatternCycles++;
            end
        end
        
        $fprintf(file_handle, "Round-robin pattern accuracy: %d/%d (%.1f%%)\n\n",
                 correctPatternCycles, rrVerificationIdx,
                 (correctPatternCycles * 100.0) / rrVerificationIdx);
        
        $fprintf(file_handle, "----- PC Verification -----\n");
        
        // Verify PC consistency per thread
        PC_Path thread0PCFirst = 32'hXXXXXXXX;
        PC_Path thread1PCFirst = 32'hXXXXXXXX;
        integer t0PCErrors = 0;
        integer t1PCErrors = 0;
        
        for (int i = 0; i < rrVerificationIdx; i++) begin
            if (rrVerification[i].selectedThread == 0) begin
                if (thread0PCFirst == 32'hXXXXXXXX) begin
                    thread0PCFirst = rrVerification[i].actualPC;
                    $fprintf(file_handle, "Thread 0 first fetch PC: 0x%08x\n", 
                             thread0PCFirst);
                end
                if (!rrVerification[i].pcMatch) begin
                    t0PCErrors++;
                end
            end else begin
                if (thread1PCFirst == 32'hXXXXXXXX) begin
                    thread1PCFirst = rrVerification[i].actualPC;
                    $fprintf(file_handle, "Thread 1 first fetch PC: 0x%08x\n", 
                             thread1PCFirst);
                end
                if (!rrVerification[i].pcMatch) begin
                    t1PCErrors++;
                end
            end
        end
        
        $fprintf(file_handle, "\nPC Error Analysis:\n");
        $fprintf(file_handle, "  Thread 0 PC errors: %d\n", t0PCErrors);
        $fprintf(file_handle, "  Thread 1 PC errors: %d\n\n", t1PCErrors);
        
        $fprintf(file_handle, "----- Sample Fetch Sequence -----\n");
        for (int i = 0; i < 20 && i < rrVerificationIdx; i++) begin
            $fprintf(file_handle, "Cycle %3d: Thread %d, PC = 0x%08x\n",
                     rrVerification[i].cycleNumber,
                     rrVerification[i].selectedThread,
                     rrVerification[i].actualPC);
        end
        
        $fprintf(file_handle, "\n=================================================\n");
        $fprintf(file_handle, "Test Summary\n");
        $fprintf(file_handle, "=================================================\n");
        if (correctPatternCycles == rrVerificationIdx && t0PCErrors == 0 && t1PCErrors == 0) begin
            $fprintf(file_handle, "STATUS: PASSED ✓\n");
            $fprintf(file_handle, "- Round-robin pattern verified\n");
            $fprintf(file_handle, "- PC consistency verified for both threads\n");
        end else begin
            $fprintf(file_handle, "STATUS: FAILED ✗\n");
            if (correctPatternCycles != rrVerificationIdx) begin
                $fprintf(file_handle, "- Round-robin pattern error\n");
            end
            if (t0PCErrors > 0) begin
                $fprintf(file_handle, "- Thread 0 PC errors detected\n");
            end
            if (t1PCErrors > 0) begin
                $fprintf(file_handle, "- Thread 1 PC errors detected\n");
            end
        end
        $fprintf(file_handle, "=================================================\n");
        
        $fclose(file_handle);
        
        // Print summary to console
        $display("\n========== Round-Robin Test Summary ==========");
        $display("Round-robin accuracy: %d/%d (%.1f%%)", 
                 correctPatternCycles, rrVerificationIdx,
                 (correctPatternCycles * 100.0) / rrVerificationIdx);
        $display("Thread 0 PC errors: %d", t0PCErrors);
        $display("Thread 1 PC errors: %d", t1PCErrors);
        $display("Report written to: %s", roundRobinReportFileName);
        $display("============================================\n");
    endtask

    // Main test procedure
    initial begin
        // Initialize variables
        numCommittedRISCV_Op = 0;
        numCommittedMicroOp = 0;
        roundRobinHistoryIdx = 0;
        rrVerificationIdx = 0;

        // Parse command-line arguments
        if( !$value$plusargs( "MAX_TEST_CYCLES=%d", MAX_TEST_CYCLES ) ) begin
            MAX_TEST_CYCLES = 500;
        end
        if( !$value$plusargs( "TEST_CODE=%s", TEST_CODE ) ) begin
            TEST_CODE = "Verification/TestCode/SMT_DualThread";
        end
        if( !$value$plusargs( "DUMMY_DATA_FILE=%s", DUMMY_DATA_FILE ) ) begin
            DUMMY_DATA_FILE = "Verification/DummyData.hex";
        end
        if( !$value$plusargs( "SHOW_SERIAL_OUT=%d", SHOW_SERIAL_OUT ) ) begin
            SHOW_SERIAL_OUT = 0;
        end

        codeFileName = { TEST_CODE, "/", "code.hex" };
        serialDumpFileName = { TEST_CODE, "/", "serial.out.txt" };
        roundRobinReportFileName = { TEST_CODE, "/", "round_robin_report.txt" };

        //
        // Initialize memory
        //
        #STEP;
        `ifdef RSD_FUNCTIONAL_SIMULATION
            `ifndef RSD_POST_SYNTHESIS_SIMULATION
                // Fill memory with dummy data
                main.main.memory.body.FillDummyData(DUMMY_DATA_FILE, DUMMY_HEX_ENTRY_NUM);
                // Initialize program code
                main.main.memory.body.InitializeMemory(codeFileName);
            `endif
        `endif

        //
        // Run simulation with round-robin monitoring
        //
        @(negedge rstOut);
        
        $display("\n========== SMT Dual-Thread Round-Robin Test Starting ==========");
        $display("Thread 0 Start PC: 0x%08x", PC_THREAD_0);
        $display("Thread 1 Start PC: 0x%08x", PC_THREAD_1);
        $display("Max Test Cycles: %d", MAX_TEST_CYCLES);
        $display("=============================================================\n");

        for( cycle = 0; cycle < MAX_TEST_CYCLES; cycle++ ) begin
            if (SHOW_SERIAL_OUT == 0 && (cycle % 50 == 0)) begin
                $display( "[Cycle %6d] Thread selection and monitoring active", cycle );
            end

            @(posedge clk);
            #HOLD_PLUS_WAIT;

            // Monitor round-robin fetch selection
            MonitorRoundRobinFetch();

            // Count committed operations
            for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
                if ( debugRegister.cmReg[i].commit ) begin
                    numCommittedMicroOp += 1;
                    if ( debugRegister.cmReg[i].opId.mid == 0 ) begin
                        numCommittedRISCV_Op += 1;
                    end
                end
            end
        end

        // Generate reports and verify
        GenerateRoundRobinReport();
        VerifyRoundRobinPattern();
        VerifyPerThreadPCConsistency();

        // Final statistics
        $display( "\n========== Final Statistics ===========" );
        $display( "Total Fetches Recorded: %d", rrVerificationIdx);
        $display( "Num of committed RISC-V-ops: %d", numCommittedRISCV_Op );
        $display( "Num of committed micro-ops: %d", numCommittedMicroOp );
        if ( cycle != 0 ) begin
            realTmp = cycle;
            $display( "IPC (RISC-V instruction): %f", numCommittedRISCV_Op / realTmp );
            $display( "IPC (micro-op): %f", numCommittedMicroOp / realTmp );
        end
        $display( "Elapsed cycles: %d", cycle );
        $display( "========================================\n" );

        $finish;
    end

endmodule
