// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for register read.
//

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import MicroOpTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import LoadStoreUnitTypes::*;
import DebugTypes::*;

// SMT UPDATE: Serializer must be thread-aware. 
// A serializing instruction (like FENCE) from Thread A should only wait for Thread A's ROB to empty.
module RenameStageSerializer(
input 
    logic clk, rst, stall, clear,
    logic activeListEmpty[NUM_THREADS], // SMT CHANGE: Array for per-thread status
    logic storeQueueEmpty[NUM_THREADS], // SMT CHANGE: Array for per-thread status
    OpInfo [RENAME_WIDTH-1:0] opInfo, 
    logic [RENAME_WIDTH-1:0] valid,
    ThreadID [RENAME_WIDTH-1:0] tid,    // SMT CHANGE: Need TID to know who is serializing
output 
    logic serialize
);
    generate
        for (genvar i = 1; i < RENAME_WIDTH; i++) begin : assertionBlock
            `RSD_ASSERT_CLK_FMT(
                clk, 
                !(opInfo[i].serialized && valid[i]), 
                ("Multiple serialized ops were sent to RenameStage. (%x, %x)", opInfo[i].serialized, valid[i])
            ) 
        end
    endgenerate

    // Serialize phase
    typedef enum logic[1:0]
    {
        PHASE_NORMAL = 0,               
        PHASE_WAIT_OWN = 2              
    } Phase;
    
    // SMT CHANGE: Maintain phase state per thread
    Phase regPhase[NUM_THREADS], nextPhase[NUM_THREADS];
    Phase currentPhase, nextPhaseSelect;

    always_ff@(posedge clk)   // synchronous rst
    begin
        if (rst) begin
            for (int i=0; i<NUM_THREADS; i++) begin
                regPhase[i] <= PHASE_NORMAL;
            end
        end
        else if(!stall) begin             
            // Update phase for all threads
            regPhase <= nextPhase;
        end
    end

    // Logic Variables
    ThreadID targetTid;
    logic currentActiveListEmpty;
    logic currentStoreQueueEmpty;

    always_comb begin
        // Default assignments
        serialize = FALSE;
        for (int i=0; i<NUM_THREADS; i++) begin
            nextPhase[i] = regPhase[i]; // Default hold
        end

        // SMT: Identify which thread is potentially serializing.
        // Assumption: DecodeStage guarantees only one serialized op exists at opInfo[0].
        targetTid = tid[0];
        currentPhase = regPhase[targetTid];
        
        // Select the status flags for the relevant thread
        currentActiveListEmpty = activeListEmpty[targetTid];
        currentStoreQueueEmpty = storeQueueEmpty[targetTid];

        if (clear) begin
            for (int i=0; i<NUM_THREADS; i++) nextPhase[i] = PHASE_NORMAL; 
        end

        if (currentPhase == PHASE_NORMAL) begin
            if (opInfo[0].serialized && valid[0]) begin
                if (opInfo[0].operand.miscMemOp.fence) begin // Fence
                    if (!currentActiveListEmpty || !currentStoreQueueEmpty) begin
                        // Fence must wait for OWN previous ops to be committed
                        serialize = TRUE;   
                        nextPhase[targetTid] = PHASE_NORMAL; // Stay/Retry
                    end
                    else begin
                        // Ready to proceed
                        nextPhase[targetTid] = PHASE_WAIT_OWN;
                    end
                end 
                else begin // Non-fence serialized op
                    if (!currentActiveListEmpty) begin
                        serialize = TRUE;   
                        nextPhase[targetTid] = PHASE_NORMAL;
                    end
                    else begin
                        nextPhase[targetTid] = PHASE_WAIT_OWN;
                    end
                end
            end
        end
        else begin
            // PHASE_WAIT_OWN: Wait for the serialized op ITSELF to commit
            // We check if the ROB/SQ is empty (meaning the serialized op finished)
            if (!currentActiveListEmpty || !currentStoreQueueEmpty) begin
                serialize = TRUE;
                nextPhase[targetTid] = PHASE_WAIT_OWN;
            end
            else begin
                nextPhase[targetTid] = PHASE_NORMAL;
            end
        end
    end

endmodule

module RenameStage(
    RenameStageIF.ThisStage port,
    DecodeStageIF.NextStage prev,
    RenameLogicIF.RenameStage renameLogic,
    ActiveListIF.RenameStage activeList,
    SchedulerIF.RenameStage scheduler,
    LoadStoreUnitIF.RenameStage loadStoreUnit,
    RecoveryManagerIF.RenameStage recovery,
    ControllerIF.RenameStage ctrl,
    DebugIF.RenameStage debug
);

    // --- Pipeline registers
    RenameStageRegPath pipeReg[RENAME_WIDTH];
    logic regFlush;
    PC_Path regRecoveredPC;


`ifndef RSD_SYNTHESIS
    `ifndef RSD_VIVADO_SIMULATION
        // Don't care these values, but avoiding undefined status in Questa.
        initial begin
            for (int i = 0; i < RENAME_WIDTH; i++) begin
                pipeReg[i] = '0;
            end
            regRecoveredPC = '0;
        end
    `endif
