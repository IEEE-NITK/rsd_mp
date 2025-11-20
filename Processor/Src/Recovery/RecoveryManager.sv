// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Recovery Manager (SMT)
// Handles recovery state machines for multiple threads independently.
//

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;

module RecoveryManager(
    RecoveryManagerIF.RecoveryManager port,
    ActiveListIF.RecoveryManager activeList,
    CSR_UnitIF.RecoveryManager csrUnit,
    ControllerIF.RecoveryManager ctrl,
    PerformanceCounterIF.RecoveryManager perfCounter
);
    typedef struct packed
    {
        PipelinePhase phase;

        logic exceptionDetectedInCommitStage;
        AddrPath recoveredPC_FromRwStage;
        AddrPath recoveredPC_FromCommitStage;

        ExecutionState excptCause;      
        AddrPath excptCauseDataAddr;    

        ActiveListIndexPath flushRangeHeadPtr;
        ActiveListIndexPath flushRangeTailPtr;
      
        logic recoveryFromRwStage;  
        RefetchType refetchType;    

    } RecoveryManagerStatePath;
    
    // SMT: Duplicate State per Thread
    RecoveryManagerStatePath regState[NUM_THREADS];
    RecoveryManagerStatePath nextState[NUM_THREADS];

    // Internal signals
    logic toRecoveryPhase[NUM_THREADS];
    logic toCommitPhase[NUM_THREADS];
    logic refetchFromCSR[NUM_THREADS];
    PC_Path recoveredPC[NUM_THREADS];
    ActiveListIndexPath exceptionOpPtr[NUM_THREADS];
    logic exceptionDetected[NUM_THREADS];

    always_ff@(posedge port.clk) begin  // synchronous rst
        if (!port.rst) begin
            for(int t=0; t<NUM_THREADS; t++) begin
                regState[t] <= nextState[t];
            end
        end
        else begin
            for(int t=0; t<NUM_THREADS; t++) begin
                regState[t].phase <= PHASE_COMMIT;
                regState[t].flushRangeHeadPtr <= '0;
                regState[t].flushRangeTailPtr <= '0;
                regState[t].recoveryFromRwStage <= FALSE;
                regState[t].refetchType <= REFETCH_TYPE_THIS_PC;

                regState[t].exceptionDetectedInCommitStage <= '0;
                regState[t].recoveredPC_FromRwStage <= '0;
                regState[t].recoveredPC_FromCommitStage <= '0;

                regState[t].excptCause <= EXEC_STATE_NOT_FINISHED;
                regState[t].excptCauseDataAddr <= '0;
            end
        end
    end


    always_comb begin
        //
        // SMT Loop
        //
        for(int t=0; t<NUM_THREADS; t++) begin
            
            // 1. Trigger Detection
            // Check if RW stage exception targets THIS thread
            logic rw_exception_for_me;
            rw_exception_for_me = port.exceptionDetectedInRwStage && (port.exceptionTidFromRwStage == t);

            toRecoveryPhase[t] = 
                port.exceptionDetectedInCommitStage[t] || 
                rw_exception_for_me;

            if (toRecoveryPhase[t]) begin
                nextState[t].recoveryFromRwStage = rw_exception_for_me;
            end
            else begin
                nextState[t].recoveryFromRwStage = FALSE;
            end

            // 2. Return to Commit
            toCommitPhase[t] =
                (regState[t].phase == PHASE_RECOVER_1) &&  
                !(port.renameLogicRecoveryRMT[t] || port.issueQueueReturnIndex); // IQ return index global? Need check.

            nextState[t].refetchType = 
                port.exceptionDetectedInCommitStage[t] ? 
                port.refetchTypeFromCommitStage[t] : 
                port.refetchTypeFromRwStage;

            // 3. Latch Requests
            nextState[t].excptCause = port.recoveryCauseFromCommitStage[t];
            nextState[t].excptCauseDataAddr = port.faultingDataAddr; // Shared fault addr?
            nextState[t].exceptionDetectedInCommitStage = port.exceptionDetectedInCommitStage[t];
            nextState[t].recoveredPC_FromRwStage = port.recoveredPC_FromRwStage;
            nextState[t].recoveredPC_FromCommitStage = port.recoveredPC_FromCommitStage[t];

            // 4. CSR / Refetch Logic
            refetchFromCSR[t] = regState[t].refetchType inside {
                REFETCH_TYPE_NEXT_PC_TO_CSR_TARGET, REFETCH_TYPE_THIS_PC_TO_CSR_TARGET
            };
            
            // CSR Unit Interface (Arbitrated or Threaded?)
            // Assuming CSR Unit handles array inputs
            csrUnit.triggerExcpt[t] = (regState[t].phase == PHASE_RECOVER_0) && refetchFromCSR[t];
            csrUnit.excptCauseAddr[t] = ToPC_FromAddr(regState[t].recoveredPC_FromCommitStage);
            csrUnit.excptCause[t] = regState[t].excptCause;
            csrUnit.excptCauseDataAddr[t] = regState[t].excptCauseDataAddr;

            // 5. Recovered PC Calculation
            if(regState[t].phase == PHASE_RECOVER_0) begin
                if (refetchFromCSR[t]) begin
                    recoveredPC[t] = ToPC_FromAddr(csrUnit.excptTargetAddr[t]);
                end
                else begin
                    if (regState[t].refetchType == REFETCH_TYPE_THIS_PC) begin
                        recoveredPC[t] = regState[t].exceptionDetectedInCommitStage ?
                            ToPC_FromAddr(regState[t].recoveredPC_FromCommitStage) : 
                            ToPC_FromAddr(regState[t].recoveredPC_FromRwStage);
                    end
                    else if (regState[t].refetchType inside{REFETCH_TYPE_NEXT_PC, REFETCH_TYPE_STORE_NEXT_PC}) begin
                        recoveredPC[t] = regState[t].exceptionDetectedInCommitStage ?
                            ToPC_FromAddr(regState[t].recoveredPC_FromCommitStage) + INSN_BYTE_WIDTH : 
                            ToPC_FromAddr(regState[t].recoveredPC_FromRwStage) + INSN_BYTE_WIDTH;
                    end
                    else begin // REFETCH_TYPE_BRANCH_TARGET
                        recoveredPC[t] = regState[t].exceptionDetectedInCommitStage ?
                            ToPC_FromAddr(regState[t].recoveredPC_FromCommitStage) : 
                            ToPC_FromAddr(regState[t].recoveredPC_FromRwStage);
                    end
                end
            end
            else begin
                recoveredPC[t] = '0;
            end

            // 6. State Transition
            if(port.rst) begin
                nextState[t].phase = PHASE_COMMIT;
            end
            else if(regState[t].phase == PHASE_COMMIT) begin
                nextState[t].phase = toRecoveryPhase[t] ? PHASE_RECOVER_0 : PHASE_COMMIT;
            end
            else if(regState[t].phase == PHASE_RECOVER_0) begin
                nextState[t].phase = PHASE_RECOVER_1;
            end
            else begin
                nextState[t].phase = toCommitPhase[t] ? PHASE_COMMIT : regState[t].phase;
            end

            // 7. Output Assignments
            port.phase[t] = regState[t].phase;
            port.toCommitPhase[t] = toCommitPhase[t];
            port.toRecoveryPhase[t] = (regState[t].phase == PHASE_RECOVER_0);
            port.recoveryFromRwStage[t] = regState[t].recoveryFromRwStage;

            // Flush Range Calculation
            exceptionDetected[t] = port.exceptionDetectedInCommitStage[t] || rw_exception_for_me;
            // activeList needs to output exceptionOpPtr for the specific thread? 
            // Or we calculate based on head/tail.
            // Assuming activeList.exceptionOpPtr is valid for the recovering thread.
            exceptionOpPtr[t] = activeList.exceptionOpPtr; 

            nextState[t].flushRangeHeadPtr = 
                (nextState[t].refetchType inside {REFETCH_TYPE_THIS_PC, REFETCH_TYPE_THIS_PC_TO_CSR_TARGET}) ?
                    exceptionOpPtr[t] : exceptionOpPtr[t] + 1;
            
            nextState[t].flushRangeTailPtr = activeList.detectedFlushRangeTailPtr;
            
            port.flushRangeHeadPtr[t] = regState[t].flushRangeHeadPtr;
            port.flushRangeTailPtr[t] = regState[t].flushRangeTailPtr;

            port.unableToStartRecovery[t] = 
                (regState[t].phase != PHASE_COMMIT) || 
                port.renameLogicRecoveryRMT[t] || 
                port.issueQueueReturnIndex || 
                port.replayQueueFlushedOpExist || 
                port.wakeupPipelineRegFlushedOpExist;
        end 

        // Muxing Global Outputs
        // The Recovered PC for FetchStage must be selected based on which thread is recovering.
        // If both recovering? Priority to T0 or separate PCs.
        // FetchStage usually has separate PC inputs for recovery, or we arbitrate.
        // Ideally FetchStage accepts recoveredPC[NUM_THREADS].
        // For now, mapping:
        // port.recoveredPC_FromRwCommit = recoveredPC[0] | recoveredPC[1]; (Assuming one active)
        // BUT, if NextPCStage handles arrays, we pass the array.
        
        // Global Signals
        ctrl.cmStageFlushUpper = (regState[0].phase == PHASE_RECOVER_0) || (regState[1].phase == PHASE_RECOVER_0);
        
    end

endmodule : RecoveryManager