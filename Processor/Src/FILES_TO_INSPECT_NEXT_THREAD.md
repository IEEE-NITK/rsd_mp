# Complete File Inspection List for Next Thread

**Purpose**: List all files that should be inspected for thread-awareness before Phase 4 implementation  
**Status**: 23/42+ files inspected in Thread 1, 17-19 remaining for Thread 2

---

## 📊 SUMMARY TABLE

| Category | Files | Inspected | Remaining | Priority |
|----------|-------|-----------|-----------|----------|
| FetchUnit | 5 | 5 | 0 | ✓ Done |
| Cache | 8 | 8 | 0 | ✓ Done |
| Pipeline Stages | 7 | 7 | 0 | ✓ Done |
| RenameLogic | 5 | 5 | 0 | ✓ Done |
| Configuration | 3 | 3 | 0 | ✓ Done |
| **Recovery** | 2 | 0 | **2** | 🔴 **CRITICAL** |
| **Scheduler** | 3 | 0 | **3** | 🔴 **CRITICAL** |
| **LoadStoreUnit** | 5 | 0 | **5** | 🔴 **CRITICAL** |
| Controller | 2 | 1 | **1** | 🟡 Medium |
| RegisterFile | 3 | 0 | **3** | 🟡 Medium |
| ExecUnits | 20+ | 0 | 20+ | 🟢 Low |
| Privileged | 2 | 0 | **2** | 🟢 Low |
| IO | 2 | 0 | 2 | 🟢 Low |
| **TOTAL** | **42+** | **23** | **17-19** | |

---

## 🔴 CRITICAL FILES (MUST INSPECT BEFORE PHASE 4)

### 1. Recovery Manager (2 files)

```
Recovery/RecoveryManager.sv
├─ Purpose: Handles recovery from branch misprediction, exceptions
├─ Size: ~800-1000 lines estimated
├─ Critical Questions:
│  ├─ How does RMT recovery work?
│  ├─ Can it support per-thread RMT?
│  ├─ Can free lists be recovered per-thread?
│  ├─ How does checkpoint mechanism work?
│  ├─ Can Thread 0 recovery affect Thread 1?
│  └─ What signals drive recovery?
├─ Lines to focus:
│  ├─ 1-50: Interface and signals
│  ├─ 50-150: Recovery phase logic
│  ├─ 200-400: RMT recovery implementation
│  └─ 400-end: State machines
├─ Expected changes for Phase 4:
│  ├─ May need to make RMT recovery per-thread aware
│  ├─ May need per-thread recovery checkpoints
│  └─ May need per-thread recovery enables
├─ Blocking potential: HIGH - If recovery doesn't support per-thread
└─ Risk to Phase 4: CRITICAL
   
Recovery/RecoveryManagerIF.sv
├─ Purpose: Interface definition for recovery
├─ Critical Questions:
│  ├─ Are recovery signals thread-aware?
│  ├─ Are there recovery enable signals per thread?
│  ├─ How do checkpoints work?
│  └─ What is the recovery protocol?
├─ Expected content:
│  ├─ Recovery control signals
│  ├─ Checkpoint signals
│  ├─ RMT clear/restore signals
│  └─ Free list signals
└─ Blocking potential: MEDIUM
```

**Next Thread Action**:
```
1. Open Recovery/RecoveryManager.sv
2. Read entire file (understand recovery flow)
3. Focus on RMT recovery section
4. Check if per-thread recovery is feasible
5. Document: Can Phase 4 have per-thread recovery?
```

---

### 2. Scheduler (3 files)

