// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Execution stage
//

`include "BasicMacros.sv"

import BasicTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import PipelineTypes::*;
import RenameLogicTypes::*;
import DebugTypes::*;
import MemoryMapTypes::*;


//
// 実行ステージ
//

module MemoryExecutionStage(
    MemoryExecutionStageIF.ThisStage port,
    MemoryRegisterReadStageIF.NextStage prev,
    LoadStoreUnitIF.MemoryExecutionStage loadStoreUnit,
    CacheFlushManagerIF.MemoryExecutionStage cacheFlush,
    MulDivUnitIF.MemoryExecutionStage mulDivUnit,
    BypassNetworkIF.MemoryExecutionStage bypass,
    RecoveryManagerIF.MemoryExecutionStage recovery,
    ControllerIF.MemoryExecutionStage ctrl,
    CSR_UnitIF.MemoryExecutionStage csrUnit,
    DebugIF.MemoryExecutionStage debug
);

    MemoryExecutionStageRegPath pipeReg[MEM_ISSUE_WIDTH];

`ifndef RSD_SYNTHESIS
    // Don't care these values, but avoiding undefined status in Questa.
    initial begin
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            pipeReg[i] = '0;
        end
    end
`endif

    // --- Pipeline registers
    always_ff@( posedge port.clk )   // synchronous rst
    begin
        if (port.rst) begin
            for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
                pipeReg[i].valid <= '0;
            end
        end
        else if(!ctrl.backEnd.stall) begin              // write data
            pipeReg <= prev.nextStage;
        end
    end


    // Pipeline control
    logic stall, clear;
    logic flush[ MEM_ISSUE_WIDTH ];

    MemIssueQueueEntry iqData[MEM_ISSUE_WIDTH];
    MemOpInfo memOpInfo  [ MEM_ISSUE_WIDTH ];
    ThreadID opTid [ MEM_ISSUE_WIDTH ];

    PRegDataPath  fuOpA  [ MEM_ISSUE_WIDTH ];
    PRegDataPath  fuOpB  [ MEM_ISSUE_WIDTH ];

    // Valid bits of registers
    logic regValid[MEM_ISSUE_WIDTH];

    AddrPath addrOut[ MEM_ISSUE_WIDTH ];
    MemoryMapType memMapType[MEM_ISSUE_WIDTH];
    PhyAddrPath phyAddrOut[MEM_ISSUE_WIDTH];
    logic isUncachable[MEM_ISSUE_WIDTH];


    // FENCE.I
    logic cacheFlushReq;

    always_comb begin
        stall = ctrl.backEnd.stall;
        clear = ctrl.backEnd.clear;

        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            iqData[i] = pipeReg[i].memQueueData;
            opTid[i] = pipeReg[i].tid;

            flush[i] = SelectiveFlushDetector(
                        recovery.toRecoveryPhase[opTid[i]],
                        recovery.flushRangeHeadPtr[opTid[i]],
                        recovery.flushRangeTailPtr[opTid[i]],
                        recovery.flushAllInsns[opTid[i]],
                        iqData[i].activeListPtr
                        );
            memOpInfo[i]  = iqData[i].memOpInfo;

      
            // オペランド
            fuOpA[i] = ( pipeReg[i].bCtrl.rA.valid ? bypass.memSrcRegDataOutA[i] : pipeReg[i].operandA );
            fuOpB[i] = ( pipeReg[i].bCtrl.rB.valid ? bypass.memSrcRegDataOutB[i] : pipeReg[i].operandB );

            // Address unit
            addrOut[i] = fuOpA[i].data + { {ADDR_SIGN_EXTENTION_WIDTH{memOpInfo[i].addrIn[ADDR_OPERAND_IMM_WIDTH-1]}}, memOpInfo[i].addrIn };
            phyAddrOut[i] = ToPhyAddrFromLogical(addrOut[i]);
            memMapType[i] = GetMemoryMapType(addrOut[i]);
            isUncachable[i] = IsPhyAddrUncachable(phyAddrOut[i]);

            // --- Bypass
            // 制御
            bypass.memCtrlIn[i] = pipeReg[i].bCtrl;

            // Register valid bits.
            regValid[i] =
                (memOpInfo[i].operandTypeA != OOT_REG || fuOpA[i].valid ) &&
                (memOpInfo[i].operandTypeB != OOT_REG || fuOpB[i].valid );

        end // for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin

        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            // --- DCache access
            loadStoreUnit.dcReadReq[i] =
                !stall && !clear && pipeReg[i].valid && regValid[i] && !flush[i] &&
                (memOpInfo[i].opType inside { MEM_MOP_TYPE_LOAD });
            
            // SMT: Pass TID to LSU for memory ordering checks
            loadStoreUnit.dcReadTid[i] = opTid[i]; // Requires update to LoadStoreUnitIF

            loadStoreUnit.dcReadAddr[i] = phyAddrOut[i];

            loadStoreUnit.dcReadUncachable[i] = isUncachable[i];

            // AL Ptr to release MSHR entry when allocator load is flushed.
            loadStoreUnit.dcReadActiveListPtr[i] = pipeReg[i].memQueueData.activeListPtr;

        end

        // FENCE.I
        // SMT: FENCE.I logic must check if current thread is executing FENCE
        // NOTE: Cache flush is global. If one thread requests flush, we flush.
        cacheFlushReq = FALSE;
        if (pipeReg[0].valid && (memOpInfo[0].opType == MEM_MOP_TYPE_FENCE) && memOpInfo[0].isFenceI) begin
            cacheFlushReq = TRUE;
            if (!cacheFlush.cacheFlushComplete) begin
                // FENCE.I must be replayed after cache flush is completed.
                regValid[0] = FALSE;
            end
        end
        cacheFlush.cacheFlushReq = cacheFlushReq;
    end

    //
    // CSR access
    //
    generate
        // Since a CSR op is serialized, so multiple CSR ops are not issued.
        for (genvar i = 1; i < MEM_ISSUE_WIDTH; i++) begin : assertionBlock
            `RSD_ASSERT_CLK(
                port.clk, 
                !(memOpInfo[i].opType inside {
                    MEM_MOP_TYPE_CSR, MEM_MOP_TYPE_FENCE, MEM_MOP_TYPE_ENV
                } && pipeReg[i].valid),
                "A CSR/FENCE/ENV op was issued to a lane other than 0."
            );
        end
    endgenerate

    logic isCSR;
    always_comb begin   // CSR must be issued to the lane 0;
        isCSR = memOpInfo[0].opType == MEM_MOP_TYPE_CSR;

        // CSR request
        csrUnit.csrWE = pipeReg[0].valid && isCSR;
        csrUnit.csrNumber = memOpInfo[0].addrIn;
        csrUnit.csrWriteIn = 
            memOpInfo[0].csrCtrl.isImm ? memOpInfo[0].csrCtrl.imm : pipeReg[0].operandA;
        csrUnit.csrCode = memOpInfo[0].csrCtrl.code;
    end

    //
    // MulDiv
    //
