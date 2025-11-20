# SMT Implementation: Load/Store Unit (LSU)

**Date:** November 2025
**Module:** LoadStoreUnit (Memory Ordering & Data Handling)
**Status:** SMT-Ready (Shared Queues, Thread-Aware Forwarding, Selective Flushing)

---

## 1. Architectural Overview
The Load/Store Unit manages memory requests, enforces dependencies, and handles data forwarding. In this SMT implementation:
* **Shared Queues:** The Load Queue (LQ) and Store Queue (SQ) are **shared circular buffers**. Entries from Thread 0 and Thread 1 are interleaved based on issue order.
* **Tagged Entries:** Every entry in the LQ and SQ is tagged with a `ThreadID (tid)` to identify ownership.
* **L1 Cache as Sync Point:** The L1 Data Cache is the shared synchronization point. It contains committed data visible to both threads.

---

## 2. Memory Ordering Rules (The Logic of Sharing)

### A. Store-to-Load Forwarding (Same Thread)
This mechanism ensures a thread sees its own actions in program order ("Sequential Consistency").
* **Scenario:** Thread 0 writes `5` to Address `A`. Immediately after, Thread 0 reads Address `A`.
* **Mechanism:** The Load instruction checks the Store Queue.
* **Logic:** `if (Load.Addr == Store.Addr) AND (Load.TID == Store.TID)`
* **Action:** **FORWARD**. The data `5` is sent directly from the SQ to the Load Unit.
* **Why:** A thread must always see the most recent version of its own data, even if that data is speculative and hasn't reached the cache yet.

### B. True Sharing (Cross-Thread Communication)
This handles how Thread 0 sees data written by Thread 1.
* **Scenario:** Thread 1 writes `99` to Address `B`. Thread 0 reads Address `B`.
* **Mechanism:** The Load instruction checks the Store Queue.
* **Logic:** `if (Load.Addr == Store.Addr) BUT (Load.TID != Store.TID)`
* **Action:** **DO NOT FORWARD**. The Load ignores the Store Queue entry and reads from the L1 Data Cache.
* **Why:**
    1.  **Isolation:** Thread 1's write is **speculative**. If Thread 1 encounters an exception later, that store will be flushed. If Thread 0 read it, Thread 0 would be processing "illegal" data.
    2.  **Consistency Model:** In standard consistency models, a thread is not required to see another thread's writes until they are **Committed** to the memory hierarchy.
* **Result:** Thread 0 sees the *old* value until Thread 1 retires the store and writes `99` to the L1 Cache. Once in the cache, Thread 0 will see `99`.

---

## 3. The Flush Strategy: "Swiss Cheese" vs. Rollback

When a branch misprediction occurs for **Thread 0**, we must remove its speculative instructions from the Load Queue. However, the LQ also contains valid instructions from **Thread 1**.

### Why we CANNOT use Rollback (Tail Pointer Reset)
In a single-threaded core, flushing is easy: simply move the `Tail Pointer` back to the mispredicted instruction. Everything after it is overwritten.
* **The SMT Danger:** Since the queue is shared, valid instructions from Thread 1 might sit *after* the bad instruction from Thread 0.
* **Result:** Moving the Tail Pointer back would delete Thread 1's valid work, causing a crash.



### The Solution: "Swiss Cheese" (Validity Masking)
We use a selective invalidation strategy.
1.  **Pointers Stay:** The `Tail Pointer` is **not moved** back (unless the queue is empty or the flush is total).
2.  **Broadcast:** The system broadcasts a flush signal: "Invalidate all ops from Thread 0 younger than Age X."
3.  **Invalidation:** Instructions inside the LQ checking this signal set their `valid` bit to `0`.
4.  **Result:** The queue effectively becomes "Swiss Cheese"—it has holes (invalid entries) scattered among valid entries from Thread 1.
    * **Pros:** Thread 1 is completely unaffected. Logic is simple.
    * **Cons:** The "holes" occupy space in the RAM until they naturally reach the Head of the queue and are retired. This slightly reduces effective queue capacity.

---

## 4. File Modification Log

### `LoadStoreUnitTypes.sv`
**Status:** Modified
* **Struct Update:** Added `ThreadID tid;` to `LoadQueueEntry` and `StoreQueueAddrEntry` structs.

### `LoadStoreUnitIF.sv`
**Status:** Modified
* **Interface Update:** Added `executedLoadTid` and `executedStoreTid` signals so the pipeline can pass IDs to the queues.
* **Array Conversion:** Converted commit/release signals to arrays `[NUM_THREADS]` to support the Commit Stage arbiter.

### `LoadQueue.sv`
**Status:** Heavily Modified
* **TID Capture:** Latches `executedLoadTid` into the queue memory on execution.
* **Forwarding Logic:** Updated the address match loop to check `loadQueue[i].tid == currentLoadTid`.
* **Ordering Logic:** Updated dependency checks to ensure loads only wait for stores of the *same* thread.
* **Release Logic:** Merged (OR-ed) release signals from the Commit Stage arbiter.

### `StoreQueue.sv`
**Status:** Modified
* **TID Capture:** Latches `executedStoreTid`.
* **Forwarding Logic:** Updated logic to only forward data to loads if `load.tid == store.tid`.

### `LoadStoreUnit.sv` & `StoreCommitter.sv`
**Status:** Minor Updates
* Wired up the modified interfaces and types. No major internal logic changes were required as they operate on physical addresses/pointers provided by the queues.

---

## 5. Verification & Configuration
* **Queue Size:** Because the "Swiss Cheese" method leaves invalid entries ("holes") in the queue until they retire, it is recommended to **increase** `CONF_LOAD_QUEUE_ENTRY_NUM` and `CONF_STORE_QUEUE_ENTRY_NUM` (e.g., from 16 to 32) to compensate for the wasted space during high-misprediction scenarios.