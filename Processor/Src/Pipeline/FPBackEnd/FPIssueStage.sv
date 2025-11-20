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

`ifdef RSD_MARCH_FP_PIPE

module FPIssueStage(
    FPIssueStageIF.ThisStage port,
    ScheduleStageIF.FPNextStage prev,
    SchedulerIF.FPIssueStage scheduler,
    RecoveryManagerIF.FPIssueStage recovery,
    FPDivSqrtUnitIF.FPIssueStage fpDivSqrtUnit,
    ControllerIF.FPIssueStage ctrl,
    DebugIF.FPIssueStage debug
);

    // --- Pipeline registers
    IssueStageRegPath pipeReg [ FP_ISSUE_WIDTH ];
    IssueStageRegPath nextPipeReg [ FP_ISSUE_WIDTH ];
    always_ff@( posedge port.clk )   // synchronous rst
    begin
        if ( port.rst ) begin
            for ( int i = 0; i < FP_ISSUE_WIDTH; i++ )
                pipeReg[i] <= '0;
        end
        else if( !ctrl.isStage.stall )              // write data
            pipeReg <= prev.fpNextStage;
        else
            pipeReg <= nextPipeReg;
    end

    always_comb begin
        for ( int i = 0; i < FP_ISSUE_WIDTH; i++) begin
            // SMT Update: Retrieve TID from the scheduler data.
            // Since pipeReg contains the pointer to the IQ entry, and the IQ entry 
            // contains the TID, we can read it directly from the scheduler interface.
            ThreadID currentOpTid;
            currentOpTid = scheduler.fpIssuedData[i].tid;

            if (recovery.toRecoveryPhase[currentOpTid]) begin
                nextPipeReg[i].valid = pipeReg[i].valid &&
                                    !SelectiveFlushDetector(
                                        recovery.toRecoveryPhase[currentOpTid],
                                        recovery.flushRangeHeadPtr[currentOpTid],
                                        recovery.flushRangeTailPtr[currentOpTid],
                                        recovery.flushAllInsns[currentOpTid],
                                        scheduler.fpIssuedData[i].activeListPtr
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
    logic flush[ FP_ISSUE_WIDTH ];
    logic valid [ FP_ISSUE_WIDTH ];
    FPRegisterReadStageRegPath nextStage [ FP_ISSUE_WIDTH ];
    FPIssueQueueEntry issuedData [ FP_ISSUE_WIDTH ];
    IssueQueueIndexPath issueQueuePtr [ FP_ISSUE_WIDTH ];
    ThreadID opTid [ FP_ISSUE_WIDTH ];

    always_comb begin

        stall = ctrl.isStage.stall;
        clear = ctrl.isStage.clear;

        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin

            if (scheduler.replay) begin
                // In this cycle, the pipeline replays ops.
                issuedData[i] = scheduler.fpReplayData[i];
                valid[i] = scheduler.fpReplayEntry[i];
            end
            else begin
                // In this cycle, the pipeline issues ops.
                issuedData[i] = scheduler.fpIssuedData[i];
                valid[i] = !stall && pipeReg[i].valid;
            end

            // SMT: Extract TID from the issued data structure
            opTid[i] = issuedData[i].tid;

            issueQueuePtr[i] = pipeReg[i].issueQueuePtr;

            // SMT: Check flush using specific Thread ID
            flush[i] = SelectiveFlushDetector(
                        recovery.toRecoveryPhase[opTid[i]],
                        recovery.flushRangeHeadPtr[opTid[i]],
                        recovery.flushRangeTailPtr[opTid[i]],
                        recovery.flushAllInsns[opTid[i]],
                        issuedData[i].activeListPtr
                        );

            // Issue.
            scheduler.fpIssue[i] = !clear && valid[i] && !flush[i];
            scheduler.fpIssuePtr[i] = issueQueuePtr[i];

            // Lock div units
            fpDivSqrtUnit.Acquire[i] = 
                !clear && valid[i] &&
                !flush[i] && (issuedData[i].fpOpInfo.opType inside {FP_MOP_TYPE_DIV, FP_MOP_TYPE_SQRT});
            fpDivSqrtUnit.acquireActiveListPtr[i] = issuedData[i].activeListPtr;

            // --- Pipeline ラッチ書き込み
            // リセットorフラッシュ時はNOP
            nextStage[i].valid =
                (clear || port.rst || flush[i]) ? FALSE : valid[i];
            
            // SMT: Propagate TID to next stage
            nextStage[i].tid = opTid[i];

            nextStage[i].fpQueueData = issuedData[i];
            nextStage[i].replay = scheduler.replay;
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].opId = issuedData[i].opId;
`endif
        end

        port.nextStage = nextStage;

`ifndef RSD_DISABLE_DEBUG_REGISTER
        // Debug Register
        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            debug.fpIsReg[i].valid = valid[i];
            debug.fpIsReg[i].flush = flush[i];
            debug.fpIsReg[i].opId = issuedData[i].opId;
        end
`endif
    end


endmodule : FPIssueStage

`endif