`endif

    always_ff@( posedge port.clk )   // synchronous rst
    begin
        if (port.rst) begin
            for (int i = 0; i < RENAME_WIDTH; i++) begin
                pipeReg[i].valid <= FALSE;
            end
            regFlush <= '0;
            regRecoveredPC <= '0;
        end
        else if(!ctrl.rnStage.stall) begin            // write data
            pipeReg <= prev.nextStage;
            regFlush <= prev.nextFlush;
            regRecoveredPC <= prev.nextRecoveredPC;
        end
    end

    always_comb begin
        recovery.recoverFromRename = regFlush;
        recovery.recoveredPC_FromRename = regRecoveredPC;
        ctrl.rnStageFlushUpper = regFlush;
    end


    // Pipeline controll
    logic stall, clear;
    logic empty;
    logic serialize;

    logic [ RENAME_WIDTH-1:0 ] valid;
    logic update [ RENAME_WIDTH ];
    OpInfo [RENAME_WIDTH-1:0] opInfo;
    ThreadID [RENAME_WIDTH-1:0] opTid; // SMT: Extract TIDs for serializer

    ActiveListEntry alEntry [ RENAME_WIDTH ];
    DispatchStageRegPath nextStage [ RENAME_WIDTH ];

    logic isLoad[RENAME_WIDTH];
    logic isStore[RENAME_WIDTH];
    logic isBranch[RENAME_WIDTH];

    // SMT CHANGE: track empty status per thread
    logic activeListEmpty[NUM_THREADS];
    logic storeQueueEmpty[NUM_THREADS];

    always_comb begin
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            valid[i] = pipeReg[i].valid;
            opInfo[i] = pipeReg[i].opInfo;
            opTid[i] = pipeReg[i].tid;
        end

        // SMT CHANGE: In a partitioned resource model, we need to check if 
        // the specific thread has resources. 
        // NOTE: Assuming interfaces (.allocatable) handle SMT internally 
        // or return a simplified global signal for now.
        ctrl.rnStageSendBubbleLower =
            (
                ( |valid ) &&
                (
                    !renameLogic.allocatable ||
                    !scheduler.allocatable ||
                    !activeList.allocatable ||
                    !loadStoreUnit.allocatable
                )
            ) || serialize;

        stall = ctrl.rnStage.stall;
        clear = ctrl.rnStage.clear;
        
        // SMT CHANGE: Map interface signals to array. 
        // Assuming ActiveListIF exposes per-thread usage or we infer it.
        // For now, we assume activeList provides a usage count per thread 
        // OR we stick to global check if interfaces aren't updated yet.
        // Ideally: activeListEmpty[t] = (activeList.usage[t] == 0);
        // Fallback (Conservative): Use global empty for all.
        for(int t=0; t<NUM_THREADS; t++) begin
            activeListEmpty[t] = (activeList.validEntryNum == 0); 
            storeQueueEmpty[t] = loadStoreUnit.storeQueueEmpty;
        end
    end

    RenameStageSerializer serializer(
        port.clk, port.rst, stall, clear, activeListEmpty, storeQueueEmpty,
        opInfo, 
        valid,
        opTid, // Pass TIDs
        serialize
    );

    logic isEnv[RENAME_WIDTH];
    always_comb begin
        //
        // --- Data to Rename logic
        //
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            // The rename stage stalls when resources cannot be allocated.
            update[i] =
                valid[i] && !stall && !clear;
        end

        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            isLoad[i] = 
                (opInfo[i].mopType == MOP_TYPE_MEM) && 
                (opInfo[i].mopSubType.memType == MEM_MOP_TYPE_LOAD);
            isStore[i] = 
                (opInfo[i].mopType == MOP_TYPE_MEM) && 
                (opInfo[i].mopSubType.memType == MEM_MOP_TYPE_STORE);
            isEnv[i] = 
                (opInfo[i].mopType == MOP_TYPE_MEM) && 
                (opInfo[i].mopSubType.memType == MEM_MOP_TYPE_ENV);
            isBranch[i] =
                (opInfo[i].mopType == MOP_TYPE_INT) && 
                (opInfo[i].mopSubType.intType inside {INT_MOP_TYPE_BR, INT_MOP_TYPE_RIJ});
        end

        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            renameLogic.updateRMT[i] = update[i];
            renameLogic.tid[i] = pipeReg[i].tid; // Existing TID pass

            // Logical register numbers
            renameLogic.logSrcRegA[i] = isBranch[i] ? opInfo[i].operand.brOp.srcRegNumA : opInfo[i].operand.intOp.srcRegNumA;
            renameLogic.logSrcRegB[i] = isBranch[i] ? opInfo[i].operand.brOp.srcRegNumB : opInfo[i].operand.intOp.srcRegNumB;
`ifdef RSD_MARCH_FP_PIPE
            renameLogic.logSrcRegC[i] = opInfo[i].operand.fpOp.srcRegNumC;
