// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- NextPCStageIF
//

import BasicTypes::*;
import PipelineTypes::*;
import FetchUnitTypes::*;
import MemoryMapTypes::*;

interface NextPCStageIF( input logic clk, rst, rstStart );
    
    // PC
`ifdef RSD_ENABLE_SMT
    // Multi-threaded: per-thread PC
    logic    pcWE[THREAD_NUM];
    PC_Path  pcOut[THREAD_NUM];
    PC_Path  pcIn[THREAD_NUM];
    ThreadID currentThread;
`else
    // Single-threaded: compatible with original design
    logic    pcWE;
    PC_Path  pcOut;
    PC_Path  pcIn;
`endif

    PC_Path  predNextPC;

    // Executed branch results for updating a branch predictor.
    // This signal is written back from a write back stage.
    BranchResult brResult[ INT_ISSUE_WIDTH ];

    // Interrupt
    PC_Path interruptAddrIn;
    logic interruptAddrWE;

    // I-cache
    PhyAddrPath   icNextReadAddrIn; // Value of icReadAddrIn in next cycle.

    // Pipeline register
    FetchStageRegPath nextStage[ FETCH_WIDTH ];

`ifdef RSD_ENABLE_SMT
    modport PC(
    input
        clk, rst, pcWE, pcIn,
    output
        pcOut, currentThread
    );

    modport ThisStage(
    input
        clk,
        rst,
        pcOut,
        brResult,
        interruptAddrIn,
        interruptAddrWE,
        currentThread,
    output
        pcWE,
        pcIn,
        predNextPC,
        icNextReadAddrIn,
        nextStage
    );
`else
    modport PC(
    input
        clk, rst, pcWE, pcIn,
    output
        pcOut
    );

    modport ThisStage(
    input
        clk,
        rst,
        pcOut,
        brResult,
        interruptAddrIn,
        interruptAddrWE,
    output
        pcWE,
        pcIn,
        predNextPC,
        icNextReadAddrIn,
        nextStage
    );
`endif

    modport NextStage(
    input
        predNextPC,
        nextStage
    );

    modport IntegerRegisterWriteStage(
    output
        brResult
    );

    modport BTB(
    input
        clk,
        rst,
        rstStart,
        predNextPC,
        brResult
    );

    modport BranchPredictor(
    input
        clk,
        rst,
        rstStart,
        predNextPC,
        brResult
    );

    modport ICache(
    input
        clk,
        rst,
        rstStart,
        icNextReadAddrIn
    );

    modport InterruptController(
    input
        pcOut,
    output
        interruptAddrIn,
        interruptAddrWE
    );


endinterface : NextPCStageIF