```
Scheduler/Scheduler.sv
├─ Purpose: Main scheduler (coordinates all issue queues)
├─ Size: ~1000-2000 lines estimated
├─ Critical Questions:
│  ├─ How are instructions allocated to issue queue?
│  ├─ What's the selection/issue strategy?
│  ├─ Are there thread priorities?
│  ├─ Can we dispatch per-thread?
│  ├─ How does wakeup work?
│  └─ Can threads block each other?
├─ Lines to focus:
│  ├─ 1-50: Interface definition
│  ├─ 100-200: Allocation logic
│  ├─ 300-500: Selection logic
│  └─ 600-end: Wakeup logic
├─ Design decision:
│  ├─ Option A: Shared queue, thread-aware dispatch
│  ├─ Option B: Per-thread issue queues (replicates Scheduler)
│  └─ RECOMMENDED: Option A (simpler)
├─ Expected changes for Phase 4:
│  ├─ Add thread field to allocation signals
│  ├─ Modify dispatch to be thread-aware
│  └─ May need thread priority logic
└─ Blocking potential: MEDIUM
   
Scheduler/IssueQueue.sv
├─ Purpose: Issue queue implementation
├─ Critical Questions:
│  ├─ How are entries allocated?
│  ├─ How are entries deallocated?
│  ├─ What's the entry structure?
│  ├─ Does entry have thread field?
│  └─ Can queue be shared across threads?
├─ Expected changes for Phase 4:
│  ├─ May need to add ThreadID field to entry
│  ├─ May need per-thread read pointers
│  └─ Keep write path shared
└─ Blocking potential: LOW
   
Scheduler/SchedulerIF.sv
├─ Purpose: Interface for scheduler
├─ Critical Questions:
│  ├─ Are allocation signals thread-aware?
│  ├─ Are dispatch signals thread-aware?
│  ├─ Are there thread control signals?
│  └─ What's the scheduler protocol?
├─ Expected content:
│  ├─ Allocate signals
│  ├─ Issue/dispatch signals
│  ├─ Wakeup signals
│  └─ Control signals
└─ Blocking potential: LOW
```

**Next Thread Action**:
```
1. Open Scheduler/Scheduler.sv (large file, skim)
2. Find "allocate" logic
3. Find "dispatch" or "issue" logic
4. Question: Can dispatch be made thread-aware?
5. Open Scheduler/IssueQueue.sv
6. Find entry type definition
7. Question: Can entries have thread field?
8. Decision: Shared or per-thread queue?
9. Document design choice
```

---

### 3. Load/Store Unit (5 files)

```
LoadStoreUnit/LoadStoreUnit.sv
├─ Purpose: Main load/store unit (coordinates load/store queues)
├─ Size: ~1000-1500 lines estimated
├─ Critical Questions:
│  ├─ How are load/store queues allocated?
│  ├─ How is memory ordering enforced?
│  ├─ How are dependencies tracked?
│  ├─ Can Thread 0 load block Thread 1 store?
│  ├─ Can we have per-thread queues?
│  └─ What changes needed for thread-awareness?
├─ Lines to focus:
│  ├─ 1-50: Interface definition
│  ├─ 100-200: Allocation logic
│  ├─ 300-500: Memory ordering logic
│  └─ 600-end: Dependency logic
├─ Design decision:
│  ├─ Option A: Per-thread load/store queues
│  ├─ Option B: Shared with thread tracking
│  └─ RECOMMENDED: Option A (following RMT pattern)
├─ Expected changes for Phase 4:
│  ├─ Replicate load queue per thread
│  ├─ Replicate store queue per thread
│  ├─ Modify allocation to be thread-aware
│  └─ Modify memory ordering to work per-thread
└─ Blocking potential: MEDIUM
   
LoadStoreUnit/LoadQueue.sv
├─ Purpose: Load queue implementation
├─ Critical Questions:
│  ├─ How is allocation done?
│  ├─ How is deallocation done?
│  ├─ What's the entry structure?
│  ├─ How is dependency checking done?
│  ├─ What's the queue size?
│  └─ Can it be replicated?
├─ Expected changes for Phase 4:
│  ├─ Create per-thread instances
│  ├─ Modify allocation to index by thread
│  ├─ Modify deallocation to be thread-aware
│  └─ Keep dependency checking logic same
└─ Blocking potential: LOW
   
LoadStoreUnit/StoreQueue.sv
├─ Purpose: Store queue implementation
├─ Critical Questions:
│  ├─ How is allocation done?
│  ├─ How is write-back done?
│  ├─ What's the entry structure?
│  ├─ How is memory ordering done?
│  └─ Can it be replicated?
├─ Expected changes for Phase 4:
│  ├─ Create per-thread instances
│  ├─ Modify allocation to index by thread
│  ├─ Modify write-back to be thread-aware
│  └─ Keep memory ordering logic same (or enhance)
└─ Blocking potential: LOW
   
LoadStoreUnit/LoadStoreUnitIF.sv
├─ Purpose: Interface for load/store unit
├─ Critical Questions:
│  ├─ Are allocation signals thread-aware?
│  ├─ Are there thread control signals?
│  ├─ What's the load/store protocol?
│  └─ How are results communicated?
├─ Expected content:
│  ├─ Allocation request signals
│  ├─ Allocation grant signals
│  ├─ Queue pointer signals
│  ├─ Execute/commit signals
│  └─ Memory result signals
└─ Blocking potential: LOW
   
LoadStoreUnit/LoadStoreUnitTypes.sv
├─ Purpose: Type definitions for load/store unit
├─ Critical Questions:
│  ├─ What's the load queue entry structure?
│  ├─ What's the store queue entry structure?
│  ├─ Are entries thread-aware?
│  ├─ What's the queue index width?
│  └─ Can entries be extended with ThreadID?
├─ Expected content:
│  ├─ LoadQueueEntry typedef
│  ├─ StoreQueueEntry typedef
│  ├─ Queue size parameters
│  └─ Dependency tracking types
└─ Blocking potential: LOW
```

