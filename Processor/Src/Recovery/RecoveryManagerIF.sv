// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- RecoveryManagerIF
// SMT Updated: Signals are now arrays to support independent thread recovery.
//

import BasicTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import LoadStoreUnitTypes::*;

interface RecoveryManagerIF( input logic clk, rst );

    // Phase of a pipeline (Per Thread)
    PipelinePhase phase[NUM_THREADS];

    // A type of exception from CommitStage
    RefetchType refetchTypeFromCommitStage[NUM_THREADS];

    // A type of exception from RwStage
    RefetchType refetchTypeFromRwStage; // Shared? Or tagged with TID? 
    // SMT: Ideally per thread, but usually RwStage exceptions are precise or handled via Commit.
    // For simplicity, we assume RwStage signals come with a TID or are arrayed if RwStage supports it.
    // Assuming RwStage is NOT duplicated, we need to know WHICH thread caused the RW exception.
    // Added TID signal for RwStage exception.
    ThreadID    exceptionTidFromRwStage;

    // Index of detected exception op in CommitStage
    CommitLaneIndexPath recoveryOpIndex[NUM_THREADS];

    // Exception detected in CommitStage
    logic exceptionDetectedInCommitStage[NUM_THREADS];

    // Exception detected in RwStage
    logic exceptionDetectedInRwStage;

    // PC control
    logic    toCommitPhase[NUM_THREADS];
    AddrPath recoveredPC_FromCommitStage[NUM_THREADS];
    AddrPath recoveredPC_FromRwStage;
    AddrPath recoveredPC_FromRwCommit;      // Correct PC (Muxed output)

    // For fault handling
    AddrPath faultingDataAddr;

    // Miss prediction detected in RenameStage
    logic    recoverFromRename;
    AddrPath recoveredPC_FromRename;

    // Trigger recovery of each module (Per Thread)
    logic toRecoveryPhase[NUM_THREADS];

    // Flush range to broadcast (Per Thread)
    ActiveListIndexPath flushRangeHeadPtr[NUM_THREADS];
    ActiveListIndexPath flushRangeTailPtr[NUM_THREADS];
    
    // Whether flush all instructions in ActiveList
    logic flushAllInsns[NUM_THREADS];

    // ActiveList/LSQ TailPtr for recovery
    LoadQueueIndexPath loadQueueRecoveryTailPtr;
    LoadQueueIndexPath loadQueueHeadPtr;
    StoreQueueIndexPath storeQueueRecoveryTailPtr;
    StoreQueueIndexPath storeQueueHeadPtr;

    // IssueQueueEntryPtr to be flushed at recovery
    IssueQueueOneHotPath flushIQ_Entry;

    // In IQ returning index to freelist
    logic issueQueueReturnIndex;

    // In AL recovery (Per Thread)
    logic inRecoveryAL[NUM_THREADS];

    // In RMT recovery (Per Thread)
    logic renameLogicRecoveryRMT[NUM_THREADS];

    // In ReplayQueue flushing
    logic replayQueueFlushedOpExist;

    // In wakeupPipelineReg flushing
    logic wakeupPipelineRegFlushedOpExist;

    // Unable to detect exception and start recovery
    logic unableToStartRecovery[NUM_THREADS];

    // IssueQueue flush
    IssueQueueOneHotPath notIssued;

    // wakeupPipelineRegister
    logic selected [ ISSUE_WIDTH ];
    IssueQueueIndexPath selectedPtr [ ISSUE_WIDTH ];
    ActiveListIndexPath selectedActiveListPtr [ ISSUE_WIDTH ];

    // RwStage recovery flag (Per Thread)
    logic recoveryFromRwStage[NUM_THREADS];

    // Why recovery is caused
    ExecutionState recoveryCauseFromCommitStage[NUM_THREADS];

    modport RecoveryManager(
    input
        clk,
        rst,
        exceptionDetectedInCommitStage,
        refetchTypeFromCommitStage,
        exceptionDetectedInRwStage,
        exceptionTidFromRwStage, // SMT
        refetchTypeFromRwStage,
        renameLogicRecoveryRMT,
        issueQueueReturnIndex,
        replayQueueFlushedOpExist,
        wakeupPipelineRegFlushedOpExist,
        recoveredPC_FromCommitStage,
        recoveredPC_FromRwStage,
        faultingDataAddr,
        notIssued,
        flushIQ_Entry,
        recoveryCauseFromCommitStage,
    output
        phase,
        toRecoveryPhase,
        recoveredPC_FromRwCommit,
        toCommitPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        unableToStartRecovery,
        recoveryFromRwStage,
        loadQueueRecoveryTailPtr,
        storeQueueRecoveryTailPtr,
        flushAllInsns // Added
    );

    // ... (Renamed and duplicated modports below for Thread-Aware modules) ...
    // Most modules (IssueQueue, Scheduler) take the GLOBAL signal array and decide internally
    // or we pass the specific signal. Ideally, we pass the whole array so they can check:
    // if (toRecoveryPhase[my_tid]) flush();

    modport RenameStage(
    output
        recoverFromRename,
        recoveredPC_FromRename
    );

    modport CommitStage(
    input
        phase,
        unableToStartRecovery,
        renameLogicRecoveryRMT,
    output
        exceptionDetectedInCommitStage,
        recoveryOpIndex,
        refetchTypeFromCommitStage,
        recoveryCauseFromCommitStage
    );

    modport NextPCStage(
    input
        toCommitPhase,
        toRecoveryPhase,
        recoveredPC_FromRwCommit,
        recoverFromRename,
        recoveredPC_FromRename
    );

    modport RenameLogic(
    input
        toRecoveryPhase,
        inRecoveryAL,
    output
        renameLogicRecoveryRMT
    );

    modport RenameLogicCommitter(
    input
        toRecoveryPhase,
        toCommitPhase,
    output
        inRecoveryAL
    );

    // SMT NOTE: Backend modules (IssueQueue, etc.) usually flush based on ActiveList IDs.
    // They need to know which thread is flushing to invalidate the correct entries.
    // We export the arrays to them.
    
    modport IssueQueue(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns,
        notIssued,
        selected,
        selectedPtr,
        recoveryFromRwStage,
    output
        flushIQ_Entry,
        issueQueueReturnIndex,
        selectedActiveListPtr
    );
    
