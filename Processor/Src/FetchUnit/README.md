# SMT Implementation: Fetch Unit Modifications

**Date:** November 2025  
**Module:** Fetch Unit (Frontend)  
**Objective:** Enable Simultaneous Multithreading (SMT) by making branch prediction and target resolution thread-aware.

---

## Overview of Changes
To support multiple threads, the Fetch Unit must distinguish between instruction streams. The primary modifications involve:
1.  **Tagging** branch target entries with Thread IDs (TID) to prevent target aliasing.
2.  **Duplicating** architectural state (Global History Register) per thread to ensure prediction isolation.
3.  **Updating** interfaces to pass `ThreadID` signals through the pipeline.

---

## File-by-File Modification Log

### 1. `FetchUnitTypes.sv`
**Status:** Modified  
**Key Changes:**
* **Struct Updates:** Added `ThreadID tid;` to the following structures:
    * `BTB_Entry`: To tag cached targets.
    * `BranchResult`: To track which thread executed the branch (for updates).
    * `BranchPred`: To track which thread made the prediction.
* **Purpose:** ensures that any data passed between the Fetch Stage and the Execute/Commit stages carries the context of the thread it belongs to.

### 2. `BTB.sv` (Branch Target Buffer)
**Status:** Modified  
**Key Changes:**
* **Storage:** Added a `tid` field to the BTB RAM entry.
* **Lookup Logic:** Changed the hit detection logic. 
    * *Old:* `match = (tag == entry.tag)`
    * *New:* `match = (tag == entry.tag) && (fetchThreadID == entry.tid)`
* **Update Logic:** When writing new entries (on branch resolution), the `tid` from the `BranchResult` is written into the BTB.
* **Reset:** Added logic to reset state for all threads.
* **Reasoning:** Prevents **Target Aliasing**. Without this, Thread A could fetch from PC `0x100`, hit a BTB entry created by Thread B at `0x100`, and jump to a target address that is invalid for Thread A.

### 3. `Gshare.sv` (Global History Predictor)
**Status:** Heavily Modified  
**Key Changes:**
* **State Duplication:** `regBrGlobalHistory` converted from a single register to an array: `logic [...] regBrGlobalHistory [NUM_THREADS]`.
* **Context Switching:** * Added combinational logic to select the history of the **current fetching thread** (`fetchThreadID`) for prediction lookups.
* **Update/Recovery:** * On branch updates or mispredictions, only the specific `tid`'s history index is updated/restored.
    * Other threads' histories remain untouched.
* **Reasoning:** A global history pattern (e.g., Taken-Taken-NotTaken) is only semantically valid within a single execution stream. Mixing histories destroys prediction accuracy.

### 4. `Bimodal.sv`
**Status:** Updated for Compatibility  
**Key Changes:**
* **Shared PHT:** The Pattern History Table (PHT) remains **shared** between threads.
* **Interface Update:** Updated to handle the `BranchResult` struct containing `tid`, though the logic doesn't strictly segregate the counters.
* **Reasoning:** While this introduces "interference" (Thread A and B updating the same counter), it is a standard SMT design trade-off to save area. The predictor remains functional, though slightly less accurate than a duplicated PHT.

### 5. `BranchPredictor.sv`
**Status:** Updated Wrapper  
**Key Changes:**
* Pass-through of updated interfaces.
* Ensures the correct `ThreadID` signals flow from the controller to the specific predictor sub-modules (`Gshare` or `Bimodal`).

---

## New Parameters & Signals
The following assumptions were made regarding the system configuration (likely in `BasicTypes` or `MicroArchConf`):

| Parameter / Signal | Description |
| :--- | :--- |
| `NUM_THREADS` | Total number of hardware threads supported (e.g., 2). |
| `ThreadID` | Typedef for thread identifier (e.g., `logic [0:0]` for 2 threads). |
| `fetchThreadID` | Input signal to Fetch Unit indicating which thread is currently fetching. |

## Next Steps
1.  **Arbitration:** Implement Round-Robin or ICount policy in `FetchStage.sv` / `NextPCStage.sv` to drive the `fetchThreadID` signal.
2.  **PC Management:** Duplicate the Program Counter (PC) for each thread in the Pipeline control logic.