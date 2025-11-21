// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// --- Core module (SMT-Modified Version)
//
// プロセッサ・コアに含まれる全てのモジュールをインスタンシエートし、
// インターフェースで接続する
//
// SMT Modifications:
// - Updated all interface instantiations to include SMT parameters
// - Thread ID signals are now part of interface definitions
// - Verified all modport connections for SMT signals
//

import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryTypes::*;
import MemoryMapTypes::*;
import IO_UnitTypes::*;
import DebugTypes::*;

module Core (
input
    logic clk,
    logic rst, rstStart,
    MemAccessSerial nextMemReadSerial, // RSDの次の読み出し要求に割り当てられるシリアル(id)
    MemWriteSerial nextMemWriteSerial, // RSDの次の書き込み要求に割り当てられるシリアル(id)
    MemoryEntryDataPath memReadData,
    logic memReadDataReady,
    MemAccessSerial memReadSerial, // メモリの読み出しデータのシリアル
    MemAccessResponse memAccessResponse, // メモリ書き込み完了通知
    logic memAccessReadBusy,
    logic memAccessWriteBusy,
    logic reqExternalInterrupt,
    ExternalInterruptCodePath externalInterruptCode,
output
    DebugRegister debugRegister,
    PC_Path lastCommittedPC,
    PhyAddrPath memAccessAddr,
    MemoryEntryDataPath memAccessWriteData,
    logic memAccessRE,
    logic memAccessWE,
    logic serialWE,
    SerialDataPath serialWriteData
);
    //
    // --- For Debug
    //
    DebugIF debugIF( clk, rst );
    PerformanceCounterIF perfCounterIF( clk, rst );

    assign debugRegister = debugIF.debugRegister;

`ifndef RSD_DISABLE_DEBUG_REGISTER
    Debug debug ( debugIF, lastCommittedPC );
`else
    always_ff @(posedge clk) begin
        lastCommittedPC <= debugIF.lastCommittedPC;
    end
`endif

`ifndef RSD_DISABLE_PERFORMANCE_COUNTER
    PerformanceCounter perfCounter(perfCounterIF, debugIF);
