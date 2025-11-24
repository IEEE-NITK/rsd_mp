# Phase 5 Quick Start Guide

**Objective**: Run 2 threads simultaneously and measure performance  
**Duration**: 8-9 hours  
**Prerequisite**: Phase 4 complete with verified baseline  

---

## 🚀 THE 30-SECOND VERSION

After Phase 4 is done:

1. Create test directory: `mkdir Verification/TestCode/Asm/MultiThread`
2. Create 3 test programs (Independent, LoadStore, Sync)
3. Modify TestMain.sv to load 2 programs
4. Add per-thread performance counters
5. Run tests and measure IPC with 2 threads
6. Document results

**Expected Result**: 2-thread baseline IPC = 0.85-0.95 (slightly lower than 0.985 due to contention)

---

## 📋 QUICK TASK LIST

- [ ] **Task 1**: Create MultiThread directory and setup (1 hour)
- [ ] **Task 2**: Modify test framework (2 hours)
- [ ] **Task 3**: Create 3 test programs (1.5 hours)
- [ ] **Task 4**: Verify processor threading (1 hour)
- [ ] **Task 5**: Add performance instrumentation (1 hour)
- [ ] **Task 6**: Run tests and collect results (2 hours)
- [ ] **Task 7**: Document findings (1 hour)

**Total**: 9.5 hours (realistic: 8-9 hours with overlapping tasks)

---

## 🔧 KEY MODIFICATIONS NEEDED

### 1. Test Framework (TestMain.sv)

**Add**: Load Thread 0 and Thread 1 code at different addresses
```systemverilog
// Load Thread 0: 0x1000
// Load Thread 1: 0x3000
```

### 2. Performance Tracking

**Add**: Per-thread instruction and cycle counters
```systemverilog
logic [63:0] instructionCount[THREAD_NUM];
logic [63:0] cycleCount[THREAD_NUM];
```

### 3. Output Formatting

**Add**: [T0] and [T1] prefixes to trace output for each thread

---

## 📝 TEST PROGRAMS NEEDED

### Test 1: Independent Execution
- Thread 0: Arithmetic only (no memory interaction)
- Thread 1: Different arithmetic
- Expected: Both complete, values correct
- Time: ~10 minutes to create

### Test 2: Load-Store Interaction
- Thread 0: Write to shared memory, read from Thread 1
- Thread 1: Write to shared memory, read from Thread 0
- Expected: Correct data transfer
- Time: ~10 minutes to create

### Test 3: Basic Synchronization
- Thread 0: Do work, set flag, wait for Thread 1 flag
- Thread 1: Do work, set flag, wait for Thread 0 flag
- Expected: Both reach sync point without deadlock
- Time: ~5 minutes to create

---

## ⚡ QUICK EXECUTION PLAN

### Phase 5 Session Timeline

**Hour 1: Setup**
```
0:00 - 0:15  Create directory structure
0:15 - 0:45  Read PHASE5_IMPLEMENTATION_PLAN.md Task 1 & 2
0:45 - 1:00  Start TestMain.sv modifications
```

**Hours 2-3: Framework & Tests**
```
1:00 - 2:00  Complete TestMain.sv modifications (Task 2)
2:00 - 3:00  Create 3 test programs (Task 3)
3:00 - 3:30  Compile tests and verify they build
```

**Hours 4-5: Verification**
```
3:30 - 4:15  Verify processor threading (Task 4)
4:15 - 5:00  Add performance instrumentation (Task 5)
```

**Hours 6-8: Testing**
```
5:00 - 6:00  Run independent execution test
6:00 - 7:00  Run load-store and sync tests
7:00 - 8:00  Collect metrics, debug any issues
```

**Hour 9: Documentation**
```
8:00 - 9:00  Document results and findings
```

---

## 🎯 CRITICAL SUCCESS FACTORS

✅ **MUST HAVE**:
1. Both threads load into memory at different addresses
2. Both threads execute simultaneously (visible in trace)
3. Each thread runs correct program (no corruption)
4. System doesn't crash or deadlock
5. Performance metrics measurable

❌ **MUST NOT HAVE**:
1. Cross-thread register value leakage
2. Cross-thread memory corruption
3. System crashes or hangs
4. Deadlocks between threads
5. Compilation errors

