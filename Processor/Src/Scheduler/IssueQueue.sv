// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// IssueQueue ( Allocator and payloadRAM )
//

`include "BasicMacros.sv"

import BasicTypes::*;
import PipelineTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import RenameLogicTypes::*;

module IssueQueue (
    SchedulerIF.IssueQueue port,
    WakeupSelectIF.IssueQueue wakeupSelect,
    RecoveryManagerIF.IssueQueue recovery,
    DebugIF.IssueQueue debug
);

    //
    // Issue queue allocator
    //

    // A free list for an issue queue entries.
    // Both its index and values have the same bit width, because
    // the sizes of an issue queue and its free list are same.
    logic releaseEntry [ ISSUE_WIDTH + ISSUE_QUEUE_RETURN_INDEX_WIDTH ];
    IssueQueueIndexPath releasePtr [ ISSUE_WIDTH + ISSUE_QUEUE_RETURN_INDEX_WIDTH ];
    IssueQueueCountPath freeListCount;
    logic freeListReset;
    logic [ ISSUE_QUEUE_RESET_CYCLE_BIT_SIZE-1 : 0 ] freeListResetCycleCount;

    // 選択的フラッシュ検出
    ActiveListIndexPath alPtrReg [ ISSUE_QUEUE_ENTRY_NUM ];  //IssueQueueのActivlistPtrのフィールドを複製したレジスタ

    // SMT: Shadow Register for TID to allow simultaneous flush checking
    ThreadID tidReg [ ISSUE_QUEUE_ENTRY_NUM ];

    logic [ ISSUE_QUEUE_ENTRY_NUM-1:0 ] flush;   //フラッシュされるべきエントリの信号(例外命令AL中で後方にあるエントリ)
    logic [ ISSUE_QUEUE_ENTRY_NUM-1:0 ] prevFlushAtRecovery;  //フリーリストにフラッシュされたインデックスを返却するためのレジスタ
    logic issueQueueReturnIndex;    //フリーリストにインデックスを返却中かどうか
    logic [ ISSUE_QUEUE_RETURN_INDEX_CYCLE_BIT_SIZE-1:0 ] issueQueueReturnIndexCycleCount;
    IssueQueueIndexPath returnIndexOffset;//フラッシュの判定をした後にIQのフリーリストへの返却用インデックス
    logic triggerReturnIndex;

    IssueQueueIndexPath writePtr[ DISPATCH_WIDTH ];
    IssueQueueIndexPath selectedPtr [ ISSUE_WIDTH ];

    // SMT: Trigger reset if ANY thread recovers from RW stage
    logic triggerReset;
    always_comb begin
        // default
        triggerReset = FALSE;
        for(int t=0; t<NUM_THREADS; t++) begin
             if(recovery.toRecoveryPhase[t] && !recovery.recoveryFromRwStage[t])
                 triggerReset = TRUE;
        end
    end

    MultiWidthFreeList #(
        .SIZE( ISSUE_QUEUE_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( ISSUE_QUEUE_ENTRY_NUM_BIT_WIDTH ),
        .PUSH_WIDTH( ISSUE_WIDTH + ISSUE_QUEUE_RETURN_INDEX_WIDTH ),
        .POP_WIDTH( RENAME_WIDTH ),
        .INITIAL_LENGTH (ISSUE_QUEUE_ENTRY_NUM)
    ) issueQueueFreeList (
            .clk( port.clk ),
            .rst( port.rst || freeListReset ),
            .rstStart( port.rstStart ),
            .count( freeListCount ),

            .pop( port.allocate ),
            .poppedData( port.allocatedPtr ),

            .push( releaseEntry ),
            .pushedData( releasePtr )
        );

    always_comb begin
        // --- Defaults to avoid inferred latches ------------------------------
        port.allocatable = FALSE;
        // default the release arrays to safe values
        for (int i = 0; i < ISSUE_WIDTH + ISSUE_QUEUE_RETURN_INDEX_WIDTH; i++) begin
            releaseEntry[i] = FALSE;
            releasePtr[i] = '0;
        end
        // --------------------------------------------------------------------

        // Allocate
        // freeListReset がアサートされているリセット中に，
        // 新しくエントリを確保させるとキューがこわれるのでブロックする
        port.allocatable = (!freeListReset && freeListCount >= RENAME_WIDTH) ? TRUE : FALSE;

        // Release
        for ( int i = 0; i < ISSUE_WIDTH; i++ ) begin
            releasePtr[i] = wakeupSelect.releasePtr[i];
            releaseEntry[i] = wakeupSelect.releaseEntry[i];
        end
        for ( int i = 0; i < ISSUE_QUEUE_RETURN_INDEX_WIDTH; i++ ) begin
            if ( issueQueueReturnIndex && prevFlushAtRecovery[returnIndexOffset+i] ) begin
                releaseEntry[ ISSUE_WIDTH + i ] = TRUE;
                releasePtr[ ISSUE_WIDTH + i ] = returnIndexOffset + i;
            end
            else begin
                releaseEntry[ ISSUE_WIDTH + i ] = FALSE;
                //Don't care - still assign deterministic value
                releasePtr[ ISSUE_WIDTH + i ] = returnIndexOffset + i;
            end
        end
    end

    // Reset(when recovery at commit occurs)
    always_ff @( posedge port.clk ) begin
        if ( port.rst ) begin
            freeListReset <= FALSE;
            freeListResetCycleCount <= 0;
        end
        else if ( triggerReset ) begin
            // Start of reset sequence
            freeListReset <= TRUE;
            freeListResetCycleCount <= 0;
        end
        else if ( freeListResetCycleCount == ISSUE_QUEUE_RESET_CYCLE - 1 ) begin
            // End of reset sequence
            freeListReset <= FALSE;
            freeListResetCycleCount <= 0;
        end
        else begin
            freeListReset <= freeListReset;
            freeListResetCycleCount <= freeListResetCycleCount + 1;
        end
    end


    //
    // Issue queue (payload ram).
    //
    IssueQueueIndexPath    intIssuePtr       [ INT_ISSUE_WIDTH ];
    IssueQueueIndexPath    memIssuePtr       [ MEM_ISSUE_WIDTH ];
    IntIssueQueueEntry     intIssuedData     [ INT_ISSUE_WIDTH ];
    MemIssueQueueEntry     memIssuedData     [ MEM_ISSUE_WIDTH ];

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    IssueQueueIndexPath    complexIssuePtr   [ COMPLEX_ISSUE_WIDTH ];
    ComplexIssueQueueEntry complexIssuedData [ COMPLEX_ISSUE_WIDTH ];
`endif
`ifdef RSD_MARCH_FP_PIPE
    IssueQueueIndexPath    fpIssuePtr   [ FP_ISSUE_WIDTH ];
    FPIssueQueueEntry      fpIssuedData [ FP_ISSUE_WIDTH ];
`endif


    DistributedMultiPortRAM #(
        .ENTRY_NUM( ISSUE_QUEUE_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( $bits( IntIssueQueueEntry ) ),
        .READ_NUM( INT_ISSUE_WIDTH ),
        .WRITE_NUM( DISPATCH_WIDTH )
    ) intPayloadRAM (
        .clk( port.clk ),
        .we( port.write ),
        .wa( port.writePtr ),
        .wv( port.intWriteData ),
        .ra( intIssuePtr ),
        .rv( intIssuedData )
    );

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    DistributedMultiPortRAM #(
        .ENTRY_NUM( ISSUE_QUEUE_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( $bits( ComplexIssueQueueEntry ) ),
        .READ_NUM( COMPLEX_ISSUE_WIDTH ),
        .WRITE_NUM( DISPATCH_WIDTH )
    ) complexPayloadRAM (
        .clk( port.clk ),
        .we( port.write ),
        .wa( port.writePtr ),
        .wv( port.complexWriteData ),
        .ra( complexIssuePtr ),
        .rv( complexIssuedData )
    );
