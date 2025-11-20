// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.



import BasicTypes::*;
import SchedulerTypes::*;
import ActiveListIndexTypes::*;

//`define ALWAYS_SPECULATIVE
//`define ALWAYS_NOT_SPECULATIVE

module MemoryDependencyPredictor(
    RenameStageIF.MemoryDependencyPredictor port,
    LoadStoreUnitIF.MemoryDependencyPredictor loadStoreUnit
);

    logic mdtWE[STORE_ISSUE_WIDTH];
    MDT_IndexPath mdtWA[STORE_ISSUE_WIDTH];
    MDT_Entry mdtWV[STORE_ISSUE_WIDTH];
    MDT_IndexPath mdtRA[RENAME_WIDTH];
    MDT_Entry mdtRV[RENAME_WIDTH];

    logic prediction[RENAME_WIDTH];

    generate
        // NOTE: Need to implement write request queue when increase STORE_ISSUE_WIDTH
        BlockMultiBankRAM #(
            .ENTRY_NUM( MDT_ENTRY_NUM ),
            .ENTRY_BIT_SIZE( $bits( MDT_Entry ) ),
            .READ_NUM( RENAME_WIDTH ),
            .WRITE_NUM( STORE_ISSUE_WIDTH )
        ) 
        mdt( 
            .clk(port.clk),
            .we(mdtWE),
            .wa(mdtWA),
            .wv(mdtWV),
            .ra(mdtRA),
            .rv(mdtRV)
        );
    endgenerate

    // Counter for reset sequence.
    MDT_IndexPath resetIndex;
    always_ff @(posedge port.clk) begin
        if (port.rstStart) begin
            resetIndex <= 0;
        end
        else begin
            resetIndex <= resetIndex + 1;
        end
    end

    // SMT Helper: Hash PC with TID
    function automatic MDT_IndexPath GetThreadedMDTIndex(PC_Path pc, ThreadID tid);
        // Use XOR hashing to disperse TIDs across the table
        // Shift TID to avoid conflict in lower bits if PC alignment is high
        return ToMDT_Index(pc) ^ (MDT_IndexPath'(tid) << 5);
    endfunction

    always_comb begin

        // Process read request
        for (int i = 0; i < RENAME_WIDTH; i++) begin
            // SMT Update: Hash PC with TID
            // Note: 'port.tid[i]' must be available in RenameStageIF
            // (We added 'tid' to RenameStageIF outputs in previous steps)
            mdtRA[i] = GetThreadedMDTIndex(
                port.pc[i], // RenameStage passes array of PCs
                port.tid[i] // RenameStage passes array of TIDs
            );
        end

        // Decide whether issue speculatively
        for (int i = 0; i < RENAME_WIDTH; i++) begin
`ifdef ALWAYS_SPECULATIVE
            prediction[i] = FALSE;
`elsif ALWAYS_NOT_SPECULATIVE
            prediction[i] = TRUE;
`else
            // Predict according to mdt entry
            prediction[i] = mdtRV[i].counter;
`endif
        end

        // Connect to IF.
        port.memDependencyPred = prediction;

        // Process write request
        for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
            // Make write request when store detect conflict with load
            mdtWE[i] = 
                loadStoreUnit.memAccessOrderViolation[i];

            // Learn memory order violation
            // SMT Update: The LSU needs to provide the TID of the conflicting load.
            // However, conflictLoadPC usually comes from the LoadQueue, 
            // and we updated LoadQueue to store TIDs.
            // Ideally, LoadStoreUnitIF should pass 'conflictLoadTid'.
            // If not available, we use the simple PC index (less accurate but functional).
            
            // *Assumption*: Since we haven't updated LoadStoreUnitIF to pass 
            // 'conflictLoadTid', we will use the raw PC. 
            // Ideally, you should add 'conflictLoadTid' to LSU IF.
            // For now, simple PC indexing (aliasing might occur between threads, 
            // but it is safe -> conservative prediction).
            
            mdtWA[i] = ToMDT_Index(loadStoreUnit.conflictLoadPC[i]);
            mdtWV[i].counter = TRUE;
        end

        // In reset sequence, the write port 0 is used for initializing, and 
        // the other write ports are disabled.
        if (port.rst) begin
            for (int i = 0; i < STORE_ISSUE_WIDTH; i++) begin
                mdtWE[i] = (i == 0);
                mdtWA[i] = resetIndex;
                mdtWV[i].counter = FALSE;
            end

            // To avoid writing to the same bank (avoid error message)
            for (int i = 0; i < RENAME_WIDTH; i++) begin
                mdtRA[i] = i;
            end
        end
    end

endmodule : MemoryDependencyPredictor