`endif
            renameLogic.logDstReg[i] = isBranch[i] ? opInfo[i].operand.brOp.dstRegNum : opInfo[i].operand.intOp.dstRegNum;

            // Read/Write control
            renameLogic.readRegA[i] = opInfo[i].opTypeA == OOT_REG;
            renameLogic.readRegB[i] = opInfo[i].opTypeB == OOT_REG;
`ifdef RSD_MARCH_FP_PIPE
            renameLogic.readRegC[i] = opInfo[i].opTypeC == OOT_REG;
`endif

            renameLogic.writeReg[i] = opInfo[i].writeReg;

            // to WAT
            renameLogic.watWriteRegFromPipeReg[i] = opInfo[i].writeReg && update[i];
            renameLogic.watWriteIssueQueuePtrFromPipeReg[i] = scheduler.allocatedPtr[i];
        end


        //
        // --- Renamed operands
        //
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            // Renamed physical register numbers.
            nextStage[i].phySrcRegNumA = renameLogic.phySrcRegA[i];
            nextStage[i].phySrcRegNumB = renameLogic.phySrcRegB[i];
`ifdef RSD_MARCH_FP_PIPE
            nextStage[i].phySrcRegNumC = renameLogic.phySrcRegC[i];
`endif
            nextStage[i].phyDstRegNum = renameLogic.phyDstReg[i];
            nextStage[i].phyPrevDstRegNum = renameLogic.phyPrevDstReg[i];

        end

        // Source pointer for a matrix scheduler.
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            // Renamed physical register numbers.
            nextStage[i].srcIssueQueuePtrRegA = renameLogic.srcIssueQueuePtrRegA[i];
            nextStage[i].srcIssueQueuePtrRegB = renameLogic.srcIssueQueuePtrRegB[i];
`ifdef RSD_MARCH_FP_PIPE
            nextStage[i].srcIssueQueuePtrRegC = renameLogic.srcIssueQueuePtrRegC[i];