**Next Thread Action**:
```
1. Open LoadStoreUnit/LoadStoreUnit.sv
2. Skim for allocation logic
3. Find memory ordering enforcement
4. Question: Can queues be per-thread?
5. Open LoadStoreUnit/LoadQueue.sv
6. Find entry type, understand structure
7. Open LoadStoreUnit/StoreQueue.sv
8. Find entry type, understand structure
9. Decision: Replicate per-thread or shared with thread ID?
10. Recommend: Per-thread (following RMT pattern)
11. Document design choice
```

---

## 🟡 MEDIUM PRIORITY FILES (Important but not blocking)

### 4. Controller (2 files)

```
Controller.sv
├─ Purpose: Main pipeline controller (stall, clear, flush)
├─ Critical Questions:
│  ├─ How does stall/clear work?
│  ├─ Can we stall per-thread?
│  ├─ Can we clear per-thread?
│  ├─ How does flush work?
│  └─ Can threads be independent?
├─ Partial inspection in Thread 1: YES
├─ Focus for Thread 2:
│  ├─ Understand stall logic
│  ├─ Understand clear logic
│  ├─ Check if per-thread signals exist
│  └─ Document feasibility of per-thread control
└─ Risk to Phase 4: LOW-MEDIUM

ControllerIF.sv
├─ Purpose: Controller interface
├─ Critical Questions:
│  ├─ What control signals exist?
│  ├─ Are they thread-aware?
│  └─ What's the control protocol?
├─ Partial inspection in Thread 1: YES
└─ Risk to Phase 4: LOW
```

---

### 5. Register File (3 files)

```
RegisterFile/RegisterFile.sv
├─ Purpose: Physical register file
├─ Critical Questions:
│  ├─ Is register file thread-aware?
│  ├─ Are there per-thread register sets?
│  ├─ How are physical registers shared?
│  ├─ What happens on simultaneous access?
│  ├─ Can Thread 0 read Thread 1's register?
│  └─ Do we need thread field in requests?
├─ Expected: Single shared register file (all threads access same)
├─ Concern: Make sure bypass respects thread boundaries
└─ Risk to Phase 4: LOW (probably no changes needed)

RegisterFile/BypassController.sv
├─ Purpose: Bypass control logic
├─ Critical Questions:
│  ├─ How does bypass work?
│  ├─ Can it forward cross-thread?
│  ├─ Does it check thread match?
│  ├─ What about bypassing within RMT stage?
│  └─ Is there cross-thread vulnerability?
├─ Expected: Should NOT bypass across threads (critical!)
├─ Verification needed: Ensure thread safety
└─ Risk to Phase 4: MEDIUM if not thread-safe

RegisterFile/BypassNetwork.sv
├─ Purpose: Bypass paths implementation
├─ Critical Questions:
│  ├─ How many bypass paths?
│  ├─ Which stages bypass to which?
│  ├─ Can bypass paths cross threads?
│  └─ Is there thread filtering?
├─ Expected: Bypass only within thread pipeline
├─ Verification needed: Trace bypass paths
└─ Risk to Phase 4: MEDIUM if not thread-safe
```

