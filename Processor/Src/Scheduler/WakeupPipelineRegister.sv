// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Scheduler
//
`include "BasicMacros.sv"

import BasicTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import MicroOpTypes::*;

//
// Track issues ops. Tracked information is used for waking up and releasing entries.
//
module WakeupPipelineRegister(
    WakeupSelectIF.WakeupPipelineRegister port,
    RecoveryManagerIF.WakeupPipelineRegister recovery
);
    `RSD_STATIC_ASSERT(
        ISSUE_QUEUE_INT_LATENCY == 1, 
        "Int latency must be 1."
    );
    // Normally, the latency of INT is 1, so when ISSUE_QUEUE_INT_LATENCY is other than 1, it is not supported.
    // To make ISSUE_QUEUE_INT_LATENCY larger than 1, the following part must be changed. (Refer to the implementation of COMPLEX or MEM)
    // - update of intPipeReg.
    // - port.wakeup, port.wakeupVector 
    // - port.releaseEntry

    // Pipeline registers
    typedef struct packed
    {
        logic valid;              // Valid flag.
        IssueQueueIndexPath ptr;  // A pointer to a selected entry.
        IssueQueueOneHotPath depVector;    // A producer vector for a producer matrix.
        ActiveListIndexPath activeListPtr;     // A pointer of active list for flush
        ThreadID tid;             // SMT: Thread ID of the op
    } WakeupPipeReg;

    WakeupPipeReg intPipeReg[ INT_ISSUE_WIDTH ][ ISSUE_QUEUE_INT_LATENCY ];
    WakeupPipeReg memPipeReg[ MEM_ISSUE_WIDTH ][ ISSUE_QUEUE_MEM_LATENCY ];
    WakeupPipeReg nextIntPipeReg[ INT_ISSUE_WIDTH ];
    WakeupPipeReg nextMemPipeReg[ MEM_ISSUE_WIDTH ];

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    WakeupPipeReg complexPipeReg[ COMPLEX_ISSUE_WIDTH ][ ISSUE_QUEUE_COMPLEX_LATENCY ];
    WakeupPipeReg nextComplexPipeReg[ COMPLEX_ISSUE_WIDTH ];
    
    // SMT: Flush counters per thread
    logic [$clog2(ISSUE_QUEUE_COMPLEX_LATENCY):0] canBeFlushedRegCountComplex[NUM_THREADS];    
    logic flushComplex[ COMPLEX_ISSUE_WIDTH ];
    IssueQueueIndexPath complexSelectedPtr[ COMPLEX_ISSUE_WIDTH ];
`endif

`ifdef RSD_MARCH_FP_PIPE
    WakeupPipeReg fpPipeReg[ FP_ISSUE_WIDTH ][ ISSUE_QUEUE_FP_LATENCY ];
    WakeupPipeReg nextFPPipeReg[ FP_ISSUE_WIDTH ];
    
    // SMT: Flush counters per thread
    logic [$clog2(ISSUE_QUEUE_FP_LATENCY):0] canBeFlushedRegCountFP[NUM_THREADS];
    logic flushFP[ FP_ISSUE_WIDTH ];
    IssueQueueIndexPath fpSelectedPtr[ FP_ISSUE_WIDTH ];