`endif
        end


        //
        // Active list allocation
        //
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            activeList.pushTail[i] = update[i];
            
            // SMT CHANGE: Ensure Active List knows which thread is pushing
            // (Assuming interface allows 'tid' input, usually implied by the data packet)
            // activeList.tid[i] = pipeReg[i].tid; 

            `ifndef RSD_DISABLE_DEBUG_REGISTER
                alEntry[i].opId = pipeReg[i].opId;
            `endif

            alEntry[i].pc = pipeReg[i].pc;
            alEntry[i].tid = pipeReg[i].tid; // Passed into the struct

            alEntry[i].phyPrevDstRegNum = nextStage[i].phyPrevDstRegNum;
            alEntry[i].phyDstRegNum = nextStage[i].phyDstRegNum;
            alEntry[i].logDstRegNum = opInfo[i].operand.intOp.dstRegNum;
            alEntry[i].writeReg = opInfo[i].writeReg;
            alEntry[i].isLoad = isLoad[i];
            alEntry[i].isStore = isStore[i];
            alEntry[i].isBranch = isBranch[i];
            alEntry[i].isEnv = opInfo[i].operand.systemOp.isEnv;
            alEntry[i].undefined = opInfo[i].undefined || opInfo[i].unsupported;
            alEntry[i].last = opInfo[i].last;
            alEntry[i].prevDependIssueQueuePtr = renameLogic.prevDependIssueQueuePtr[i];

            nextStage[i].activeListPtr = activeList.pushedTailPtr[i];
        end
        activeList.pushedTailData = alEntry;

        //
        // Issue queue allocation
        //
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            scheduler.allocate[i] = update[i];
            // SMT CHANGE: Pass TID to scheduler allocation so it knows which partition to use
            // scheduler.tid[i] = pipeReg[i].tid; 
            nextStage[i].issueQueuePtr = scheduler.allocatedPtr[i];
        end


        //
        // Load/store unit allocation
        //
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            loadStoreUnit.allocateLoadQueue[i] = update[i] && isLoad[i];
            loadStoreUnit.allocateStoreQueue[i] = update[i] && isStore[i];
            // SMT CHANGE: Pass TID to LSU allocation
            // loadStoreUnit.tid[i] = pipeReg[i].tid;

            nextStage[i].loadQueuePtr = loadStoreUnit.allocatedLoadQueuePtr[i];
            nextStage[i].storeQueuePtr = loadStoreUnit.allocatedStoreQueuePtr[i];
        end

        // Make read request to Memory Dependent Prediction
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            port.pc[i] = pipeReg[i].pc;
            port.tid[i] = pipeReg[i].tid; // SMT: Pass TID to predictor
        end
        
        //
        // --- Pipeline control
        //

        // 'valid' is invalidate, if 'stall' or 'clear' or 'rst' is enabled.
        // That is, a op is treated as a NOP.
        // Otherwise 'valid' is set to a previous stage's 'valid.'
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].opId = pipeReg[i].opId;
`endif

            nextStage[i].valid =
                ( stall || clear || port.rst ) ? FALSE : valid[i];

            // Decoded micr-op and context.
            nextStage[i].tid = pipeReg[i].tid;
            nextStage[i].pc = pipeReg[i].pc;
            nextStage[i].brPred = pipeReg[i].bPred;
            nextStage[i].opInfo = opInfo[i];

            // 以下のLSQのポインタはLSQのリカバリに用いる
            nextStage[i].loadQueueRecoveryPtr = loadStoreUnit.allocatedLoadQueuePtr[i];
            nextStage[i].storeQueueRecoveryPtr = loadStoreUnit.allocatedStoreQueuePtr[i];

        end
        port.nextStage = nextStage;

        empty = TRUE;
        for (int i = 0; i < DECODE_WIDTH; i++) begin
            if (pipeReg[i].valid)
                empty = FALSE;
        end
        ctrl.rnStageEmpty = empty;

        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            debug.rnReg[i].valid = valid[i];
            debug.rnReg[i].opId = pipeReg[i].opId;
        end
`endif
    end

endmodule : RenameStage