---

## 📊 EXPECTED PERFORMANCE

**Single-thread baseline** (Phase 4): IPC = 0.985285

**2-thread expected**:
- Best case: IPC = 0.95-1.0 (minor contention)
- Expected: IPC = 0.85-0.95 (moderate contention)
- Worst case: IPC = 0.70-0.85 (significant contention)

**Why lower with 2 threads?**
- Competing for shared execution units
- Cache conflicts
- Register file port contention
- This is NORMAL and expected

---

## 🐛 DEBUGGING QUICK REFERENCE

| Problem | Cause | Fix |
|---------|-------|-----|
| Only Thread 0 executes | Thread 1 code not loaded | Check TestMain.sv Task 2 |
| Wrong values calculated | Cross-thread register interference | Verify Phase 4 bypass logic |
| Deadlock/hang | Synchronization issue | Check test logic, add timeouts |
| IPC much lower than expected | Register file contention | Document and move to Phase 6 |
| Crash at specific cycle | Memory access issue | Check memory layout in test |

---

## 📈 RESULTS TO COLLECT

**For Each Test**:
- [ ] Did both threads execute?
- [ ] Were results correct?
- [ ] How many cycles did it take?
- [ ] What was the per-thread IPC?
- [ ] Were there resource conflicts?

**System Total**:
- [ ] 2-thread baseline IPC established
- [ ] Per-thread isolation verified
- [ ] Performance degradation measured
- [ ] Issues identified for Phase 6

---

## 🚀 COMMANDS TO KNOW

```bash
# Create test directory
mkdir -p Verification/TestCode/Asm/MultiThread

# Compile Phase 5 tests
make compile_multithread

# Run specific test
make run_multithread_independent
make run_multithread_loadstore
make run_multithread_sync

# View results
cat results/phase5_results.txt

# Check for crashes/hangs
make run_multithread 2>&1 | grep -i "error\|crash\|fail"
```

---

## 💡 KEY INSIGHTS

**What You're Testing**:
1. Can the processor execute 2 programs simultaneously?
2. Does each thread operate independently?
3. Can threads interact through memory correctly?
4. What's the performance penalty of multi-threading?

**What You're NOT Testing Yet** (Phase 6+):
- Cache coherency for multi-threaded workloads
- Branch prediction with multiple threads
- Dynamic thread scheduling
- Thread priority/fairness

---

## ✅ GO/NO-GO DECISION POINT

**Before starting Phase 5, verify**:
- [ ] Phase 4 baseline: 0.985285, 4621 cycles ✅
- [ ] Compilation successful: 0 errors, 0 warnings ✅
- [ ] All Phase 4 bugs fixed ✅
- [ ] RSD_ENABLE_SMT properly enabled ✅
- [ ] Test framework builds successfully ✅

**If ALL above ✅**: PROCEED TO PHASE 5  
**If ANY ❌**: Return to Phase 4, fix issues first

---

## 🎓 LEARNING OUTCOMES

After Phase 5, you will understand:
1. How multi-threaded processors execute code
2. How thread isolation is maintained
3. How shared resources cause contention
4. What bottlenecks exist in the current design
5. What optimizations are needed (Phase 6+)

---

## 📞 REFERENCE DOCUMENTS

- `PHASE5_IMPLEMENTATION_PLAN.md` - Detailed task breakdown (read before starting)
- `PHASE4_COMPLETION_SUMMARY.md` - Phase 4 recap
- `PHASE5_REQUIREMENTS_ANALYSIS.md` - Why Phase 5 matters

---

## 🏁 PHASE 5 COMPLETE WHEN

- [x] 2 threads load and execute simultaneously
- [x] All 3 test programs pass
- [x] Per-thread performance measured
- [x] Results documented
- [x] Issues identified
- [x] Phase 5 report created

**Expected Outcome**: A functioning 2-thread processor with performance baseline established

**Next**: Phase 6 - Thread-Aware Cache Optimization

---

**Status**: READY TO BEGIN (after Phase 4 complete)  
**Confidence**: HIGH  
**Risk**: MEDIUM (depends on Phase 4 quality)

**Let's build a multi-threaded processor! 🚀**
