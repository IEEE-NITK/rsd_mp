// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Interrupt Controller (SMT)
//

`include "BasicMacros.sv"

import BasicTypes::*;
import CSR_UnitTypes::*;
import MemoryMapTypes::*;

module InterruptController(
    CSR_UnitIF.InterruptController csrUnit,
    ControllerIF.InterruptController ctrl,
    NextPCStageIF.InterruptController fetchStage,
    RecoveryManagerIF.InterruptController recoveryManager
);
    logic reqInterrupt[NUM_THREADS];
    logic triggerInterrupt[NUM_THREADS];
    logic reqTimerInterrupt[NUM_THREADS];
    logic reqExternalInterrupt[NUM_THREADS];
    
    CSR_CAUSE_InterruptCodePath interruptCode[NUM_THREADS];
    PC_Path interruptTargetAddr[NUM_THREADS];
    CSR_BodyPath csrReg[NUM_THREADS];
    InterruptCodeConvPath interruptCodeConv[NUM_THREADS];

    `RSD_STATIC_ASSERT(
        RSD_EXTERNAL_INTERRUPT_CODE_WIDTH == CSR_CAUSE_INTERRUPT_CODE_WIDTH,
        "The width of an external interrupt code and the code in the CSR do not match"
    );

    always_comb begin
        
        // SMT Loop
        for(int t=0; t<NUM_THREADS; t++) begin
            csrReg[t] = csrUnit.csrWholeOut[t];

            reqTimerInterrupt[t] =     csrReg[t].mie.MTIE && csrReg[t].mip.MTIP;
            reqExternalInterrupt[t] =  csrReg[t].mie.MEIE && csrReg[t].mip.MEIP;

            reqInterrupt[t] = csrReg[t].mstatus.MIE && (reqTimerInterrupt[t] || reqExternalInterrupt[t]);
            
            interruptCodeConv[t].exCode = csrUnit.externalInterruptCodeInCSR[t]; 
            
            if (reqTimerInterrupt[t]) begin
                // Timer has higher priority.
                interruptCode[t] = CSR_CAUSE_INTERRUPT_CODE_TIMER;
            end
            else begin
                interruptCode[t] = interruptCodeConv[t].csrCode;
            end

            // Interrupt Trigger Logic
            // Only trigger if pipeline is empty AND recovery is done.
            // SMT Note 'ctrl.wholePipelineEmpty' might be global. 
            // If so, both threads wait for total empty. 
            triggerInterrupt[t] = 
                ctrl.wholePipelineEmpty && 
                !recoveryManager.unableToStartRecovery[t] && 
                reqInterrupt[t];

            csrUnit.triggerInterrupt[t] = triggerInterrupt[t];
            // Assumption: PC Out is arrayed in FetchStage
            csrUnit.interruptRetAddr[t] = fetchStage.pcOut[t]; 
            csrUnit.interruptCode[t] = interruptCode[t];

            interruptTargetAddr[t] = ToPC_FromAddr({
                (csrReg[t].mtvec.mode == CSR_MTVEC_MODE_VECTORED) ? 
                    (csrReg[t].mtvec.base + interruptCode[t]) : csrReg[t].mtvec.base, 
                CSR_MTVEC_BASE_PADDING
            });

            // Drive Fetch Stage Inputs (Arrayed)
            fetchStage.interruptAddrWE[t] = triggerInterrupt[t];
            fetchStage.interruptAddrIn[t] = interruptTargetAddr[t];
        end
        
        // Bubble Request (Aggregate)
        ctrl.npStageSendBubbleLowerForInterrupt =
            reqInterrupt[0] || reqInterrupt[1];
    end

endmodule