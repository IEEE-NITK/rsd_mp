// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for fetching instructions.
//

import BasicTypes::*;
import PipelineTypes::*;
import FetchUnitTypes::*;
import MemoryMapTypes::*;

module FetchStage(
    FetchStageIF.ThisStage port,
    NextPCStageIF.NextStage prev,
    ControllerIF.FetchStage ctrl,
    DebugIF.FetchStage debug,
    PerformanceCounterIF.FetchStage perfCounter
);

    // Pipeline Control
    logic stall, clear;
    logic empty;
    logic regStall, beginStall;
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            regStall <= FALSE;
        end
        else begin
            regStall <= stall;
        end
    end

    
    // --- Pipeline registers
    FetchStageRegPath pipeReg[FETCH_WIDTH];
    PreDecodeStageRegPath nextStage[ FETCH_WIDTH ];

    always_comb begin
        // Stall logic ...
        ctrl.ifStageSendBubbleLower = 
            pipeReg[0].valid && !port.icReadHit[0];

        // Control
        stall = ctrl.ifStage.stall;
        clear = ctrl.ifStage.clear;

        // Check empty
        empty = TRUE;
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            if (pipeReg[i].valid)
                empty = FALSE;
        end
        ctrl.ifStageEmpty = empty;

        beginStall = !regStall && stall;

`ifndef RSD_DISABLE_PERFORMANCE_COUNTER
        perfCounter.icMiss = beginStall && pipeReg[0].valid && !port.icReadHit[0];
`endif
    end

    logic isFlushed[FETCH_WIDTH];

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < FETCH_WIDTH; i++) begin
                pipeReg[i] <= '0;
            end
        end
        else if (!stall) begin
            pipeReg <= prev.nextStage;
        end
        else begin
            for (int i = 0; i < FETCH_WIDTH; i++) begin
                if (isFlushed[i]) begin                     
                    pipeReg[i].valid <= FALSE;
                end
            end
        end
    end


    BranchPred brPred[FETCH_WIDTH];
    BranchPred regBrPred[FETCH_WIDTH];

    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < FETCH_WIDTH; i++) begin
                regBrPred[i] <= '0;
            end
        end
        else if (beginStall) begin
            regBrPred <= brPred;
        end
    end


    //
    // Branch Prediction
    //
    always_comb begin

        // The result of branch prediction
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            brPred[i].predAddr = port.brPredTaken[i] ? 
                port.btbOut[i] : pipeReg[i].pc + INSN_BYTE_WIDTH;
            brPred[i].predTaken = port.brPredTaken[i];
            brPred[i].globalHistory = port.brGlobalHistory[i];
            brPred[i].phtPrevValue = port.phtPrevValue[i];
            
            // SMT: Pass the Thread ID to the branch predictor result
            brPred[i].tid = pipeReg[i].tid; 
        end

        // Check whether instructions are flushed by branch prediction
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            isFlushed[i] = FALSE;
            if (!regStall && pipeReg[i].valid && brPred[i].predTaken) begin
                for (int j = i + 1; j < FETCH_WIDTH; j++) begin
                    isFlushed[j] = pipeReg[j].valid;
                end
                break;
            end
        end

        // Update the branch history
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            port.updateBrHistory[i] = !regStall && pipeReg[i].valid;
        end
    end


    //
    // I-cache Access
    //
    AddrPath fetchAddrOut;
    always_comb begin
        // --- I-cache read
        port.icRE = pipeReg[0].valid; 
        fetchAddrOut = ToAddrFromPC(pipeReg[0].pc);
        port.icReadAddrIn = ToPhyAddrFromLogical(fetchAddrOut);


        for (int i = 0; i < FETCH_WIDTH; i++) begin
            port.fetchStageIsValid[i] = pipeReg[i].valid;
            port.fetchStagePC[i] = pipeReg[i].pc;
        end
    end


    //
    // --- Pipeline registers
    //
    always_comb begin
        for ( int i = 0; i < FETCH_WIDTH; i++ ) begin
            if (stall || clear || port.rst || isFlushed[i]) begin
                nextStage[i].valid = FALSE;
                nextStage[i].tid = pipeReg[i].tid; // Keep tid even if invalid
            end
            else begin
                nextStage[i].valid = pipeReg[i].valid;
                nextStage[i].tid = pipeReg[i].tid; // Pass TID
            end

            nextStage[i].pc = pipeReg[i].pc;
            nextStage[i].brPred = regStall ? regBrPred[i] : brPred[i];
            nextStage[i].insn = pipeReg[i].valid ? 
                port.icReadDataOut[i] : '0;
        end

        port.nextStage = nextStage;
        
        // Pass through thread IDs to interface (needed for BTB/Pred updates)
        for ( int i = 0; i < FETCH_WIDTH; i++ ) begin
            port.fetchThreadId[i] = nextStage[i].tid;
        end
    end

endmodule : FetchStage