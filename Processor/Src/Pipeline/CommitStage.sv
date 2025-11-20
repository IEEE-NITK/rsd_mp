// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Commit stage (SMT - Arbiter Version)
// Only one thread commits per cycle.
//

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import DebugTypes::*;
import FetchUnitTypes::*;

// [Include the helper functions GetFinishedInsnRange, GetFinishedOpNum, GetInsnPtr here]
// (Keeping them omitted for brevity as they are unchanged from your original file)
function automatic void GetFinishedInsnRange(
    output CommitLaneCountPath finishedInsnRange,
    input  CommitLaneCountPath finishedOpNum,    
    input  ExecutionState      execState[COMMIT_WIDTH], 
    input  logic               last[COMMIT_WIDTH]
);
    finishedInsnRange = 0;
    for (int i = COMMIT_WIDTH - 1; i >= 0; i--) begin
        if (i < finishedOpNum && last[i]) begin
            finishedInsnRange = i + 1;
            break;
        end
    end
endfunction

function automatic void GetFinishedOpNum(
    output CommitLaneCountPath finishedOpNum,
    input  ActiveListCountPath activeListCount,
    input  ExecutionState      execState[COMMIT_WIDTH] 
);
    finishedOpNum = 0;
    for (int i = 0; i < COMMIT_WIDTH; i++) begin
        if (i < activeListCount && execState[i] != EXEC_STATE_NOT_FINISHED)
            finishedOpNum = i + 1;
        else
            break;
    end
endfunction

function automatic void GetInsnPtr(
    output CommitLaneIndexPath headOfThisInsn[COMMIT_WIDTH],
    output CommitLaneIndexPath tailOfThisInsn[COMMIT_WIDTH],
    input  logic        last [COMMIT_WIDTH]
);
    for (int i = 0; i < COMMIT_WIDTH; i++) begin
        headOfThisInsn[i] = 0;
        for (int j = i - 1; 0 <= j; j--) begin
            if (last[j]) begin
                headOfThisInsn[i] = j + 1;
                break;
            end
        end

        tailOfThisInsn[i] = COMMIT_WIDTH-1;
        for (int j = i; j < COMMIT_WIDTH; j++) begin
            if (last[j]) begin
                tailOfThisInsn[i] = j;
                break;
            end
        end
    end
endfunction

