// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

import BasicTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import MemoryMapTypes::*;

module RenameLogic (
    RenameLogicIF.RenameLogic port,
    ActiveListIF.RenameLogic activeList,
    RecoveryManagerIF.RenameLogic recovery
);

    logic allocatePhyReg [ RENAME_WIDTH ];
    PRegNumPath allocatedPhyRegNum [ RENAME_WIDTH ];
    logic allocatePhyScalarReg [ RENAME_WIDTH ];
    PScalarRegNumPath allocatedPhyScalarRegNum [ RENAME_WIDTH ];
    
    // Aggregated release signals
    logic releasePhyScalarReg [ COMMIT_WIDTH ];
    PScalarRegNumPath releasedPhyScalarRegNum [ COMMIT_WIDTH ];
    ScalarFreeListCountPath scalarFreeListCount;
    
`ifdef RSD_MARCH_FP_PIPE
    logic allocatePhyScalarFPReg [ RENAME_WIDTH ];
    PScalarFPRegNumPath allocatedPhyScalarFPRegNum [ RENAME_WIDTH ];
    logic releasePhyScalarFPReg [ COMMIT_WIDTH ];
    PScalarFPRegNumPath releasedPhyScalarFPRegNum [ COMMIT_WIDTH ];
    ScalarFPFreeListCountPath scalarFPFreeListCount;
`endif

    // Free lists
    MultiWidthFreeList #(
        .SIZE( SCALAR_FREE_LIST_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( PSCALAR_NUM_BIT_WIDTH ),
        .PUSH_WIDTH( COMMIT_WIDTH ),
        .POP_WIDTH( RENAME_WIDTH ),
        .INITIAL_LENGTH( SCALAR_FREE_LIST_ENTRY_NUM )
    ) scalarFreeList (
        .clk( port.clk ),
        .rst( port.rst ),
        .rstStart( port.rstStart ),
        .count( scalarFreeListCount ),
        .pop( allocatePhyScalarReg ),
        .poppedData( allocatedPhyScalarRegNum ),
        .push( releasePhyScalarReg ),
        .pushedData( releasedPhyScalarRegNum )
    );

`ifdef RSD_MARCH_FP_PIPE
    MultiWidthFreeList #(
        .SIZE( SCALAR_FP_FREE_LIST_ENTRY_NUM ),
        .ENTRY_BIT_SIZE( PSCALAR_FP_NUM_BIT_WIDTH ),
        .PUSH_WIDTH( COMMIT_WIDTH ),
        .POP_WIDTH( RENAME_WIDTH ),
        .INITIAL_LENGTH( SCALAR_FP_FREE_LIST_ENTRY_NUM )
    ) scalarFPFreeList (
        .clk( port.clk ),
        .rst( port.rst ),
        .rstStart( port.rstStart ),
        .count( scalarFPFreeListCount ),
        .pop( allocatePhyScalarFPReg ),
        .poppedData( allocatedPhyScalarFPRegNum ),
        .push( releasePhyScalarFPReg ),
        .pushedData( releasedPhyScalarFPRegNum )
    );
`endif

    // Internal signals to connect Committers
    logic [NUM_THREADS-1:0][COMMIT_WIDTH-1:0] committerReleaseReg;
    PRegNumPath [NUM_THREADS-1:0][COMMIT_WIDTH-1:0] committerPhyReleasedReg;
    
    // Generate Committers per Thread
    generate
        for (genvar t = 0; t < NUM_THREADS; t++) begin : gen_committer
            RenameLogicIF committerPort(port.clk, port.rst, port.rstStart);
            
            always_comb begin
                committerPort.commit = port.commit[t];
                committerPort.commitNum = port.commitNum[t];
                committerPort.recoveryEntryNum = activeList.recoveryEntryNum[t];
                committerPort.readData = activeList.readData[t];
                
                activeList.popHeadNum[t] = committerPort.popHeadNum;
                activeList.popTailNum[t] = committerPort.popTailNum;
                
                committerReleaseReg[t] = committerPort.releaseReg;
                committerPhyReleasedReg[t] = committerPort.phyReleasedReg;
                
                port.flushNum[t] = committerPort.flushNum;
            end

            RenameLogicCommitter #(.TID(t)) committer(
                .port(committerPort.RenameLogicCommitter),
                .activeList(activeList.RenameLogicCommitter),
                .recovery(recovery.RenameLogicCommitter)
            );
            
            // Retirement RMT (One per thread)
            RenameLogicIF retRmtPort(port.clk, port.rst, port.rstStart);
            always_comb begin
                retRmtPort.retRMT_WriteReg = port.retRMT_WriteReg[t];
                retRmtPort.retRMT_WriteReg_PhyRegNum = port.retRMT_WriteReg_PhyRegNum[t];
                retRmtPort.retRMT_WriteReg_LogRegNum = port.retRMT_WriteReg_LogRegNum[t];
                
                for(int i=0; i<RENAME_WIDTH; i++) begin
                    if (port.tid[i] == t) 
                         retRmtPort.retRMT_ReadReg_LogRegNum[i] = port.retRMT_ReadReg_LogRegNum[i];
                    else 
                         retRmtPort.retRMT_ReadReg_LogRegNum[i] = 0;
                end
            end
            
            // SMT FIX: Pass TID parameter for correct reset initialization
            RetirementRMT #(.THREAD_ID(t)) retRMT(retRmtPort.RetirementRMT);
        end
    endgenerate

    // RMT Instantiation
    RenameLogicIF rmtPort(port.clk, port.rst, port.rstStart);
    RMT rmt(rmtPort.RMT);
    
    // Internal RMT control
    logic [ COMMIT_WIDTH-1:0 ] rmtWriteReg;
    PRegNumPath [ COMMIT_WIDTH-1:0 ] rmtWriteReg_PhyRegNum;
    LRegNumPath [ COMMIT_WIDTH-1:0 ] rmtWriteReg_LogRegNum;
    ThreadID    [ COMMIT_WIDTH-1:0 ] rmtWriteReg_Tid; 

    always_comb begin
        
        // SMT FIX: Aggregate Release Signals (OR Logic)
        // Since only one thread commits per cycle, we can safely OR the signals.
        for (int i = 0; i < COMMIT_WIDTH; i++) begin
             releasePhyScalarReg[i] = committerReleaseReg[0][i] | committerReleaseReg[1][i];
             
             // Mux the data based on which commit signal is active
             if (committerReleaseReg[0][i]) 
                 releasedPhyScalarRegNum[i] = committerPhyReleasedReg[0][i];
             else 
                 releasedPhyScalarRegNum[i] = committerPhyReleasedReg[1][i];
                 