`ifdef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    logic isDiv         [ MULDIV_ISSUE_WIDTH ]; 
    logic finished      [ MULDIV_ISSUE_WIDTH ];

    MulOpSubInfo mulSubInfo[MULDIV_ISSUE_WIDTH];
    DivOpSubInfo divSubInfo[MULDIV_ISSUE_WIDTH];
    always_comb begin

        for (int i = 0; i < MULDIV_ISSUE_WIDTH; i++) begin
            mulDivUnit.dataInA[i] = fuOpA[i].data;
            mulDivUnit.dataInB[i] = fuOpB[i].data;

            // MUL
            mulSubInfo[i]  = memOpInfo[i].mulSubInfo;
            divSubInfo[i]  = memOpInfo[i].divSubInfo;
            mulDivUnit.mulGetUpper[i] = mulSubInfo[i].mulGetUpper;
            mulDivUnit.mulCode[i] = mulSubInfo[i].mulCode;

            // DIV
            mulDivUnit.divCode[i] = divSubInfo[i].divCode;

            isDiv[i] =  
                memOpInfo[i].opType inside {MEM_MOP_TYPE_DIV};

            // Request to the divider
            mulDivUnit.divReq[i] = 
                mulDivUnit.divReserved[i] && 
                pipeReg[i].valid && isDiv[i] && 
                fuOpA[i].valid && fuOpB[i].valid;
        end

    end
`endif



    //
    // --- Pipeline レジスタ書き込み
    //
    MemoryTagAccessStageRegPath nextStage [ MEM_ISSUE_WIDTH ];

    always_comb begin
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            nextStage[i].memQueueData = pipeReg[i].memQueueData;
            
            // リセットorフラッシュ時はNOP
            nextStage[i].valid =
                (stall || clear || port.rst || flush[i]) ? FALSE : pipeReg[i].valid;
            
            nextStage[i].tid = opTid[i];
            nextStage[i].condEnabled = TRUE;
            nextStage[i].dataIn = (i == 0 && isCSR) ? csrUnit.csrReadOut : fuOpB[i].data;   // CSR must be issued to the lane 0
            nextStage[i].addrOut = addrOut[i];
            nextStage[i].regValid = regValid[i];
            nextStage[i].memMapType = memMapType[i];
            nextStage[i].phyAddrOut = phyAddrOut[i];
`ifndef RSD_DISABLE_DEBUG_REGISTER
            nextStage[i].opId = pipeReg[i].opId;
`endif
        end


        // Output
        port.nextStage = nextStage;

        // Debug Register
`ifndef RSD_DISABLE_DEBUG_REGISTER
        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            debug.memExReg[i].valid = pipeReg[i].valid;
            debug.memExReg[i].flush = flush[i];
            debug.memExReg[i].opId = pipeReg[i].opId;
`ifdef RSD_FUNCTIONAL_SIMULATION
            if (isCSR && i == 0) begin  // Special case for CSR
                debug.memExReg[i].addrOut = csrUnit.csrReadOut;
                debug.memExReg[i].fuOpA   = memOpInfo[0].addrIn;
                debug.memExReg[i].fuOpB   = memOpInfo[0].csrCtrl.isImm ? memOpInfo[0].csrCtrl.imm : pipeReg[0].operandA;
            end
            else begin
                debug.memExReg[i].addrOut = addrOut[i];
                debug.memExReg[i].fuOpA   = fuOpA[i].data;
                debug.memExReg[i].fuOpB   = fuOpB[i].data;
            end
            debug.memExReg[i].opType = memOpInfo[i].opType;
            debug.memExReg[i].size = memOpInfo[i].memAccessMode.size;
            debug.memExReg[i].isSigned = memOpInfo[i].memAccessMode.isSigned;
`endif
        end
`endif
    end

    generate 
        for (genvar i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            `RSD_ASSERT_CLK(
                port.clk, 
                !(pipeReg[i].valid && 
                pipeReg[i].memQueueData.memOpInfo.opType != MEM_MOP_TYPE_LOAD && 
                pipeReg[i].memQueueData.hasAllocatedMSHR),
                "hasAllocatedMSHR is asserted other than a load pipe"
            );
        end
    endgenerate


endmodule : MemoryExecutionStage