`endif

    DistributedMultiPortRAM #(
        .ENTRY_NUM( ISSUE_QUEUE_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( $bits( MemIssueQueueEntry ) ),
        .READ_NUM( MEM_ISSUE_WIDTH ),
        .WRITE_NUM( DISPATCH_WIDTH )
    ) memPayloadRAM (
        .clk( port.clk ),
        .we( port.write ),
        .wa( port.writePtr ),
        .wv( port.memWriteData ),
        .ra( memIssuePtr ),
        .rv( memIssuedData )
    );

`ifdef RSD_MARCH_FP_PIPE
    DistributedMultiPortRAM #(
        .ENTRY_NUM( ISSUE_QUEUE_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( $bits( FPIssueQueueEntry ) ),
        .READ_NUM( FP_ISSUE_WIDTH ),
        .WRITE_NUM( DISPATCH_WIDTH )
    ) fpPayloadRAM (
        .clk( port.clk ),
        .we( port.write ),
        .wa( port.writePtr ),
        .wv( port.fpWriteData ),
        .ra( fpIssuePtr ),
        .rv( fpIssuedData )
    );
`endif


    always_comb begin
        // defaults to avoid latches
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            intIssuePtr[i] = '0;
            port.intIssuedData[i] = '0;
        end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            complexIssuePtr[i] = '0;
            port.complexIssuedData[i] = '0;
        end
`endif
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            memIssuePtr[i] = '0;
            port.memIssuedData[i] = '0;
        end
