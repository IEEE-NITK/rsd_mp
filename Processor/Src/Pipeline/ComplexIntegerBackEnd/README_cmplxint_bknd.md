# SMT Implementation: Complex Integer Backend

**Date:** November 2025
**Module:** ComplexIntegerBackEnd (Mul/Div/SIMD Pipeline)
**Status:** SMT-Ready (Thread-Aware Execution and Control)

---

## 1. Architectural Overview
This module handles complex integer operations (Multiplication and Division).
* **Shared Pipeline:** The execution pipeline (MULDIV Unit) is shared between threads.
* **Thread-Aware:** Instructions carry their `ThreadID (tid)` throughout the pipeline to ensure correct exception handling and writeback.

## 2. File Modification Log

### `ComplexIntegerIssueStage.sv`
**Status:** Modified
* **TID Extraction:** Retrieves `tid` from the Scheduler's issued data (`scheduler.complexIssuedData[i].tid`).
* **Flush Logic:** Uses the `tid` to check the thread-specific recovery signals from the `RecoveryManager`.
* **Pipeline Register:** Passes `tid` to the next stage.

### `ComplexIntegerRegisterReadStage.sv`
**Status:** Modified
* **TID Propagation:** Reads `tid` from input registers and passes it to output.
* **Selective Flush:** Ensures instructions are only flushed if their specific thread triggers a recovery.

### `ComplexIntegerExecutionStage.sv`
**Status:** Modified
* **Multi-Cycle Operations:**
    * The `LocalPipeReg` struct (used for the multi-stage pipeline) now includes `ThreadID tid`.
    * This ensures that if a Divide operation takes 20 cycles, the TID travels with it through every cycle.
* **Flush Logic:** Checks for recovery in every stage of the local pipeline using the instruction's TID.

### `ComplexIntegerRegisterWriteStage.sv`
**Status:** Modified
* **Active List Writeback:** Writes `alWriteData[i].tid` to the Reorder Buffer.
* **Pipeline Control:** Standard SMT valid/flush checks.