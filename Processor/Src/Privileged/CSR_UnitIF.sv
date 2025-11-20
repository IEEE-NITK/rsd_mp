// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// The interface of a CSR unit.
//

import BasicTypes::*;
import MemoryMapTypes::*;
import OpFormatTypes::*;
import MicroOpTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;
import CSR_UnitTypes::*;

interface CSR_UnitIF(
    input logic clk, rst, rstStart, reqExternalInterrupt, 
    ExternalInterruptCodePath externalInterruptCode
);

    // SMT: All CSR accesses must be banked/duplicated per thread.
    // Interfaces must support arrays.

    logic csrWE;  // CSR write enable (Single port, Muxed inside CSR Unit?)
    // Ideally, CSR Unit should support 1 write port per cycle, 
    // but taking TID as input to select bank.
    
    // SMT: Adding TID for Read/Write selection
    ThreadID csrAccessTid; 
    
    CSR_NumberPath csrNumber;   // CSR number
    CSR_Code csrCode;           // CSR operation code
    DataPath csrReadOut;        // Read Result
    DataPath csrWriteIn;        // Write Data
    
    // Whole CSR State (Duplicated for Interrupt Controller)
    CSR_BodyPath csrWholeOut [NUM_THREADS];

    // Exception = trap or fault (Per Thread)
    // Trap request
    logic    triggerExcpt [NUM_THREADS];
    ExecutionState excptCause [NUM_THREADS];
    PC_Path excptCauseAddr [NUM_THREADS];     // EBREAK/ECALL mepc
    AddrPath excptTargetAddr [NUM_THREADS];   // Trap vector target
    AddrPath excptCauseDataAddr [NUM_THREADS]; // Fault data address

    // Interrupt (Per Thread)
    logic triggerInterrupt [NUM_THREADS];
    CSR_CAUSE_InterruptCodePath interruptCode [NUM_THREADS];
    PC_Path interruptRetAddr [NUM_THREADS];

    // Timer interrupt request (Global or Per Thread?)
    // Timer usually per HART (Hardware Thread)
    logic reqTimerInterrupt [NUM_THREADS];

    // Latched code
    ExternalInterruptCodePath externalInterruptCodeInCSR [NUM_THREADS];

    // Used in updating minstret
    CommitLaneCountPath commitNum [NUM_THREADS];

`ifdef RSD_MARCH_FP_PIPE
    FFlags_Path fflags [NUM_THREADS];
    Rounding_Mode frm [NUM_THREADS];
    logic fflagsWE [NUM_THREADS];
    FFlags_Path fflagsData [NUM_THREADS];
`endif

    modport MemoryExecutionStage(
    input
        clk, rst, rstStart,
        csrReadOut,
    output 
        csrAccessTid, // Added
        csrWE,
        csrNumber,
        csrCode,
        csrWriteIn
    );

`ifdef RSD_MARCH_FP_PIPE
    modport FPExecutionStage(
    input
        frm // Array access required in module
    );
`endif

    // IO_Unit drives interrupts. Assuming it knows about threads or broadcasts.
    modport IO_Unit(
    output 
        reqTimerInterrupt
    );

    // For counter update
    modport CommitStage (
`ifdef RSD_MARCH_FP_PIPE
    input
        fflags,
`endif
    output
        commitNum
`ifdef RSD_MARCH_FP_PIPE
        ,
        fflagsWE,
        fflagsData
`endif
    );


    modport RecoveryManager(
    input
        excptTargetAddr,
    output
        triggerExcpt,
        excptCauseAddr,
        excptCause,
        excptCauseDataAddr
    );

    modport CSR_Unit(
    input
        clk, rst, rstStart,
        csrAccessTid, // Added
        csrWE,
        csrNumber,
        csrCode,
        csrWriteIn,
        triggerExcpt,
        excptCauseAddr,
        excptCause,
        excptCauseDataAddr,
        commitNum,
        reqTimerInterrupt,
        reqExternalInterrupt,
        externalInterruptCode,
        triggerInterrupt,
        interruptCode,
        interruptRetAddr,
`ifdef RSD_MARCH_FP_PIPE
        fflagsWE,
        fflagsData,
`endif
    output 
`ifdef RSD_MARCH_FP_PIPE
        fflags,
        frm,
`endif
        csrWholeOut,
        csrReadOut,
        excptTargetAddr,
        externalInterruptCodeInCSR
    );

    modport InterruptController(
    input
        clk, rst, rstStart,
        csrWholeOut,
        externalInterruptCodeInCSR,
    output
        triggerInterrupt,
        interruptRetAddr,
        interruptCode
    );

endinterface