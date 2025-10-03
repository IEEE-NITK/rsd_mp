// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- FetchPipe
//

import BasicTypes::*;
import PipelineTypes::*;
import MicroOpTypes::*;

interface DecodeStageIF( input logic clk, rst );

    // Pipeline registers 
    RenameStageRegPath nextStage[ DECODE_WIDTH ];
    logic nextFlush;
    AddrPath nextRecoveredPC;

    ELP_State_Type elpState;
    logic recoverELP_FromRwStage;
    ELP_State_Type recoveredELP_FromRwStage;
    logic recoverELP_FromCSR;
    ELP_State_Type recoveredELP_FromCSR;
    
    modport ThisStage(
    input 
        clk, 
        rst,
        recoverELP_FromRwStage,
        recoveredELP_FromRwStage,
        recoverELP_FromCSR,
        recoveredELP_FromCSR,
    output 
        nextStage,
        nextFlush,
        nextRecoveredPC,
        elpState
    );
    
    modport NextStage(
    input
        nextStage,
        nextFlush,
        nextRecoveredPC
    );

    modport InterruptController(
    input
        elpState
    );

    modport RecoveryManager(
    output
        recoverELP_FromRwStage,
        recoveredELP_FromRwStage
    );

    modport CSR_Unit(
    output
        recoveredELP_FromCSR,
        recoverELP_FromCSR
    );
    
endinterface : DecodeStageIF



