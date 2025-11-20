# SMT Implementation: Rename Logic & Reorder Buffer

**Date:** November 2025
**Module:** RenameLogic (Processor Backend Frontend)
**Status:** SMT-Ready (Partitioned Resources, Single-Thread Commit Arbitration)

---

## 1. Architectural Overview
This directory implements the **Resource Allocation** and **Retirement** logic for the SMT core. The design uses a **Static Partitioning** strategy for the Reorder Buffer and a **Banked/Duplicated** strategy for Register Map Tables.

### SMT Strategy
* **Dispatch:** Instructions from Thread 0 and Thread 1 are renamed using independent logical-to-physical mappings.
* **Active List (ROB):** The memory is statically partitioned. Thread 0 uses the lower half, Thread 1 uses the upper half.
* **Commit:** A Round-Robin Arbiter (in `CommitStage`) selects **one thread per cycle** to retire up to `COMMIT_WIDTH` instructions.
* **Free List:** The Physical Register Free List is a **Shared Global Resource**. Threads compete for available registers.

---

## 2. File Modification Log

### `ActiveList.sv` & `ActiveListIF.sv` (The Reorder Buffer)
**Status:** Heavily Modified
* **Partitioning:** The underlying RAM is split into `NUM_THREADS` partitions.
* **Pointers:** `headPtr` and `tailPtr` are converted to arrays `[NUM_THREADS]`.
    * Push logic uses `pushTid` to select the correct tail pointer.
    * Pop logic uses `popHeadNum[tid]` to update the correct head pointer.
* **Read Ports:** The module now exposes the Head entries of **ALL threads simultaneously** (`readData[NUM_THREADS][COMMIT_WIDTH]`). This allows the Commit Stage arbiter to inspect the status of both threads before deciding who commits.
* **Allocatable:** Now returns an array `allocatable[NUM_THREADS]`. Thread 0 stalling (full ROB) does not prevent Thread 1 from dispatching.

### `RMT.sv` (Speculative Register Map Table)
**Status:** Modified
* **Banking:** The RAM depth is increased to `LREG_NUM * NUM_THREADS`.
* **Addressing:** Accesses are now banked using the Thread ID.
    * Address = `{tid, logical_reg_index}`.
* **Interface:** Reads and Writes now utilize `tid` signals from `RenameLogicIF` to target the correct bank.

### `RetirementRMT.sv` (Architectural Register Map Table)
**Status:** Modified
* **Instantiation Strategy:** This module is designed to be instantiated **once per thread** inside `RenameLogic.sv`.
* **Reset Logic:** Added logic to offset the initial physical register mapping based on `THREAD_ID`.
    * Thread 0 maps `r0->phy0`.
    * Thread 1 maps `r0->phy(offset)`.

### `RenameLogic.sv` (Top-Level Glue)
**Status:** Modified
* **Committer Generation:** Instantiates `RenameLogicCommitter` inside a `generate` loop (one per thread).
* **Release Aggregation:** Because only one thread commits per cycle (Arbiter strategy), the physical register release signals from all committers are **OR-ed** together to feed the single shared Free List.
* **Wiring:** Extracts `tid` from pipeline registers and passes it to `RMT` and `ActiveList` to ensure correct partitioning.

### `RenameLogicCommitter.sv` (Commit State Machine)
**Status:** Modified
* **Parameterization:** Added `parameter integer TID` to allow specific instances to index into the thread-array interfaces (`activeList.popHeadNum[TID]`, etc.).
* **Function:** Tracks the commit/recovery phase for a single thread independently of the others.

### `RenameLogicIF.sv` (Interface)
**Status:** Updated
* **Signal Widening:** Converted `readData`, `headExecState`, and `allocatable` to thread-indexed arrays.
* **TID Support:** Added `rmtWriteReg_Tid` to support banked RMT writes.

### `RenameLogicTypes.sv` (Struct Definitions)
**Status:** Updated
* **ActiveListEntry:** Added `ThreadID tid;` to the struct so the ROB knows which thread owns an instruction (crucial for selective flushing).
* **ActiveListWriteData:** Added struct definition required by the ActiveList module.

---

## 3. Critical Logic Details

### The "Single-Thread Commit" Logic
To simplify the Write Ports on the Retirement RMT and Free List, we assume an **Arbiter** in the `CommitStage`.
1.  `RenameLogic.sv` generates commit signals for T0 and T1.
2.  `CommitStage` selects **one** active thread.
3.  `RenameLogic` sees `commit[selected]` go high.
4.  `RenameLogic` sets `releasePhyScalarReg` based on the selected thread.
5.  Since only one thread releases registers in a cycle, we do not need extra write ports on the Free List.

### Resource Partitioning Math
* **ROB Size:** `CONF_ACTIVE_LIST_ENTRY_NUM` (Global).
* **Per-Thread ROB:** `CONF_ACTIVE_LIST_ENTRY_NUM / NUM_THREADS`.
* **Physical Registers:** Shared pool.
    * Reset state: T0 gets first `LREG_NUM` regs, T1 gets next `LREG_NUM` regs. Remaining regs are in Free List.

## 4. Dependencies
* Requires `COMMIT_WIDTH` and `NUM_THREADS` to be defined in `MicroArchConf.sv` or `BasicTypes.sv`.
* Requires `CommitStage.sv` to be updated to support the Arbiter logic (provided separately).