`endif

    // Flushed Op detection
    // SMT: Flush counters per thread
    logic [$clog2(ISSUE_QUEUE_INT_LATENCY):0] canBeFlushedRegCountInt[NUM_THREADS];
    logic [$clog2(ISSUE_QUEUE_MEM_LATENCY):0] canBeFlushedRegCountMem[NUM_THREADS];
    
    // Flush range snapshot (Per Thread)
    ActiveListIndexPath flushRangeHeadPtr[NUM_THREADS];
    ActiveListIndexPath flushRangeTailPtr[NUM_THREADS];
    logic flushAllInsns[NUM_THREADS];
    
    logic flushInt[ INT_ISSUE_WIDTH ];
    logic flushMem[ LOAD_ISSUE_WIDTH ];
    IssueQueueIndexPath intSelectedPtr[ INT_ISSUE_WIDTH ];
    IssueQueueIndexPath memSelectedPtr[ MEM_ISSUE_WIDTH ];
    IssueQueueOneHotPath flushIQ_Entry;

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            for( int j = 0; j < ISSUE_QUEUE_INT_LATENCY; j++ ) begin
                intPipeReg[i][j].ptr <= '1;
                intPipeReg[i][j].depVector <= '1;
                intPipeReg[i][j].activeListPtr <= '1;
                intPipeReg[i][j].tid <= '0;
            end
        end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            for( int j = 0; j < ISSUE_QUEUE_COMPLEX_LATENCY; j++ ) begin
                complexPipeReg[i][j].ptr <= '1;
                complexPipeReg[i][j].depVector <= '1;
                complexPipeReg[i][j].activeListPtr <= '1;
                complexPipeReg[i][j].tid <= '0;
            end
        end
`endif

        for( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            for( int j = 0; j < ISSUE_QUEUE_MEM_LATENCY; j++ ) begin
                memPipeReg[i][j].ptr <= '1;
                memPipeReg[i][j].depVector <= '1;
                memPipeReg[i][j].activeListPtr <= '1;
                memPipeReg[i][j].tid <= '0;
            end
        end

`ifdef RSD_MARCH_FP_PIPE
        for( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            for( int j = 0; j < ISSUE_QUEUE_FP_LATENCY; j++ ) begin
                fpPipeReg[i][j].ptr <= '1;
                fpPipeReg[i][j].depVector <= '1;
                fpPipeReg[i][j].activeListPtr <= '1;
                fpPipeReg[i][j].tid <= '0;
            end
        end
`endif
    end
`endif

    // Helper to derive TID from ActiveListPtr
    function automatic ThreadID GetTidFromALPtr(ActiveListIndexPath ptr);
        // Simple static partitioning check
        // T0: 0 to N/2 - 1
        // T1: N/2 to N - 1
        if (ptr >= (ACTIVE_LIST_ENTRY_NUM / NUM_THREADS)) 
            return 1;
        else 
            return 0;
    endfunction

    always_ff @( posedge port.clk ) begin
        if( port.rst ||(recovery.toRecoveryPhase[0] && !recovery.recoveryFromRwStage[0]) || (recovery.toRecoveryPhase[1] && !recovery.recoveryFromRwStage[1])) begin
            // SMT Note: If ANY thread triggers a global-style reset (commit phase recovery), 
            // we clear the wakeup pipeline. This is conservative but safe.
            
            for( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
                for( int j = 0; j < ISSUE_QUEUE_INT_LATENCY; j++ ) begin
                    intPipeReg[i][j].valid <= FALSE;
                    intPipeReg[i][j].depVector <= '0;
                end
            end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
                for( int j = 0; j < ISSUE_QUEUE_COMPLEX_LATENCY; j++ ) begin
                    complexPipeReg[i][j].valid <= FALSE;
                    complexPipeReg[i][j].depVector <= '0;
                end
            end
`endif

            for( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
                for( int j = 0; j < ISSUE_QUEUE_MEM_LATENCY; j++ ) begin
                    memPipeReg[i][j].valid <= FALSE;
                    memPipeReg[i][j].depVector <= '0;
                end
            end

`ifdef RSD_MARCH_FP_PIPE
            for( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
                for( int j = 0; j < ISSUE_QUEUE_FP_LATENCY; j++ ) begin
                    fpPipeReg[i][j].valid <= FALSE;
                    fpPipeReg[i][j].depVector <= '0;
                end
            end
`endif
        end
        else if ( !port.stall ) begin
            // Normal operation
            for( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
                for( int j = 1; j < ISSUE_QUEUE_INT_LATENCY; j++ ) begin
                    intPipeReg[i][j-1] <= intPipeReg[i][j];
                end
                intPipeReg[i][ ISSUE_QUEUE_INT_LATENCY-1 ] <= nextIntPipeReg[i];
            end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
                for( int j = 1; j < ISSUE_QUEUE_COMPLEX_LATENCY; j++ ) begin
                    complexPipeReg[i][j-1] <= complexPipeReg[i][j];
                end
                complexPipeReg[i][ ISSUE_QUEUE_COMPLEX_LATENCY-1 ] <= nextComplexPipeReg[i];
            end
`endif

            for( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
                for( int j = 1; j < ISSUE_QUEUE_MEM_LATENCY; j++ ) begin
                    memPipeReg[i][j-1] <= memPipeReg[i][j];
                end
                memPipeReg[i][ ISSUE_QUEUE_MEM_LATENCY-1 ] <= nextMemPipeReg[i];
            end

`ifdef RSD_MARCH_FP_PIPE
            for( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
                for( int j = 1; j < ISSUE_QUEUE_FP_LATENCY; j++ ) begin
                    fpPipeReg[i][j-1] <= fpPipeReg[i][j];
                end
                fpPipeReg[i][ ISSUE_QUEUE_FP_LATENCY-1 ] <= nextFPPipeReg[i];
            end
`endif
        end
        else begin
            // Stall Logic
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
            for( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
                for( int j = 1; j < ISSUE_QUEUE_COMPLEX_LATENCY-1; j++ ) begin
                    complexPipeReg[i][j-1] <= complexPipeReg[i][j];
                end
                complexPipeReg[i][ ISSUE_QUEUE_COMPLEX_LATENCY-2 ].valid <= FALSE;
                complexPipeReg[i][ ISSUE_QUEUE_COMPLEX_LATENCY-2 ].depVector <= '0;
            end
`endif
            for( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
                for( int j = 1; j < ISSUE_QUEUE_MEM_LATENCY-1; j++ ) begin
                    memPipeReg[i][j-1] <= memPipeReg[i][j];
                end
                memPipeReg[i][ ISSUE_QUEUE_MEM_LATENCY-2 ].valid <= FALSE;
                memPipeReg[i][ ISSUE_QUEUE_MEM_LATENCY-2 ].depVector <= '0;
            end
`ifdef RSD_MARCH_FP_PIPE
            for( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
                for( int j = 1; j < ISSUE_QUEUE_FP_LATENCY-1; j++ ) begin
                    fpPipeReg[i][j-1] <= fpPipeReg[i][j];
                end
                fpPipeReg[i][ ISSUE_QUEUE_FP_LATENCY-2 ].valid <= FALSE;
                fpPipeReg[i][ ISSUE_QUEUE_FP_LATENCY-2 ].depVector <= '0;
            end
`endif
        end
    end



    always_comb begin
        // A bit vector indicating whether each IQ entry is flushed.
        flushIQ_Entry = recovery.flushIQ_Entry;
        
        //
        // Register selected ops.
        //
        for (int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            intSelectedPtr[i] = port.selectedPtr[i];
            nextIntPipeReg[i].valid = port.selected[i] && !flushIQ_Entry[intSelectedPtr[i]];
            nextIntPipeReg[i].ptr = port.selectedPtr[i];
            nextIntPipeReg[i].depVector = port.selectedVector[i] & ~flushIQ_Entry;
            nextIntPipeReg[i].activeListPtr = recovery.selectedActiveListPtr[i];
            // SMT: Derive TID
            nextIntPipeReg[i].tid = GetTidFromALPtr(recovery.selectedActiveListPtr[i]);
        end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            complexSelectedPtr[i] = port.selectedPtr[(i+INT_ISSUE_WIDTH)];
            nextComplexPipeReg[i].valid = port.selected[(i+INT_ISSUE_WIDTH)] && !flushIQ_Entry[complexSelectedPtr[i]];
            nextComplexPipeReg[i].ptr = port.selectedPtr[(i+INT_ISSUE_WIDTH)];
            nextComplexPipeReg[i].depVector = port.selectedVector[(i+INT_ISSUE_WIDTH)] & ~flushIQ_Entry;
            nextComplexPipeReg[i].activeListPtr = recovery.selectedActiveListPtr[(i+INT_ISSUE_WIDTH)];
            // SMT: Derive TID
            nextComplexPipeReg[i].tid = GetTidFromALPtr(recovery.selectedActiveListPtr[(i+INT_ISSUE_WIDTH)]);
        end
`endif

        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            memSelectedPtr[i] = port.selectedPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)];
            nextMemPipeReg[i].valid = port.selected[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] && !flushIQ_Entry[memSelectedPtr[i]];
            nextMemPipeReg[i].ptr = port.selectedPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)];
            nextMemPipeReg[i].depVector = port.selectedVector[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] & ~flushIQ_Entry;
            nextMemPipeReg[i].activeListPtr = recovery.selectedActiveListPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)];
            // SMT: Derive TID
            nextMemPipeReg[i].tid = GetTidFromALPtr(recovery.selectedActiveListPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)]);
        end

`ifdef RSD_MARCH_FP_PIPE
        for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
            fpSelectedPtr[i] = port.selectedPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)];
            nextFPPipeReg[i].valid = port.selected[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)] && !flushIQ_Entry[fpSelectedPtr[i]];
            nextFPPipeReg[i].ptr = port.selectedPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)];
            nextFPPipeReg[i].depVector = port.selectedVector[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)] & ~flushIQ_Entry;
            nextFPPipeReg[i].activeListPtr = recovery.selectedActiveListPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)];
            // SMT: Derive TID
            nextFPPipeReg[i].tid = GetTidFromALPtr(recovery.selectedActiveListPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)]);
        end
