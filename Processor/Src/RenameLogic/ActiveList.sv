// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// Active list (SMT Partitioned)
//

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import MicroOpTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import LoadStoreUnitTypes::*;
import PipelineTypes::*;
import DebugTypes::*;
import OpFormatTypes::*;


module ActiveList(
    ActiveListIF.ActiveList port,
    RecoveryManagerIF.ActiveList recovery,
    ControllerIF.ActiveList ctrl,
    DebugIF.ActiveList debug
);
    // SMT Partitioning Configuration
    localparam THREAD_PARTITION_SIZE = ACTIVE_LIST_ENTRY_NUM / NUM_THREADS;

    //
    // --- Pointers (Duplicated per Thread)
    //
    ActiveListIndexPath headPtr[NUM_THREADS];
    ActiveListIndexPath tailPtr[NUM_THREADS];
    ActiveListCountPath count[NUM_THREADS];
    
    // Internal Signals for Pointer Logic
    ActiveListIndexPath headPtrList[NUM_THREADS][COMMIT_WIDTH];
    ActiveListIndexPath tailPtrList[NUM_THREADS][COMMIT_WIDTH];
    
    // We need Read Pointers for ALL threads to feed the 'readData' array
    ActiveListIndexPath readPtrList[NUM_THREADS * COMMIT_WIDTH]; 

    ActiveListIndexPath pushedTailPtr [RENAME_WIDTH]; // Output to RenameLogic
    RenameLaneCountPath pushNum; // Current cycle push count

    // Generate Pointers for each thread
    // no muxing, sequential commit from one thread only commit width per thread.
    // between threads, commit is round robin.
    // push from rename is directed by TID.
    generate
        for (genvar i = 0; i < NUM_THREADS; i++) begin : ptr_gen
            BiTailMultiWidthQueuePointer #(THREAD_PARTITION_SIZE, 0, 0, 0, RENAME_WIDTH, COMMIT_WIDTH)
                activeListPointer(
                    .clk(port.clk),
                    .rst(port.rst),
                    .popHead(port.popHeadNum[i] > 0),
                    .popHeadCount(port.popHeadNum[i]),
                    // Push only enables if the incoming TID matches this thread
                    .pushTail( (port.pushTid == i) && (pushNum > 0) ),
                    .pushTailCount(pushNum),
                    .popTail( port.popTailNum[i] > 0 ),
                    .popTailCount( port.popTailNum[i] ),
                    .count(count[i]),
                    .headPtr(headPtr[i]),
                    .tailPtr(tailPtr[i])
                );
        end
    endgenerate

    // Helper function to offset pointers based on Thread ID
    function automatic ActiveListIndexPath GetPartitionedPtr(ThreadID tid, ActiveListIndexPath localPtr);
        // Simple static partitioning:
        if (tid == 0) return localPtr;
        else return localPtr + THREAD_PARTITION_SIZE;
    endfunction

    always_comb begin
        // 1. Check Allocatable (Per Thread)
        for(int i=0; i<NUM_THREADS; i++) begin
            port.allocatable[i] = (count[i] <= THREAD_PARTITION_SIZE - RENAME_WIDTH) ? TRUE : FALSE;
            port.validEntryNum[i] = count[i];
        end

        // 2. Calculate Push Pointers (Based on incoming TID from Rename)
        pushNum = 0;
        for (int i = 0; i < RENAME_WIDTH; i++) begin
            // Calculate local pointer then add partition offset
            ActiveListIndexPath localPushPtr;
            if ((tailPtr[port.pushTid] + pushNum) >= THREAD_PARTITION_SIZE) begin
                localPushPtr = tailPtr[port.pushTid] + pushNum - THREAD_PARTITION_SIZE;
            end
            else begin
                localPushPtr = tailPtr[port.pushTid] + pushNum;
            end
            
            pushedTailPtr[i] = GetPartitionedPtr(port.pushTid, localPushPtr);
            pushNum += (port.pushTail[i] ? 1 : 0);
        end
        port.pushedTailPtr = pushedTailPtr;


        // 3. Calculate Read Pointers (Head of ALL threads)
        for(int t=0; t<NUM_THREADS; t++) begin
            for (int i = 0; i < COMMIT_WIDTH; i++) begin
                if ((headPtr[t] + i) < THREAD_PARTITION_SIZE) begin
                    headPtrList[t][i] = GetPartitionedPtr(t, headPtr[t] + i);
                end
                else begin
                    headPtrList[t][i] = GetPartitionedPtr(t, headPtr[t] + i - THREAD_PARTITION_SIZE);
                end
                // Flatten for RAM Interface
                readPtrList[(t*COMMIT_WIDTH) + i] = headPtrList[t][i];
            end
        end

        ctrl.activeListEmpty = (count[0] == 0) && (count[1] == 0);
    end


    //
    // --- Active List RAM (Shared)
    //
    logic pushTail [RENAME_WIDTH];
    ActiveListEntry pushedTailData [RENAME_WIDTH];
    
    // Read output from RAM is flat: [NUM_THREADS * COMMIT_WIDTH]
    ActiveListEntry readDataFlat[NUM_THREADS * COMMIT_WIDTH];

    DistributedMultiBankRAM #(
        .ENTRY_NUM( ACTIVE_LIST_ENTRY_NUM ), // Full size
        .ENTRY_BIT_SIZE( $bits( ActiveListEntry ) ),
        .READ_NUM( NUM_THREADS * COMMIT_WIDTH  ), // SMT Increase: Must read heads of both threads
        .WRITE_NUM( RENAME_WIDTH )
    ) activeList (
        .clk( port.clk ),
        .we( pushTail ),
        .wa( pushedTailPtr ), // Already partitioned indices
        .wv( pushedTailData ),
        .ra( readPtrList ),
        .rv( readDataFlat )
    );

    always_comb begin
        pushTail = port.pushTail;
        pushedTailData = port.pushedTailData;
        
        // Unpack flat read data into interface array
        for(int t=0; t<NUM_THREADS; t++) begin
            for(int i=0; i<COMMIT_WIDTH; i++) begin
                port.readData[t][i] = readDataFlat[(t*COMMIT_WIDTH) + i];
            end
        end
    end

    // ... (Write Logic for Execution Results remains mostly same, addressing is absolute) ...
    
    // Note HeadExecState logic also needs to be duplicated per thread similar to readData.
    
endmodule : ActiveList