`ifdef RSD_MARCH_FP_PIPE
             // FP Release Logic (Placeholder - similar OR logic needed)
             releasePhyScalarFPReg[i] = FALSE; 
`endif
        end

        // Allocations
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
`ifdef RSD_MARCH_FP_PIPE
            allocatedPhyRegNum[i].isFP = port.logDstReg[i].isFP;
            allocatedPhyRegNum[i].regNum = (port.logDstReg[i].isFP ? allocatedPhyScalarFPRegNum[i] : allocatedPhyScalarRegNum[i]);
`else
            allocatedPhyRegNum[i].regNum = allocatedPhyScalarRegNum[i];
`endif
        end
        port.phyDstReg = allocatedPhyRegNum;

        // Allocatable if Global Free List OK and Local Active List OK
        port.allocatable = 
            (scalarFreeListCount >= RENAME_WIDTH) &&
            activeList.allocatable[port.tid[0]]; 


        // Rename Writes
        for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
            allocatePhyReg[i] = port.updateRMT[i] && port.writeReg[i];
`ifdef RSD_MARCH_FP_PIPE
            allocatePhyScalarReg[i] = allocatePhyReg[i] && !port.logDstReg[i].isFP;
            allocatePhyScalarFPReg[i] = allocatePhyReg[i] && port.logDstReg[i].isFP;
`else
            allocatePhyScalarReg[i] = allocatePhyReg[i];
`endif
            
            rmtWriteReg[i] = port.updateRMT[i] && port.writeReg[i];
            rmtWriteReg_PhyRegNum[i] = allocatedPhyRegNum[i];
            rmtWriteReg_LogRegNum[i] = port.logDstReg[i];
            rmtWriteReg_Tid[i] = port.tid[i]; // Pass TID
        end
        
        for ( int i = RENAME_WIDTH; i < COMMIT_WIDTH; i++ ) begin
            rmtWriteReg[i] = FALSE;
            rmtWriteReg_Tid[i] = 0;
        end
        
        // Wiring RMT
        rmtPort.rmtWriteReg = rmtWriteReg;
        rmtPort.rmtWriteReg_PhyRegNum = rmtWriteReg_PhyRegNum;
        rmtPort.rmtWriteReg_LogRegNum = rmtWriteReg_LogRegNum;
        rmtPort.rmtWriteReg_Tid = rmtWriteReg_Tid; // SMT FIX: Wired to interface

        rmtPort.tid = port.tid;
        rmtPort.logSrcRegA = port.logSrcRegA;
        rmtPort.logSrcRegB = port.logSrcRegB;
`ifdef RSD_MARCH_FP_PIPE
        rmtPort.logSrcRegC = port.logSrcRegC;
`endif
        rmtPort.logDstReg = port.logDstReg;
        
        rmtPort.watWriteRegFromPipeReg = port.watWriteRegFromPipeReg;
        rmtPort.watWriteIssueQueuePtrFromPipeReg = port.watWriteIssueQueuePtrFromPipeReg;
        
        port.phySrcRegA = rmtPort.phySrcRegA;
        port.phySrcRegB = rmtPort.phySrcRegB;
`ifdef RSD_MARCH_FP_PIPE
        port.phySrcRegC = rmtPort.phySrcRegC;
`endif
        port.phyPrevDstReg = rmtPort.phyPrevDstReg;
        
        port.srcIssueQueuePtrRegA = rmtPort.srcIssueQueuePtrRegA;
        port.srcIssueQueuePtrRegB = rmtPort.srcIssueQueuePtrRegB;
`ifdef RSD_MARCH_FP_PIPE
        port.srcIssueQueuePtrRegC = rmtPort.srcIssueQueuePtrRegC;
`endif
        port.prevDependIssueQueuePtr = rmtPort.prevDependIssueQueuePtr;
    end

endmodule