// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// Load queue
//

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import LoadStoreUnitTypes::*;

// Convert a pointer of an active list to an "age."
// An "age" is directly compared with a comparator.
function automatic LoadQueueCountPath LoadQueuePtrToAge(LoadQueueIndexPath ptr, LoadQueueIndexPath head);
    LoadQueueCountPath age;
    age = ptr;
    if (ptr < head)
        return age + LOAD_QUEUE_ENTRY_NUM; // Wrap around.
    else
        return age;
endfunction

module LoadQueue(
    LoadStoreUnitIF.LoadQueue port,
    RecoveryManagerIF.LoadQueue recovery
);

    logic reset;

    // Head and tail pointers.
    LoadQueueIndexPath headPtr;
    LoadQueueIndexPath tailPtr;

    // FIFO controller.
    logic push; // push request.
    RenameLaneCountPath pushCount;  // pushed count.
    LoadQueueCountPath curCount;    // current size.
    
    // SMT: Release logic handles array inputs
    logic releaseLoadQueueMerged;
    CommitLaneCountPath releaseLoadQueueEntryNumMerged;
    
    // SMT: Helper signal for recovery trigger
    logic anyThreadRecovering;
    
    always_comb begin
        // Merge release signals across commit lanes (generalized, no hard-coded [1])
        releaseLoadQueueMerged       = FALSE;
        releaseLoadQueueEntryNumMerged = '0;

        for (int c = 0; c < COMMIT_WIDTH; c++) begin
            if (port.releaseLoadQueue[c]) begin
                releaseLoadQueueMerged         = TRUE;
                releaseLoadQueueEntryNumMerged = port.releaseLoadQueueEntryNum[c];
                // If you want "lowest c wins", keep this; if you want "highest c wins", remove break.
                // break;
            end
        end
        
        // SMT: Compute if any thread is recovering
        anyThreadRecovering = FALSE;
        for (int t = 0; t < NUM_THREADS; t++) begin
            if (recovery.toRecoveryPhase[t]) anyThreadRecovering = TRUE;
        end
    end

    SetTailMultiWidthQueuePointer #(
        LOAD_QUEUE_ENTRY_NUM, 0, 0, 0, RENAME_WIDTH, COMMIT_WIDTH
    ) loadQueuePointer(
        .clk(port.clk),
        .rst(reset),
        .pop(releaseLoadQueueMerged),
        .popCount(releaseLoadQueueEntryNumMerged),
        .push(push),
        .pushCount(pushCount),
        .setTail(anyThreadRecovering), // SMT FIX: Use helper signal
        .setTailPtr(recovery.loadQueueRecoveryTailPtr),
        .count(curCount),
        .headPtr(headPtr),
        .tailPtr(tailPtr)
    );

    always_comb begin
        // Generate push signals.
        pushCount = 0;
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            if (tailPtr + pushCount < LOAD_QUEUE_ENTRY_NUM) begin
                port.allocatedLoadQueuePtr[i] = tailPtr + pushCount;
            end
            else begin
                // Out of range of load queue
                port.allocatedLoadQueuePtr[i] = 
                    tailPtr + pushCount - LOAD_QUEUE_ENTRY_NUM;
            end
            pushCount += port.allocateLoadQueue[i];
        end
        push = pushCount > 0;

        // All entries are not used for avoiding head==tail problem.
        port.loadQueueAllocatable =
            (curCount <= LOAD_QUEUE_ENTRY_NUM - RENAME_WIDTH - 1) ? TRUE : FALSE;

        recovery.loadQueueHeadPtr = headPtr;
    end


    // Address and finish flag storage.
    LoadQueueEntry      loadQueue[LOAD_QUEUE_ENTRY_NUM];
    LoadQueueIndexPath  executedLoadQueuePtrByLoad[LOAD_ISSUE_WIDTH];
    LSQ_BlockAddrPath   executedLoadAddr[LOAD_ISSUE_WIDTH];
    LSQ_BlockWordEnablePath executedLoadWordRE[LOAD_ISSUE_WIDTH];
    logic executedLoadRegValid[LOAD_ISSUE_WIDTH];
    
    always_ff @(posedge port.clk) begin
        if (reset) begin
            for (int i = 0; i < LOAD_QUEUE_ENTRY_NUM; i++) begin
                loadQueue[i].finished <= FALSE;
                loadQueue[i].tid      <= 0;
            end
        end
        else begin
            for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
                if (port.executeLoad[i]) begin
                    loadQueue[ executedLoadQueuePtrByLoad[i] ].regValid <= executedLoadRegValid[i];
                    loadQueue[ executedLoadQueuePtrByLoad[i] ].finished <= TRUE;
                    loadQueue[ executedLoadQueuePtrByLoad[i] ].address  <= executedLoadAddr[i];
                    loadQueue[ executedLoadQueuePtrByLoad[i] ].wordRE   <= executedLoadWordRE[i];
                    loadQueue[ executedLoadQueuePtrByLoad[i] ].pc       <= port.executedLoadPC[i];
                    // SMT: Capture TID
                    loadQueue[ executedLoadQueuePtrByLoad[i] ].tid      <= port.executedLoadTid[i];
                end
            end

            for (int i = 0; i < RENAME_WIDTH; i++) begin
                if (port.allocateLoadQueue[i]) begin
                    loadQueue[ port.allocatedLoadQueuePtr[i] ].finished <= FALSE;
                end
            end
        end
    end

    always_comb begin
        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            executedLoadRegValid[i]           = port.executedLoadRegValid[i];
            executedLoadQueuePtrByLoad[i]     = port.executedLoadQueuePtrByLoad[i];
            executedLoadAddr[i]               = LSQ_ToBlockAddr(port.executedLoadAddr[i]);
            executedLoadWordRE[i]             =
                LSQ_ToBlockWordEnable(
                    port.executedLoadAddr[i],
                    port.executedLoadMemAccessMode[i]
                );
        end
    end


    // Store-load access order violation detector.

    // A picker of violated entries.
    LoadQueueIndexPath executedLoadQueuePtrByStore[STORE_ISSUE_WIDTH];
    LoadQueueOneHotPath addrMatch[STORE_ISSUE_WIDTH];    // The outputs of address comparators.
    LoadQueueIndexPath pickedPtr[STORE_ISSUE_WIDTH];
    logic picked[STORE_ISSUE_WIDTH];  // This flag is true if violation is detected.
    generate
        for(genvar i = 0; i < STORE_ISSUE_WIDTH; i++) begin
            CircularRangePicker #(
                .ENTRY_NUM(LOAD_QUEUE_ENTRY_NUM)
            ) picker(
                .headPtr(executedLoadQueuePtrByStore[i]),
                .tailPtr(tailPtr),
                .request(addrMatch[i]),
                .grantPtr(pickedPtr[i]),
                .picked(picked[i])
            );
        end
    endgenerate

    // These flags are TRUE if violation is detected.
    logic violation[STORE_ISSUE_WIDTH];

    // The addresses of executed stores/loads.
    LSQ_BlockAddrPath executedStoreAddr[STORE_ISSUE_WIDTH];
    LSQ_BlockWordEnablePath executedStoreWordWE[STORE_ISSUE_WIDTH];

    // This is assigned with PC of load that caused a violation with store.
    PC_Path conflictLoadPC[STORE_ISSUE_WIDTH];
    
    always_comb begin

        // Generate a reset signal.
        reset = port.rst;

        // Detect access order violation between already executed loads and
        // a currently executed store.
        for (int si = 0; si < STORE_ISSUE_WIDTH; si++) begin
            violation[si]         = FALSE;
            conflictLoadPC[si]    = '0;
            executedStoreAddr[si] = LSQ_ToBlockAddr(port.executedStoreAddr[si]);
            executedStoreWordWE[si] = LSQ_ToBlockWordEnable(
                port.executedStoreAddr[si],
                port.executedStoreMemAccessMode[si]
            );
            executedLoadQueuePtrByStore[si] = port.executedLoadQueuePtrByStore[si];
        end

        // Compares a stored address and already executed load addresses.
        for (int si = 0; si < STORE_ISSUE_WIDTH; si++) begin
            for (int lqe = 0; lqe < LOAD_QUEUE_ENTRY_NUM; lqe++) begin
                // SMT: Add Thread Check
                addrMatch[si][lqe] =
                    loadQueue[lqe].finished &&
                    loadQueue[lqe].regValid &&
                    (loadQueue[lqe].tid == port.executedStoreTid[si]) && // TID Match
                    loadQueue[lqe].address == executedStoreAddr[si] &&
                    (loadQueue[lqe].wordRE & executedStoreWordWE[si]) != '0;
            end
        end

        // Set address match results.
        for (int si = 0; si < STORE_ISSUE_WIDTH; si++) begin
            if (port.executeStore[si]) begin
                violation[si] = picked[si];

                // Violation is occurred with instruction inside load queue.
                if (picked[si] && pickedPtr[si] < LOAD_QUEUE_ENTRY_NUM) begin
                    conflictLoadPC[si] = loadQueue[pickedPtr[si]].pc;
                end
            end
            else begin
                violation[si] = FALSE;
            end
        end

        // Detect violation between executed loads and stores in this cycle.
        for (int si = 0; si < STORE_ISSUE_WIDTH; si++) begin
            for (int li = 0; li < LOAD_ISSUE_WIDTH; li++) begin

                // Continue if this slot is not a load.
                if (!port.executeLoad[li]) begin
                    continue;
                end
                
                // SMT: Check TID
                if (port.executedLoadTid[li] != port.executedStoreTid[si]) begin
                    continue; // Different threads don't conflict on ordering
                end

                // Check an address.
                if (executedLoadAddr[li] != executedStoreAddr[si]) begin
                    continue;
                end

                if ((executedLoadWordRE[li] & executedStoreWordWE[si]) == '0) begin
                    continue;
                end

                // Check orders.
                if (LoadQueuePtrToAge(port.executedLoadQueuePtrByLoad[li], headPtr) >=
                    LoadQueuePtrToAge(executedLoadQueuePtrByStore[si], headPtr)
                ) begin
                    // Violation is caused by load & store executed in this cycle.
                    violation[si]      = TRUE;
                    conflictLoadPC[si] = port.executedLoadPC[li];
                end
            end
        end

        port.conflictLoadPC = conflictLoadPC;
        
        for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
            port.conflict[i] = violation[i];
        end
    end

endmodule : LoadQueue
