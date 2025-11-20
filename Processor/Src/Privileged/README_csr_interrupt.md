# SMT Implementation: Privileged Architecture (CSRs & Interrupts)

**Date:** November 2025
**Module:** Privileged (Control Status Registers, Interrupt Controller)
**Status:** SMT-Ready (Duplicated Architectural State)

---

## 1. Architectural Overview
In an SMT processor, the Operating System views each hardware thread as a distinct logical core. Therefore, the **Architectural State** defining the privilege level, exception handling, and configuration must be duplicated.

* **State Duplication:** Each thread has its own set of Control Status Registers (CSRs), including `mepc` (Exception PC), `mcause` (Trap Cause), and `satp` (Page Table Pointer).
* **Interrupt Isolation:** Interrupts (Timer, External) are targeted at specific threads. If Thread 0 receives a timer interrupt, it must trap to its own handler without disturbing Thread 1.

---

## 2. File Modification Log

### `CSR_UnitIF.sv` (Interface)
**Status:** Modified
* **Signal Banking:** Converted all scalar control and data signals to arrays `[NUM_THREADS]`.
    * Examples: `triggerExcpt[t]`, `excptCause[t]`, `mepc[t]`.
* **Read/Write Selection:** Added `ThreadID csrAccessTid` to the interface. This allows the Memory Pipeline (which executes CSR instructions) to specify *which* bank to read or write.

### `CSR_Unit.sv` (Register File)
**Status:** Modified
* **Storage:** Changed `CSR_BodyPath csrReg` to `csrReg[NUM_THREADS]`.
* **Read Logic:** Uses `port.csrAccessTid` to multiplex the output. When the pipeline executes `CSRRW`, it reads the register belonging to the thread that issued the instruction.
* **Update Logic:** Wrapped in a loop `for(int t=0; t<NUM_THREADS; t++)`.
    * **Exceptions:** If `triggerExcpt[t]` is asserted, only `csrReg[t]` is updated (e.g., `mepc[t] <= fault_pc`).
    * **Commit:** Updates `minstret[t]` (Instructions Retired) independently based on `commitNum[t]`.

### `InterruptController.sv`
**Status:** Modified
* **Logic Duplication:** The logic checks for pending interrupts for *each* thread independently.
* **Flow:**
    1.  Reads `csrReg[t].mie` (Interrupt Enable) and `csrReg[t].mip` (Interrupt Pending).
    2.  Determines if Thread `t` should take a trap.
    3.  Asserts `triggerInterrupt[t]` to the CSR Unit and Fetch Stage.
* **Arbitration:** The signal `ctrl.npStageSendBubbleLowerForInterrupt` is now an OR of all threads' requests, ensuring the pipeline bubbles correctly if *any* thread needs to jump to an ISR (Interrupt Service Routine).

---

## 3. Data Flow: Exception Handling

1.  **Fault:** Thread 0 executes an illegal instruction in `DecodeStage`.
2.  **Propagation:** The fault flows down the pipeline tagged with `TID=0`.
3.  **Recovery:** `RecoveryManager` detects the fault for Thread 0.
4.  **Trap:** `RecoveryManager` asserts `triggerExcpt[0]` to `CSR_Unit`.
5.  **CSR Update:** `CSR_Unit` updates `csrReg[0].mcause` and `csrReg[0].mepc`. **`csrReg[1]` remains unchanged.**
6.  **Redirect:** The Fetch Unit receives the trap vector address for Thread 0 and redirects the PC for Thread 0 only.

## 4. Verification Notes
* **Independence:** Verify that writing to a scratch register (e.g., `mscratch`) on Thread 0 does not change the value read from `mscratch` on Thread 1.
* **Counters:** Verify `minstret` (Instructions Retired) increments only for the thread that is actually committing instructions.