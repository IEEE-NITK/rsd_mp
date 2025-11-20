// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for issuing ops.
//

import BasicTypes::*;
import MicroOpTypes::*;
import PipelineTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import DebugTypes::*;

module IntegerIssueStage(
    IntegerIssueStageIF.ThisStage port,
    ScheduleStageIF.IntNextStage prev,
    SchedulerIF.IntegerIssueStage scheduler,
    RecoveryManagerIF.IntegerIssueStage recovery,
    ControllerIF.IntegerIssueStage ctrl,
    DebugIF.IntegerIssueStage debug
);

    // --- Pipeline registers
    IssueStageRegPath pipeReg [ INT_ISSUE_WIDTH ];
    IssueStageRegPath nextPipeReg [ INT_ISSUE_WIDTH ];
    always_ff@( posedge port.clk )   // synchronous rst
    begin
        if ( port.rst ) begin
            for ( int i = 0; i < INT_ISSUE_WIDTH; i++ )
                pipeReg[i] <= '0;
        end
        else if( !ctrl.isStage.stall )              // write data
            pipeReg <= prev.intNextStage;
        else
            pipeReg <= nextPipeReg;
    end

    always_comb begin
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            // SMT: Retrieve TID from Scheduler data (since IssueStageRegPath doesn't carry it)
            ThreadID currentOpTid;
            currentOpTid = scheduler.intIssuedData[i].tid;
            
            if (recovery.toRecoveryPhase[currentOpTid]) begin // SMT Array Indexing
                nextPipeReg[i].valid = pipeReg[i].valid &&
                                    !SelectiveFlushDetector(
                                        recovery.toRecoveryPhase[currentOpTid],
                                        recovery.flushRangeHeadPtr[currentOpTid],
                                        recovery.flushRangeTailPtr[currentOpTid],
                                        recovery.flushAllInsns[currentOpTid],
                                        scheduler.intIssuedData[i].activeListPtr
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
    logic flush[ INT_ISSUE_WIDTH ];
    logic valid [ INT_ISSUE_WIDTH ];
    IntegerRegisterReadStageRegPath nextStage [ INT_ISSUE_WIDTH ];
    IntIssueQueueEntry issuedData [ INT_ISSUE_WIDTH ];
    IssueQueueIndexPath issueQueuePtr [ INT_ISSUE_WIDTH ];
    ThreadID opTid [ INT_ISSUE_WIDTH ];

    always_comb begin

        stall = ctrl.isStage.stall;
        clear = ctrl.isStage.clear;

        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin

            if (scheduler.replay) begin
                // In this cycle, the pipeline replays ops.
                issuedData[i] = scheduler.intReplayData[i];
                valid[i] = scheduler.intReplayEntry[i];
            end
            else begin
                // In this cycle, the pipeline issues ops.
                issuedData[i] = scheduler.intIssuedData[i];
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
            scheduler.intIssue[i] = !clear && valid[i] && !flush[i];
            scheduler.intIssuePtr[i] = issueQueuePtr[i];

            // --- Pipeline ラッチ書き込み
            // リセットorフラッシュ時はNOP
            nextStage[i].valid =
                (clear || port.rst || flush[i]) ? FALSE : valid[i];
            
            // SMT: Propagate TID
            nextStage[i].tid = opTid[i];
            nextStage[i].intQueueData = issuedData[i];

`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].opId = issuedData[i].opId;
`endif
        end

        port.nextStage = nextStage;

`ifndef RSD_DISABLE_DEBUG_REGISTER
        // Debug Register
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            debug.intIsReg[i].valid = valid[i];
            debug.intIsReg[i].flush = flush[i];
            debug.intIsReg[i].opId = issuedData[i].opId;
        end
`endif
    end


endmodule : IntegerIssueStage