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
    typedef struct packed // RMT_Entry
    {
        logic [ RMT_ENTRY_BIT_SIZE-1:0 ] phyRegNum;
        IssueQueueIndexPath regIssueQueuePtr;
    } RMT_Entry;
    
    // Write ports to RMT/WAT
    logic rmtWE [ COMMIT_WIDTH ];
    
    // Address width: log reg index + thread id
    localparam int RMT_ADDR_BIT_WIDTH = LREG_NUM_BIT_WIDTH + THREAD_NUM_BIT_WIDTH;

    // UNPACKED arrays of packed address vectors
    logic [RMT_ADDR_BIT_WIDTH-1:0] rmtWA[ COMMIT_WIDTH ];
    logic [RMT_ADDR_BIT_WIDTH-1:0] rmtRA[ RMT_REG_OPERAND_NUM * RENAME_WIDTH ];
    
    RMT_Entry rmtWV[ COMMIT_WIDTH ];
    RMT_Entry rmtRV[ RMT_REG_OPERAND_NUM * RENAME_WIDTH ];

    // For initialize
    LRegNumPath rstWriteLogRegNum [ COMMIT_WIDTH ];
    logic [ RMT_ENTRY_BIT_SIZE-1:0 ] rstWritePhyRegNum [ COMMIT_WIDTH ];
    ThreadID rstWriteTid [ COMMIT_WIDTH ];  // which thread we are resetting for this port

    // Helper to generate banked address (TID as MSB)
    function automatic logic [RMT_ADDR_BIT_WIDTH-1:0]
        GetBankedAddr(ThreadID tid, LRegNumPath logReg);
        // When THREAD_NUM_BIT_WIDTH == 0, {tid, logReg} collapses to logReg
        return {tid, logReg};
    endfunction

    //
    // Simple behavioral multi-port RAM
    // Works for any NUM_THREADS, COMMIT_WIDTH, RENAME_WIDTH.
    //
    RMT_Entry mem [ RMT_ENTRY_NUM ];

    // Multi-write: each write port updates mem if enabled.
    integer w;
    always_ff @(posedge port.clk) begin
        for (w = 0; w < COMMIT_WIDTH; w++) begin
            if (rmtWE[w]) begin
                mem[ rmtWA[w] ] <= rmtWV[w];
            end
        end
    end

    // Multi-read: combinational read for each read port
    integer r;
    always_comb begin
        for (r = 0; r < RMT_REG_OPERAND_NUM * RENAME_WIDTH; r++) begin
            rmtRV[r] = mem[ rmtRA[r] ];
        end
    end

    // --- RMT combinational: writes, reads, and bypass logic (with safe defaults) ---
    always_comb begin
        // --- DEFAULTS: avoid latches ---

        // Default write enables / addresses / data for writes
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
            rmtWE[i]                  = 1'b0;
            rmtWA[i]                  = '0;
            rmtWV[i].phyRegNum        = '0;
            rmtWV[i].regIssueQueuePtr = '0;
        end

        // Default read addresses
        for (int i = 0; i < RMT_REG_OPERAND_NUM * RENAME_WIDTH; i++) begin
            rmtRA[i] = '0;
        end

        // Default outputs (all RENAME_WIDTH entries)
        phySrcRegA    = '{default: '0};
        phySrcRegB    = '{default: '0};
`ifdef RSD_MARCH_FP_PIPE
        phySrcRegC    = '{default: '0};
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
                rmtWA[i] = GetBankedAddr(
                    port.rmtWriteReg_Tid[i],
                    port.rmtWriteReg_LogRegNum[i]
                );

                rmtWV[i].phyRegNum        = port.rmtWriteReg_PhyRegNum[i].regNum;
                rmtWV[i].regIssueQueuePtr = port.watWriteIssueQueuePtr[i];

                // Write-bypass: clear older writes to same banked address
                for ( int j = 0; j < i; j++ ) begin
                    if ( rmtWE[i] && (rmtWA[i] == rmtWA[j]) ) begin
                        rmtWE[j] = 1'b0;
                    end
                end
            end
            else begin
                // Reset RMT initialization values
                // Only the first port is actually used for reset writes
                rmtWE[i] = ( i == 0 ) ? 1'b1 : 1'b0;
                rmtWA[i] = GetBankedAddr(
                    rstWriteTid[i],
                    rstWriteLogRegNum[i]
                );
                rmtWV[i].phyRegNum        = rstWritePhyRegNum[i];
                rmtWV[i].regIssueQueuePtr = '0;
            end
        end

        // --- Read addresses: build banked addresses for each operand of each slot ---
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            rmtRA[ RMT_REG_OPERAND_NUM*i   ] = GetBankedAddr(
                port.tid[i],
                port.logSrcRegA[i]
            );
            rmtRA[ RMT_REG_OPERAND_NUM*i+1 ] = GetBankedAddr(
                port.tid[i],
                port.logSrcRegB[i]
            );
            rmtRA[ RMT_REG_OPERAND_NUM*i+2 ] = GetBankedAddr(
                port.tid[i],
                port.logDstReg[i]
            );
`ifdef RSD_MARCH_FP_PIPE
            rmtRA[ RMT_REG_OPERAND_NUM*i+3 ] = GetBankedAddr(
                port.tid[i],
                port.logSrcRegC[i]
            );
