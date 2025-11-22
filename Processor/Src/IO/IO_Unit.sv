// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// IO Unit
//

`include "BasicMacros.sv"

import BasicTypes::*;
import LoadStoreUnitTypes::*;
import MemoryMapTypes::*;
import IO_UnitTypes::*;
import DebugTypes::*;

module IO_Unit(
    IO_UnitIF.IO_Unit port,
    CSR_UnitIF.IO_Unit csrUnit
);

    // Timer register
    TimerRegsters tmReg;
    TimerRegsters tmNext;
    
    // For comparison - use simple logic vectors
    logic [TIMER_REGISTER_WIDTH-1:0] mtime_val;
    logic [TIMER_REGISTER_WIDTH-1:0] mtimecmp_val;
    
    // Intermediate result for timer interrupt
    logic timerInterruptTriggered;

    always_ff@(posedge port.clk) begin
        if (port.rst) begin
            tmReg <= '0;
        end
        else begin
            tmReg <= tmNext;
        end
    end

    PhyRawAddrPath phyRawReadAddr, phyRawWriteAddr;

    always_comb begin
        phyRawReadAddr = port.ioReadAddrIn.addr;
        phyRawWriteAddr = port.ioWriteAddrIn.addr;

        // Update timer
        tmNext = tmReg;
        tmNext.mtime.raw = tmNext.mtime.raw + 1;

        // FIXED: Build 64-bit values from split fields to avoid union comparison issues
        mtime_val = {tmNext.mtime.split.hi, tmNext.mtime.split.low};
        mtimecmp_val = {tmNext.mtimecmp.split.hi, tmNext.mtimecmp.split.low};
        
        // Compute comparison to intermediate variable first
        if (mtime_val >= mtimecmp_val) begin
            timerInterruptTriggered = TRUE;
        end
        else begin
            timerInterruptTriggered = FALSE;
        end
        
        // FIXED: Assign to ALL threads (timer is shared, all threads see the same timer interrupt)
        for (int t = 0; t < NUM_THREADS; t++) begin
            csrUnit.reqTimerInterrupt[t] = timerInterruptTriggered;
        end

        // Write a timer register
        if (port.ioWE) begin
            if (phyRawWriteAddr == PHY_ADDR_TIMER_LOW) begin
                tmNext.mtime.split.low = port.ioWriteDataIn;
            end
            else if (phyRawWriteAddr == PHY_ADDR_TIMER_HI) begin
                tmNext.mtime.split.hi = port.ioWriteDataIn;
            end
            else if (phyRawWriteAddr == PHY_ADDR_TIMER_CMP_LOW) begin
                tmNext.mtimecmp.split.low = port.ioWriteDataIn;
            end
            else if (phyRawWriteAddr == PHY_ADDR_TIMER_CMP_HI) begin
                tmNext.mtimecmp.split.hi = port.ioWriteDataIn;
            end
        end

        // Read a timer register
        if (phyRawReadAddr == PHY_ADDR_TIMER_LOW) begin
            port.ioReadDataOut = tmReg.mtime.split.low;
        end
        else if (phyRawReadAddr == PHY_ADDR_TIMER_HI) begin
            port.ioReadDataOut = tmReg.mtime.split.hi;
        end
        else if (phyRawReadAddr == PHY_ADDR_TIMER_CMP_LOW) begin
            port.ioReadDataOut = tmReg.mtimecmp.split.low;
        end
        else begin
            port.ioReadDataOut = tmReg.mtimecmp.split.hi;
        end
    end

    always_comb begin
        // Serial IO
        port.serialWE = FALSE;
        port.serialWriteDataOut = port.ioWriteDataIn[SERIAL_OUTPUT_WIDTH-1 : 0];
        if (port.ioWE && phyRawWriteAddr == PHY_ADDR_SERIAL_OUTPUT) begin
            port.serialWE = TRUE;
        end
    end
endmodule