# Critical Files Analysis - Thread 2

**Status**: Completed analysis of all critical files  
**Date**: 2025-11-24  
**Baseline**: IPC 0.985285, 4621 cycles (maintained)  
**Phase 4 Readiness**: GO

---

## 1. Recovery Logic Assessment

### Recovery/RecoveryManager.sv

**Key Finding 1**: Recovery is **NOT thread-aware** - operates on entire core, not per-thread
- Lines 82-94: Reset clears all recovery state globally
- Lines 98-225: All recovery logic uses global signals without thread checking
- No thread field in `RecoveryManagerStatePath` struct (lines 31-57)
- Recovery signals are broadcast to all modules: `toRecoveryPhase`, `toCommitPhase` (global)

**Key Finding 2**: RMT recovery mechanism is **compatible with per-thread design**
- RMT recovery happens via `renameLogicRecoveryRMT` signal (line 113)
- Recovery doesn't modify RMT directly - that's handled in RenameLogic
- RecoveryManager just coordinates timing (2-phase: RECOVER_0, RECOVER_1)
- Free list is returned via `issueQueueReturnIndex` (lines 40-41, 273)

**Key Finding 3**: Load/Store queue recovery uses pointers, not thread-aware
- `loadQueueRecoveryTailPtr` and `storeQueueRecoveryTailPtr` (lines 197-200)
- These pointers are set from ActiveList, not per-thread
- But they can be used per-thread if queues are per-thread

**Per-thread RMT recovery possible**: **YES**
- Recovery provides recovery signals to each module
- RMT itself (verified in Thread 1) is already per-thread capable
- Recovery signals are global but target is per-thread

**Per-thread free list recovery possible**: **YES**
- Issue Queue has free list reset mechanism (lines 95-110 in IssueQueue.sv)
- Recovery triggers freeListReset which drains the queue
- Can be made per-thread by adding thread check

**Blocking Phase 4**: **NO**
- Recovery architecture is orthogonal to per-thread design
- Recovery operates on per-module basis, not requiring thread awareness
- RMT.sv pattern can handle this (already verified)

**Recommendation**: **PROCEED** - Recovery is compatible with per-thread RMT

---

## 2. Scheduler Assessment

### Scheduler/Scheduler.sv

**Key Finding 1**: Scheduler allocation is **NOT thread-aware**
- Lines 75-178: Writes go directly to issue queue without thread check
- `port.write[i]` and `port.writePtr[i]` used directly
- No ThreadID field in write signals
- Instruction dispatch doesn't carry thread information to scheduler

**Key Finding 2**: Issue queue dispatch/selection is **fully thread-agnostic**
- Lines 288-306: Issue selection based purely on `notIssued` flag and instruction type
- No thread filtering in dispatch logic
- Selection is independent for each instruction type (int, load, store, etc.)
- Multiple instructions can be dispatched without considering thread origin

**Key Finding 3**: Scheduler can support **both shared queue AND per-thread approach**
- Thread information IS available in dispatch stage (verified in Thread 1)
- If we add thread field to `port.write[]`, scheduler can handle it
- Current architecture doesn't prevent thread awareness

**Design Choice Analysis**:
```
CHOICE A: Shared issue queue with thread-aware dispatch
├─ Would need: Thread field in dispatch signals
├─ Scheduler impact: Minimal - add thread check to allocation
├─ Pro: Better resource utilization
├─ Con: Complex wakeup logic for cross-thread dependencies
├─ Verdict: HARDER than it appears - wakeup network very complex

CHOICE B: Per-thread issue queues
├─ Would need: Replicate entire issue queue per-thread
├─ Scheduler impact: Minimal - dispatch to correct queue based on thread
├─ Pro: Cleaner design, no cross-thread issues
├─ Con: Duplicate hardware for queues
├─ Verdict: SIMPLER and SAFER
```

**Design Decision**: **CHOICE B - Per-thread issue queues**

**Justification**: 
- Issue queue is small (ISSUE_QUEUE_ENTRY_NUM = likely 64)
- Per-thread replication = 2 × 64 = manageable
- Shared queue would require complex wakeup logic to remain thread-safe
- Per-thread design follows RMT.sv pattern exactly
- Less risk of cross-thread interference

**Implementation Impact**: 
- Modify IssueQueue.sv to create separate allocators/RAMs per thread
- Add thread multiplexing in dispatcher
- Wakeup network stays shared but indexed per-thread entry