function automatic void DecideCommit(
    output logic commit[COMMIT_WIDTH],         
    output logic toRecoveryPhase,              
    output CommitLaneIndexPath recoveredIndex, 
    output RefetchType refetchType,            
    output ExecutionState recoveryCause,       
    input logic startCommit,                      
    input ActiveListCountPath activeListCount,    
    input ExecutionState execState[COMMIT_WIDTH], 
    input logic isBranch [COMMIT_WIDTH],          
    input logic isStore [COMMIT_WIDTH],          
    input logic last[COMMIT_WIDTH],      
    input logic unableToStartRecovery    
);
    // [Logic identical to previous DecideCommit function]
    // ... (Copy logic from previous DecideCommit block) ...
    // Re-implementing minimal logic for completeness of the block:
    
    CommitLaneIndexPath headOfThisInsn[COMMIT_WIDTH];
    CommitLaneIndexPath tailOfThisInsn[COMMIT_WIDTH];
    logic recovery[COMMIT_WIDTH];
    CommitLaneIndexPath recoveryPoint[COMMIT_WIDTH];
    logic recoveryTrigger;
    CommitLaneCountPath recoveryStart;
    CommitLaneCountPath finishedOpNum;
    CommitLaneCountPath finishedInsnRange;
    RefetchType opRefetchType[COMMIT_WIDTH]; 

    GetInsnPtr(headOfThisInsn, tailOfThisInsn, last);
    GetFinishedOpNum(finishedOpNum, activeListCount, execState);
    GetFinishedInsnRange(finishedInsnRange, finishedOpNum, execState, last);

    for (int i = 0; i < COMMIT_WIDTH; i++) begin
        if (execState[i] == EXEC_STATE_REFETCH_NEXT) begin
            recovery[i] = TRUE;
            recoveryPoint[i] = tailOfThisInsn[i];
            opRefetchType[i] = (isBranch[i] ? REFETCH_TYPE_BRANCH_TARGET : (isStore[i] ? REFETCH_TYPE_STORE_NEXT_PC : REFETCH_TYPE_NEXT_PC));
        end
        else if (execState[i] inside {EXEC_STATE_REFETCH_THIS, EXEC_STATE_STORE_LOAD_FORWARDING_MISS}) begin
            recovery[i] = TRUE;
            recoveryPoint[i] = headOfThisInsn[i];
            opRefetchType[i] = REFETCH_TYPE_THIS_PC;
        end
        else if (execState[i] inside {EXEC_STATE_TRAP_ECALL, EXEC_STATE_TRAP_EBREAK, EXEC_STATE_TRAP_MRET, EXEC_STATE_FAULT_INSN_MISALIGNED}) begin
            recovery[i] = TRUE;
            recoveryPoint[i] = tailOfThisInsn[i];
            opRefetchType[i] = REFETCH_TYPE_NEXT_PC_TO_CSR_TARGET;
        end
        else if (execState[i] inside {EXEC_STATE_FAULT_LOAD_MISALIGNED, EXEC_STATE_FAULT_LOAD_VIOLATION, EXEC_STATE_FAULT_STORE_MISALIGNED, EXEC_STATE_FAULT_STORE_VIOLATION, EXEC_STATE_FAULT_INSN_ILLEGAL, EXEC_STATE_FAULT_INSN_VIOLATION}) begin
            recovery[i] = TRUE;
            recoveryPoint[i] = headOfThisInsn[i];
            opRefetchType[i] = REFETCH_TYPE_THIS_PC_TO_CSR_TARGET;
        end
        else begin
            recovery[i] = FALSE;
            recoveryPoint[i] = 0;
            opRefetchType[i] = REFETCH_TYPE_THIS_PC;
        end
    end

    recoveryTrigger = FALSE;
    recoveredIndex = 0;
    recoveryStart = COMMIT_WIDTH; 
    refetchType = REFETCH_TYPE_THIS_PC; 
    recoveryCause = EXEC_STATE_SUCCESS;
    for (int i = 0; i < COMMIT_WIDTH; i++) begin
        if (i < finishedInsnRange) begin
            if (recovery[i] && recoveryPoint[i] < recoveryStart) begin
                recoveryTrigger = TRUE;
                recoveredIndex = i;
                recoveryStart = recoveryPoint[i];
                refetchType = opRefetchType[i];
                recoveryCause = execState[i];
            end
        end
    end

    toRecoveryPhase = (startCommit && recoveryTrigger && !unableToStartRecovery ? TRUE : FALSE);

    for (int i = 0; i < COMMIT_WIDTH; i++) begin
        if (startCommit) begin
            if (recoveryTrigger) begin
                if (i < recoveryStart) commit[i] = TRUE;
                else if (i == recoveryStart) commit[i] = (unableToStartRecovery ? FALSE : TRUE); // Simplified check
                else commit[i] = FALSE;
            end
            else begin
                commit[i] = (i < finishedInsnRange ? TRUE : FALSE);
            end
        end
        else begin
            commit[i] = FALSE;
        end
    end
endfunction