**Next Thread Action**:
```
1. Skim Controller.sv (understand stall/clear)
2. Question: Can control be per-thread?
3. Skim ControllerIF.sv (see control signals)
4. Read RegisterFile/RegisterFile.sv (understand structure)
5. Question: Is it shared? (Probably yes)
6. Read RegisterFile/BypassController.sv
7. CRITICAL: Find where bypass target is selected
8. Question: Can bypass go cross-thread?
9. If yes: Document as HIGH RISK
10. If no: Document as safe
```

---

## 🟢 LOW PRIORITY FILES (Probably don't need changes)

### 6. Execution Units (20+ files)

**Files**:
```
Pipeline/IntegerBackEnd/IntegerIssueStage.sv
Pipeline/IntegerBackEnd/IntegerRegisterReadStage.sv
Pipeline/IntegerBackEnd/IntegerExecutionStage.sv
Pipeline/IntegerBackEnd/IntegerRegisterWriteStage.sv

Pipeline/ComplexIntegerBackEnd/ComplexIntegerIssueStage.sv
Pipeline/ComplexIntegerBackEnd/ComplexIntegerRegisterReadStage.sv
Pipeline/ComplexIntegerBackEnd/ComplexIntegerExecutionStage.sv
Pipeline/ComplexIntegerBackEnd/ComplexIntegerRegisterWriteStage.sv

Pipeline/MemoryBackEnd/MemoryIssueStage.sv
Pipeline/MemoryBackEnd/MemoryRegisterReadStage.sv
Pipeline/MemoryBackEnd/MemoryExecutionStage.sv
Pipeline/MemoryBackEnd/MemoryAccessStage.sv
Pipeline/MemoryBackEnd/MemoryTagAccessStage.sv
Pipeline/MemoryBackEnd/MemoryRegisterWriteStage.sv

Pipeline/FPBackEnd/FPIssueStage.sv
Pipeline/FPBackEnd/FPRegisterReadStage.sv
Pipeline/FPBackEnd/FPExecutionStage.sv
Pipeline/FPBackEnd/FPRegisterWriteStage.sv

ExecUnit/IntALU.sv
ExecUnit/Shifter.sv
ExecUnit/MultiplierUnit.sv
MulDivUnit/MulDivUnit.sv
FloatingPointUnit/*.sv (20+ files)
```

**Why Low Priority**:
- These operate on already-dispatched ops
- Thread information is in the op
- Should not need structural changes
- May need thread field propagation only

**When to Review**:
- Only if Phase 4 execution tests fail
- Not needed for Phase 4 resource allocation

---

### 7. Privileged/CSR Unit (2 files)

```
Privileged/CSR_Unit.sv
Privileged/CSR_UnitIF.sv
```

**Why Low Priority**:
- CSR is usually per-core or shared
- CSR access not thread-sensitive for SMT
- Can defer until Phase 5 (if needed)

---

### 8. IO Unit (2 files)

```
IO/IO_Unit.sv
IO/IO_UnitIF.sv
```

**Why Low Priority**:
- IO is usually shared
- Not part of core SMT concern
- Can defer until Phase 5 (if needed)

---

## 📋 DETAILED CHECKLIST FOR NEXT THREAD

### Step 1: Understand Recovery (90 min)
```
[ ] Read Recovery/RecoveryManager.sv completely
[ ] Identify RMT recovery section
[ ] Find checkpoint mechanism
[ ] Trace recovery signal flow
[ ] Check: Recovery per-thread capable? (Y/N)
[ ] Check: Free list recovery per-thread capable? (Y/N)
[ ] Document findings in file
```

### Step 2: Understand Scheduler (90 min)
```
[ ] Skim Scheduler/Scheduler.sv (focus on allocation)
[ ] Read Scheduler/IssueQueue.sv completely
[ ] Identify entry type structure
[ ] Find allocation/deallocation logic
[ ] Check: Can allocation be thread-aware? (Y/N)
[ ] Check: Can queues be per-thread? (Y/N)
[ ] Decision: Shared queue vs per-thread
[ ] Document findings and design decision
```

