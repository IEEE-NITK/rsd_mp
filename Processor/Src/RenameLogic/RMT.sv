// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Register Map Table and Wakeup Allocation Table
// SMT Version: Supports banked addressing for multiple threads
//

import BasicTypes::*;
import RenameLogicTypes::*;
import ActiveListIndexTypes::*;
import SchedulerTypes::*;


module RMT( RenameLogicIF.RMT port );

    // RMT read value
    PRegNumPath phySrcRegA [ RENAME_WIDTH ];
    PRegNumPath phySrcRegB [ RENAME_WIDTH ];
`ifdef RSD_MARCH_FP_PIPE
    PRegNumPath phySrcRegC [ RENAME_WIDTH ];
`endif
    PRegNumPath phyPrevDstReg [ RENAME_WIDTH ];  // For releasing a register.
    
    // WAT read value
    IssueQueueIndexPath srcIssueQueuePtrRegA[ RENAME_WIDTH ];
    IssueQueueIndexPath srcIssueQueuePtrRegB[ RENAME_WIDTH ];
`ifdef RSD_MARCH_FP_PIPE
    IssueQueueIndexPath srcIssueQueuePtrRegC[ RENAME_WIDTH ];
`endif

    //
    // -- Integrated RMT & WAT 
    //
    typedef struct packed // struct RMT_Entry
    {
        logic [ RMT_ENTRY_BIT_SIZE-1:0 ] phyRegNum;
        IssueQueueIndexPath regIssueQueuePtr;
    } RMT_Entry;
    
    logic rmtWE [ COMMIT_WIDTH ];
    
    // SMT Change: Address width includes ThreadID
    logic [LREG_NUM_BIT_WIDTH + THREAD_NUM_BIT_WIDTH - 1 : 0] rmtWA[ COMMIT_WIDTH ];
    logic [LREG_NUM_BIT_WIDTH + THREAD_NUM_BIT_WIDTH - 1 : 0] rmtRA[ RMT_REG_OPERAND_NUM * RENAME_WIDTH ];
    
    RMT_Entry rmtWV[ COMMIT_WIDTH ];
    RMT_Entry rmtRV[ RMT_REG_OPERAND_NUM* RENAME_WIDTH ];

    //
    // RAM Instantiation (Expanded for SMT)
    //
    DistributedMultiPortRAM #(
        .ENTRY_NUM( LREG_NUM * NUM_THREADS ), 
        .ENTRY_BIT_SIZE( $bits(RMT_Entry) ),
        .READ_NUM( RMT_REG_OPERAND_NUM * RENAME_WIDTH ),
        .WRITE_NUM( COMMIT_WIDTH )
    ) regRMT (
        .clk( port.clk ),
        .we( rmtWE ),
        .wa( rmtWA ),
        .wv( rmtWV ),
        .ra( rmtRA ),
        .rv( rmtRV )
    );

    // For initialize
    LRegNumPath rstWriteLogRegNum [ COMMIT_WIDTH ];
    logic [ RMT_ENTRY_BIT_SIZE-1:0 ] rstWritePhyRegNum [ COMMIT_WIDTH ];
    // SMT: Reset iterator needs to track thread as well
    ThreadID rstWriteTid [ COMMIT_WIDTH ]; 

    // Helper to generate banked address
    function automatic logic [LREG_NUM_BIT_WIDTH + THREAD_NUM_BIT_WIDTH - 1 : 0] GetBankedAddr(ThreadID tid, LRegNumPath logReg);
        return {tid, logReg}; // Concatenate TID as MSB
    endfunction

    // --- RMT combinational: writes, reads, and bypass logic (with safe defaults) ---
    always_comb begin
        // --- DEFAULTS: make every driven signal deterministic to avoid latches ---
        // Default write enables / addresses / data for writes
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            rmtWE[i] = 1'b0;
            rmtWA[i] = '0;
            rmtWV[i].phyRegNum = '0;
            rmtWV[i].regIssueQueuePtr = '0;
        end

        // Default read addresses
        for (int i = 0; i < RMT_REG_OPERAND_NUM * RENAME_WIDTH; i++) begin
            rmtRA[i] = '0;
            rmtRV[i].phyRegNum = '0;
            rmtRV[i].regIssueQueuePtr = '0;
        end

        // Default outputs (all RENAME_WIDTH entries)
        phySrcRegA = '{default: '0};
        phySrcRegB = '{default: '0};