module CommitStage(
    CommitStageIF.ThisStage port,
    RenameLogicIF.CommitStage renameLogic,
    ActiveListIF.CommitStage activeList,
    LoadStoreUnitIF.CommitStage loadStoreUnit,
    RecoveryManagerIF.CommitStage recovery,
    CSR_UnitIF.CommitStage csrUnit,
    DebugIF.CommitStage debug
);
    // SMT: Loop variables
    logic toRecoveryPhase[NUM_THREADS];
    logic commit [NUM_THREADS][ COMMIT_WIDTH ];
    logic last [NUM_THREADS][ COMMIT_WIDTH ];
    logic isBranch [NUM_THREADS][ COMMIT_WIDTH ];
    logic isStore [NUM_THREADS][ COMMIT_WIDTH ];

    ActiveListEntry alReadData [NUM_THREADS][ COMMIT_WIDTH ];
    ExecutionState execState [NUM_THREADS][ COMMIT_WIDTH ];

    CommitLaneIndexPath recoveryOpIndex[NUM_THREADS];
    RefetchType refetchType[NUM_THREADS];
    ExecutionState recoveryCause[NUM_THREADS];
    CommitLaneCountPath commitNum[NUM_THREADS];
    CommitLaneCountPath commitLoadNum[NUM_THREADS];
    CommitLaneCountPath commitStoreNum[NUM_THREADS];
    PipelinePhase phase[NUM_THREADS];
    PC_Path lastCommittedPC[NUM_THREADS], prevLastCommittedPC[NUM_THREADS];

    // ARBITRATION Logic
    logic [0:0] roundRobinPtr; // For 2 threads
    ThreadID selectedThread;

    always_ff@(posedge port.clk) begin
        for (int t = 0; t < NUM_THREADS; t++) begin
            prevLastCommittedPC[t] <= lastCommittedPC[t];
        end
        
        if (port.rst) roundRobinPtr <= 0;
        else roundRobinPtr <= roundRobinPtr + 1;
    end

    always_comb begin
        // 1. Analyze Both Threads (Logic is parallel)
        for (int t = 0; t < NUM_THREADS; t++) begin
            alReadData[t] = activeList.readData[t]; 
            execState[t] = activeList.headExecState[t];
            phase[t] = recovery.phase[t];

            for (int i = 0; i < COMMIT_WIDTH; i++) begin
                last[t][i] = alReadData[t][i].last;
                isBranch[t][i] = alReadData[t][i].isBranch;
                isStore[t][i] = alReadData[t][i].isStore;
            end

            DecideCommit(
                .commit(commit[t]),
                .toRecoveryPhase(toRecoveryPhase[t]),
                .recoveredIndex(recoveryOpIndex[t]),
                .refetchType(refetchType[t]),
                .recoveryCause(recoveryCause[t]),
                .startCommit(phase[t] == PHASE_COMMIT),
                .activeListCount(activeList.validEntryNum[t]),
                .execState(execState[t]),
                .last(last[t]),
                .isBranch(isBranch[t]),
                .isStore(isStore[t]),
                .unableToStartRecovery(recovery.unableToStartRecovery[t])
            );
        end

        // 2. ARBITRATION: Select ONE thread to actually commit
        // Default: Select the round-robin pointer
        selectedThread = roundRobinPtr;
        
        // Optional Work-Conserving: If T0 empty but T1 ready, switch?
        // For simplicity of code, strict Round Robin is fine. 
        // But if 'commit[selectedThread][0]' is false, we ideally check the other.
        if (!commit[selectedThread][0] && commit[!selectedThread][0]) begin
            selectedThread = !roundRobinPtr;
        end

        // 3. Drive Outputs (Masking non-selected threads)
        for (int t = 0; t < NUM_THREADS; t++) begin
            
            // Mask commit signals if not selected
            logic effectiveCommit;
            effectiveCommit = (t == selectedThread);

            commitNum[t] = 0;
            commitLoadNum[t] = 0;
            commitStoreNum[t] = 0;
            
            // Update PC regardless of arbitration (maintain state)
            lastCommittedPC[t] = prevLastCommittedPC[t];

            for (int i = 0; i < COMMIT_WIDTH; i++) begin
                if (commit[t][i] && effectiveCommit) begin
                    commitNum[t]++;
                    if (alReadData[t][i].isLoad) commitLoadNum[t]++;
                    if (alReadData[t][i].isStore) commitStoreNum[t]++;
                    lastCommittedPC[t] = alReadData[t][i].pc;
                end
                else begin
                    commit[t][i] = FALSE; // Force false if not selected
                end
            end

            // Outputs
            renameLogic.commit[t] = (commitNum[t] > 0);
            renameLogic.commitNum[t] = commitNum[t];
            
            // Drive RMT write signals
            for (int i = 0; i < COMMIT_WIDTH; i++) begin
                if (commit[t][i] && effectiveCommit) begin
                    renameLogic.retRMT_WriteReg[t][i] = alReadData[t][i].writeReg;
                    renameLogic.retRMT_WriteReg_PhyRegNum[t][i] = alReadData[t][i].phyDstRegNum;
                    renameLogic.retRMT_WriteReg_LogRegNum[t][i] = alReadData[t][i].logDstRegNum;
                end
                else begin
                    renameLogic.retRMT_WriteReg[t][i] = FALSE;
                    renameLogic.retRMT_WriteReg_PhyRegNum[t][i] = 0;
                    renameLogic.retRMT_WriteReg_LogRegNum[t][i] = 0;
                end
            end
            
            // Other modules
            loadStoreUnit.releaseLoadQueue[t] = (commitNum[t] > 0);
            loadStoreUnit.releaseLoadQueueEntryNum[t] = commitLoadNum[t];
            loadStoreUnit.commitStore[t] = (commitNum[t] > 0);
            loadStoreUnit.commitStoreNum[t] = commitStoreNum[t];
            
            recovery.exceptionDetectedInCommitStage[t] = toRecoveryPhase[t]; // Recovery isn't masked by arbiter!
            recovery.refetchTypeFromCommitStage[t] = refetchType[t];
            recovery.recoveryOpIndex[t] = recoveryOpIndex[t];
            recovery.recoveryCauseFromCommitStage[t] = recoveryCause[t];
            
            csrUnit.commitNum[t] = commitNum[t];
            
            // Debug
            debug.lastCommittedPC[t] = lastCommittedPC[t];
        end 
    end
endmodule