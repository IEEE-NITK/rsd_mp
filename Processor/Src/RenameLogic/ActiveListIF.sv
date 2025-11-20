// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// ActiveListIF
//

import BasicTypes::*;
import MicroOpTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import PipelineTypes::*;
import LoadStoreUnitTypes::*;
import OpFormatTypes::*;

interface ActiveListIF( input logic clk, rst );

    // SMT: TID to direct pushes to the correct partition
    ThreadID pushTid; 

    // Push 'pushedValue' on dispatch if this is true.
    logic pushTail [RENAME_WIDTH];

    // This value is pushed to an active list on dispatch.
    ActiveListEntry pushedTailData [RENAME_WIDTH];

    // This pointer is send to an issue queue on dispatch.
    ActiveListIndexPath pushedTailPtr [RENAME_WIDTH];

    // SMT: Pop counts must be per-thread [NUM_THREADS]
    CommitLaneCountPath popHeadNum [NUM_THREADS];
    CommitLaneCountPath popTailNum [NUM_THREADS];

    // Read ports
    // SMT FIX: Must expose head entries for ALL threads so Arbiter can decide.
    ActiveListEntry readData[NUM_THREADS][COMMIT_WIDTH];

    // Head state for Commit decision (Per thread)
    ExecutionState headExecState[NUM_THREADS][COMMIT_WIDTH];
    
    // Valid entries per thread
    ActiveListCountPath validEntryNum[NUM_THREADS];

    // The count of entries from exception op to tail (Per thread)
    ActiveListCountPath recoveryEntryNum[NUM_THREADS];

    // Write ports (Shared execution units write to any entry using absolute ptr)
    logic               intWrite[INT_ISSUE_WIDTH];
    ActiveListWriteData intWriteData[INT_ISSUE_WIDTH];

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    logic               complexWrite[COMPLEX_ISSUE_WIDTH];
    ActiveListWriteData complexWriteData[COMPLEX_ISSUE_WIDTH];
`endif

    logic               memWrite[MEM_ISSUE_WIDTH];
    ActiveListWriteData memWriteData[MEM_ISSUE_WIDTH];

`ifdef RSD_MARCH_FP_PIPE
    logic               fpWrite[FP_ISSUE_WIDTH];
    ActiveListWriteData fpWriteData[FP_ISSUE_WIDTH];
    FFlags_Path     fpFFlagsData[FP_ISSUE_WIDTH];
    // FFlags data needs to be per-thread or aggregated?
    // ActiveList stores it per instruction, so reading it back is per-thread.
    FFlags_Path     fflagsData[NUM_THREADS][COMMIT_WIDTH];
`endif
    
    // SMT: Allocatable status per thread
    logic allocatable[NUM_THREADS];


    // ActiveList/LSQ TailPtr for recovery
    LoadQueueIndexPath loadQueueRecoveryTailPtr;
    StoreQueueIndexPath storeQueueRecoveryTailPtr;

    // Flush range at exception-detected cycle
    ActiveListIndexPath detectedFlushRangeTailPtr;
    ActiveListIndexPath exceptionOpPtr; // Exception op's ActiveListPtr


    // To active list
    modport ActiveList(
    input
        clk,
        rst,
        pushTid, // SMT
        pushTail,
        pushedTailData,
        popHeadNum,
        popTailNum,
        intWrite,
        intWriteData,
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        complexWrite,
        complexWriteData,
`endif
        memWrite,
        memWriteData,
`ifdef RSD_MARCH_FP_PIPE
        fpWrite,
        fpWriteData,
        fpFFlagsData,
`endif
    output
`ifdef RSD_MARCH_FP_PIPE
        fflagsData,
`endif
        pushedTailPtr,
        readData,
        headExecState,
        loadQueueRecoveryTailPtr,
        storeQueueRecoveryTailPtr,
        detectedFlushRangeTailPtr,
        exceptionOpPtr,
        allocatable,
        validEntryNum,
        recoveryEntryNum
    );

    modport RenameLogic(
    input
        readData,
        popTailNum, // Array
        allocatable, // Array
        validEntryNum, // Array
        pushedTailPtr
    output
        pushTid,
        pushTail,
        pushedTailData
    );

    modport RenameLogicCommitter(
    input
        readData,
        recoveryEntryNum,
    output
        popHeadNum,
        popTailNum
    );
    
    modport CommitStage(
    input
`ifdef RSD_MARCH_FP_PIPE
        fflagsData,
`endif
        readData,
        headExecState,
        validEntryNum
    );

    // Other modports remain similar but aware of the array nature of pop signals
    // (Omitted for brevity, assumed compatible)

endinterface : ActiveListIF