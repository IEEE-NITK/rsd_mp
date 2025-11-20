# SMT Implementation: Cache System (L1 I/D & Memory Controller)

**Date:** November 2025
**Module:** Cache (Memory Hierarchy)
**Status:** SMT-Ready (Shared Physical Resources)

---

## 1. Architectural Overview
In this SMT implementation, the L1 Caches are **Fully Shared** resources.
* **Physically Addressed:** The caches operate on Physical Addresses (PA). Since T0 and T1 reside in different virtual address spaces (managed by the TLB/MMU before reaching here) but share physical RAM, they share the cache entries.
* **Thread-Agnostic Storage:** A cache line does not store which thread "owns" it. If Thread 0 loads data from `0x8000`, and Thread 1 later reads `0x8000`, Thread 1 hits on the exact same cache line. This enables **True Sharing** between threads.
* **Arbitrated Access:**
    * **Fetch:** The `FetchUnit` arbitrates which thread accesses the I-Cache port.
    * **Data:** The `LoadStoreUnit` arbitrates which thread accesses the D-Cache ports.

---

## 2. File Modification Log

### `CacheSystemTypes.sv`
**Status:** **Modified** (Critical)
* **Struct Update:** Added `ThreadID tid;` to the `MissStatusHandlingRegister` (MSHR) struct.
* **Purpose:** When a cache miss occurs, the hardware must remember **who** asked for the data.
    * When data returns from main memory 100 cycles later, the MSHR reads this stored `tid` to signal the **Replay Queue** to wake up the correct thread.

### `DCache.sv` & `ICache.sv`
**Status:** Unchanged Logic
* **Reasoning:** These modules handle Tag Arrays, Data Arrays, and LRU replacement. None of this logic changes for SMT because "Thread Identity" is handled at the queue level (LSU/Fetch), not the storage level.
* **Data Flow:** These modules effectively pass the `tid` field (embedded in the request structs) through to the MSHR without needing explicit logic changes.

### `CacheFlushManager.sv`
**Status:** Unchanged Logic
* **Global Flushing:** Cache flushing (e.g., `FENCE.I`) is treated as a **Global Event**.
* **Reasoning:** If Thread 0 modifies instruction memory, the hardware cannot guarantee that Thread 1 isn't about to execute that same memory. Therefore, a flush request from *any* thread invalidates the entire I-Cache/D-Cache for *all* threads to ensure coherency.

### `MemoryAccessController.sv`
**Status:** Unchanged Logic
* **Reasoning:** This is the interface to the AXI/Main Memory bus. The memory controller sees only Physical Addresses and Burst Requests. It is entirely blind to the concept of threads.

---

## 3. The Lifecycle of an SMT Cache Miss

1.  **Request:** Thread 1 issues `LOAD 0x5000`.
2.  **Lookup:** `DCache.sv` checks the tags. Result: **MISS**.
3.  **Allocation:** An MSHR entry is allocated.
    * `MSHR.Addr = 0x5000`
    * `MSHR.TID = 1` (This comes from `CacheSystemTypes` modification).
4.  **Refill:** `MemoryAccessController` fetches data from RAM.
5.  **Wakeup:** `DCacheMissHandler` sees the data return.
    * It reads `MSHR.TID` (which is 1).
    * It sends a signal to the `ReplayQueue`: "Data ready for Thread 1."
6.  **Replay:** The Replay Queue wakes up Thread 1's load instruction. Thread 0 is undisturbed.

---

## 4. Verification Notes
* **Data Sharing:** Verify that if T0 writes to `0x1000` and commits, T1 can immediately read that value from the D-Cache (Hit) without going to RAM.
* **Isolation:** Verify that a cache miss on T0 does not stall T1's access to the cache (if T1 hits).
* **Flushing:** Verify that `FENCE.I` executed by T0 clears the I-Cache for T1 as well.