`endif

    //
    // --- Interfaces
    //
    // SMT: All interface instantiations automatically handle SMT signals
    // based on NUM_THREADS and THREAD_NUM_BIT_WIDTH defined in BasicTypes.sv

    // Pipeline control logic
    ControllerIF ctrlIF( clk, rst );

    // Pipeline stages
    // SMT MODIFICATION: NextPCStageIF now includes selectedTid output
    NextPCStageIF npStageIF( clk, rst, rstStart );
    
    // SMT MODIFICATION: FetchStageIF now includes fetchThreadId[FETCH_WIDTH] output
    FetchStageIF ifStageIF( clk, rst, rstStart );
    
    PreDecodeStageIF pdStageIF( clk, rst );
    DecodeStageIF idStageIF( clk, rst );
    
    // SMT MODIFICATION: RenameStageIF now includes tid[RENAME_WIDTH] input and 
    // rmtWriteReg_Tid[COMMIT_WIDTH] output for thread-aware register mapping
    RenameStageIF rnStageIF( clk, rst, rstStart );
    //DispatchStageIF dsStageIF( clk, rst );
    ScheduleStageIF scStageIF( clk, rst );

    IntegerIssueStageIF intIsStageIF( clk, rst );
    IntegerRegisterReadStageIF intRrStageIF( clk, rst );
    IntegerExecutionStageIF intExStageIF( clk, rst );
    //IntegerRegisterWriteStageIF intRwStageIF( clk, rst );

    ComplexIntegerIssueStageIF complexIsStageIF( clk, rst );
    ComplexIntegerRegisterReadStageIF complexRrStageIF( clk, rst );
    ComplexIntegerExecutionStageIF complexExStageIF( clk, rst );

    MemoryIssueStageIF memIsStageIF( clk, rst );
    MemoryRegisterReadStageIF memRrStageIF( clk, rst );
    MemoryExecutionStageIF memExStageIF( clk, rst );
    MemoryTagAccessStageIF mtStageIF( clk, rst );
    MemoryAccessStageIF maStageIF( clk, rst );
    //MemoryRegisterWriteStageIF memRwStageIF( clk, rst );
    
    FPIssueStageIF fpIsStageIF( clk, rst );
    FPRegisterReadStageIF fpRrStageIF( clk, rst );
    FPExecutionStageIF fpExStageIF( clk, rst );
    FPDivSqrtUnitIF fpDivSqrtUnitIF(clk, rst);

    CommitStageIF cmStageIF( clk, rst );

    // Other interfaces.
    CacheSystemIF cacheSystemIF( clk, rst );
    
    // SMT MODIFICATION: RenameLogicIF now includes tid[RENAME_WIDTH] and 
    // rmtWriteReg_Tid[COMMIT_WIDTH] for thread-aware RMT operations
    RenameLogicIF renameLogicIF( clk, rst, rstStart );
    
    // SMT MODIFICATION: ActiveListIF now includes pushTid for thread-partitioned
    // Active List management
    ActiveListIF activeListIF( clk, rst );
    
    SchedulerIF schedulerIF( clk, rst, rstStart );
    WakeupSelectIF wakeupSelectIF( clk, rst, rstStart );
    RegisterFileIF registerFileIF( clk, rst, rstStart );
    BypassNetworkIF bypassNetworkIF( clk, rst, rstStart );
    
    // SMT MODIFICATION: LoadStoreUnitIF now includes:
    // - executedLoadTid[LOAD_ISSUE_WIDTH]: Thread ID for executed loads
    // - executedStoreTid[STORE_ISSUE_WIDTH]: Thread ID for executed stores
    // - dcReadTid[LOAD_ISSUE_WIDTH]: Thread ID for D-cache read requests
    // - dcWriteTid: Thread ID for D-cache write requests
    // - commitStore[NUM_THREADS]: Per-thread commit signal
    // - releaseLoadQueue[NUM_THREADS]: Per-thread load queue release
    LoadStoreUnitIF loadStoreUnitIF( clk, rst, rstStart );
    
    // SMT MODIFICATION: RecoveryManagerIF now includes per-thread recovery signals
    // including exceptionTidFromRwStage for thread-specific exception handling
    RecoveryManagerIF recoveryManagerIF( clk, rst );
    
    // SMT MODIFICATION: CSR_UnitIF now includes csrAccessTid for thread-banked CSR access
    CSR_UnitIF csrUnitIF(clk, rst, rstStart, reqExternalInterrupt, externalInterruptCode);
    
    IO_UnitIF ioUnitIF(clk, rst, rstStart, serialWE, serialWriteData);
    MulDivUnitIF mulDivUnitIF(clk, rst);
    CacheFlushManagerIF cacheFlushManagerIF(clk, rst);

    //
    // --- Modules
    //
    Controller controller( ctrlIF, debugIF );
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
        .memAccessResponse( memAccessResponse )
    );


    // SMT: NextPCStage now handles round-robin thread selection
    // Outputs: selectedTid indicates which thread is being fetched from
    NextPCStage npStage( npStageIF, ifStageIF, recoveryManagerIF, ctrlIF, debugIF );
        PC pc( npStageIF );
        BTB btb( npStageIF, ifStageIF );
        BranchPredictor brPred( npStageIF, ifStageIF, ctrlIF );
    
    // SMT: FetchStage now propagates thread IDs
    // Outputs: fetchThreadId[FETCH_WIDTH] carries thread ID for each fetched instruction
    FetchStage ifStage( ifStageIF, npStageIF, ctrlIF, debugIF, perfCounterIF );
        ICache iCache( npStageIF, ifStageIF, cacheSystemIF );
    
    PreDecodeStage pdStage( pdStageIF, ifStageIF, ctrlIF, debugIF );
    DecodeStage idStage( idStageIF, pdStageIF, ctrlIF, debugIF, perfCounterIF );

    // SMT: RenameStage now handles thread-aware register mapping
    // Key signal: rnStageIF.tid[RENAME_WIDTH] carries thread ID for rename operations
    RenameStage rnStage( rnStageIF, idStageIF, renameLogicIF, activeListIF, schedulerIF, loadStoreUnitIF, recoveryManagerIF, ctrlIF, debugIF );
        // SMT: RenameLogic performs thread-indexed RMT (Register Map Table) access
        // RMT address generation includes thread ID to prevent register aliasing between threads
        RenameLogic renameLogic( renameLogicIF, activeListIF, recoveryManagerIF );
        RenameLogicCommitter renameLogicCommitter( renameLogicIF, activeListIF, recoveryManagerIF );
        
        // SMT: ActiveList is partitioned between threads
        // Thread 0 uses first half of AL_ENTRY_NUM entries
        // Thread 1 uses second half of AL_ENTRY_NUM entries
        ActiveList activeList( activeListIF, recoveryManagerIF, ctrlIF, debugIF );
        RMT rmt_wat( renameLogicIF );
        RetirementRMT retirementRMT( renameLogicIF );
        MemoryDependencyPredictor memoryDependencyPredictor( rnStageIF, loadStoreUnitIF );
    
    DispatchStage dsStage( /*dsStageIF,*/ rnStageIF, schedulerIF, ctrlIF, debugIF );

    ScheduleStage scStage( scStageIF, schedulerIF, recoveryManagerIF, ctrlIF );
        IssueQueue issueQueue( schedulerIF, wakeupSelectIF, recoveryManagerIF, debugIF );
        ReplayQueue replayQueue( schedulerIF, loadStoreUnitIF, mulDivUnitIF, fpDivSqrtUnitIF, cacheFlushManagerIF, recoveryManagerIF, ctrlIF );
        Scheduler scheduler( schedulerIF, wakeupSelectIF, recoveryManagerIF, mulDivUnitIF, fpDivSqrtUnitIF, debugIF );
        WakeupPipelineRegister wakeupPipelineRegister( wakeupSelectIF, recoveryManagerIF );
        DestinationRAM destinationRAM( wakeupSelectIF );
        WakeupLogic wakeupLogic( wakeupSelectIF );
        SelectLogic selectLogic( wakeupSelectIF, recoveryManagerIF );

    IntegerIssueStage intIsStage( intIsStageIF, scStageIF, schedulerIF, recoveryManagerIF, ctrlIF, debugIF );
    IntegerRegisterReadStage intRrStage( intRrStageIF, intIsStageIF, registerFileIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF );
    IntegerExecutionStage intExStage( intExStageIF, intRrStageIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF );
    IntegerRegisterWriteStage intRwStage( /*intRwStageIF,*/ intExStageIF, schedulerIF, npStageIF, registerFileIF, activeListIF, recoveryManagerIF, ctrlIF, debugIF );

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    ComplexIntegerIssueStage complexIsStage( complexIsStageIF, scStageIF, schedulerIF, recoveryManagerIF, mulDivUnitIF, ctrlIF, debugIF );
    ComplexIntegerRegisterReadStage complexRrStage( complexRrStageIF, complexIsStageIF, registerFileIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF );
    ComplexIntegerExecutionStage complexExStage( complexExStageIF, complexRrStageIF, mulDivUnitIF, schedulerIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF );
    ComplexIntegerRegisterWriteStage complexRwStage( complexExStageIF, registerFileIF, activeListIF, recoveryManagerIF, ctrlIF, debugIF );
`endif
        MulDivUnit mulDivUnit(mulDivUnitIF, recoveryManagerIF);

    // SMT: Memory backend now includes thread-aware load/store tracking
    MemoryIssueStage memIsStage( memIsStageIF, scStageIF, schedulerIF, recoveryManagerIF, mulDivUnitIF, ctrlIF, debugIF );
    MemoryRegisterReadStage memRrStage( memRrStageIF, memIsStageIF, registerFileIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF );
    
    // SMT: MemoryExecutionStage outputs dcReadTid and dcWriteTid to cache system
    MemoryExecutionStage memExStage( memExStageIF, memRrStageIF, loadStoreUnitIF, cacheFlushManagerIF, mulDivUnitIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, csrUnitIF, debugIF );
    MemoryTagAccessStage mtStage( mtStageIF, memExStageIF, schedulerIF, loadStoreUnitIF, mulDivUnitIF, recoveryManagerIF, ctrlIF, debugIF, perfCounterIF );
    MemoryAccessStage maStage( maStageIF, mtStageIF, loadStoreUnitIF, mulDivUnitIF, bypassNetworkIF, ioUnitIF, recoveryManagerIF, ctrlIF, debugIF );
        // SMT: LoadStoreUnit now tracks thread for each load/store in-flight
        // - LoadQueue stores executedLoadTid for each load
        // - StoreQueue stores executedStoreTid for each store
        // - Thread IDs are used for store-load forwarding and hazard detection
        LoadStoreUnit loadStoreUnit( loadStoreUnitIF, ctrlIF );
        LoadQueue loadQueue( loadStoreUnitIF, recoveryManagerIF );
        StoreQueue storeQueue( loadStoreUnitIF, recoveryManagerIF );
        StoreCommitter storeCommitter(loadStoreUnitIF, recoveryManagerIF, ioUnitIF, debugIF, perfCounterIF);
        
        // SMT: DCache now includes MSHR thread tracking
        // - Each MSHR entry stores the thread ID that allocated it
        // - Cache flushes are thread-selective via dcFlushTid signal
        // - MSHR allocation uses dcReadTid (loads) and dcWriteTid (stores)
        DCache dCache( loadStoreUnitIF, cacheSystemIF, ctrlIF, recoveryManagerIF);
    MemoryRegisterWriteStage memRwStage( /*memRwStageIF,*/ maStageIF, loadStoreUnitIF, registerFileIF, activeListIF, recoveryManagerIF, ctrlIF, debugIF );

