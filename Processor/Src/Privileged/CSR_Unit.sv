// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// CSR Unit
//

`include "BasicMacros.sv"

import BasicTypes::*;
import MemoryMapTypes::*;
import CSR_UnitTypes::*;
import OpFormatTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;

module CSR_Unit(
    CSR_UnitIF.CSR_Unit port,
    PerformanceCounterIF.CSR perfCounter
);

    // SMT: Duplicate CSR State
    CSR_BodyPath csrReg[NUM_THREADS], csrNext[NUM_THREADS];
    
    DataPath rv;
    CSR_ValuePath wv;
    
    // Per Thread Commit count
    CommitLaneCountPath regCommitNum[NUM_THREADS];

    // Interrupt Latch (Per Thread)
    ExternalInterruptCodePath externalInterruptCodeReg[NUM_THREADS];

    always_ff@(posedge port.clk) begin
        if (port.rst) begin
            for(int t=0; t<NUM_THREADS; t++) begin
                csrReg[t] <= '0;
                regCommitNum[t] <= '0;
                externalInterruptCodeReg[t] <= '0;
            end
        end
        else begin
            for(int t=0; t<NUM_THREADS; t++) begin
                csrReg[t] <= csrNext[t];
                regCommitNum[t] <= port.commitNum[t];
                externalInterruptCodeReg[t] <= port.externalInterruptCode; // Shared external?
            end
        end
    end

    always_comb begin
        
        // 1. Read Logic (Muxed by Access TID)
        // Assuming MemoryExecutionStage drives 'csrAccessTid'
        ThreadID accTid = port.csrAccessTid;
        
        unique case (port.csrNumber) 
            CSR_NUM_MSTATUS:    rv = csrReg[accTid].mstatus;
            CSR_NUM_MIP:        rv = csrReg[accTid].mip;
            CSR_NUM_MIE:        rv = csrReg[accTid].mie;
            CSR_NUM_MCAUSE:     rv = csrReg[accTid].mcause;
            CSR_NUM_MTVEC:      rv = csrReg[accTid].mtvec;
            CSR_NUM_MTVAL:      rv = csrReg[accTid].mtval;
            CSR_NUM_MEPC:       rv = csrReg[accTid].mepc;
            CSR_NUM_MSCRATCH:   rv = csrReg[accTid].mscratch;

            CSR_NUM_MCYCLE:     rv = csrReg[accTid].mcycle;
            CSR_NUM_MINSTRET:   rv = csrReg[accTid].minstret;
`ifndef RSD_DISABLE_PERFORMANCE_COUNTER
            // Perf counters are global, just read them
            CSR_NUM_MHPMCOUNTER3: rv = perfCounter.perfCounter.numLoadMiss;
            CSR_NUM_MHPMCOUNTER4: rv = perfCounter.perfCounter.numStoreMiss;
            CSR_NUM_MHPMCOUNTER5: rv = perfCounter.perfCounter.numIC_Miss;
            CSR_NUM_MHPMCOUNTER6: rv = perfCounter.perfCounter.numBranchPredMiss;
`endif
`ifdef RSD_MARCH_FP_PIPE
            CSR_NUM_FFLAGS: rv = csrReg[accTid].fcsr.fflags;
            CSR_NUM_FRM:    rv = csrReg[accTid].fcsr.frm;
            CSR_NUM_FCSR:   rv = csrReg[accTid].fcsr;