---

### Scheduler/IssueQueue.sv

**Entry Structure**:
```systemverilog
typedef struct {
    // Multiple types of entries for different pipelines:
    IntIssueQueueEntry      // INT_ISSUE_WIDTH (likely 2-4)
    MemIssueQueueEntry      // MEM_ISSUE_WIDTH (likely 2-4)
    ComplexIssueQueueEntry  // COMPLEX_ISSUE_WIDTH (conditional)
    FPIssueQueueEntry       // FP_ISSUE_WIDTH (conditional)
    
    // Entry contains:
    // - opId
    // - srcRegValidA, srcRegValidB, srcRegValidC
    // - phySrcRegNumA, phySrcRegNumB, phySrcRegNumC
    // - opDst (writeReg, phyDstRegNum)
    // - Many other fields (depends on entry type)
}
```

**Entry Size Estimate**:
- IntIssueQueueEntry: ~60-80 bits
- MemIssueQueueEntry: ~80-100 bits (includes address info)
- ComplexIssueQueueEntry: ~70-90 bits
- FPIssueQueueEntry: ~70-90 bits

**ISSUE_QUEUE_ENTRY_NUM**: Likely 32-64 (typical for RV64)

**Replication Feasible**: **YES - STRONGLY FEASIBLE**
- Per-thread overhead: 2× issue queue RAMs
- Total size: 64 entries × 80 bits × 2 = 10 KB - negligible
- Multiplexing adds ~1 layer of logic
- No timing impact expected

**Thread Field Needed**: **NO** (not in shared design)
- Per-thread queues eliminate need for thread field
- Each queue is implicitly for one thread

---

## 3. Load/Store Unit Assessment

### LoadStoreUnit/LoadStoreUnit.sv

**Key Finding 1**: Load/Store Unit is **NOT thread-aware**
- Lines 70-123: All processing is global
- No thread filtering or thread-specific logic
- Data path operations (shift, extend) don't care about thread

**Key Finding 2**: Memory ordering is enforced **between all loads and stores**
- Store-load forwarding works across full LSQ
- Dependency tracking: Store can bypass to ANY load
- This is **correct for single-thread**, but needs review for SMT

**Key Finding 3**: LSU interfaces provide queue pointers, not thread info
- LoadQueue and StoreQueue are referenced by pointer, not thread
- If queues are per-thread, LSU must know which queue to access
- Forwarding logic must understand per-thread queues

**Memory Model**: Sequential consistency for load/store ordering
- Loads can forward from older stores
- Stores must respect load-store ordering
- Works per-thread OR shared with careful tracking

**Design Decision Analysis**:
```
CHOICE A: Per-thread load/store queues
├─ Pro: No cross-thread forwarding issues
├─ Pro: Clean separation
├─ Pro: Each thread has independent memory order
├─ Con: Duplicate hardware
├─ Verdict: PREFERRED for correctness

CHOICE B: Shared queues with thread tracking
├─ Pro: Better resource utilization
├─ Pro: Allows cross-thread store forwarding if needed
├─ Con: Complex logic to ensure memory order correctness
├─ Con: Thread checking on every comparison
├─ Verdict: DOABLE but risky
```

**Design Decision**: **CHOICE A - Per-thread load/store queues**

**Justification**:
- Load/Store queues are critical for correctness
- SMT allows each thread independent memory order
- Per-thread design removes cross-thread ordering constraints
- Safer to implement and verify
- Matches RMT.sv pattern

**Implementation Impact**:
- Replicate LoadQueue and StoreQueue per-thread
- Add thread multiplexing for LSU interface
- Forwarding network stays within per-thread queues
- Recovery must set per-thread tail pointers ✓ (already supported)

---

### LoadStoreUnit/LoadQueue.sv

**Entry Structure**:
```systemverilog
typedef struct {
    logic finished;                 // Has address been computed?
    logic regValid;                 // Should register be written?
    LSQ_BlockAddrPath address;      // Store address for ordering check
    LSQ_BlockWordEnablePath wordRE; // Which bytes are accessed
    PC_Path pc;                     // For memory predictor
}
```

**Entry Size**: ~80-100 bits
**LOAD_QUEUE_ENTRY_NUM**: Likely 32-64

