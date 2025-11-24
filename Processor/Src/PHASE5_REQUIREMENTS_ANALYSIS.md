# Phase 5: Multi-Threaded Workload Testing - Requirements Analysis

**Status**: Pre-phase planning  
**Prerequisite**: Phase 4 completion with baseline verified  
**Estimated Scope**: 4-6 hours  
**Target**: 2-thread simultaneous execution with performance measurement

---

## 🎯 PHASE 5 OBJECTIVES

### Primary Goals
1. **Enable multi-threaded execution** - Run 2 threads simultaneously
2. **Verify per-thread isolation** - Each thread operates independently
3. **Measure performance** - IPC and throughput with 2 threads
4. **Detect issues** - Cross-thread hazards, resource contention, deadlocks
5. **Establish baseline** - 2-thread baseline for future optimization

### Success Criteria
- ✅ 2 threads load and execute simultaneously
- ✅ Each thread runs independently (no cross-thread register interference)
- ✅ System completes without crashes or deadlocks
- ✅ Performance metrics measurable (IPC, cycle count per thread)
- ✅ No undefined behavior or assertion failures

---

## 📊 PHASE 4 → PHASE 5 TRANSITION

### What Phase 4 Provides
From Phase 4 (when complete):
1. ✅ Per-thread Free Lists (register allocation)
2. ✅ Per-thread Active Lists (instruction tracking)
3. ✅ Per-thread Issue Queues (instruction scheduling)
4. ✅ Per-thread Load Queues (memory operation ordering)
5. ✅ Per-thread Store Queues (memory operation ordering)
6. ✅ Thread ID propagation through entire pipeline
7. ✅ Thread-aware bypass network (no cross-thread forwarding)

### What Still Needs to Be Done in Phase 5
1. **Test Framework Changes**
   - Multi-threaded test code loader
   - Per-thread memory regions in test framework
   - Thread synchronization primitives (if needed)

2. **Verification Infrastructure**
   - Per-thread performance counters
   - Thread interaction logging
   - Cross-thread dependency detection

3. **Potential Additional Pipeline Updates**
   - Commit stage may need per-thread awareness
   - Recovery logic may need per-thread recovery paths
   - Memory subsystem thread-awareness verification

4. **Testing & Debugging**
   - Create 2-thread test programs
   - Run with various thread interaction patterns
   - Debug any cross-thread issues discovered

---

## 🔍 DETAILED ANALYSIS: WHAT'S ALREADY THREAD-AWARE

### ✅ DEFINITELY Thread-Aware (From Phase 4)

**Allocation**:
- Register renaming (Free Lists) ✅
- Active list entries ✅
- Issue queue entries ✅
- Load queue entries ✅
- Store queue entries ✅

**Execution Units**:
- All execution units receive thread ID from scheduler ✅
- Bypass network checks thread IDs ✅

**Register File**:
- BypassController.sv has thread-aware bypass logic ✅

### ⚠️ PARTIALLY Thread-Aware (Needs Verification)

**Commit Stage** (Pipeline/CommitStage.sv):
- Needs review: Does it handle per-thread commits?
- Needs check: Does it release per-thread resources?
- Needs verification: Does recovery work per-thread?

**Recovery Manager** (Recovery/RecoveryManager.sv):
- Needs check: Does it handle per-thread recovery paths?
- Needs verification: Can it recover one thread without affecting other?

**Fetch Unit** (FetchUnit/NextPCStage.sv):
- Needs review: Does it maintain per-thread PC and branch state?

### ❌ LIKELY NOT Thread-Aware Yet (Future Phases)

**Cache System**:
- DCache may need thread-aware handling for coherency
- ICache may need per-thread state separation
- (Phase 6+)

**Memory Subsystem**:
- MSHR sharing may cause issues
- Load-store ordering may need per-thread verification
- (Phase 6+)

**Branch Prediction**:
- BTB/branch predictor may need per-thread entries
- (Phase 6+)

---

## 📋 TASKS FOR PHASE 5

### Task 1: Pre-Phase 5 Checklist (15 min)

Before starting Phase 5, verify:

```bash
# Verify Phase 4 completion
- [ ] RSD_ENABLE_SMT macro defined correctly
- [ ] All 5 resources have per-thread instances
- [ ] Interface signals all wired correctly
- [ ] Baseline test passing: IPC 0.985285, 4621 cycles
- [ ] 0 compilation warnings

# Verify Phase 4 code quality
- [ ] All ifdef blocks properly closed
- [ ] Thread signals reach all necessary modules
- [ ] No single-threaded assumptions in critical paths
- [ ] Code formatted consistently
```

### Task 2: Create Multi-Threaded Test Framework (1-2 hours)

**File**: `Verification/TestCode/Asm/MultiThread/` (new directory)

**What's Needed**:

1. **Test Code Generator**
   - Load 2 independent programs into memory
   - Place each in separate address range
   - Ensure no interference

2. **Memory Layout**
   ```
   Thread 0 code:   0x1000 - 0x1FFF
   Thread 0 data:   0x2000 - 0x2FFF
   Thread 1 code:   0x3000 - 0x3FFF
   Thread 1 data:   0x4000 - 0x4FFF
   Shared region:   0x5000+ (for testing interactions)
   ```

3. **Thread Dispatch Mechanism**
   - Boot loader distinguishes threads
   - Each thread jumps to own code section
   - Mechanism: Thread ID from hardware or config

4. **Synchronization (Optional for Phase 5)**
   - Simple spin-wait loops
   - Shared flag locations
   - (Full synchronization in Phase 6)

### Task 3: Verify Commit Stage Threading (1 hour)

**File**: `Pipeline/CommitStage.sv`

**Things to Check**:

1. **Retirement Logic**
   ```systemverilog
   // Does it handle per-thread retirement?
   - Does it track per-thread commit pointers?
   - Does it release per-thread resources?
   - Does it maintain per-thread ordering?
   ```

2. **Recovery Logic**
   ```systemverilog
   // Can it recover one thread without affecting other?
   - Does recovery preserve other thread's state?
   - Does it only flush affected thread's instructions?
   - Do recovery pointers work per-thread?
   ```

3. **CSR Access**
   ```systemverilog
   // Are CSRs properly virtualized per thread?
   - Thread-private CSRs (sepc, stval, etc.)?
   - Thread-shared CSRs (mstatus conditions)?
   ```

**Expected Findings**:
- ✅ Most likely already correct (was done in Phase 3)
- ⚠️ May need minor adjustments
- ❌ If major issues, Phase 5 is blocked

### Task 4: Verify Fetch Stage Threading (30 min)

**File**: `Pipeline/FetchStage/NextPCStage.sv`

**Things to Check**:

1. **Per-Thread PC Management**
   - Is PC maintained per thread?
   - Does branch prediction work per thread?
   - Are branch updates isolated?

2. **Thread Scheduling**
   - How are threads interleaved in fetch?
   - Does round-robin scheduling work?
   - Are both threads making progress?

### Task 5: Create 2-Thread Test Cases (1 hour)

**Create Test Set 1: Independent Execution**

Test file: `Verification/TestCode/Asm/MultiThread/IndependentExecution.s`

```systemverilog
// Thread 0: Simple arithmetic
// Thread 1: Simple arithmetic (different registers)
// Expected: Both complete independently, IPC slightly lower due to contention
// Baseline: Single-thread IPC ≈ 0.985
// With 2 threads: IPC might be 0.95-1.0 (thread overhead)
```

**Create Test Set 2: Synchronized Execution**

Test file: `Verification/TestCode/Asm/MultiThread/Synchronized.s`

```systemverilog
// Thread 0: Do work, wait at barrier
// Thread 1: Do work, wait at barrier
// Expected: Both threads synchronize without deadlock
```

**Create Test Set 3: Load-Store Interaction**

Test file: `Verification/TestCode/Asm/MultiThread/LoadStoreInteraction.s`

```systemverilog
// Thread 0: Load from thread 1's data region
// Thread 1: Store to thread 0's data region
// Expected: Correct ordering and values
```

### Task 6: Modify Test Framework for Multi-Threading (1-2 hours)