// fix to local missing modport error 

    modport ScheduleStage(
    input
        toRecoveryPhase,
        flushIQ_Entry
    );

    modport IntegerIssueStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport IntegerRegisterReadStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport IntegerExecutionStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport IntegerRegisterWriteStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    modport ComplexIntegerIssueStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport ComplexIntegerRegisterReadStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport ComplexIntegerExecutionStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport ComplexIntegerRegisterWriteStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );
`endif

    modport MemoryIssueStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport MemoryRegisterReadStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport MemoryExecutionStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport MemoryAccessStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport MemoryTagAccessStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport MemoryRegisterWriteStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

`ifdef RSD_MARCH_FP_PIPE
    modport FPIssueStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport FPRegisterReadStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport FPExecutionStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport FPRegisterWriteStage(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );
    
    modport FPDivSqrtUnit(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );
`endif

    modport MulDivUnit(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport LoadQueue(
    input
        toRecoveryPhase,
        loadQueueRecoveryTailPtr,
    output 
        loadQueueHeadPtr
    );

    modport StoreQueue(
    input
        toRecoveryPhase,
        storeQueueRecoveryTailPtr,
    output 
        storeQueueHeadPtr
    );

    modport StoreCommitter(
    input
        toRecoveryPhase
    );

    modport ActiveList(
    input
        toRecoveryPhase,
        toCommitPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns,
    output
        exceptionDetectedInRwStage, // These outputs might be needed if ActiveList drives recovery trigger
        refetchTypeFromRwStage
    );

    modport ReplayQueue(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns,
        recoveryFromRwStage,
    output
        replayQueueFlushedOpExist
    );

    modport Scheduler(
    input
        toRecoveryPhase,
        flushIQ_Entry,
    output
        notIssued
    );
      
    modport SelectLogic(
    output 
        selected,
        selectedPtr
    );
    
// Inside RecoveryManagerIF.sv

    modport WakeupPipelineRegister(
    input
        toRecoveryPhase,      // Array [NUM_THREADS]
        recoveryFromRwStage,  // Array [NUM_THREADS]
        flushRangeHeadPtr,    // Array [NUM_THREADS] -- THIS WAS MISSING
        flushRangeTailPtr,    // Array [NUM_THREADS] -- THIS WAS MISSING
        flushAllInsns,        // Array [NUM_THREADS] -- THIS WAS MISSING
        selectedActiveListPtr, // Array [ISSUE_WIDTH]
        flushIQ_Entry,        // One-Hot Vector -- THIS WAS MISSING
    output
        wakeupPipelineRegFlushedOpExist
    );

    modport DCacheMissHandler(
    input
        toRecoveryPhase,
        flushRangeHeadPtr,
        flushRangeTailPtr,
        flushAllInsns
    );

    modport InterruptController(
    input
        unableToStartRecovery
    );

endinterface : RecoveryManagerIF