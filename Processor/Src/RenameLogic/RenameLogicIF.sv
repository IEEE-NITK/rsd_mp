// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// RenameLogic Interface
//

import BasicTypes::*;
import RenameLogicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;


interface RenameLogicIF( input logic clk, rst, rstStart );

    // Logical register numbers.
    ThreadID tid [ RENAME_WIDTH ];
    LRegNumPath logSrcRegA [ RENAME_WIDTH ];
    LRegNumPath logSrcRegB [ RENAME_WIDTH ];
`ifdef RSD_MARCH_FP_PIPE
    LRegNumPath logSrcRegC [ RENAME_WIDTH ];
`endif
    LRegNumPath logDstReg [ RENAME_WIDTH ];

    // Renamed physical register numbers.
    PRegNumPath phySrcRegA [ RENAME_WIDTH ];
    PRegNumPath phySrcRegB [ RENAME_WIDTH ];
`ifdef RSD_MARCH_FP_PIPE
    PRegNumPath phySrcRegC [ RENAME_WIDTH ];
`endif
    PRegNumPath phyDstReg [ RENAME_WIDTH ];
    PRegNumPath phyPrevDstReg [ RENAME_WIDTH ];  // For releasing a register.

    // Read/Write control
    logic [ RENAME_WIDTH-1:0 ] updateRMT;
    logic readRegA [ RENAME_WIDTH ];
    logic readRegB [ RENAME_WIDTH ];
`ifdef RSD_MARCH_FP_PIPE
    logic readRegC [ RENAME_WIDTH ];
`endif
    logic writeReg [ RENAME_WIDTH ];

    // Release registers on retirement and recovery.
    logic releaseReg [ COMMIT_WIDTH ];
    PRegNumPath phyReleasedReg [ COMMIT_WIDTH ];

    // There are enough resources to rename.
    logic allocatable;

    // RMT control signals, which are generated in RenameLogic.
    logic [ COMMIT_WIDTH-1:0 ] rmtWriteReg;
    PRegNumPath  rmtWriteReg_PhyRegNum[ COMMIT_WIDTH ];
    LRegNumPath  rmtWriteReg_LogRegNum[ COMMIT_WIDTH ];
    ThreadID     rmtWriteReg_Tid[ COMMIT_WIDTH ]; // Added

    // Retirement RMT control signals, which are generated in CommitStage.
    logic [COMMIT_WIDTH-1:0] retRMT_WriteReg [NUM_THREADS]; // Arrayed for SMT
    PRegNumPath retRMT_WriteReg_PhyRegNum [NUM_THREADS][COMMIT_WIDTH];
    LRegNumPath retRMT_WriteReg_LogRegNum [NUM_THREADS][COMMIT_WIDTH];

    PRegNumPath retRMT_ReadReg_PhyRegNum[RENAME_WIDTH];
    LRegNumPath retRMT_ReadReg_LogRegNum[RENAME_WIDTH];

    // WAT control signals, which are generated in RenameLogic.
    logic [RENAME_WIDTH-1 : 0] watWriteRegFromPipeReg;
    IssueQueueIndexPath  watWriteIssueQueuePtrFromPipeReg[ RENAME_WIDTH ];
    IssueQueueIndexPath srcIssueQueuePtrRegA[ RENAME_WIDTH ];
    IssueQueueIndexPath srcIssueQueuePtrRegB[ RENAME_WIDTH ];
