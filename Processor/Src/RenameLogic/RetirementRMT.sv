// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

import BasicTypes::*;
import RenameLogicTypes::*;

module RetirementRMT #(
    parameter integer THREAD_ID = 0 // SMT: Used for Reset Offset
)(
    RenameLogicIF.RetirementRMT port
);
    logic we [ COMMIT_WIDTH ];
    LRegNumPath writeLogRegNum[ COMMIT_WIDTH ];
    logic [ RMT_ENTRY_BIT_SIZE-1:0 ] writePhyRegNum[ COMMIT_WIDTH ];

    LRegNumPath rstWriteLogRegNum[ COMMIT_WIDTH ];
    logic [ RMT_ENTRY_BIT_SIZE-1:0 ] rstWritePhyRegNum[ COMMIT_WIDTH ];

    LRegNumPath readLogRegNum[ RENAME_WIDTH ];
    logic [ RMT_ENTRY_BIT_SIZE-1:0 ] readPhyRegNum[ RENAME_WIDTH ];

    // SMT FIX: Use standard entry number (One instance per thread)
    DistributedMultiPortRAM #(
        .ENTRY_NUM( RMT_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( RMT_ENTRY_BIT_SIZE ),
        .READ_NUM( RENAME_WIDTH ),
        .WRITE_NUM( COMMIT_WIDTH )
    ) regRMT (
        .clk( port.clk ),
        .we( we ),
        .wa( writeLogRegNum ),
        .wv( writePhyRegNum ),
        .ra( readLogRegNum ),
        .rv( readPhyRegNum )
    );

    always_comb begin
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            if ( !port.rst ) begin
                // <-- USE THE _Single NAMES FROM THE RetirementRMT MODPORT
                writeLogRegNum[i] = port.retRMT_WriteReg_LogRegNum_Single[i];
                writePhyRegNum[i] = port.retRMT_WriteReg_PhyRegNum_Single[i].regNum;
                we[i] = port.retRMT_WriteReg_Single[i];

                for (int j = 0; j < i; j++) begin
                    if (we[i] && writeLogRegNum[i] == writeLogRegNum[j])
                        we[j] = FALSE;
                end
            end
            else begin
                writeLogRegNum[i] = rstWriteLogRegNum[i];
                writePhyRegNum[i] = rstWritePhyRegNum[i];
                we[i] = (i == 0 ? TRUE : FALSE);
            end
        end

        for (int i = 0; i < RENAME_WIDTH; i++) begin
            readLogRegNum[i] = port.retRMT_ReadReg_LogRegNum[i];
            port.retRMT_ReadReg_PhyRegNum[i].regNum = readPhyRegNum[i];
`ifdef RSD_MARCH_FP_PIPE
            port.retRMT_ReadReg_PhyRegNum[i].isFP = port.retRMT_ReadReg_LogRegNum[i].isFP;
`endif
        end
    end

    always_ff @( posedge port.clk ) begin
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            if (port.rstStart)
                rstWriteLogRegNum[i] <= 0;
            else
                rstWriteLogRegNum[i] <= rstWriteLogRegNum[i] + 1;
        end
    end

    // SMT FIX: Initialize with thread offset
    always_comb begin
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            logic [ RMT_ENTRY_BIT_SIZE-1:0 ] base_offset;
`ifdef RSD_MARCH_FP_PIPE
             if ( !rstWriteLogRegNum[i].isFP )
                 base_offset = SCALAR_FREE_LIST_ENTRY_NUM + (THREAD_ID * 32);
             else
                 base_offset = SCALAR_FP_FREE_LIST_ENTRY_NUM + (THREAD_ID * 32);
`else
             base_offset = SCALAR_FREE_LIST_ENTRY_NUM + (THREAD_ID * 32);
`endif
            rstWritePhyRegNum[i] = rstWriteLogRegNum[i].regNum + base_offset;
        end
    end
endmodule
