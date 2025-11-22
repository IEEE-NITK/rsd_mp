// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// Branch predictor -- 2bc with SMT-aware PHT indexing.
//

import BasicTypes::*;
import MemoryMapTypes::*;
import FetchUnitTypes::*;
import MicroArchConf::*;   // <-- for ThreadID / THREAD_NUM_BIT_WIDTH

// Build a PHT index from PC, **including thread-id** to separate threads logically.
function automatic PHT_IndexPath ToPHT_Index_Local(PC_Path pc);
    PHT_IndexPath base;
    PHT_IndexPath tid_mask;

    // Original index from PC address bits
    base = pc.addr[
        PHT_ENTRY_NUM_BIT_WIDTH + INSN_ADDR_BIT_WIDTH - 1 :
        INSN_ADDR_BIT_WIDTH
    ];

    // Zero-extend tid and XOR it into the index so each thread uses different counters.
    tid_mask = '0;
    tid_mask[THREAD_NUM_BIT_WIDTH-1:0] = pc.tid;

    return base ^ tid_mask;
endfunction

module Bimodal(
    NextPCStageIF.BranchPredictor port,
    FetchStageIF.BranchPredictor   next
);

    PC_Path pcIn;

    logic brPredTaken;

    // PHT control logic
    logic         phtWE      [INT_ISSUE_WIDTH];
    PHT_IndexPath phtWA      [INT_ISSUE_WIDTH];
    PHT_EntryPath phtWV      [INT_ISSUE_WIDTH];
    PHT_EntryPath phtPrevValue[INT_ISSUE_WIDTH];

    // Read ports for prediction and counter read
    PHT_IndexPath phtRA[FETCH_WIDTH];
    PHT_EntryPath phtRV[FETCH_WIDTH];

    // Assert when misprediction occurred
    logic mispred;

    logic pushPhtQueue, popPhtQueue;
    logic full, empty;

    PhtQueueEntry      phtQueue[PHT_QUEUE_SIZE];
    PhtQueuePointerPath headPtr, tailPtr;

    logic updatePht;

    // PHT body
    generate
        BlockMultiBankRAM #(
            .ENTRY_NUM      (PHT_ENTRY_NUM),
            .ENTRY_BIT_SIZE ($bits(PHT_EntryPath)),
            .READ_NUM       (FETCH_WIDTH),
            .WRITE_NUM      (INT_ISSUE_WIDTH)
        )
        pht (
            .clk (port.clk),
            .we  (phtWE),
            .wa  (phtWA),
            .wv  (phtWV),
            .ra  (phtRA),
            .rv  (phtRV)
        );

        QueuePointer #(
            .SIZE (PHT_QUEUE_SIZE)
        )
        phtQueuePointer (
            .clk     (port.clk),
            .rst     (port.rst),
            .push    (pushPhtQueue),
            .pop     (popPhtQueue),
            .full    (full),
            .empty   (empty),
            .headPtr (headPtr),
            .tailPtr (tailPtr)
        );
    endgenerate

    // Counter for reset sequence
    PHT_IndexPath resetIndex;
    always_ff @(posedge port.clk) begin
        if (port.rstStart) begin
            resetIndex <= '0;
        end
        else begin
            resetIndex <= resetIndex + 1;
        end
    end

    // PHT queue write: either reset init or delayed updates
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            // During reset, prefill queue entries with neutral counters
            phtQueue[resetIndex % PHT_QUEUE_SIZE].phtWA <= '0;
            phtQueue[resetIndex % PHT_QUEUE_SIZE].phtWV <= PHT_ENTRY_MAX / 2 + 1;
        end
        else if (pushPhtQueue) begin
            // Store the *already tid-folded* index and counter value
            phtQueue[headPtr].phtWA <= phtWA[INT_ISSUE_WIDTH-1];
            phtQueue[headPtr].phtWV <= phtWV[INT_ISSUE_WIDTH-1];
        end
    end

    always_comb begin
        pcIn = port.predNextPC;   // PC_Path, includes tid

        // ---- Prediction path ----
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            next.phtPrevValue[i] = phtRV[i];

            // Predict direction: MSB of counter && BTB hit
            brPredTaken =
                phtRV[i][PHT_ENTRY_WIDTH - 1] && next.btbHit[i];
            next.brPredTaken[i] = brPredTaken;

            if (brPredTaken) begin
                // If branch predicted taken for this slot, later slots are not executed.
                break;
            end
        end

        // Clear write enables & queue control defaults
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            phtWE[i]        = FALSE;
            phtPrevValue[i] = '0;
        end
        updatePht     = FALSE;
        pushPhtQueue  = FALSE;

        // ---- Update path (from brResult) ----
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            // When branch instruction is executed, update PHT.
            if (updatePht) begin
                // Multiple updates in same cycle: push additional ones into queue
                pushPhtQueue = port.brResult[i].valid;
            end
            else begin
                phtWE[i]   = port.brResult[i].valid;
                updatePht |= phtWE[i];
            end

            // *** SMT-aware index: brAddr is a PC_Path w/ tid ***
            // If brAddr is just an AddrPath in your code, change its type to PC_Path
            // and ensure .tid is coming from the correct thread.
            phtWA[i] = ToPHT_Index_Local(port.brResult[i].brAddr);

            mispred = port.brResult[i].mispred && port.brResult[i].valid;

            // Previous counter value from the branch result (snapshotted at fetch)
            phtPrevValue[i] = port.brResult[i].phtPrevValue;

            // Saturating up/down counter update
            if (port.brResult[i].execTaken) begin
                phtWV[i] = (phtPrevValue[i] == PHT_ENTRY_MAX) ?
                           PHT_ENTRY_MAX :
                           phtPrevValue[i] + 1;
            end
            else begin
                phtWV[i] = (phtPrevValue[i] == 0) ?
                           0 :
                           phtPrevValue[i] - 1;
            end

            // On mispredict, stop processing further updates for this cycle
            if (mispred) begin
                break;
            end
        end

        // ---- PHT read addresses for next cycle (prediction path) ----
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            // pcIn + i*INSN_BYTE_WIDTH keeps the same tid; index function folds tid in.
            phtRA[i] = ToPHT_Index_Local(pcIn + i*INSN_BYTE_WIDTH);
        end

        // ---- Pop PHT Queue (delayed update) ----
        if (!empty && !updatePht) begin
            popPhtQueue = TRUE;
            phtWE[0]    = TRUE;
            phtWA[0]    = phtQueue[tailPtr].phtWA;  // already tid-folded index
            phtWV[0]    = phtQueue[tailPtr].phtWV;
        end
        else begin
            popPhtQueue = FALSE;
        end

        // ---- Reset sequence: initialize all PHT entries to weakly taken ----
        if (port.rst) begin
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                phtWE[i] = (i == 0) ? TRUE : FALSE;
                // We don't care about tid during reset: we just want all entries neutral.
                phtWA[i] = resetIndex;
                phtWV[i] = PHT_ENTRY_MAX / 2 + 1;
            end

            // To avoid writing to the same bank (avoid error message)
            for (int i = 0; i < FETCH_WIDTH; i++) begin
                phtRA[i] = i;
            end

            pushPhtQueue = FALSE;
            popPhtQueue  = FALSE;
        end
    end

endmodule : Bimodal


