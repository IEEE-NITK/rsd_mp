# SMT Implementation: Integer Backend

**Date:** November 2025
**Module:** IntegerBackEnd (Issue, RegRead, Execution, Writeback)
**Status:** SMT-Ready (Shared Execution, Thread-Aware Control)

---

## 1. Architectural Overview
The Integer Backend executes ALU operations (Add, Sub, Shift, Branch) for all threads. In this SMT implementation, the execution units are **Fully Shared**.
* **Efficiency:** An ALU can execute an instruction from Thread 0 in Cycle $N$, and an instruction from Thread 1 in Cycle $N+1$ (or simultaneously if multiple ALUs exist).
* **Isolation:** Control signals (Flush/Stall) are decoupled. A branch misprediction in Thread 0 will flush only Thread 0's instructions from the pipeline, leaving Thread 1's instructions intact.

---

## 2. File Modification Log

### `IntegerIssueStage.sv`
**Status:** Modified
* **TID Extraction:** Retrieves the `tid` from the Scheduler's issued data structure (`scheduler.intIssuedData[i].tid`).
* **Selective Flushing:** Uses the extracted `tid` to index into the `recovery.toRecoveryPhase` array.
    * *Logic:* `if (recovery.toRecoveryPhase[tid]) flush();`
* **Pipeline Register:** Passes the `tid` to the next stage (`IntegerRegisterReadStage`).

### `IntegerRegisterReadStage.sv`
**Status:** Modified
* **TID Propagation:** Reads `tid` from the input pipeline register and passes it to the output register.
* **Selective Flushing:** Checks the recovery signal specific to the instruction's thread ID.
* **Operand Selection:** No changes to operand logic; physical register indices are already unique per thread (handled by Rename).

### `IntegerExecutionStage.sv`
**Status:** Modified
* **Branch Resolution (Crucial):**
    * When a branch is executed, the result structure (`BranchResult`) is tagged with `tid`.
    * `brResult[i].tid = opTid[i];`
    * **Why:** This allows the **Fetch Unit** to update the Branch History / Predictor tables for the *specific* thread that executed the branch.
* **Flush Logic:** Updated `SelectiveFlushDetector` calls to use `opTid[i]` for indexing recovery signals.

### `IntegerRegisterWriteStage.sv`
**Status:** Modified
* **Active List Writeback:**
    * Writes `alWriteData[i].tid` to the Active List.
    * **Purpose:** Allows the Reorder Buffer to attribute instruction completion to the correct thread partition.
* **Pipeline Logic:** Ensures valid signals (`update[i]`, `valid[i]`) respect the flush status of the specific thread owning the instruction.

---

## 3. Data Flow Example (Branch Misprediction)
1.  **Execute:** Thread 0 executes a Branch at `IntegerExecutionStage`. It resolves as **Taken** (prediction was Not Taken).
2.  **Tagging:** The stage outputs `brResult` with `mispred=1` and `tid=0`.
3.  **Writeback:** `IntegerRegisterWriteStage` sends this result to the Active List and Global Control.
4.  **Recovery:** The `RecoveryManager` sees the misprediction for `tid=0`. It raises `toRecoveryPhase[0]`.
5.  **Selective Flush:**
    * In the next cycle, `IntegerIssueStage` sees `toRecoveryPhase[0]` is High. It flushes all instructions belonging to Thread 0.
    * It sees `toRecoveryPhase[1]` is Low. Instructions for Thread 1 continue to issue and execute normally.

## 4. Dependencies
* Requires `PipelineTypes.sv` to include `tid` in `IntegerRegisterWriteStageRegPath`.
* Requires `FetchUnitTypes.sv` to include `tid` in `BranchResult`.