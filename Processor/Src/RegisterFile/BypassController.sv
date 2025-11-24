// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


import BasicTypes::*;
import ActiveListIndexTypes::*;
import PipelineTypes::*;
import BypassTypes::*;

//
// --- Bypass controller
//
// BypassController outputs control information that controlls BypassNetwork.
// BypassController is connected to a register read stage.
//

typedef struct packed // struct BypassCtrlOperand
{
    PRegNumPath dstRegNum;
    logic writeReg;
    ThreadID thread;  // ADD THIS FOR SMT
} BypassCtrlOperand;


module BypassCtrlStage(
    input  logic clk, rst, 
    input  PipelineControll ctrl,
    input  BypassCtrlOperand in, 
    input  ThreadID threadIn,  // ADD THIS FOR SMT
    output BypassCtrlOperand out,
    output ThreadID threadOut  // ADD THIS FOR SMT
);
    BypassCtrlOperand body;
    ThreadID bodyThread;  // ADD THIS FOR SMT
    
    always_ff@( posedge clk )               // synchronous rst 
    begin
        if( rst || ctrl.clear ) begin              // rst 
            body.dstRegNum <= 0;
            body.writeReg  <= FALSE;
            bodyThread <= '0;  // ADD THIS FOR SMT
        end
        else if( ctrl.stall ) begin         // write data
            body <= body;
            bodyThread <= bodyThread;  // ADD THIS FOR SMT
        end
        else begin
            body <= in;
            bodyThread <= threadIn;  // ADD THIS FOR SMT
        end
    end
    
    assign out = body;
    assign threadOut = bodyThread;  // ADD THIS FOR SMT
endmodule

module BypassController( 
    BypassNetworkIF.BypassController port,
    ControllerIF.BypassController ctrl
);

    function automatic BypassSelect SelectReg( 
    input
        PRegNumPath regNum,
        logic read,
        ThreadID reqThread,  // ADD THIS FOR SMT
        BypassCtrlOperand intEX [ INT_ISSUE_WIDTH ],
        BypassCtrlOperand intWB [ INT_ISSUE_WIDTH ],
        BypassCtrlOperand memMA [ LOAD_ISSUE_WIDTH ],
        BypassCtrlOperand memWB [ LOAD_ISSUE_WIDTH ]
    );
        BypassSelect ret;
        ret.valid = FALSE;
        //ret.stg = BYPASS_STAGE_DEFAULT;
        ret.stg = BYPASS_STAGE_INT_EX;
        ret.lane.intLane = 0;
        ret.lane.memLane = 0;
        // Not implemented 
        ret.lane.complexLane = 0; 
