# SMT Implementation: Floating Point Backend

**Date:** November 2025
**Module:** FPBackEnd (Issue, RegRead, Execution, Writeback)
**Status:** SMT-Ready (Shared Resources, Thread-Aware Control)

---

## 1. Architectural Overview
In this SMT implementation, the Floating Point Execution Units (FPU, Div/Sqrt) are **Fully Shared Resources**.
* **No Duplication:** We do not create separate FPUs for Thread 0 and Thread 1.
* **Tagging:** Instructions flowing through the backend carry a `ThreadID (tid)` tag.
* **Note** Another hidden detail called ptr is created at the start of midcore(rename), this basically tells in the rob which segment (Thread 0 or Thread 1) will the mop be placed when it completes write back. (t0-> ptr = 0-63, t1-> ptr =64-127). So we essentially just look at ptr while writing to rob n place in the appropriate segment.
* **Isolation:** While execution is shared, control logic (Flushing and Stalling) is isolated. An exception in Thread 0 will selectively flush only Thread 0's instructions from the pipeline, allowing Thread 1's instructions (even those in the same pipeline stage) to complete.

---

## 2. File Modification Log

### `FPIssueStage.sv`
**Status:** Modified
* **TID Extraction:** Retrieves the `tid` from the Scheduler's issued data structure (`scheduler.fpIssuedData[i].tid`).
* **Selective Flushing:** Uses the extracted `tid` to index into the `recovery.toRecoveryPhase` array.
    * *Logic:* `if (recovery.toRecoveryPhase[tid]) flush();`
* **Pipeline Register:** Passes the `tid` to the next stage (`FPRegisterReadStage`).

### `FPRegisterReadStage.sv`
**Status:** Modified
* **TID Propagation:** Reads `tid` from the input pipeline register.
* **Selective Flushing:** Checks the recovery signal specific to the instruction's thread ID.
* **Register File Access:** No changes needed to the Register File interface itself, as the `RenameLogic` has already mapped the logical registers to unique physical registers (which are shared global resources).

### `FPExecutionStage.sv`
**Status:** Modified
* **Local Pipeline Registers:** Added `ThreadID tid` to the `LocalPipeReg` struct used for multi-cycle operations (like FMA).
* **TID Propagation:** Ensures `tid` travels through the execution pipeline stages alongside the data.
* **Flush Logic:** Updated `SelectiveFlushDetector` calls to use `opTid[i]` for indexing recovery signals.

### `FPRegisterWriteStage.sv`
**Status:** Modified
* **Active List Writeback:**
    * Extracted `tid` from the finishing instruction.
    * Writes `alWriteData[i].tid` to the Active List.
    * **Purpose:** This allows the Active List to attribute completion (or exceptions) to the correct thread.
* **Flush Check:** Ensures that a retiring instruction isn't written back if its specific thread is currently in a recovery phase.

---

## 3. Data Flow Summary

1.  **Scheduler:** Issues an instruction tagged with `TID: 0`.
2.  **Issue Stage:** Checks `recovery[0]`. If safe, sends to RegRead.
3.  **Execution:** The FPU calculates the result. If `recovery[1]` triggers (Thread 1 flushes), this Thread 0 instruction is **unaffected** and continues processing.
4.  **Writeback:** The result is written to the Physical Register File (using the physical pointer assigned at Rename). The Active List is notified that "Ptr X (Thread 0)" is complete.

## 4. Verification Notes
* **Correct Flush Behavior:** Verify that asserting `toRecoveryPhase[0]` flushes T0 instructions in the pipeline but allows T1 instructions to reach Writeback.
* **Active List Mapping:** Verify that `alWriteData.tid` matches the partition of `alWriteData.ptr` (e.g., if Ptr is in T0's range, TID should be 0).