# SMT Implementation: Scheduler & Issue Queue

**Date:** November 2025
**Module:** Scheduler (Out-of-Order Instruction Engine)
**Status:** SMT-Ready (Shared Resources, Selective Flushing)

---

## 1. Architectural Overview
The Scheduler is the heart of the Out-of-Order engine. It holds instructions in the **Issue Queue (IQ)**, waits for their operands to become ready, and selects them for execution.

In this SMT implementation:
* **Shared Queue:** The Issue Queue is a **fully shared resource**. Thread 0 and Thread 1 compete dynamically for slots. There is no hard partitioning (e.g., T0 gets 0-31, T1 gets 32-63).
* **Tagged Entries:** Every instruction sitting in the queue is tagged with its `ThreadID`.
* **Selective Flushing:** While execution is shared, **Recovery is isolated**. If Thread 0 mispredicts a branch, the Scheduler selectively invalidates only Thread 0's instructions, leaving Thread 1's instructions valid and ready to execute.
* **Wakeup/Select:** The core dependency tracking logic (Wakeup Matrix / CAM) remains thread-agnostic, operating purely on unique Issue Queue Indices and Physical Register Numbers.

---

## 2. File Modification Log

### `SchedulerTypes.sv`
**Status:** Modified
* **Struct Updates:** Added `ThreadID tid;` to all Issue Queue entry structures:
    * `IntIssueQueueEntry`
    * `MemIssueQueueEntry`
    * `ComplexIssueQueueEntry`
    * `FPIssueQueueEntry`
* **Purpose:** Ensures that ownership information persists while an instruction waits in the queue.

### `SchedulerIF.sv`
**Status:** Modified
* **Interface Update:** While the file itself primarily uses `modport`s, it now relies on `RecoveryManagerIF` exposing arrayed signals (e.g., `toRecoveryPhase[NUM_THREADS]`) which are consumed by the Issue Queue logic.

### `IssueQueue.sv`
**Status:** Heavily Modified
* **Shadow TID Array:** Added `ThreadID tidReg[ISSUE_QUEUE_ENTRY_NUM]`.
    * *Reason:* The main Payload RAMs do not have enough read ports to check the TID of every instruction simultaneously during a flush event. This shadow register allows parallel access.
* **Selective Flush Logic:**
    * Updated the valid/flush check loop: `flush[i] = (recovery.toRecoveryPhase[tidReg[i]] && ...)`
    * **Result:** A global flush signal for Thread 0 will only kill instructions where `tidReg[i] == 0`.

### `ReplayQueue.sv`
**Status:** Modified
* **Flush Logic:** Similar to the Issue Queue, the Replay Queue (which holds instructions waiting for cache misses) now checks the `tid` inside the `ReplayQueueEntry` before invalidating it during a recovery phase.
* **Flush Counters:** `canBeFlushedEntryCount` is duplicated per thread `[NUM_THREADS]` to accurately track when the pipeline has drained a specific thread's flushed operations.

### `WakeupPipelineRegister.sv`
**Status:** Modified
* **TID Tracking:** Added `tid` to the pipeline registers that handle the latency between Issue and Wakeup.
* **Flush Counters:** Duplicated `canBeFlushedRegCount` per thread. This prevents the Recovery Manager from exiting the recovery phase prematurely while "zombie" instructions from the recovering thread are still moving through the wakeup delay slots.

### `MemoryDependencyPredictor.sv`
**Status:** Modified
* **Index Hashing:** Updated the indexing logic to hash the `PC` with the `ThreadID`.
    * `Index = ToMDT_Index(pc) ^ (tid << 5)`
* **Why:** Prevents **Aliasing**. Thread 0 executing code at `0x1000` (a Load) should not be penalized by dependency history created by Thread 1 executing code at `0x1000` (an unrelated Load).

---

## 3. Unchanged Files (Thread-Agnostic Logic)
The following files required **NO** modifications because they operate on resources that are already unique/renamed:

* **`WakeupLogic.sv` & `SourceCAM.sv`:**
    * These track dependencies based on **Physical Register Numbers**. Since `RenameLogic` ensures T0 and T1 never share physical registers, the dependency graph is naturally isolated.
* **`SelectLogic.sv`:**
    * This picks the "Oldest Ready" instruction. It operates on a bitmask of ready instructions. It does not care which thread owns the instruction; it simply fills the execution pipeline with valid work.
* **`DestinationRAM.sv`:**
    * Maps Issue Queue Indices to Physical Registers. Since Issue Queue indices are unique (0-63), no thread awareness is needed here.

---

## 4. Verification Notes
* **Flush Isolation:** Verify that asserting `toRecoveryPhase[0]` removes T0 instructions from the Issue Queue but leaves T1 instructions valid.
* **Replay Safety:** Verify that if T0 flushes, a T1 instruction waiting in the Replay Queue (e.g., for a cache miss) is **not** dropped.
* **Reset:** Verify that a hard system reset (`rst`) clears the Issue Queue for **all** threads.