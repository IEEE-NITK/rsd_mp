// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// --- DecodeStageIF
//

import BasicTypes::*;
import PipelineTypes::*;
import MicroOpTypes::*;

interface DecodeStageIF( input logic clk, rst );

    // Pipeline registers 
    RenameStageRegPath nextStage[ DECODE_WIDTH ];
    
    // Flush control
    logic nextFlush;
    AddrPath nextRecoveredPC;
    
    // SMT CHANGE: We must identify WHICH thread triggered the flush
    // so the RecoveryManager doesn't flush the wrong thread.
    ThreadID nextFlushTid;
    
    modport ThisStage(
    input 
        clk, 
        rst,
    output 
        nextStage,
        nextFlush,
        nextRecoveredPC,
        nextFlushTid // Added
    );
    
    modport NextStage(
    input
        nextStage,
        nextFlush,
        nextRecoveredPC,
        nextFlushTid // Added
    );
    
endinterface : DecodeStageIF