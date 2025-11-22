// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// PC
// PC has INSN_RESET_VECTOR and cannot use AddrReg.
//

// PC.sv
import BasicTypes::*;
import MemoryMapTypes::*;
import MicroArchConf::*;

module PC(NextPCStageIF.PC port);

    // One PC register per thread
    logic [PC_WIDTH-1:0] pc_addr[CONF_THREAD_NUM];

    generate
        for (genvar i = 0; i < CONF_THREAD_NUM; i++) begin : pc_thread
            FlipFlopWE #(
                .FF_WIDTH    (PC_WIDTH),
                .RESET_VALUE (INSN_RESET_VECTOR)
            ) body (
                .out (pc_addr[i]),
                .in  (port.pcIn.addr),
                .we  (port.pcWE && (port.pcIn.tid == i)),
                .clk (port.clk),
                .rst (port.rst)
            );
        end
    endgenerate

    // Always output the PC for the thread currently addressed by pcIn.tid
    // (NextPCStage is responsible for setting pcIn.tid correctly)
    always_comb begin
        port.pcOut.addr = pc_addr[port.pcIn.tid];
        port.pcOut.tid  = port.pcIn.tid;
    end

endmodule : PC