`ifdef RSD_MARCH_FP_PIPE
    FPIssueStage fpIsStage( fpIsStageIF, scStageIF, schedulerIF, recoveryManagerIF, fpDivSqrtUnitIF, ctrlIF, debugIF );
    FPRegisterReadStage fpRrStage( fpRrStageIF, fpIsStageIF, registerFileIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF );
    FPExecutionStage fpExStage( fpExStageIF, fpRrStageIF, fpDivSqrtUnitIF, schedulerIF, bypassNetworkIF, recoveryManagerIF, ctrlIF, debugIF, csrUnitIF);
    FPRegisterWriteStage fpRwStage( fpExStageIF, registerFileIF, activeListIF, recoveryManagerIF, ctrlIF, debugIF );
    FPDivSqrtUnit fpDivSqrtUnit(fpDivSqrtUnitIF, recoveryManagerIF);
`endif

    RegisterFile registerFile( registerFileIF );
        BypassController bypassController( bypassNetworkIF, ctrlIF );
        BypassNetwork  bypassNetwork( bypassNetworkIF, ctrlIF );
    
    // SMT: CommitStage now implements round-robin commit arbitration between threads
    // Each thread commits independently from its partition of the Active List
    CommitStage cmStage( cmStageIF, renameLogicIF, activeListIF, loadStoreUnitIF, recoveryManagerIF, csrUnitIF, debugIF );
        // SMT: RecoveryManager now handles per-thread recovery
        // - Separate recovery state machine for each thread
        // - Thread-selective flushing based on exception/misspeculation
        RecoveryManager recoveryManager( recoveryManagerIF, activeListIF, csrUnitIF, ctrlIF, perfCounterIF );

    // SMT: CSR_Unit now maintains per-thread CSR register state
    // - Each thread has independent CSR registers (mstatus, mip, mie, etc.)
    // - CSR access is routed based on csrAccessTid signal
    CSR_Unit csrUnit(csrUnitIF, perfCounterIF);
    CacheFlushManager cacheFlushManager( cacheFlushManagerIF, cacheSystemIF );
    InterruptController interruptCtrl(csrUnitIF, ctrlIF, npStageIF, recoveryManagerIF);
    IO_Unit ioUnit(ioUnitIF, csrUnitIF);

endmodule : Core