`endif
        end

        // --- Read data -> assign outputs from RAM results + bypass ------------------
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
`ifdef RSD_MARCH_FP_PIPE
            phySrcRegA[i].isFP    = port.logSrcRegA[i].isFP;
            phySrcRegB[i].isFP    = port.logSrcRegB[i].isFP;
            phySrcRegC[i].isFP    = port.logSrcRegC[i].isFP;
            phyPrevDstReg[i].isFP = port.logDstReg[i].isFP;
`endif

            // Physical register number is read from RMT
            phySrcRegA[i].regNum    = rmtRV[ RMT_REG_OPERAND_NUM*i   ].phyRegNum;
            phySrcRegB[i].regNum    = rmtRV[ RMT_REG_OPERAND_NUM*i+1 ].phyRegNum;
            phyPrevDstReg[i].regNum = rmtRV[ RMT_REG_OPERAND_NUM*i+2 ].phyRegNum;
`ifdef RSD_MARCH_FP_PIPE
            phySrcRegC[i].regNum    = rmtRV[ RMT_REG_OPERAND_NUM*i+3 ].phyRegNum;
`endif

            // Dependent instructions' issue queue pointer is read from WAT
            srcIssueQueuePtrRegA[i] = rmtRV[ RMT_REG_OPERAND_NUM*i   ].regIssueQueuePtr;
            srcIssueQueuePtrRegB[i] = rmtRV[ RMT_REG_OPERAND_NUM*i+1 ].regIssueQueuePtr;
            port.prevDependIssueQueuePtr[i] =
                rmtRV[ RMT_REG_OPERAND_NUM*i+2 ].regIssueQueuePtr;
`ifdef RSD_MARCH_FP_PIPE
            srcIssueQueuePtrRegC[i] = rmtRV[ RMT_REG_OPERAND_NUM*i+3 ].regIssueQueuePtr;
`endif

            // Read-bypass: override with any in-flight writes (must match TID and log reg)
            for ( int j = 0; j < i; j++ ) begin
                if ( port.rmtWriteReg[j] ) begin
                    // Compare TID and logical reg numbers
                    if ( (port.tid[i] == port.rmtWriteReg_Tid[j]) &&
                         (port.logSrcRegA[i] == port.rmtWriteReg_LogRegNum[j]) ) begin
                        phySrcRegA[i].regNum      = port.rmtWriteReg_PhyRegNum[j].regNum;
                        srcIssueQueuePtrRegA[i]   = port.watWriteIssueQueuePtr[j];
                    end
                    if ( (port.tid[i] == port.rmtWriteReg_Tid[j]) &&
                         (port.logSrcRegB[i] == port.rmtWriteReg_LogRegNum[j]) ) begin
                        phySrcRegB[i].regNum      = port.rmtWriteReg_PhyRegNum[j].regNum;
                        srcIssueQueuePtrRegB[i]   = port.watWriteIssueQueuePtr[j];
                    end
`ifdef RSD_MARCH_FP_PIPE
                    if ( (port.tid[i] == port.rmtWriteReg_Tid[j]) &&
                         (port.logSrcRegC[i] == port.rmtWriteReg_LogRegNum[j]) ) begin
                        phySrcRegC[i].regNum      = port.rmtWriteReg_PhyRegNum[j].regNum;
                        srcIssueQueuePtrRegC[i]   = port.watWriteIssueQueuePtr[j];
                    end
`endif
                    if ( (port.tid[i] == port.rmtWriteReg_Tid[j]) &&
                         (port.logDstReg[i] == port.rmtWriteReg_LogRegNum[j]) ) begin
                        phyPrevDstReg[i].regNum         = port.rmtWriteReg_PhyRegNum[j].regNum;
                        port.prevDependIssueQueuePtr[i] = port.watWriteIssueQueuePtr[j];
                    end
                end
            end
        end

        // --- Drive outputs to interface ---
        port.phySrcRegA      = phySrcRegA;
        port.phySrcRegB      = phySrcRegB;
`ifdef RSD_MARCH_FP_PIPE
        port.phySrcRegC      = phySrcRegC;
`endif
        port.phyPrevDstReg   = phyPrevDstReg;

        port.srcIssueQueuePtrRegA = srcIssueQueuePtrRegA;
        port.srcIssueQueuePtrRegB = srcIssueQueuePtrRegB;
`ifdef RSD_MARCH_FP_PIPE
        port.srcIssueQueuePtrRegC = srcIssueQueuePtrRegC;
`endif
    end

    // - Initialization logic
    // SMT: iterate through ALL registers of ALL threads.
    always_ff @( posedge port.clk ) begin
        for ( int i = 0; i < COMMIT_WIDTH; i++ ) begin
            if ( port.rstStart ) begin
                rstWriteLogRegNum[i] <= '0;
                rstWriteTid[i]       <= '0;
            end
            else begin
                if ( rstWriteLogRegNum[i] == LREG_NUM - 1 ) begin
                    rstWriteLogRegNum[i] <= '0;
                    // Guard NUM_THREADS > 1 to avoid UNSIGNED warning
                    if (NUM_THREADS > 1 && (rstWriteTid[i] < NUM_THREADS - 1)) begin
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