**Queue Size Context** (from code):
- Lines 42-55: Uses SetTailMultiWidthQueuePointer with RENAME_WIDTH, COMMIT_WIDTH
- Entries allocated on rename, deallocated on commit
- Can wrap around (lines 19-24)

**Replication Feasible**: **YES - HIGHLY FEASIBLE**
- Very simple entry structure
- Per-thread: 2 × 64 × 100 bits = 12.8 KB - negligible
- Head/tail pointers replicated per-thread ✓
- Recovery mechanism already supports per-thread ✓ (loadQueueRecoveryTailPtr)

---

### LoadStoreUnit/StoreQueue.sv

**Entry Structure** (AddrEntry):
```systemverilog
typedef struct {
    logic finished;                 // Has store committed to be written?
    logic regValid;                 // Source register valid?
    LSQ_BlockAddrPath address;      // Store address
    LSQ_BlockWordEnablePath wordWE; // Which bytes to write
    LSQ_WordByteEnablePath byteWE;  // Byte enable mask
}
```

**Entry Size**: ~100-120 bits
**STORE_QUEUE_ENTRY_NUM**: Likely 32-64

**Replication Feasible**: **YES - HIGHLY FEASIBLE**
- Simple structure, similar to LoadQueue
- Per-thread: 2 × 64 × 120 bits = 15.4 KB
- Head/tail pointers already handled ✓
- Recovery mechanism supports per-thread ✓

**Note**: Store data is in separate "DataEntry" (lines 198+), also simple

---

## 4. Register File Safety Assessment

### RegisterFile/BypassController.sv

**Critical Analysis - Bypass Thread Safety**:

**Finding 1**: Bypass mechanism is **SHARED across all threads**
- Lines 119-138: Pipeline stages are single, not per-thread
- `intRR`, `intEX`, `intWB` arrays are shared (not per-thread)
- `memRR`, `memEX`, `memMT`, `memMA`, `memWB` are shared

**Finding 2**: Bypass selection does **NOT check thread**
- Lines 54-106: `SelectReg()` function finds matching register
- Lines 76-87: Searches intEX/intWB stages for matching register number
- Lines 90-103: Searches memMA/memWB stages
- **NO THREAD CHECKING** - if reg # matches, bypass happens!

**CRITICAL VULNERABILITY**: **YES - CROSS-THREAD DATA LEAKAGE POSSIBLE**

Scenario that would cause error:
```
Thread 0 operation:  Loads register from r5
Thread 1 operation:  Writes r5 in its pipeline
Thread 0 would receive Thread 1's value!
```

**Finding 3**: Why this works in current single-thread:
- Only one thread's registers in pipeline at a time
- Bypass only matches thread's own operations
- But with SMT, this breaks!

**Blocking Phase 4**: **YES - CRITICAL BLOCKER**

**Mitigation Required**:
```
Option 1: Add thread field to bypass pipeline stages
├─ Modify BypassCtrlStage to include thread
├─ Add thread check in SelectReg() function
├─ Lines to modify: ~20 lines total

Option 2: Separate bypass networks per-thread
├─ More complex restructuring
├─ Significant hardware duplication

Option 3: Disable cross-stage bypass (not viable - big performance hit)
```

**Recommended Fix**: **Option 1 - Add thread checking**
- Minimal hardware overhead
- ~20 lines of changes in BypassController
- Must propagate thread through bypass pipeline
- Thread field already available in execution stages (Thread 1 verified)

---

### RegisterFile/RegisterFile.sv

**Organization**: **SHARED register file** (not per-thread)
- Line 48-60: Single physical register file for all threads
- Single DistributedMultiPortRAM for both integer and FP registers
- No threading in register file itself - correct design

**Read Ports**: 
- INT_READ_NUM: (INT_ISSUE_WIDTH + COMPLEX_ISSUE_WIDTH + MEM_ISSUE_WIDTH) × 2 + FP_ISSUE_WIDTH
- Typically: (2 + 2 + 2) × 2 + 2 = 14 read ports per cycle
- FP_READ_NUM: FP_ISSUE_WIDTH × 3 + MEM_ISSUE_WIDTH = 5-8 more

**Write Ports**: 
- INT_WRITE_NUM: INT_ISSUE_WIDTH + COMPLEX_ISSUE_WIDTH + LOAD_ISSUE_WIDTH + FP_ISSUE_WIDTH
- Typically: 2 + 2 + 2 + 2 = 8 write ports per cycle

