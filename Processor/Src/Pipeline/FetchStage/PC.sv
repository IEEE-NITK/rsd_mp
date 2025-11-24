// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// PC
// PC has INSN_RESET_VECTOR and cannot use AddrReg.
//

import BasicTypes::*;
import MemoryMapTypes::*;

module PC( NextPCStageIF.PC port );
    
`ifdef RSD_ENABLE_SMT
    // Multi-threaded mode: Per-thread PC registers
    genvar t;
    generate
        for (t = 0; t < THREAD_NUM; t++) begin : pc_threads
            FlipFlopWE#( PC_WIDTH, INSN_RESET_VECTOR ) 
                body( 
                    .out( port.pcOut[t] ), 
                    .in ( port.pcIn[t] ),
                    .we ( port.pcWE[t] ), 
                    .clk( port.clk ),
                    .rst( port.rst )
                );
        end
    endgenerate
    
    // Thread round-robin selector
    logic [THREAD_ID_BIT_WIDTH-1:0] threadCounter;
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            threadCounter <= '0;
        end
        else begin
            if (threadCounter == THREAD_NUM - 1) begin
                threadCounter <= '0;
            end
            else begin
                threadCounter <= threadCounter + 1;
            end
        end
    end
    assign port.currentThread = threadCounter;
`else
    // Single-threaded mode: Single PC register
    FlipFlopWE#( PC_WIDTH, INSN_RESET_VECTOR ) 
        body( 
            .out( port.pcOut ), 
            .in ( port.pcIn ),
            .we ( port.pcWE ), 
            .clk( port.clk ),
            .rst( port.rst )
        );
`endif
        
endmodule : PC