`endif

        //
        // Exit from the pipeline registers and now wakeup consumers.
        //
        for (int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            // SMT: Use the stored TID to check the correct recovery array index
            ThreadID t = intPipeReg[i][0].tid;
            
            flushInt[i] = SelectiveFlushDetector(
                            canBeFlushedRegCountInt[t] != 0,
                            flushRangeHeadPtr[t],
                            flushRangeTailPtr[t],
                            flushAllInsns[t],
                            intPipeReg[i][0].activeListPtr
                            );
            port.wakeup[i] = intPipeReg[i][0].valid && !flushInt[i] && !port.stall;
            port.wakeupPtr[i] = intPipeReg[i][0].ptr;
            port.wakeupVector[i] = !port.stall ? intPipeReg[i][0].depVector : '0;
        end

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            ThreadID t = complexPipeReg[i][0].tid;
            flushComplex[i] = SelectiveFlushDetector(
                            canBeFlushedRegCountComplex[t] != 0,
                            flushRangeHeadPtr[t],
                            flushRangeTailPtr[t],
                            flushAllInsns[t],
                            complexPipeReg[i][0].activeListPtr
                            );
            port.wakeup[(i+INT_ISSUE_WIDTH)] = complexPipeReg[i][0].valid && !flushComplex[i];
            port.wakeupPtr[(i+INT_ISSUE_WIDTH)] = complexPipeReg[i][0].ptr;
            port.wakeupVector[(i+INT_ISSUE_WIDTH)] = complexPipeReg[i][0].depVector;
        end
`endif