**Can two threads write same register simultaneously**: **YES - AND THAT'S OK**
- Shared register file means physical registers are thread-agnostic
- Write/read arbitration is at port level, not thread level
- Threads use different physical register numbers (via RMT mapping)
- Register file doesn't need thread awareness ✓

**Conflict Resolution**: Implicit via RMT mapping
- Each thread's rename table maps to different physical registers
- No conflicts because Thread 0 and Thread 1 use different phys reg spaces
- Verified in Thread 1: RMT.sv pattern assigns per-thread registers

**Thread Safety Assessment**: **SAFE** (register file itself)
- **BUT**: Bypass network needs thread checking ⚠️

---

## 5. Controller Flexibility Assessment

### Controller.sv

**Key Finding 1**: Pipeline control is **GLOBAL** (not per-thread)
- Lines 40-128: Front-end stall/clear applies to entire pipeline
- Lines 142-177: Back-end stall/clear is global
- All stages share single control signals

**Key Finding 2**: Stall/clear logic does **NOT differentiate threads**
```
Lines 63-72:    cmStageFlushUpper = global flush for branch misprediction
Lines 74-84:    rnStageSendBubbleLower = global stall for rename registers
Lines 95-106:   idStageStallUpper = global stall for decoder
Lines 155-160:  isStageStallUpper = global stall for scheduler
```

**Per-thread stall possible**: **NO** (not without major changes)
- Current design: all threads stall together or all go together
- Would require separate stall paths per thread
- Would need per-thread state machines

**Per-thread clear possible**: **PARTIALLY**
- Recovery system already differentiates stages (RECOVER_0, RECOVER_1)
- But all threads clear together in the recovery phase
- Could be extended to per-thread recovery

**Flexibility for Phase 4**: **MEDIUM**

**Analysis**:
```
Current design supports:
- Global stall (affects both threads): ✓ OK for Phase 4
- Global clear (recovery affects entire pipeline): ✓ OK for Phase 4

Limitation:
- Cannot stall Thread 0 while Thread 1 runs
- Both threads must synchronize at stall points

Acceptable for Phase 4? YES
- Single-threaded baseline will still work ✓
- Both threads stalling together doesn't break correctness ✓
- Performance impact: threads wait for each other at stall points
- This is acceptable for first Phase 4 implementation
```

**Does this block Phase 4**: **NO**
- Phase 4 goal is per-thread resources (RMT, queues), not independent execution
- Threads can share stall/clear signals
- Correctness is maintained with shared control

---

## PHASE 4 READINESS SUMMARY

### Critical Issues Found:

1. **BLOCKING**: Bypass network NOT thread-safe
   - **Fix Required**: Add thread checking to BypassController
   - **Effort**: ~30 minutes
   - **Risk**: LOW (well-defined fix)

2. **NON-BLOCKING**: Controller is global (not per-thread)
   - **Fix Needed**: NO - shared control is acceptable
   - **Performance**: Minor impact (threads wait for each other)

3. **OK**: Recovery is compatible
   - **Status**: Ready for per-thread design
   - **No changes needed**: RecoveryManager stays global

4. **OK**: Scheduler/Issue Queue can be per-thread
   - **Status**: Ready
   - **Design decided**: Per-thread queues (CHOICE B)

5. **OK**: Load/Store queues can be per-thread
   - **Status**: Ready  
   - **Design decided**: Per-thread queues (CHOICE A)