`ifdef RSD_MARCH_FP_PIPE
        phySrcRegC = '{default: '0};
`endif
        phyPrevDstReg = '{default: '0};

        srcIssueQueuePtrRegA = '{default: '0};
        srcIssueQueuePtrRegB = '{default: '0};
`ifdef RSD_MARCH_FP_PIPE
        srcIssueQueuePtrRegC = '{default: '0};
`endif

        port.prevDependIssueQueuePtr = '{default: '0};
        // --- end defaults -----------------------------------------------------

        // --- Write data (and write-bypass protection) ------------------------
        for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
            if ( !port.rst ) begin
                rmtWE[i] = port.rmtWriteReg[i];
                // SMT: Combine TID and Logical Register for address
                rmtWA[i] = GetBankedAddr(port.rmtWriteReg_Tid[i], port.rmtWriteReg_LogRegNum[i]);

                rmtWV[i].phyRegNum = port.rmtWriteReg_PhyRegNum[i].regNum;
                rmtWV[i].regIssueQueuePtr = port.watWriteIssueQueuePtr[i];

                // Write bypass: clear older writes to same banked address
                for ( int j = 0; j < i; j++ ) begin
                    if ( rmtWE[i] && rmtWA[i] == rmtWA[j] ) begin
                        rmtWE[j] = 1'b0;
                    end
                end
            end
            else begin
                // Reset RMT initialization values
                rmtWE[i] = ( i == 0 ? 1'b1 : 1'b0 );
                rmtWA[i] = GetBankedAddr(rstWriteTid[i], rstWriteLogRegNum[i]);
                rmtWV[i].phyRegNum = rstWritePhyRegNum[i];
                rmtWV[i].regIssueQueuePtr = '0;
            end
        end

        // --- Read addresses: build banked addresses for each operand of each slot ---
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            rmtRA[ RMT_REG_OPERAND_NUM*i   ] = GetBankedAddr(port.tid[i], port.logSrcRegA[i]);
            rmtRA[ RMT_REG_OPERAND_NUM*i+1 ] = GetBankedAddr(port.tid[i], port.logSrcRegB[i]);
            rmtRA[ RMT_REG_OPERAND_NUM*i+2 ] = GetBankedAddr(port.tid[i], port.logDstReg[i]);
`ifdef RSD_MARCH_FP_PIPE
            rmtRA[ RMT_REG_OPERAND_NUM*i+3 ] = GetBankedAddr(port.tid[i], port.logSrcRegC[i]);
`endif
        end

        // --- Read data -> defaulted above by rmtRV defaults; assign outputs from RAM results ---
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
`ifdef RSD_MARCH_FP_PIPE
            phySrcRegA[i].isFP        = port.logSrcRegA[i].isFP;
            phySrcRegB[i].isFP        = port.logSrcRegB[i].isFP;
            phySrcRegC[i].isFP        = port.logSrcRegC[i].isFP;
            phyPrevDstReg[i].isFP     = port.logDstReg[i].isFP;
`endif

            // Physical register number is read from RMT
            phySrcRegA[i].regNum    = rmtRV[ RMT_REG_OPERAND_NUM*i   ].phyRegNum;
            phySrcRegB[i].regNum    = rmtRV[ RMT_REG_OPERAND_NUM*i+1 ].phyRegNum;
            phyPrevDstReg[i].regNum = rmtRV[ RMT_REG_OPERAND_NUM*i+2 ].phyRegNum;
`ifdef RSD_MARCH_FP_PIPE
            phySrcRegC[i].regNum    = rmtRV[ RMT_REG_OPERAND_NUM*i+3 ].phyRegNum;
`endif

            // Dependent instructions' issue queue pointer is read from WAT
            srcIssueQueuePtrRegA[i] = rmtRV[RMT_REG_OPERAND_NUM*i].regIssueQueuePtr;
            srcIssueQueuePtrRegB[i] = rmtRV[RMT_REG_OPERAND_NUM*i + 1].regIssueQueuePtr;
            port.prevDependIssueQueuePtr[i] = rmtRV[RMT_REG_OPERAND_NUM*i + 2].regIssueQueuePtr;