`ifdef RSD_MARCH_UNIFIED_LDST_MEM_PIPE
        // Store ports do not wake up consumers, thus LOAD_ISSUE_WIDTH is used.
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            ThreadID t = memPipeReg[i][0].tid;
            flushMem[i] = SelectiveFlushDetector(
                            canBeFlushedRegCountMem[t] != 0,
                            flushRangeHeadPtr[t],
                            flushRangeTailPtr[t],
                            flushAllInsns[t],
                            memPipeReg[i][0].activeListPtr
                          );
            port.wakeup[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].valid && !flushMem[i];
            port.wakeupPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].ptr;
            port.wakeupVector[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].depVector;
        end

        // Wake up an instruction that depends on the store
        for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
            port.wakeupPtr[i+WAKEUP_WIDTH] = memPipeReg[i][0].ptr;
            port.wakeupVector[i+WAKEUP_WIDTH] = memPipeReg[i][0].depVector;
        end
`else
        for (int i = 0; i < LOAD_ISSUE_WIDTH; i++) begin
            ThreadID t = memPipeReg[i][0].tid;
            flushMem[i] = SelectiveFlushDetector(
                            canBeFlushedRegCountMem[t] != 0,
                            flushRangeHeadPtr[t],
                            flushRangeTailPtr[t],
                            flushAllInsns[t],
                            memPipeReg[i][0].activeListPtr
                            );
            port.wakeup[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].valid && !flushMem[i];
            port.wakeupPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].ptr;
            port.wakeupVector[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].depVector;
        end
        for (int i = 0; i < MEM_ISSUE_WIDTH - LOAD_ISSUE_WIDTH; i++) begin
            port.wakeupPtr[i+WAKEUP_WIDTH] = memPipeReg[i+LOAD_ISSUE_WIDTH][0].ptr;
            port.wakeupVector[i+WAKEUP_WIDTH] = memPipeReg[i+LOAD_ISSUE_WIDTH][0].depVector;
        end
`endif

`ifdef RSD_MARCH_FP_PIPE
        for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
            ThreadID t = fpPipeReg[i][0].tid;
            flushFP[i] = SelectiveFlushDetector(
                            canBeFlushedRegCountFP[t] != 0,
                            flushRangeHeadPtr[t],
                            flushRangeTailPtr[t],
                            flushAllInsns[t],
                            fpPipeReg[i][0].activeListPtr
                            );
            port.wakeup[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+LOAD_ISSUE_WIDTH)] = fpPipeReg[i][0].valid && !flushFP[i];
            port.wakeupPtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+LOAD_ISSUE_WIDTH)] = fpPipeReg[i][0].ptr;
            port.wakeupVector[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+LOAD_ISSUE_WIDTH)] = fpPipeReg[i][0].depVector;
        end
