// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// PC (Program Counter)
// SMT Update: Now contains a bank of PC registers, one per thread.
//

import BasicTypes::*;
import MemoryMapTypes::*;

module PC( NextPCStageIF.PC port );
    
    // SMT CHANGE: Generate a PC register for each thread
    generate
        for (genvar i = 0; i < NUM_THREADS; i++) begin : pc_regs
            FlipFlopWE#( PC_WIDTH, INSN_RESET_VECTOR ) 
            body( 
                .out( port.pcOut[i] ),   // Output array
                .in ( port.pcIn ),       // Shared input (muxed in NextPCStage)
                .we ( port.pcWE[i] ),    // Individual write enable
                .clk( port.clk ),
                .rst( port.rst )
            );
        end
    endgenerate
        
endmodule : PC