`ifdef RSD_MARCH_FP_PIPE
    IssueQueueIndexPath srcIssueQueuePtrRegC[ RENAME_WIDTH ];
`endif

    // For Recover WAT from Activelist
    IssueQueueIndexPath prevDependIssueQueuePtr[ RENAME_WIDTH ];

    // Write port for WAT
    logic watWriteReg[ COMMIT_WIDTH ];
    LRegNumPath watWriteLogRegNum[ COMMIT_WIDTH ];
    IssueQueueIndexPath  watWriteIssueQueuePtr[ COMMIT_WIDTH ];

    // Commitment/recovery
    logic commit [NUM_THREADS];
    CommitLaneCountPath commitNum [NUM_THREADS];
    CommitLaneCountPath flushNum [NUM_THREADS];

    // Interface for Committers (Internal)
    ActiveListEntry readData [COMMIT_WIDTH]; // Temp wire for committer
    ActiveListCountPath recoveryEntryNum;   // Temp wire for committer
    CommitLaneCountPath popHeadNum;
    CommitLaneCountPath popTailNum;

    // To a rename logic
    modport RenameLogic(
    input
        clk,
        rst,
        rstStart,
        updateRMT,
        writeReg,
        releaseReg,
        phyReleasedReg,
        retRMT_ReadReg_PhyRegNum,
        tid,
        logDstReg,
        logSrcRegA,       // Fix
        logSrcRegB,       // Fix
`ifdef RSD_MARCH_FP_PIPE
        logSrcRegC,       // Fix
`endif
        watWriteRegFromPipeReg,
        watWriteIssueQueuePtrFromPipeReg,
        commit,           // Fix
        commitNum,        // Fix
        retRMT_WriteReg,         // Fix
        retRMT_WriteReg_PhyRegNum, // Fix
        retRMT_WriteReg_LogRegNum, // Fix
    output
        allocatable,
        phyDstReg,
        retRMT_ReadReg_LogRegNum,
        rmtWriteReg,
        rmtWriteReg_PhyRegNum,
        rmtWriteReg_LogRegNum,
        rmtWriteReg_Tid,
        watWriteReg,
        watWriteLogRegNum,
        watWriteIssueQueuePtr,
        phySrcRegA,       // Fix
        phySrcRegB,       // Fix
`ifdef RSD_MARCH_FP_PIPE
        phySrcRegC,       // Fix
`endif
        phyPrevDstReg,           // Fix
        srcIssueQueuePtrRegA,    // Fix
        srcIssueQueuePtrRegB,    // Fix
`ifdef RSD_MARCH_FP_PIPE
        srcIssueQueuePtrRegC,    // Fix
`endif
        prevDependIssueQueuePtr,  // Fix
        flushNum                 // Fix
    );

    modport RenameStage(
    input
        phySrcRegA,
        phySrcRegB,
`ifdef RSD_MARCH_FP_PIPE
        phySrcRegC,
`endif
        phyDstReg,
        phyPrevDstReg,
        srcIssueQueuePtrRegA,
        srcIssueQueuePtrRegB,
`ifdef RSD_MARCH_FP_PIPE
        srcIssueQueuePtrRegC,
`endif
        allocatable,
        prevDependIssueQueuePtr,
    output
        tid,
        logSrcRegA,
        logSrcRegB,
`ifdef RSD_MARCH_FP_PIPE
        logSrcRegC,
`endif
        logDstReg,
        updateRMT,
        readRegA,
        readRegB,
`ifdef RSD_MARCH_FP_PIPE
        readRegC,
`endif
        writeReg,
        watWriteRegFromPipeReg,
        watWriteIssueQueuePtrFromPipeReg
    );

    modport CommitStage(
    input
        releaseReg,
        phyReleasedReg,
        flushNum,
    output
        commit,
        commitNum,
        retRMT_WriteReg,
        retRMT_WriteReg_PhyRegNum,
        retRMT_WriteReg_LogRegNum
    );

    modport RenameLogicCommitter(
    input
        clk,
        rst,
        commit,
        commitNum,
        readData,         // Fix
        recoveryEntryNum, // Fix
    output
        releaseReg,
        phyReleasedReg,
        flushNum,
        popHeadNum, // Fix
        popTailNum  // Fix
    );

    modport RetirementRMT(
    input
        clk,
        rst,
        rstStart,
        retRMT_WriteReg,
        retRMT_WriteReg_PhyRegNum,
        retRMT_WriteReg_LogRegNum,
        retRMT_ReadReg_LogRegNum,
    output
        retRMT_ReadReg_PhyRegNum
    );

    modport RMT(
    input
        clk,
        rst,
        rstStart,
        rmtWriteReg,
        rmtWriteReg_PhyRegNum,
        rmtWriteReg_LogRegNum,
        rmtWriteReg_Tid, // Added to input
        watWriteReg,
        watWriteLogRegNum,
        watWriteIssueQueuePtr,
        tid,
        logSrcRegA,
        logSrcRegB,
`ifdef RSD_MARCH_FP_PIPE
        logSrcRegC,
`endif
        logDstReg,
    output
        phySrcRegA,
        phySrcRegB,
`ifdef RSD_MARCH_FP_PIPE
        phySrcRegC,
`endif
        phyPrevDstReg,
        srcIssueQueuePtrRegA,
        srcIssueQueuePtrRegB,
`ifdef RSD_MARCH_FP_PIPE
        srcIssueQueuePtrRegC,
`endif
        prevDependIssueQueuePtr
    );

endinterface : RenameLogicIF