`ifdef RSD_MARCH_FP_PIPE
        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            fpIssuePtr[i] = '0;
            port.fpIssuedData[i] = '0;
        end
`endif

        // then copy actual values
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            intIssuePtr[i] = port.intIssuePtr[i];
            port.intIssuedData[i] = intIssuedData[i];
        end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            complexIssuePtr[i] = port.complexIssuePtr[i];
            port.complexIssuedData[i] = complexIssuedData[i];
        end
`endif
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            memIssuePtr[i] = port.memIssuePtr[i];
            port.memIssuedData[i] = memIssuedData[i];
        end
`ifdef RSD_MARCH_FP_PIPE
        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            fpIssuePtr[i] = port.fpIssuePtr[i];
            port.fpIssuedData[i] = fpIssuedData[i];
        end
`endif
    end


    //以下は選択的フラッシュのための機構
`ifndef RSD_SYNTHESIS
    initial begin
        for (int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++) begin
            alPtrReg[i]<='0;
            tidReg[i] <= 0;
        end
    end
`endif

    //alPtrRegにIssueQueueの各エントリのActiveListPtrを複製しておく
    // SMT: Also duplicate TID in tidReg
    always_ff @( posedge port.clk ) begin
        for ( int i = 0; i < DISPATCH_WIDTH; i++ ) begin
            if ( port.write[i] ) begin
                alPtrReg[ writePtr[i] ] <= port.writeAL_Ptr[i];
                // SMT: Capture TID from one of the write data structures
                // (Assuming TID is consistent across Int/Mem/etc entries for the same dispatch slot)
                tidReg[ writePtr[i] ] <= port.intWriteData[i].tid;
            end
        end
    end

    //WakeupPipelineRegisterにおいてフラッシュされた命令が後続にブロードキャストされないための判定に使う
    always_comb begin
        // default
        for ( int i = 0; i < ISSUE_WIDTH; i++ ) recovery.selectedActiveListPtr[i] = '0;

        for ( int i = 0; i < ISSUE_WIDTH; i++ ) begin
            recovery.selectedActiveListPtr[i] = alPtrReg[ selectedPtr[i] ];
        end
    end

    //synopsysの合成においてインターフェースの配列を直接使うのが怪しいので一度変数に落とす
    always_comb begin
        // defaults
        for (int i = 0; i < DISPATCH_WIDTH; i++) writePtr[i] = '0;
        for (int i = 0; i < ISSUE_WIDTH; i++) selectedPtr[i] = '0;

        writePtr = port.writePtr;
        selectedPtr = recovery.selectedPtr;
    end

    //例外が発生したとき, IssueQueueの各エントリに対してフラッシュを行うかどうかを判定する
    //また, dispatchステージにある命令はすでにリネームステージでIssueQueueをアロケートしているのでそれもここで判定をする
      // Flush evaluation and assign recovery outputs (explicit defaults to avoid latches)
    always_comb begin
        // ---------- defaults (must set everything used in this combinational block) ----------
        // default flush for all entries (explicitly zero every element)
        for ( int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++ ) begin
            flush[i] = 1'b0;
        end

        // default recovery outputs
        // If recovery.flushIQ_Entry is an unpacked array this aggregate sets every element to zero.
        recovery.flushIQ_Entry = '{default: '0};
        recovery.issueQueueReturnIndex = 1'b0;
        // ------------------------------------------------------------------------------------

        // Compute flush for entries already in the IQ (use tidReg to determine thread owner)
        for ( int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++ ) begin
            // Note: this matches single-thread semantics because tidReg[i] will be 0 when only one thread.
            flush[i] = SelectiveFlushDetector(
                        (recovery.toRecoveryPhase[ tidReg[i] ] && recovery.notIssued[i]),
                        recovery.flushRangeHeadPtr[ tidReg[i] ],
                        recovery.flushRangeTailPtr[ tidReg[i] ],
                        recovery.flushAllInsns[ tidReg[i] ],
                        alPtrReg[i]
                        );
        end

        // Compute flush for dispatched ops that have allocated an IQ entry but are not activated yet
        for (int d = 0; d < DISPATCH_WIDTH; d++ ) begin
            if ( port.allocated[d] ) begin
                // use direct expressions for thread and ptr values
                // defensive: ensure index is within range to avoid accidental out-of-bounds in simulation
                if ( writePtr[d] < ISSUE_QUEUE_ENTRY_NUM ) begin
                    flush[ writePtr[d] ] = SelectiveFlushDetector(
                                recovery.toRecoveryPhase[ port.intWriteData[d].tid ],
                                recovery.flushRangeHeadPtr[ port.intWriteData[d].tid ],
                                recovery.flushRangeTailPtr[ port.intWriteData[d].tid ],
                                recovery.flushAllInsns[ port.intWriteData[d].tid ],
                                port.writeAL_Ptr[d]
                                );
                end
            end
        end

        // Final outputs: broadcast the computed flush vector and issueQueueReturnIndex
        recovery.flushIQ_Entry = flush;
        recovery.issueQueueReturnIndex = issueQueueReturnIndex || freeListReset;
    end


    always_ff @ (posedge port.clk) begin
        if (port.rst || triggerReturnIndex) begin
            returnIndexOffset <= 0;
        end
        else if ( returnIndexOffset >= ISSUE_QUEUE_ENTRY_NUM - ISSUE_QUEUE_RETURN_INDEX_WIDTH ) begin
            returnIndexOffset <= 0;
        end
        else begin
            returnIndexOffset <= returnIndexOffset + ISSUE_QUEUE_RETURN_INDEX_WIDTH;
        end
    end

    //
    // OpId for Debug
    //
    `ifndef RSD_DISABLE_DEBUG_REGISTER
        OpId opId[ ISSUE_QUEUE_ENTRY_NUM ];
        always_ff @( posedge port.clk ) begin
            if( port.rst ) begin
                for( int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++ ) begin
                    opId[i].sid <= 0;
                    opId[i].mid <= 0;
                end
            end
            else begin
                // Dispatch
                for ( int i = 0; i < DISPATCH_WIDTH; i++ ) begin
                    if( port.write[i] ) begin
                        opId[ writePtr[i] ] <= port.intWriteData[i].opId;
                    end
                end
            end
        end

        always_comb begin
            for ( int i = 0; i < ISSUE_QUEUE_ENTRY_NUM; i++ ) begin
                debug.issueQueue[i].flush = flush[i];
                debug.issueQueue[i].opId = opId[i];
            end
        end
    `endif

endmodule : IssueQueue