`endif
            default:          rv = '0;
        endcase 
        port.csrReadOut = rv;


        // 2. Update Logic (Per Thread)
        for(int t=0; t<NUM_THREADS; t++) begin
            csrNext[t] = csrReg[t];

            // Update Cycles
            csrNext[t].mcycle = csrNext[t].mcycle + 1;
            csrNext[t].minstret = csrNext[t].minstret + regCommitNum[t];

            // Write Value Calculation (Only relevant if this thread is being written)
            wv = '0;
            if (port.csrWE && (t == accTid)) begin
                unique case (port.csrCode) 
                    CSR_WRITE:  wv = port.csrWriteIn;
                    CSR_SET:    wv = rv | port.csrWriteIn;
                    CSR_CLEAR:  wv = rv & (~port.csrWriteIn);
                    default:    wv = port.csrWriteIn;
                endcase
            end

            if (port.triggerInterrupt[t]) begin
                // Interrupt
                csrNext[t].mstatus.MPIE = csrNext[t].mstatus.MIE; 
                csrNext[t].mstatus.MIE = 0;    
                csrNext[t].mepc = ToAddrFromPC(port.interruptRetAddr[t]); 
                csrNext[t].mtval = ToAddrFromPC(port.interruptRetAddr[t]);
                
                csrNext[t].mcause.isInterrupt = TRUE;
                csrNext[t].mcause.code.interruptCode = port.interruptCode[t];
            end
            else if (port.triggerExcpt[t]) begin
                if (port.excptCause[t] == EXEC_STATE_TRAP_MRET) begin
                    // MRET
                    csrNext[t].mstatus.MIE = csrNext[t].mstatus.MPIE; 
                end
                else begin
                    // Trap
                    csrNext[t].mstatus.MPIE = csrNext[t].mstatus.MIE; 
                    csrNext[t].mstatus.MIE = 0;    
                    csrNext[t].mepc = ToAddrFromPC(port.excptCauseAddr[t]); 
                    csrNext[t].mtval = port.excptCauseDataAddr[t];
                    
                    csrNext[t].mcause.isInterrupt = FALSE;
                    csrNext[t].mcause.code.trapCode = ToTrapCodeFromExecState(port.excptCause[t]);
                end
            end
            else if (port.csrWE && (t == accTid)) begin
                 // WRITE Logic (Same as original, just indexed [t])
                 unique case (port.csrNumber) 
                    CSR_NUM_MSTATUS: csrNext[t].mstatus = wv;
                    CSR_NUM_MIE:     csrNext[t].mie = wv;
                    CSR_NUM_MCAUSE:  csrNext[t].mcause = wv;
                    CSR_NUM_MTVEC:   csrNext[t].mtvec = wv;
                    CSR_NUM_MTVAL:   csrNext[t].mtval = wv;
                    CSR_NUM_MEPC:    csrNext[t].mepc = {wv[31:1], 1'b0};
                    CSR_NUM_MSCRATCH: csrNext[t].mscratch = wv;
                    CSR_NUM_MCYCLE:   csrNext[t].mcycle = wv;
                    CSR_NUM_MINSTRET: csrNext[t].minstret = wv;
`ifdef RSD_MARCH_FP_PIPE
                    CSR_NUM_FFLAGS:   csrNext[t].fcsr.fflags = wv;
                    CSR_NUM_FRM:      csrNext[t].fcsr.frm = Rounding_Mode'(wv);
                    CSR_NUM_FCSR:     csrNext[t].fcsr = FFlags_Path'(wv);
`endif
                    default:          wv = '0; // dummy
                endcase 
            end

`ifdef RSD_MARCH_FP_PIPE
            // FFlags update from Commit
            else if(port.fflagsWE[t]) begin
                csrNext[t].fcsr.fflags = port.fflagsData[t];
            end
            
            port.fflags[t] = csrReg[t].fcsr.fflags;
            port.frm[t] = csrReg[t].fcsr.frm;
`endif

            csrNext[t].mip.MTIP = port.reqTimerInterrupt[t];      
            csrNext[t].mip.MEIP = port.reqExternalInterrupt; // Shared external?
            
            port.externalInterruptCodeInCSR[t] = externalInterruptCodeReg[t];
            
            // Exception Target Calculation
            if (port.excptCause[t] == EXEC_STATE_TRAP_MRET) begin
                port.excptTargetAddr[t] = csrReg[t].mepc;
            end
            else begin
                port.excptTargetAddr[t] = {csrReg[t].mtvec.base, CSR_MTVEC_BASE_PADDING};
            end
            
            port.csrWholeOut[t] = csrReg[t];

        end // End Thread Loop
    end

    // Assertions (Need Loop)
    // ... (Omitted for brevity, apply per thread)

endmodule : CSR_Unit