# SMT Implementation: Fetch Pipeline & PC Arbitration

**Date:** November 2025
**Module:** Pipeline/Fetch (NextPCStage, FetchStage)
**Objective:** Implement multi-thread fetch arbitration and duplicated PC management.

---

## Overview
This update transforms the core from a single-threaded fetch loop to a **Simultaneous Multithreaded (SMT)** frontend. The `NextPCStage` now acts as an arbiter, selecting which thread to fetch instructions for in each cycle using a **Round-Robin** policy.

## Key Modifications

### 1. `PC.sv` (Program Counter)
* **Structure:** Changed from a single `FlipFlopWE` to a generated bank of registers: `FlipFlopWE ... [NUM_THREADS]`.
* **Reason:** Each thread must maintain its own instruction pointer.

### 2. `NextPCStageIF.sv` (Interface)
* **Interface Widening:**
    * `pcOut` is now an array `PC_Path pcOut[NUM_THREADS]`.
    * `pcWE` is now a write-mask array `logic pcWE[NUM_THREADS]`.
* **Flow:** Allows `NextPCStage` to read all PCs simultaneously (to select one) and write back to specific PCs individually.

### 3. `NextPCStage.sv` (Arbitration Logic)
* **Round-Robin Arbiter:**
    * Added a `threadCounter` that increments every clock cycle **unless stalled**.
    * `currentThread = threadCounter % NUM_THREADS`.
* **Stall Handling:**
    * **Critical SMT Logic:** If the pipeline stalls (e.g., I-Cache miss), the arbiter **pauses**. It must retry the *same* thread in the next cycle until the instruction fetch succeeds.
* **Multiplexing:**
    * `currentPC` is selected from `port.pcOut[currentThread]`.
    * `predNextPC` is calculated based on `currentPC`.
* **Write Enable Demux:**
    * Only `port.pcWE[currentThread]` is asserted during normal fetch.
    * Other threads preserve their PC values.

### 4. `FetchStage.sv`
* **TID Propagation:**
    * Receives `tid` from `NextPCStage` via pipeline registers (`prev.nextStage`).
    * Passes `tid` to the `BranchPredictor` and `BTB` via the `FetchStageIF`.
    * Ensures that when instructions are passed to the Decode stage, they are tagged with their owner `ThreadID`.

## Verification Notes
* **Reset:** Verify that on `rst`, all PC banks reset to `INSN_RESET_VECTOR`.
* **Stall Behavior:** Ensure that when `icReadHit` is false, `currentThread` does **not** change in the next cycle.