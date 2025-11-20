# SMT Implementation: Memory Backend Pipeline

**Date:** November 2025
**Module:** MemoryBackEnd (Pipeline Stages)
**Status:** SMT-Ready (Thread-Aware Control Flow)

---

## 1. Architectural Overview
The Memory Backend Pipeline handles Load, Store, and Atomic instructions. In SMT, while the pipeline stages are shared, the memory consistency model must be isolated per thread.
* **Pipeline Flow:** Instructions flow through Issue $\rightarrow$ Read $\rightarrow$ Execution $\rightarrow$ TagAccess $\rightarrow$ Writeback.
* **Thread Tagging:** Every stage now propagates the `ThreadID (tid)` alongside the data.
* **LSU Interface:** The `MemoryTagAccessStage` now explicitly passes the `tid` to the Load/Store Unit, allowing the LSU to enforce thread isolation in memory ordering.

---

## 2. File Modification Log

### `MemoryIssueStage.sv`
**Status:** Modified
* **TID Extraction:** Retrieves `tid` from the Scheduler (`scheduler.memIssuedData[i].tid`) or Replay data.
* **Selective Flushing:** Indexes `recovery.toRecoveryPhase` using the extracted `tid` to ensure only the correct thread is flushed during exceptions.

### `MemoryRegisterReadStage.sv`
**Status:** Modified
* **TID Propagation:** Reads `tid` from the pipeline register and passes it to the next stage.
* **Flush Logic:** Updates `SelectiveFlushDetector` to check the recovery signal for the specific `opTid`.

### `MemoryExecutionStage.sv`
**Status:** Modified
* **TID Propagation:** Passes `tid` through the pipeline.
* **LSU Interface:** Passes `tid` to the Load Store Unit during DCache read requests (`loadStoreUnit.dcReadTid`).
* **Logic:** Ensures flush logic respects thread boundaries.

### `MemoryTagAccessStage.sv`
**Status:** Modified
* **LSU Interface (Crucial):**
    * Passes `ldTid` to `loadStoreUnit.executedLoadTid`.
    * Passes `stTid` to `loadStoreUnit.executedStoreTid`.
* **Purpose:** This allows the Load Queue and Store Queue to tag entries. A Load from Thread 0 will only check for forwarding against Stores from Thread 0.
* **MSHR Handling:** Tracks MSHR allocation per instruction/thread (logic remains mostly shared as MSHRs are physically addressed).

### `MemoryRegisterWriteStage.sv`
**Status:** Modified
* **Active List Writeback:** Writes `alWriteData[i].tid` to the Reorder Buffer so retirement can be attributed to the correct thread.
* **MSHR Release:** Ensures MSHR release logic is valid for the completing thread.

---

## 3. Integration Notes

### Load/Store Unit (LSU) Dependency
These pipeline stages **drive** the LSU, but the LSU itself must be updated to handle the new `tid` signals defined in the interface.
* **Load Queue:** Must store TID. When checking for dependencies, `if (store_addr == load_addr && store_tid == load_tid)`.
* **Store Queue:** Must store TID.

### Recovery
* If Thread 0 triggers a fault (e.g., `EXEC_STATE_FAULT_LOAD_VIOLATION`), the Recovery Manager will receive this signal tagged with Thread 0 (via the Active List writeback).