// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Register Map Table and Wakeup Allocation Table
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
    
`ifdef RSD_ENABLE_SMT
    // Per-thread RMT arrays
    logic rmtWE [ THREAD_NUM ][ COMMIT_WIDTH ];
    LRegNumPath rmtWA[ THREAD_NUM ][ COMMIT_WIDTH ];
    RMT_Entry rmtWV[ THREAD_NUM ][ COMMIT_WIDTH ];
    LRegNumPath rmtRA[ THREAD_NUM ][ RMT_REG_OPERAND_NUM * RENAME_WIDTH ];
    RMT_Entry rmtRV[ THREAD_NUM ][ RMT_REG_OPERAND_NUM * RENAME_WIDTH ];

    // Per-thread RMT instances
    for (genvar t = 0; t < THREAD_NUM; t++) begin : rmtInstances
        DistributedMultiPortRAM #(
            .ENTRY_NUM( LREG_NUM ),
            .ENTRY_BIT_SIZE( $bits(RMT_Entry) ),
            .READ_NUM( RMT_REG_OPERAND_NUM * RENAME_WIDTH ),
            .WRITE_NUM( COMMIT_WIDTH )
        ) regRMT (
            .clk( port.clk ),
            .we( rmtWE[t] ),
            .wa( rmtWA[t] ),
            .wv( rmtWV[t] ),
            .ra( rmtRA[t] ),
            .rv( rmtRV[t] )
        );
    end
`else
    // Single-threaded RMT
    logic rmtWE [ COMMIT_WIDTH ];
    LRegNumPath rmtWA[ COMMIT_WIDTH ];
    RMT_Entry rmtWV[ COMMIT_WIDTH ];
    LRegNumPath rmtRA[ RMT_REG_OPERAND_NUM * RENAME_WIDTH ];
    RMT_Entry rmtRV[ RMT_REG_OPERAND_NUM* RENAME_WIDTH ];

    DistributedMultiPortRAM #(
        .ENTRY_NUM( LREG_NUM ),
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
`endif

    // For initialize
    LRegNumPath rstWriteLogRegNum [ COMMIT_WIDTH ];
    logic [ RMT_ENTRY_BIT_SIZE-1:0 ] rstWritePhyRegNum [ COMMIT_WIDTH ];

    always_comb begin
`ifdef RSD_ENABLE_SMT
        // Per-thread RMT write and read logic
        for (int t = 0; t < THREAD_NUM; t++) begin
            // Write data
            for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
                if ( !port.rst ) begin
                    // Only write if the thread ID matches
                    rmtWE[t][i] = port.rmtWriteReg[i] && (port.thread[i] == t);
                    rmtWA[t][i] = port.rmtWriteReg_LogRegNum[i];
                    rmtWV[t][i].phyRegNum = port.rmtWriteReg_PhyRegNum[i].regNum;
                    
                    // Write to Write Bypass
                    for ( int j = 0; j < i; j++ ) begin
                        if ( rmtWE[t][i] && rmtWA[t][i] == rmtWA[t][j] ) begin
                            rmtWE[t][j] = FALSE;
                        end
                    end

                    // Write data
                    rmtWV[t][i].regIssueQueuePtr = port.watWriteIssueQueuePtr[i];
                end
                else begin
                    // Reset RMT
                    rmtWE[t][i] = ( i == 0 ? TRUE : FALSE );
                    rmtWA[t][i] = rstWriteLogRegNum[i];
                    rmtWV[t][i].phyRegNum = rstWritePhyRegNum[i];
                    rmtWV[t][i].regIssueQueuePtr = '0;
                end
            end

            // Read data from the appropriate thread's RMT
            for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
                rmtRA[t][ RMT_REG_OPERAND_NUM*i   ] = port.logSrcRegA[i];
                rmtRA[t][ RMT_REG_OPERAND_NUM*i+1 ] = port.logSrcRegB[i];
                rmtRA[t][ RMT_REG_OPERAND_NUM*i+2 ] = port.logDstReg[i];
            `ifdef RSD_MARCH_FP_PIPE
                rmtRA[t][ RMT_REG_OPERAND_NUM*i+3 ] = port.logSrcRegC[i];
            `endif
            end
        end

        // Output reads from the appropriate thread's RMT
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            ThreadID threadID = port.thread[i];
            
            `ifdef RSD_MARCH_FP_PIPE
                phySrcRegA[i].isFP        = port.logSrcRegA[i].isFP;
                phySrcRegB[i].isFP        = port.logSrcRegB[i].isFP;
                phySrcRegC[i].isFP        = port.logSrcRegC[i].isFP;
                phyPrevDstReg[i].isFP     = port.logDstReg[i].isFP;
            `endif
                
                // Physical register number is read from thread-specific RMT
                phySrcRegA[i].regNum    = rmtRV[ threadID ][ RMT_REG_OPERAND_NUM*i   ].phyRegNum;
                phySrcRegB[i].regNum    = rmtRV[ threadID ][ RMT_REG_OPERAND_NUM*i+1 ].phyRegNum;
                phyPrevDstReg[i].regNum = rmtRV[ threadID ][ RMT_REG_OPERAND_NUM*i+2 ].phyRegNum;
            `ifdef RSD_MARCH_FP_PIPE
                phySrcRegC[i].regNum    = rmtRV[ threadID ][ RMT_REG_OPERAND_NUM*i+3 ].phyRegNum;
            `endif

                // Dependent instructions' issue queue pointer is read from thread-specific WAT
                srcIssueQueuePtrRegA[i] = rmtRV[threadID][RMT_REG_OPERAND_NUM*i].regIssueQueuePtr;
                srcIssueQueuePtrRegB[i] = rmtRV[threadID][RMT_REG_OPERAND_NUM*i + 1].regIssueQueuePtr;
                port.prevDependIssueQueuePtr[i] = rmtRV[threadID][RMT_REG_OPERAND_NUM*i + 2].regIssueQueuePtr;
            `ifdef RSD_MARCH_FP_PIPE
                srcIssueQueuePtrRegC[i] = rmtRV[threadID][RMT_REG_OPERAND_NUM*i + 3].regIssueQueuePtr;
            `endif
                
                // Write to Read Bypass
                for ( int j = 0; j < i; j++ ) begin
                    if ( port.rmtWriteReg[j] && (port.thread[j] == threadID) ) begin
                        if ( port.logSrcRegA[i] == port.logDstReg[j] ) begin
                            phySrcRegA[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                            srcIssueQueuePtrRegA[i] = port.watWriteIssueQueuePtr[j];
                        end
                        if ( port.logSrcRegB[i] == port.logDstReg[j] ) begin
                            phySrcRegB[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                            srcIssueQueuePtrRegB[i] = port.watWriteIssueQueuePtr[j];
                        end
                    `ifdef RSD_MARCH_FP_PIPE
                        if ( port.logSrcRegC[i] == port.logDstReg[j] ) begin
                            phySrcRegC[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                            srcIssueQueuePtrRegC[i] = port.watWriteIssueQueuePtr[j];
                        end
                    `endif
                        if ( port.logDstReg[i] == port.logDstReg[j] ) begin
                            phyPrevDstReg[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                            port.prevDependIssueQueuePtr[i] = port.watWriteIssueQueuePtr[j];
                        end
                    end
                end
        end
`else
        // Single-threaded logic (unchanged from original)
        // Write data
        for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
            if ( !port.rst ) begin
                rmtWE[i] = port.rmtWriteReg[i];
                rmtWA[i] = port.rmtWriteReg_LogRegNum[i];
                rmtWV[i].phyRegNum = port.rmtWriteReg_PhyRegNum[i].regNum;
                
                // Write to Write Bypass
                for ( int j = 0; j < i; j++ ) begin
                    if ( rmtWE[i] && rmtWA[i] == rmtWA[j] ) begin
                        rmtWE[j] = FALSE;
                    end
                end

                // Write data
                rmtWV[i].regIssueQueuePtr = port.watWriteIssueQueuePtr[i];
            end
            else begin
                // Reset RMT
                rmtWE[i] = ( i == 0 ? TRUE : FALSE );
                rmtWA[i] = rstWriteLogRegNum[i];
                rmtWV[i].phyRegNum = rstWritePhyRegNum[i];
                rmtWV[i].regIssueQueuePtr = '0;
            end
        end

        // Read data
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            // Read RMT with using logical register number
            rmtRA[ RMT_REG_OPERAND_NUM*i   ] = port.logSrcRegA[i];
            rmtRA[ RMT_REG_OPERAND_NUM*i+1 ] = port.logSrcRegB[i];
            rmtRA[ RMT_REG_OPERAND_NUM*i+2 ] = port.logDstReg[i];
`ifdef RSD_MARCH_FP_PIPE
            rmtRA[ RMT_REG_OPERAND_NUM*i+3 ] = port.logSrcRegC[i];
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
                    if ( port.logSrcRegA[i] == port.logDstReg[j] ) begin
                        phySrcRegA[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                        srcIssueQueuePtrRegA[i] = port.watWriteIssueQueuePtr[j];
                    end
                    if ( port.logSrcRegB[i] == port.logDstReg[j] ) begin
                        phySrcRegB[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                        srcIssueQueuePtrRegB[i] = port.watWriteIssueQueuePtr[j];
                    end
`ifdef RSD_MARCH_FP_PIPE
                    if ( port.logSrcRegC[i] == port.logDstReg[j] ) begin
                        phySrcRegC[i].regNum = port.rmtWriteReg_PhyRegNum[j].regNum;
                        srcIssueQueuePtrRegC[i] = port.watWriteIssueQueuePtr[j];
                    end
`endif
                    if ( port.logDstReg[i] == port.logDstReg[j] ) begin
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
`endif
`ifdef RSD_MARCH_FP_PIPE
        port.srcIssueQueuePtrRegC = srcIssueQueuePtrRegC;
`endif
    end
    
    // - Initialization logic
    always_ff @( posedge port.clk ) begin
        for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
            if ( port.rstStart ) begin
                rstWriteLogRegNum[i] <= 0;
            end
            else begin
                rstWriteLogRegNum[i] <= rstWriteLogRegNum[i] + 1;
            end
        end
    end
    
    // フリーリストには0からFREE_LIST_ENTRY_NUM-1が入っているので、
    // RMTの初期値はFREE_LIST_ENTRY_NUM以上の値を使う
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