`ifdef RSD_MARCH_FP_PIPE
        ret.lane.fpLane = 0; 
`endif

        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            // CHANGE: Add thread check for SMT
            if ( read && intEX[i].writeReg && regNum == intEX[i].dstRegNum &&
                 reqThread == intEX[i].thread ) begin
                ret.valid = TRUE;
                ret.stg = BYPASS_STAGE_INT_EX;
                ret.lane.intLane = i;
                break;
            end
            // CHANGE: Add thread check for SMT
            if ( read && intWB[i].writeReg && regNum == intWB[i].dstRegNum &&
                 reqThread == intWB[i].thread ) begin
                ret.valid = TRUE;
                ret.stg = BYPASS_STAGE_INT_WB;
                ret.lane.intLane = i;
                break;
            end
        end
        
        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            // CHANGE: Add thread check for SMT
            if ( read && memMA[i].writeReg && regNum == memMA[i].dstRegNum &&
                 reqThread == memMA[i].thread ) begin
                ret.valid = TRUE;
                ret.stg = BYPASS_STAGE_MEM_MA;
                ret.lane.memLane = i;
                break;
            end
            // CHANGE: Add thread check for SMT
            if ( read && memWB[i].writeReg && regNum == memWB[i].dstRegNum &&
                 reqThread == memWB[i].thread ) begin
                ret.valid = TRUE;
                ret.stg = BYPASS_STAGE_MEM_WB;
                ret.lane.memLane = i;
                break;
            end
        end
        
        return ret;
    endfunction

    logic clk, rst;
    
    assign clk = port.clk;
    assign rst = port.rst;
    
    //
    // Back-end Pipeline Structure
    //
    // Int:     IS RR EX WB
    // Complex: IS RR EX WB
    // Mem:     IS RR EX MT MA WB
    BypassCtrlOperand intRR [ INT_ISSUE_WIDTH ];
    BypassCtrlOperand intEX [ INT_ISSUE_WIDTH ];
    BypassCtrlOperand intWB [ INT_ISSUE_WIDTH ];
    BypassCtrlOperand memRR [ LOAD_ISSUE_WIDTH ];
    BypassCtrlOperand memEX [ LOAD_ISSUE_WIDTH ];
    BypassCtrlOperand memMT [ LOAD_ISSUE_WIDTH ];
    BypassCtrlOperand memMA [ LOAD_ISSUE_WIDTH ];
    BypassCtrlOperand memWB [ LOAD_ISSUE_WIDTH ];
    
    // ADD THIS FOR SMT: Thread tracking for pipeline stages
    ThreadID intThreadRR_EX [ INT_ISSUE_WIDTH ];
    ThreadID intThreadEX_WB [ INT_ISSUE_WIDTH ];
    ThreadID memThreadRR_EX [ LOAD_ISSUE_WIDTH ];
    ThreadID memThreadEX_MT [ LOAD_ISSUE_WIDTH ];
    ThreadID memThreadMT_MA [ LOAD_ISSUE_WIDTH ];
    ThreadID memThreadMA_WB [ LOAD_ISSUE_WIDTH ];

    for ( genvar i = 0; i < INT_ISSUE_WIDTH; i++ ) begin : stgInt
        BypassCtrlStage stgIntRR( clk, rst, ctrl.backEnd, intRR[i], port.intThreadID[i], intEX[i], intThreadRR_EX[i] );
        BypassCtrlStage stgIntEX( clk, rst, ctrl.backEnd, intEX[i], intThreadRR_EX[i], intWB[i], intThreadEX_WB[i] );
    end

    for ( genvar i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin : stgMem
        BypassCtrlStage stgMemRR( clk, rst, ctrl.backEnd, memRR[i], port.memThreadID[i], memEX[i], memThreadRR_EX[i] );
        BypassCtrlStage stgMemEX( clk, rst, ctrl.backEnd, memEX[i], memThreadRR_EX[i], memMT[i], memThreadEX_MT[i] );
        BypassCtrlStage stgMemMT( clk, rst, ctrl.backEnd, memMT[i], memThreadEX_MT[i], memMA[i], memThreadMT_MA[i] );
        BypassCtrlStage stgMemMA( clk, rst, ctrl.backEnd, memMA[i], memThreadMT_MA[i], memWB[i], memThreadMA_WB[i] );
    end
    
    BypassControll intBypassCtrl [ INT_ISSUE_WIDTH ];
`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
    BypassControll complexBypassCtrl [ COMPLEX_ISSUE_WIDTH ];
`endif
    BypassControll memBypassCtrl [ MEM_ISSUE_WIDTH ];
`ifdef  RSD_MARCH_FP_PIPE
    BypassControll fpBypassCtrl [ FP_ISSUE_WIDTH ];
`endif

    always_comb begin
        for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
            intRR[i].dstRegNum = port.intPhyDstRegNum[i];
            intRR[i].writeReg  = port.intWriteReg[i];
            intRR[i].thread = port.intThreadID[i];  // ADD THIS FOR SMT

            intBypassCtrl[i].rA   = SelectReg ( port.intPhySrcRegNumA[i], port.intReadRegA[i], port.intThreadID[i], intEX, intWB, memMA, memWB );
            intBypassCtrl[i].rB   = SelectReg ( port.intPhySrcRegNumB[i], port.intReadRegB[i], port.intThreadID[i], intEX, intWB, memMA, memWB );
        end
        port.intCtrlOut = intBypassCtrl;

`ifndef RSD_MARCH_UNIFIED_MULDIV_MEM_PIPE
        for ( int i = 0; i < COMPLEX_ISSUE_WIDTH; i++ ) begin
            complexBypassCtrl[i].rA   = SelectReg ( port.complexPhySrcRegNumA[i], port.complexReadRegA[i], port.complexThreadID[i], intEX, intWB, memMA, memWB );
            complexBypassCtrl[i].rB   = SelectReg ( port.complexPhySrcRegNumB[i], port.complexReadRegB[i], port.complexThreadID[i], intEX, intWB, memMA, memWB );
        end
        port.complexCtrlOut = complexBypassCtrl;
`endif

        for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
            memRR[i].dstRegNum = port.memPhyDstRegNum[i];
            memRR[i].writeReg  = port.memWriteReg[i];
            memRR[i].thread = port.memThreadID[i];  // ADD THIS FOR SMT
        end

        for ( int i = 0; i < MEM_ISSUE_WIDTH; i++ ) begin
            memBypassCtrl[i].rA   = SelectReg ( port.memPhySrcRegNumA[i], port.memReadRegA[i], port.memThreadID[i], intEX, intWB, memMA, memWB );
            memBypassCtrl[i].rB   = SelectReg ( port.memPhySrcRegNumB[i], port.memReadRegB[i], port.memThreadID[i], intEX, intWB, memMA, memWB );
        end
        port.memCtrlOut = memBypassCtrl;

`ifdef RSD_MARCH_FP_PIPE
        for ( int i = 0; i < FP_ISSUE_WIDTH; i++ ) begin
            fpBypassCtrl[i].rA   = SelectReg ( port.fpPhySrcRegNumA[i], port.fpReadRegA[i], port.fpThreadID[i], intEX, intWB, memMA, memWB );
            fpBypassCtrl[i].rB   = SelectReg ( port.fpPhySrcRegNumB[i], port.fpReadRegB[i], port.fpThreadID[i], intEX, intWB, memMA, memWB );
            fpBypassCtrl[i].rC   = SelectReg ( port.fpPhySrcRegNumC[i], port.fpReadRegC[i], port.fpThreadID[i], intEX, intWB, memMA, memWB );
        end
        port.fpCtrlOut = fpBypassCtrl;
`endif
    end

endmodule : BypassController

