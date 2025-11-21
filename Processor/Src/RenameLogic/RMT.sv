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

    always_comb begin
            logic tidMatch; 
           // tidMatch = FALSE;
        // Write data
        for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
            if ( !port.rst ) begin
                rmtWE[i] = port.rmtWriteReg[i];
                // SMT: Combine TID and Logical Register for address
                rmtWA[i] = GetBankedAddr(port.rmtWriteReg_Tid[i], port.rmtWriteReg_LogRegNum[i]);
                
                rmtWV[i].phyRegNum = port.rmtWriteReg_PhyRegNum[i].regNum;
                
                // Write to Write Bypass
                for ( int j = 0; j < i; j++ ) begin
                    if ( rmtWE[i] && rmtWA[i] == rmtWA[j] ) begin
                        rmtWE[j] = FALSE;
                    end
                end

                // Write data (WAT)
                rmtWV[i].regIssueQueuePtr = port.watWriteIssueQueuePtr[i];
            end
            else begin
                // Reset RMT
                rmtWE[i] = ( i == 0 ? TRUE : FALSE );
                rmtWA[i] = GetBankedAddr(rstWriteTid[i], rstWriteLogRegNum[i]);
                rmtWV[i].phyRegNum = rstWritePhyRegNum[i];
                rmtWV[i].regIssueQueuePtr = '0;
            end
        end

        // Read data
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            // Read RMT with using logical register number AND ThreadID
            
            // Initialize tidMatch for safety
            rmtRA[ RMT_REG_OPERAND_NUM*i   ] = GetBankedAddr(port.tid[i], port.logSrcRegA[i]);
            rmtRA[ RMT_REG_OPERAND_NUM*i+1 ] = GetBankedAddr(port.tid[i], port.logSrcRegB[i]);
            rmtRA[ RMT_REG_OPERAND_NUM*i+2 ] = GetBankedAddr(port.tid[i], port.logDstReg[i]);
`ifdef RSD_MARCH_FP_PIPE
            rmtRA[ RMT_REG_OPERAND_NUM*i+3 ] = GetBankedAddr(port.tid[i], port.logSrcRegC[i]);
`endif
            
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
            
            // Write to Read Bypass
            for ( int j = 0; j < i; j++ ) begin
                if ( port.rmtWriteReg[j] ) begin
                    // SMT Check: Must match TID as well as Register Number
                    logic tidMatch;
                    tidMatch = (port.tid[i] == port.rmtWriteReg_Tid[j]);

                    if ( tidMatch && port.logSrcRegA[i] == port.rmtWriteReg_LogRegNum[j] ) begin
                        phySrcRegA[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                        srcIssueQueuePtrRegA[i] = port.watWriteIssueQueuePtr[j];
                    end
                    if ( tidMatch && port.logSrcRegB[i] == port.rmtWriteReg_LogRegNum[j] ) begin
                        phySrcRegB[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                        srcIssueQueuePtrRegB[i] = port.watWriteIssueQueuePtr[j];
                    end
`ifdef RSD_MARCH_FP_PIPE
                    if ( tidMatch && port.logSrcRegC[i] == port.rmtWriteReg_LogRegNum[j] ) begin
                        phySrcRegC[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                        srcIssueQueuePtrRegC[i] = port.watWriteIssueQueuePtr[j];
                    end
`endif
                    if ( tidMatch && port.logDstReg[i] == port.rmtWriteReg_LogRegNum[j] ) begin
                        phyPrevDstReg[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                        port.prevDependIssueQueuePtr[i] = port.watWriteIssueQueuePtr[j];
                    end
                end
            end
        end

        // To interface
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