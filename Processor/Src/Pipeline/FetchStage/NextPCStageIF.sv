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
    // SMT CHANGE: pcWE is now one bit per thread, pcOut is an array
    logic        pcWE[NUM_THREADS]; 
    PC_Path      pcOut[NUM_THREADS];
    PC_Path      pcIn; // Shared input (arbitrated)

    PC_Path      predNextPC;

    // Executed branch results for updating a branch predictor.
    BranchResult brResult[ INT_ISSUE_WIDTH ];

    // Interrupt
    // SMT FIX: These must be arrays because InterruptController drives them per thread.
    PC_Path interruptAddrIn [NUM_THREADS];
    logic interruptAddrWE [NUM_THREADS];

    // I-cache
    PhyAddrPath   icNextReadAddrIn; // Value of icReadAddrIn in next cycle.

    // Pipeline register
    FetchStageRegPath nextStage[ FETCH_WIDTH ];
    
    // SMT FIX: Renamed from selectedTid to fetchThreadID to match BTB/Gshare expectations
    ThreadID fetchThreadID;

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
        fetchThreadID, // Updated name
        icNextReadAddrIn,
        nextStage
    );

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
        brResult,
        fetchThreadID // Added so BTB knows which thread is fetching
    );

    modport BranchPredictor(
    input
        clk,
        rst,
        rstStart,
        predNextPC,
        brResult,
        fetchThreadID // Added so Predictor knows which history to use
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