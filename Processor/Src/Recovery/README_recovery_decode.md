# SMT Implementation: Middle Pipeline & Recovery Logic

**Date:** November 2025
**Modules:** DecodeStage, DispatchStage, RecoveryManager
**Objective:** Enable thread-specific instruction tagging and selective pipeline flushing.

---

## 1. Decode Stage (`DecodeStage.sv`, `DecodeStageIF.sv`)
**Status:** Modified for SMT
**Key Concept:** The Decode stage is responsible not just for decoding instructions, but for detecting early branch mispredictions. In SMT, we must identify *which* thread caused a misprediction to avoid flushing the innocent thread.

### Changes:
* **Interface Update (`DecodeStageIF.sv`):**
    * Added `ThreadID nextFlushTid`: Signal to tell the backend exactly which thread needs recovery.
* **Logic Update (`DecodeStage.sv`):**
    * **Pass-Through:** Propagates `pipeReg[i].tid` to `nextStage[i].tid`.
    * **Flush Identification:** Added logic to scan `insnFlushTriggering`. The first lane triggering a flush extracts its `tid` and drives `port.nextFlushTid`.
    * **Purpose:** Ensures that if Thread 0 mispredicts a branch, the Recovery Manager receives "Flush Request: Thread 0", keeping Thread 1 alive.

---

## 2. Dispatch Stage (`DispatchStage.sv`)
**Status:** Modified for SMT
**Key Concept:** Dispatch is the bridge between the In-Order frontend and the Out-of-Order backend. This is where instructions are inserted into the Issue Queues (Scheduler).

### Changes:
* **Instruction Tagging:** * Extracted `tid` from the input pipeline register.
    * Wrote `tid` into every backend queue entry structure:
        * `intEntry[i].tid` (Integer Queue)
        * `memEntry[i].tid` (Memory Queue)
        * `complexEntry[i].tid` (Complex Queue)
        * `fpEntry[i].tid` (Floating Point Queue)
* **Purpose:** The Scheduler and Execution Units are shared resources. By tagging entries here, the backend can later arbitrate fairness or enforce memory ordering per thread.

---

## 3. Recovery Manager (`RecoveryManager.sv`, `RecoveryManagerIF.sv`)
**Status:** Heavily Modified (Core SMT Logic)
**Key Concept:** This module controls the global state of the processor (Commit vs. Recovery). In SMT, having one global state is inefficient (one thread crashing stops the other).

### Changes:
* **Interface Arrays (`RecoveryManagerIF.sv`):**
    * Converted scalar control signals to arrays `[NUM_THREADS]`.
    * Examples: `toRecoveryPhase[NUM_THREADS]`, `toCommitPhase[NUM_THREADS]`, `recoveredPC[NUM_THREADS]`.
* **State Machine Duplication (`RecoveryManager.sv`):**
    * Replaced the single `regState` struct with an array: `RecoveryManagerStatePath regState[NUM_THREADS]`.
    * Wrapped the main control logic in a `for(int t=0; t<NUM_THREADS; t++)` loop.
* **Selective Flushing:**
    * Thread 0 can be in `PHASE_RECOVER_0` (flushing its instructions) while Thread 1 remains in `PHASE_COMMIT` (processing normally).
    * Uses the `exceptionTidFromRwStage` (derived from Decode's `nextFlushTid`) to target the specific state machine.

---

## Summary of Data Flow
1.  **Fetch/Decode:** Instructions flow down marked with `TID`.
2.  **Decode:** If a branch is wrong, `nextFlush` goes High and `nextFlushTid` indicates the culprit.
3.  **Rename:** Passes the flush signal to `RecoveryManager`.
4.  **RecoveryManager:** Sees flush request for Thread X. Moves Thread X's state machine to Recovery. Thread Y's state machine stays in Commit.
5.  **Dispatch:** Instructions that survive are written to Issue Queues, permanently tagged with `TID` for execution.