### Step 3: Understand Load/Store Unit (120 min)
```
[ ] Skim LoadStoreUnit/LoadStoreUnit.sv
[ ] Read LoadStoreUnit/LoadQueue.sv completely
[ ] Read LoadStoreUnit/StoreQueue.sv completely
[ ] Identify entry types and sizes
[ ] Understand allocation/deallocation
[ ] Check: Memory ordering logic
[ ] Check: Dependency tracking
[ ] Check: Can queues be per-thread? (Y/N)
[ ] Decision: Per-thread queues
[ ] Document findings
```

### Step 4: Verify Register File Safety (60 min)
```
[ ] Read RegisterFile/BypassController.sv
[ ] Find bypass target selection logic
[ ] Trace: Can bypass reach cross-thread? (Y/N)
[ ] Check: Is there thread filtering? (Y/N)
[ ] CRITICAL: If can cross-thread, document as HIGH RISK
[ ] If cannot cross-thread, document as SAFE
[ ] Decision: Changes needed? (Y/N)
```

### Step 5: Assess Controller Flexibility (30 min)
```
[ ] Skim Controller.sv (understand stall/clear)
[ ] Check: Can stall be per-thread? (probably Y)
[ ] Check: Can clear be per-thread? (probably Y)
[ ] Document: Controller compatibility with per-thread resources
```

### Step 6: Create Summary (60 min)
```
[ ] List all findings
[ ] Identify any blockers for Phase 4
[ ] Make GO/NO-GO decision
[ ] Create implementation plan
[ ] Estimate timeline
```

---

## 📄 OUTPUT FORMAT FOR NEXT THREAD

For each inspected file, create summary:

```
FILE: Recovery/RecoveryManager.sv
PURPOSE: Handle recovery from branch misprediction
STATUS: CRITICAL

FINDINGS:
- RMT recovery works by: [description]
- Per-thread RMT recovery: [FEASIBLE/NOT FEASIBLE]
- Free list recovery per-thread: [FEASIBLE/NOT FEASIBLE]
- Checkpoint mechanism: [SUPPORTS/DOES NOT SUPPORT] per-thread

DESIGN IMPACT:
- Phase 4 changes needed: [YES/NO]
- If yes, what: [list changes]
- Risk level: [LOW/MEDIUM/HIGH]

BLOCKING PHASE 4: [YES/NO]
RECOMMENDATION: [proceed/hold until fixed/investigate further]
```

---

## 🎯 SUCCESS CRITERIA FOR NEXT THREAD

**Phase 4 Ready After Inspection If**:

- ✅ Recovery: Per-thread RMT recovery feasible
- ✅ Scheduler: Allocation can be thread-aware OR per-thread queues possible
- ✅ Load/Store: Queues can be replicated per-thread
- ✅ Register File: Bypass is thread-safe (no cross-thread leakage)
- ✅ Controller: Allows independent thread control
- ✅ NO critical blockers found

**Phase 4 Blocked If**:

- ❌ Recovery cannot support per-thread
- ❌ Register file has cross-thread bypass vulnerability
- ❌ Core architectural issue found
- ❌ Unresolvable design conflict discovered

---

## 📞 REFERENCE BACK TO THREAD 1

Thread 1 Findings:
- ✅ Phase 1-3 complete and correct
- ✅ RMT.sv pattern proven
- ✅ Baseline verified: IPC 0.985285
- ⚠️ Recovery/Scheduler/LSU not fully inspected
- 📋 17-19 files remaining for Thread 2

---

## 🚀 EXPECTED OUTPUT FROM NEXT THREAD

After completing this inspection, Thread 2 should produce:

1. **Critical File Audit Report**
   - Recovery assessment
   - Scheduler assessment
   - Load/Store Unit assessment
   - Register File safety assessment
   - Controller flexibility assessment

2. **GO/NO-GO Decision**
   - Phase 4 can proceed: YES/NO
   - If NO, what needs fixing first

3. **Detailed Phase 4 Plan**
   - Per-thread resource decisions
   - Implementation sequence
   - Expected timeline
   - Risk assessment

4. **Code Change Checklist**
   - All files that need modification
   - All files that are safe as-is
   - All blockers identified

5. **Ready to Code**
   - Implementation ready to begin
   - All design decisions made
   - Pattern (RMT.sv) confirmed applicable

---

**Good luck with the critical file review!**

This handover document + inspected files should give you everything needed to make Phase 4 ready.
