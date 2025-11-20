# SMT Implementation: Micro-Architecture Configuration

**Date:** November 2025
**Module:** MicroArchConf (System Parameters)
**Status:** SMT-Tuned

---

## 1. Core SMT Settings

| Parameter | Value | Description |
| :--- | :--- | :--- |
| **`CONF_THREAD_NUM`** | **2** | Defines the number of hardware threads (Harts). This controls array sizes for PC, RMT, and CSRs. |
| **`CONF_FETCH_WIDTH`** | **2** | The core fetches 2 instructions per cycle *for the selected thread*. This width flows down the pipeline. |
| **`CONF_COMMIT_WIDTH`** | **2** | The core retires up to 2 instructions per cycle *for the selected thread*. |

---

## 2. Resource Sizing & Rationale

To support SMT without degrading performance or causing deadlocks, specific resources had to be increased.

### A. Physical Register File (Critical)
**Parameter:** `CONF_PSCALAR_NUM`, `CONF_PSCALAR_FP_NUM`
* **Old Value:** 64
* **New Value:** **128**
* **Reasoning:**
    * **Architectural State:** Each thread requires 32 logical registers to hold its committed state. With 2 threads, **64 registers are permanently locked** just to hold the valid state of the software.
    * **Renaming Overhead:** If the total size were 64, the Free List would be size 0. No new instructions could be renamed, causing an immediate **Deadlock** at reset.
    * **Calculation:** `32 (T0) + 32 (T1) + 64 (Speculative Window) = 128`.

### B. Active List (Reorder Buffer)
**Parameter:** `CONF_ACTIVE_LIST_ENTRY_NUM`
* **Old Value:** 64
* **New Value:** **128**
* **Reasoning:**
    * **Partitioning:** The Active List memory is statically partitioned to prevent one thread from starving the other.
    * **Effective Depth:** Thread 0 gets indices `0-63`. Thread 1 gets indices `64-127`.
    * Increasing the total to 128 ensures each thread maintains a 64-instruction scheduling window, preserving the Out-of-Order performance capability of the original design.

### C. Issue Queue
**Parameter:** `CONF_ISSUE_QUEUE_ENTRY_NUM`
* **Old Value:** 16
* **New Value:** **32**
* **Reasoning:**
    * **Shared Resource:** The Issue Queue is shared dynamically.
    * **Throughput:** With two threads fetching instructions, a 16-entry queue fills up twice as fast. Increasing to 32 prevents the Frontend from stalling frequently due to backend congestion.

### D. Load / Store Queues
**Parameter:** `CONF_LOAD_QUEUE_ENTRY_NUM`, `CONF_STORE_QUEUE_ENTRY_NUM`
* **Old Value:** 16
* **New Value:** **32**
* **Reasoning:**
    * **"Swiss Cheese" Flushing:** We use a validity-masking flush strategy instead of pointer rollback. When Thread 0 flushes, its entries become "holes" in the circular buffer that cannot be reclaimed until they reach the head.
    * **Compensating for Waste:** Increasing the size compensates for these temporary holes, ensuring Thread 1 still has space to issue memory operations even after a flush event.

### E. Replay Queue
**Parameter:** `CONF_REPLAY_QUEUE_ENTRY_NUM`
* **Old Value:** 20
* **New Value:** **40**
* **Reasoning:**
    * **Latency Hiding:** The primary benefit of SMT is hiding cache miss latency. If Thread 0 misses in the L1 Cache, its instructions sit in the Replay Queue.
    * **Prevention of Blockage:** If the RQ is too small, a single cache miss sequence from Thread 0 could fill the RQ, stalling Dispatch and preventing Thread 1 (which might have a cache hit) from executing. Doubling the size allows Thread 1 to "pass" Thread 0.

---

## 3. Pipeline Policy Summary
* **Fetch/Commit:** **Round-Robin Arbitration**. Only one thread utilizes the Fetch/Commit bandwidth in a single cycle, but they alternate to maximize utilization.
* **Execution:** **Fully Shared**. ALUs, FPU, and Memory Units accept instructions from any thread as soon as operands are ready.
* **Queues:** **Shared**. Slots are allocated on a first-come, first-served basis (except Active List).