`ifdef RSD_MARCH_FP_PIPE
            srcIssueQueuePtrRegC[i] = rmtRV[RMT_REG_OPERAND_NUM*i + 3].regIssueQueuePtr;
`endif

            // Read-bypass: override with any in-flight writes (must match TID and log reg)
            for ( int j = 0; j < i; j++ ) begin
                if ( port.rmtWriteReg[j] ) begin
                    // Compare TID and logical reg numbers inline to avoid temporaries
                    if ( (port.tid[i] == port.rmtWriteReg_Tid[j]) &&
                         (port.logSrcRegA[i] == port.rmtWriteReg_LogRegNum[j]) ) begin
                        phySrcRegA[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                        srcIssueQueuePtrRegA[i] = port.watWriteIssueQueuePtr[j];
                    end
                    if ( (port.tid[i] == port.rmtWriteReg_Tid[j]) &&
                         (port.logSrcRegB[i] == port.rmtWriteReg_LogRegNum[j]) ) begin
                        phySrcRegB[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                        srcIssueQueuePtrRegB[i] = port.watWriteIssueQueuePtr[j];
                    end
`ifdef RSD_MARCH_FP_PIPE
                    if ( (port.tid[i] == port.rmtWriteReg_Tid[j]) &&
                         (port.logSrcRegC[i] == port.rmtWriteReg_LogRegNum[j]) ) begin
                        phySrcRegC[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                        srcIssueQueuePtrRegC[i] = port.watWriteIssueQueuePtr[j];
                    end
`endif
                    if ( (port.tid[i] == port.rmtWriteReg_Tid[j]) &&
                         (port.logDstReg[i] == port.rmtWriteReg_LogRegNum[j]) ) begin
                        phyPrevDstReg[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                        port.prevDependIssueQueuePtr[i] = port.watWriteIssueQueuePtr[j];
                    end
                end
            end
        end

        // --- Drive outputs to interface (already defaulted and possibly overwritten) ---
        port.phySrcRegA = phySrcRegA;
        port.phySrcRegB = phySrcRegB;
`ifdef RSD_MARCH_FP_PIPE
        port.phySrcRegC = phySrcRegC;
`endif
        port.phyPrevDstReg = phyPrevDstReg;

        port.srcIssueQueuePtrRegA = srcIssueQueuePtrRegA;
        port.srcIssueQueuePtrRegB = srcIssueQueuePtrRegB;
`ifdef RSD_MARCH_FP_PIPE
        port.srcIssueQueuePtrRegC = srcIssueQueuePtrRegC;
`endif
    end

    
    // - Initialization logic
    // SMT: Must iterate through ALL registers of ALL threads
    always_ff @( posedge port.clk ) begin
        for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
            if ( port.rstStart ) begin
                rstWriteLogRegNum[i] <= 0;
                rstWriteTid[i] <= 0;
            end
            else begin
                // Initialization counter
                // If current reg is max, reset reg and increment thread
                if (rstWriteLogRegNum[i] == LREG_NUM - 1) begin
                    rstWriteLogRegNum[i] <= 0;
                    if (rstWriteTid[i] < NUM_THREADS - 1) begin
                        rstWriteTid[i] <= rstWriteTid[i] + 1;
                    end
                end
                else begin
                    rstWriteLogRegNum[i] <= rstWriteLogRegNum[i] + 1;
                end
            end
        end
    end
    
    // Free List / Reset Values
    always_comb begin
        for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
`ifdef RSD_MARCH_FP_PIPE
            if ( !rstWriteLogRegNum[i].isFP ) begin
                rstWritePhyRegNum[i] =
                    rstWriteLogRegNum[i].regNum + SCALAR_FREE_LIST_ENTRY_NUM;
            end
            else begin
                rstWritePhyRegNum[i] =
                    rstWriteLogRegNum[i].regNum + SCALAR_FP_FREE_LIST_ENTRY_NUM;
            end
`else
            rstWritePhyRegNum[i] =
                rstWriteLogRegNum[i].regNum + SCALAR_FREE_LIST_ENTRY_NUM;
`endif
        end
    end   
    
endmodule