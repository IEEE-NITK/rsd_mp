`timescale 1ns/1ps

`include "BasicMacros.sv"

import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryMapTypes::*;
import LoadStoreUnitTypes::*;
import ActiveListIndexTypes::*;
import OpFormatTypes::*;

module TestCacheSMT;

    // Signals
    logic clk, rst, rstStart;
    
    // Interfaces
    LoadStoreUnitIF lsu(clk, rst, rstStart);
    CacheSystemIF cacheSystem(clk, rst);
    ControllerIF ctrl(clk, rst);
    RecoveryManagerIF recovery(clk, rst);
    
    // Instantiate DCache
    DCache dcache(
        .lsu(lsu.DCache),
        .cacheSystem(cacheSystem.DCache),
        .ctrl(ctrl.DCache),
        .recovery(recovery.DCacheMissHandler)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Signal driving tasks
    task Reset;
        input int duration;
        begin
            rst = 1;
            rstStart = 1;
            #duration;
            rst = 0;
            rstStart = 0;
            @(posedge clk);
        end
    endtask

    // Initialize signals
    task Initialize;
        begin
            rst = 1;
            rstStart = 1;
            
            // LSU
            for (int i=0; i<LOAD_ISSUE_WIDTH; i++) begin
                lsu.dcReadReq[i] = 0;
                lsu.dcReadAddr[i] = 0;
                lsu.dcReadUncachable[i] = 0;
                lsu.dcReadActiveListPtr[i] = 0;
                lsu.dcReadTid[i] = 0;
                lsu.makeMSHRCanBeInvalidDirect[i] = 0; // Actually MSHR_NUM size, but loop is OK
            end
             for (int i=0; i<MSHR_NUM; i++) begin
                lsu.makeMSHRCanBeInvalidDirect[i] = 0;
            end
            
            lsu.dcWriteReq = 0;
            lsu.dcWriteData = 0;
            lsu.dcWriteAddr = 0;
            lsu.dcWriteByteWE = 0;
            lsu.dcWriteUncachable = 0;
            lsu.dcWriteTid = 0;

            // CacheSystem (Memory side)
            cacheSystem.dcMemAccessReqAck.ack = 0;
            cacheSystem.dcMemAccessReqAck.serial = 0;
            cacheSystem.dcMemAccessReqAck.wserial = 0;
            cacheSystem.dcMemAccessResult.valid = 0;
            cacheSystem.dcMemAccessResult.serial = 0;
            cacheSystem.dcMemAccessResult.data = 0;
            cacheSystem.dcMemAccessResult.tid = 0;
            cacheSystem.dcMemAccessResponse.valid = 0;
            cacheSystem.dcMemAccessResponse.serial = 0;
            
            // CacheFlushManager
            cacheSystem.dcFlushReq = 0;
            cacheSystem.flushComplete = 0;

            // Recovery
            recovery.toRecoveryPhase = 0;
            recovery.flushRangeHeadPtr = 0;
            recovery.flushRangeTailPtr = 0;
            recovery.flushAllInsns = 0;

        end
    endtask

    task IssueLoad;
        input int slot;
        input PhyAddrPath addr;
        input ThreadID tid;
        begin
            lsu.dcReadReq[slot] = 1;
            lsu.dcReadAddr[slot] = addr;
            lsu.dcReadTid[slot] = tid;
            @(posedge clk);
            lsu.dcReadReq[slot] = 0;
        end
    endtask
    
    task IssueFlush;
        input ThreadID tid;
        begin
            cacheSystem.dcFlushReq = 1;
            // Note: CacheSystemIF doesn't pass flushTid directly in the interface definition?
            // Let's check DCacheIF again.
            // DCacheIF has dcFlushTid.
            // DCache uses cacheSystem.dcFlushReq.
            // But where does it get tid?
            // Ah, CacheSystemIF doesn't seem to have dcFlushTid!
            // Let's re-check CacheSystemIF.sv.
        end
    endtask

    // Main test sequence
    initial begin
        $dumpfile("TestCacheSMT.vcd");
        $dumpvars(0, TestCacheSMT);
        
        Initialize();
        #10;
        Reset(20);
        
        $display("Starting Cache SMT Test...");
        
        // Test 1: Thread 0 MSHR Allocation
        $display("Test 1: Thread 0 MSHR Allocation");
        IssueLoad(0, 32'h1000, 0);
        #10;
        // Verify MSHR 0 has TID 0
        if (dcache.missHandler.mshr[0].valid && dcache.missHandler.mshr[0].tid == 0) 
            $display("PASS: MSHR[0] allocated for Thread 0");
        else 
            $display("FAIL: MSHR[0] mismatch. Valid=%b, TID=%d", dcache.missHandler.mshr[0].valid, dcache.missHandler.mshr[0].tid);

        // Test 2: Thread 1 MSHR Allocation
        $display("Test 2: Thread 1 MSHR Allocation");
        IssueLoad(0, 32'h2000, 1); // Use same slot, new address
        #10;
         // Verify MSHR 1 has TID 1 (Assuming MSHR 0 is still occupied)
        if (dcache.missHandler.mshr[1].valid && dcache.missHandler.mshr[1].tid == 1) 
            $display("PASS: MSHR[1] allocated for Thread 1");
        else 
            $display("FAIL: MSHR[1] mismatch. Valid=%b, TID=%d", dcache.missHandler.mshr[1].valid, dcache.missHandler.mshr[1].tid);

        // Test 3: Check Flush Logic
        // Note: CacheSystemIF doesn't have flushTid. 
        // The README said:
        // CacheFlushManager receives cacheFlushTid
        // CacheFlushManager sends: port.dcFlushTid = cacheFlushTid
        // But DCache.sv connects port.dcFlushReq = cacheSystem.dcFlushReq
        // I need to see how dcFlushTid is passed to DCache.
        // In DCache.sv:
        // cacheSystem.dcFlushReqAck = port.dcFlushReqAck;
        // port.dcFlushReq = cacheSystem.dcFlushReq;
        // But where is dcFlushTid connected?
        // It seems DCacheIF has dcFlushTid, but DCache module doesn't seem to connect it to CacheSystemIF?
        // Let's check DCache.sv lines around 1290 again.
        
        $finish;
    end

endmodule