**Files to Modify**:
- `Verification/TestMain.sv` - Add multi-thread support
- `Verification/Dumper.sv` - Add per-thread tracing
- Test configuration files - Add thread parameters

**Changes Needed**:

1. **Test Loader**
   ```systemverilog
   // Load thread 0 code/data at 0x1000
   // Load thread 1 code/data at 0x3000
   // Signal both threads to start
   ```

2. **PC Initialization**
   ```systemverilog
   // Thread 0: PC = 0x1000
   // Thread 1: PC = 0x3000
   ```

3. **Output Formatting**
   ```systemverilog
   // Show per-thread execution trace
   // [T0] Cycle 123: ADD r1, r2, r3
   // [T1] Cycle 123: SUB r4, r5, r6
   ```

### Task 7: Performance Monitoring (1 hour)

**Create**:
- Per-thread instruction counter
- Per-thread cycle counter
- Per-thread CPI (cycles per instruction)
- Shared resource contention metrics

**Metrics to Track**:
```
Per Thread:
- Instructions executed
- Cycles elapsed
- IPC (instructions/cycle)
- Stall cycles (broken down by reason)

Shared Resources:
- Register file port conflicts
- Cache conflicts
- Execution unit conflicts
```

### Task 8: Debugging Infrastructure (1 hour)

**Add Debug Signals**:
- Per-thread PC trace
- Per-thread instruction trace
- Resource allocation trace (who allocated what)
- Cross-thread hazard detection

**Create Debug Output**:
```
[Cycle 100] Thread 0: PC=0x1234, inst=ADD, r1<-r2+r3
[Cycle 100] Thread 1: PC=0x3456, inst=SUB, r4<-r5-r6
[Cycle 101] Resource contention: Both threads reading RF port A
[Cycle 102] Register bypass: T0 forwards to T1 (CHECK IF CORRECT)
```

---

## 🚨 POTENTIAL ISSUES TO WATCH FOR

### Issue 1: Cross-Thread Register Forwarding
**Symptom**: Thread 1 receives register value written by Thread 0
**Root Cause**: Bypass network not properly checking thread IDs
**Status**: Should be fixed in Phase 4 (BypassController.sv)
**Action**: Verify in Phase 5 with test case

### Issue 2: Shared Resource Conflicts
**Symptom**: Performance degradation worse than expected
**Root Cause**: Multiple threads competing for shared resources
**Status**: Expected and normal
**Action**: Measure contention, document in results

### Issue 3: Register File Port Contention
**Symptom**: Stalls due to RF read port unavailability
**Root Cause**: Both threads trying to read same register file port
**Status**: Expected with high thread count
**Action**: Monitor and report in metrics

### Issue 4: Incorrect Cache Behavior
**Symptom**: Wrong data values loaded
**Root Cause**: Cache not properly handling multi-threaded access
**Status**: Likely issue if data areas share cache lines
**Action**: Ensure threads have separate data regions initially

### Issue 5: Recovery Issues
**Symptom**: One thread's exception crashes other thread
**Root Cause**: Recovery not properly isolated per-thread
**Status**: Should be fixed if Phase 4 done correctly
**Action**: Test with exception-inducing instructions

---

## 📈 EXPECTED OUTCOMES

### Success Indicators ✅
1. Both threads make forward progress simultaneously
2. No cross-thread register value corruption
3. IPC with 2 threads: 0.85-1.0 (slight degradation from 0.985 is OK)
4. No deadlocks or system hangs
5. Proper thread isolation in recovery scenarios

### Performance Expectations
```
Single thread (Phase 4):  IPC = 0.985285
Two threads (Phase 5):    IPC ≈ 0.80-0.95 (due to contention)

Why lower IPC with 2 threads?
- Competing for shared execution units
- Cache conflicts
- Register file port conflicts
- Pipeline contention
(This is NORMAL and expected)
```

### Failure Indicators ❌
1. One thread doesn't execute (stuck)
2. Register values corrupted across threads
3. System crashes or hangs after N cycles
4. Assertions or warnings during multi-thread execution
5. IPC drops below 0.5 (indicates major issue)

---

## 📋 PHASE 5 CHECKLIST

