// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for issuing ops.
//


import BasicTypes::*;
import MicroOpTypes::*;
import PipelineTypes::*;
import ActiveListIndexTypes::*;
import SchedulerTypes::*;
import DebugTypes::*;

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE

module ComplexIntegerIssueStage(
    ComplexIntegerIssueStageIF.ThisStage port,
    ScheduleStageIF.ComplexNextStage prev,
    SchedulerIF.ComplexIntegerIssueStage scheduler,
    RecoveryManagerIF.ComplexIntegerIssueStage recovery,
    MulDivUnitIF.ComplexIntegerIssueStage mulDivUnit,
    ControllerIF.ComplexIntegerIssueStage ctrl,
    DebugIF.ComplexIntegerIssueStage debug
);

    // --- Pipeline registers
    IssueStageRegPath pipeReg [ COMPLEX_ISSUE_WIDTH ];
    IssueStageRegPath nextPipeReg [ COMPLEX_ISSUE_WIDTH ];
    always_ff@( posedge port.clk )   // synchronous rst
    begin
        if ( port.rst ) begin
            for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ )
                pipeReg[i] <= '0;
        end
        else if( !ctrl.isStage.stall )              // write data
            pipeReg <= prev.complexNextStage;
        else
            pipeReg <= nextPipeReg;
    end

    always_comb begin
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++) begin
            // SMT: Retrieve TID from Scheduler data
            ThreadID currentOpTid;
            currentOpTid = scheduler.complexIssuedData[i].tid;

            if (recovery.toRecoveryPhase[currentOpTid]) begin // SMT Array Indexing
                nextPipeReg[i].valid = pipeReg[i].valid &&
                                    !SelectiveFlushDetector(
                                        recovery.toRecoveryPhase[currentOpTid],
                                        recovery.flushRangeHeadPtr[currentOpTid],
                                        recovery.flushRangeTailPtr[currentOpTid],
                                        recovery.flushAllInsns[currentOpTid],
                                        scheduler.complexIssuedData[i].activeListPtr
                                        );
            end
            else begin
                nextPipeReg[i].valid = pipeReg[i].valid;
            end
            nextPipeReg[i].issueQueuePtr = pipeReg[i].issueQueuePtr;
        end
    end


    // Pipeline control
    logic stall, clear;
    logic flush[ COMPLEX_ISSUE_WIDTH ];
    logic valid [ COMPLEX_ISSUE_WIDTH ];
    ComplexIntegerRegisterReadStageRegPath nextStage [ COMPLEX_ISSUE_WIDTH ];
    ComplexIssueQueueEntry issuedData [ COMPLEX_ISSUE_WIDTH ];
    IssueQueueIndexPath issueQueuePtr [ COMPLEX_ISSUE_WIDTH ];
    ThreadID opTid [ COMPLEX_ISSUE_WIDTH ];

    always_comb begin

        stall = ctrl.isStage.stall;
        clear = ctrl.isStage.clear;

        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin

            if (scheduler.replay) begin
                // In this cycle, the pipeline replays ops.
                issuedData[i] = scheduler.complexReplayData[i];
                valid[i] = scheduler.complexReplayEntry[i];
            end
            else begin
                // In this cycle, the pipeline issues ops.
                issuedData[i] = scheduler.complexIssuedData[i];
                valid[i] = !stall && pipeReg[i].valid;
            end
            
            opTid[i] = issuedData[i].tid; // Extract TID

            issueQueuePtr[i] = pipeReg[i].issueQueuePtr;

            // SMT Flush Check
            flush[i] = SelectiveFlushDetector(
                        recovery.toRecoveryPhase[opTid[i]],
                        recovery.flushRangeHeadPtr[opTid[i]],
                        recovery.flushRangeTailPtr[opTid[i]],
                        recovery.flushAllInsns[opTid[i]],
                        issuedData[i].activeListPtr
                        );

            // Issue.
            scheduler.complexIssue[i] = !clear && valid[i] && !flush[i];
            scheduler.complexIssuePtr[i] = issueQueuePtr[i];

            `ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
                // Lock div units
                // SMT Note: Divider is shared. First come first served or arbitrated in MulDivUnit.
                mulDivUnit.divAcquire[i] = 
                    !clear && valid[i] &&
                    !flush[i] && issuedData[i].opType == COMPLEX_MOP_TYPE_DIV;
                mulDivUnit.acquireActiveListPtr[i] = issuedData[i].activeListPtr;
            `endif        

            // --- Pipeline ラッチ書き込み
            // リセットorフラッシュ時はNOP
            nextStage[i].valid =
                (clear || port.rst || flush[i]) ? FALSE : valid[i];
            
            // SMT: Pass TID
            nextStage[i].tid = opTid[i];

            nextStage[i].complexQueueData = issuedData[i];
            nextStage[i].replay = scheduler.replay;
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].opId = issuedData[i].opId;
`endif
        end

        port.nextStage = nextStage;

`ifndef RSD_DISABLE_DEBUG_REGISTER
        // Debug Register
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            debug.complexIsReg[i].valid = valid[i];
            debug.complexIsReg[i].flush = flush[i];
            debug.complexIsReg[i].opId = issuedData[i].opId;
        end
`endif
    end


endmodule : ComplexIntegerIssueStage

`endif