`endif

    end

    // To an issue queue.
    always_comb begin
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            port.releaseEntry[i] = intPipeReg[i][0].valid && !port.stall;
            port.releasePtr[i] = intPipeReg[i][0].ptr;
        end
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for (int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            port.releaseEntry[(i+INT_ISSUE_WIDTH)] = complexPipeReg[i][0].valid;
            port.releasePtr[(i+INT_ISSUE_WIDTH)] = complexPipeReg[i][0].ptr;
        end
`endif
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            port.releaseEntry[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].valid;
            port.releasePtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH)] = memPipeReg[i][0].ptr;
        end
`ifdef RSD_MARCH_FP_PIPE
        for (int i = 0; i < FP_ISSUE_WIDTH; i++) begin
            port.releaseEntry[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)] = fpPipeReg[i][0].valid;
            port.releasePtr[(i+INT_ISSUE_WIDTH+COMPLEX_ISSUE_WIDTH+MEM_ISSUE_WIDTH)] = fpPipeReg[i][0].ptr;
        end
`endif
    end

    // Flush Counter Logic (SMT Updated)
    always_ff @( posedge port.clk ) begin
        if(port.rst) begin
            for(int t=0; t<NUM_THREADS; t++) begin
                canBeFlushedRegCountInt[t] <= 0;
                canBeFlushedRegCountMem[t] <= 0;
                flushRangeHeadPtr[t] <= 0;
                flushRangeTailPtr[t] <= 0;
                flushAllInsns[t] <= FALSE;
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
                canBeFlushedRegCountComplex[t] <= 0;
`endif
`ifdef RSD_MARCH_FP_PIPE
                canBeFlushedRegCountFP[t] <= 0;
`endif
            end
        end
        else begin
            for(int t=0; t<NUM_THREADS; t++) begin
                // Check if THIS thread is recovering from RW stage
                if(recovery.toRecoveryPhase[t] && recovery.recoveryFromRwStage[t]) begin
                    canBeFlushedRegCountInt[t] <= ISSUE_QUEUE_INT_LATENCY;
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
                    canBeFlushedRegCountComplex[t] <= ISSUE_QUEUE_COMPLEX_LATENCY;
`endif
                    canBeFlushedRegCountMem[t] <= ISSUE_QUEUE_MEM_LATENCY;
`ifdef RSD_MARCH_FP_PIPE
                    canBeFlushedRegCountFP[t] <= ISSUE_QUEUE_FP_LATENCY;
`endif
                    flushRangeHeadPtr[t] <= recovery.flushRangeHeadPtr[t];
                    flushRangeTailPtr[t] <= recovery.flushRangeTailPtr[t];
                    flushAllInsns[t] <= recovery.flushAllInsns[t];
                end
                else begin
                    // Decrement counters normally
                    if (canBeFlushedRegCountInt[t] > 0 && !port.stall) 
                        canBeFlushedRegCountInt[t] <= canBeFlushedRegCountInt[t]-1;
                        
                    if (canBeFlushedRegCountMem[t] > 0 && !port.stall)
                        canBeFlushedRegCountMem[t] <= canBeFlushedRegCountMem[t]-1;

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
                    if (canBeFlushedRegCountComplex[t] > 0 && !port.stall)
                        canBeFlushedRegCountComplex[t] <= canBeFlushedRegCountComplex[t]-1;
`endif
`ifdef RSD_MARCH_FP_PIPE
                    if (canBeFlushedRegCountFP[t] > 0 && !port.stall)
                        canBeFlushedRegCountFP[t] <= canBeFlushedRegCountFP[t]-1;
`endif
                end
            end
        end
    end

    // Output to Recovery Manager
    // Aggregate: If ANY thread has ops to flush, signal TRUE. 
    // This is conservative and safe.
    always_comb begin
        recovery.wakeupPipelineRegFlushedOpExist = FALSE;
        for(int t=0; t<NUM_THREADS; t++) begin
            if (canBeFlushedRegCountInt[t] != 0 || 
                canBeFlushedRegCountMem[t] != 0 
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
                || canBeFlushedRegCountComplex[t] != 0 
`endif
`ifdef RSD_MARCH_FP_PIPE
                || canBeFlushedRegCountFP[t] != 0 
`endif
               ) begin
               recovery.wakeupPipelineRegFlushedOpExist = TRUE;
            end
        end
    end

endmodule : WakeupPipelineRegister