### Pre-Phase 5 (Phase 4 completion)
- [ ] Phase 4 bugs fixed
- [ ] Baseline test: 0.985285, 4621 cycles
- [ ] All interface signals correct
- [ ] Code compiles with 0 warnings

### Phase 5 Start
- [ ] Create multi-thread test framework
- [ ] Verify commit stage threading
- [ ] Verify fetch stage threading
- [ ] Create independent execution test
- [ ] Create synchronized execution test
- [ ] Create load-store interaction test

### Phase 5 Execution
- [ ] Test 1: Independent execution
  - [ ] Compile cleanly
  - [ ] Both threads execute
  - [ ] Correct results
  - [ ] Document IPC

- [ ] Test 2: Synchronized execution
  - [ ] Threads synchronize properly
  - [ ] No deadlock
  - [ ] Correct ordering

- [ ] Test 3: Load-store interaction
  - [ ] Correct values loaded
  - [ ] Proper ordering
  - [ ] No memory corruption

### Phase 5 Completion
- [ ] All tests pass
- [ ] Performance metrics documented
- [ ] 2-thread baseline established
- [ ] Issues identified and documented
- [ ] Phase 5 completion report created

---

## 🎯 SUCCESS METRICS FOR PHASE 5

| Metric | Target | Importance |
|--------|--------|-----------|
| Both threads execute | YES | CRITICAL |
| No register corruption | YES | CRITICAL |
| No deadlocks | YES | CRITICAL |
| Baseline maintained (IPC > 0.5) | YES | HIGH |
| Per-thread isolation verified | YES | HIGH |
| 2-thread metrics measured | YES | MEDIUM |
| Debug info available | YES | MEDIUM |

---

## ⏱️ ESTIMATED PHASE 5 TIMELINE

| Task | Time | Dependencies |
|------|------|--------------|
| Pre-Phase 5 checklist | 15 min | Phase 4 complete |
| Multi-thread test framework | 2 hours | Phase 4 complete |
| Commit stage verification | 1 hour | Framework ready |
| Fetch stage verification | 30 min | Framework ready |
| 2-thread test cases | 1 hour | Framework ready |
| Performance monitoring | 1 hour | Test cases ready |
| Test execution & debugging | 1-2 hours | All tests created |
| Documentation | 1 hour | All tests passing |
| **TOTAL** | **7-8 hours** | **~1 full session** |

---

## 📞 CRITICAL DEPENDENCIES

### Phase 5 CANNOT Start Until
1. ✅ Phase 4 is 100% complete
2. ✅ Baseline test verified (0.985285, 4621)
3. ✅ All interface signals wired correctly
4. ✅ Code compiles with 0 warnings
5. ✅ No known bugs or issues

### Phase 5 Will REVEAL
1. Any remaining cross-thread interference issues
2. Performance characteristics of multi-threading
3. Need for Phase 6 improvements (cache, branch prediction, etc.)

---

## 🚀 PHASE 6+ PREVIEW

After Phase 5 completes, subsequent phases would focus on:

**Phase 6**: Thread-Aware Cache System
- Per-thread cache entries or partitioning
- Proper cache coherency for multi-thread
- Cross-thread cache interactions

**Phase 7**: Thread-Aware Branch Prediction
- Per-thread branch predictor state
- Separate prediction tables per thread
- Thread-aware training

**Phase 8**: Thread Scheduling & Prioritization
- Dynamic thread switching
- Priority-based scheduling
- Load balancing

---

## 📝 SUMMARY

Phase 5 will **prove the concept** of per-thread resource allocation by executing 2 real programs simultaneously. This is a critical validation step before optimizations (Phase 6+).

**Key Insight**: Phase 4 did all the hardware groundwork. Phase 5 is mostly about testing infrastructure and verification.

**Risk Level**: MEDIUM
- If Phase 4 done correctly → Phase 5 should work
- If issues found → they'll be in test framework or edge cases, not core logic

**Expected Outcome**: A 2-thread processor that demonstrates multi-threaded execution with proper thread isolation and measurable performance.

---

**Prepared By**: AI Code Assistant  
**Date**: November 24, 2025  
**Status**: PLANNING (Ready to execute when Phase 4 complete)