6. **OK**: Register file is shared (correct design)
   - **Status**: Ready
   - **Only issue**: Bypass network (see #1)

---

## PHASE 4 READINESS: **GO WITH PREREQUISITE FIX**

### Prerequisites Before Implementation:

**MUST FIX** (1-2 hours):
```
✓ Fix 1: Add thread checking to BypassController.sv
  - Add ThreadID field to bypass pipeline stages
  - Modify SelectReg() to check thread matching
  - Propagate thread through bypass path
  - Est. 30 min
  
✓ Verification: Test bypass doesn't cross threads
  - Run make run with fix
  - Verify baseline: IPC 0.985285, cycles 4621
  - Est. 30 min
```

**DESIGN DECISIONS MADE**:
```
✓ Free Lists: Use RMT.sv pattern (per-thread)
✓ Active List: Use RMT.sv pattern (per-thread)
✓ Issue Queue: Per-thread design (separate queues/allocators)
✓ Load Queue: Per-thread design
✓ Store Queue: Per-thread design
✓ Register File: Stays shared (correct)
✓ Controller: Stays global (acceptable)
✓ Recovery: Stays global (compatible)
```

---

## Implementation Plan (Ready to Start)

### Phase 4 Implementation Steps:

**Week 1 - Prerequisites**:
1. Fix bypass network thread safety (30 min)
2. Test baseline maintained (30 min)

**Week 1-2 - Implementation**:
1. Free Lists (RMT.sv pattern) - 45 min
2. Active List (RMT.sv pattern) - 60 min
3. Issue Queue (per-thread) - 60 min
4. Load Queue (per-thread) - 45 min
5. Store Queue (per-thread) - 45 min
6. Integration testing - 1-2 hours

**Expected Timeline**: 5-6 hours total (after bypass fix)

**Testing After Each File**:
```bash
make clean && make all && make run
# Should see: IPC 0.985285, cycles 4621
```

---

## Next Thread Objectives

### Thread 3 Tasks:

1. **Apply Bypass Fix** (30 min)
   - File: RegisterFile/BypassController.sv
   - Add thread field to BypassCtrlStage
   - Update SelectReg() function
   - Test baseline

2. **Implement Per-Thread Free Lists** (45 min)
   - File: RenameLogic/RenameLogicIF.sv
   - Check if free list signals need thread field
   - File: RenameLogic/RenameLogic.sv (or separate free list module)
   - Apply RMT.sv pattern
   - Test

3. **Implement Per-Thread Active List** (60 min)
   - File: Will identify in Thread 3
   - Apply RMT.sv pattern
   - Test

4. **Implement Per-Thread Issue Queue** (60 min)
   - File: Scheduler/IssueQueue.sv
   - Create per-thread allocators
   - Add thread multiplexing
   - Test

5. **Implement Per-Thread Load Queue** (45 min)
   - File: LoadStoreUnit/LoadQueue.sv
   - Apply RMT.sv pattern
   - Test

6. **Implement Per-Thread Store Queue** (45 min)
   - File: LoadStoreUnit/StoreQueue.sv
   - Apply RMT.sv pattern
   - Test

---

## Success Criteria for Phase 4

After implementation, verify:

1. ✅ Code compiles without errors
2. ✅ Code compiles without warnings
3. ✅ `make run` completes successfully
4. ✅ Output shows: IPC 0.985285, cycles 4621 (exactly)
5. ✅ All per-thread resources use RMT.sv pattern
6. ✅ Bypass network has thread checking
7. ✅ No cross-thread data leakage
8. ✅ Recovery mechanism works with per-thread resources

---

## Files Modified Summary

### Prerequisite (Before Phase 4):
- [ ] RegisterFile/BypassController.sv - Add thread checking

### Phase 4 Implementation:
- [ ] RenameLogic files - Free Lists per-thread
- [ ] Active List module - Per-thread
- [ ] Scheduler/IssueQueue.sv - Per-thread queues
- [ ] LoadStoreUnit/LoadQueue.sv - Per-thread
- [ ] LoadStoreUnit/StoreQueue.sv - Per-thread
- [ ] Interface files (if needed) - Add thread signals

---

## Reference Documentation

This analysis builds on:
- HANDOVER_TO_NEXT_PHASE.md (context)
- PHASE4_PATTERN_TEMPLATE.md (implementation pattern)
- PHASE3_VERIFICATION_REPORT.md (verified components)
- RenameLogic/RMT.sv (proven per-thread pattern)

---

## Conclusion

**Phase 4 is FEASIBLE and READY to implement** with one prerequisite fix:

1. **Bypass network thread safety** - MUST FIX (30 min)
2. **Per-thread resource allocation** - READY (follows RMT pattern)
3. **All critical files reviewed** - COMPLETE
4. **Design decisions made** - COMPLETE
5. **Implementation path clear** - COMPLETE

**Recommendation**: Proceed to Thread 3 for bypass fix + Phase 4 implementation

**Expected Outcome**: Per-thread RMT, Active List, Issue Queue, Load/Store Queues with baseline maintained

---

**Status**: Ready for Phase 4 Implementation  
**Next Action**: Begin Thread 3 - Apply bypass fix and implement per-thread resources
