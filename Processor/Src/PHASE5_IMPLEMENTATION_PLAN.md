# Phase 5 Implementation Plan: Multi-Threaded Workload Testing

**Status**: PLANNING & INITIAL SETUP (Ready to execute after Phase 4)  
**Prerequisite**: Phase 4 complete with baseline verified (IPC 0.985285, 4621 cycles)  
**Estimated Duration**: 7-8 hours  
**Target**: Execute 2 threads simultaneously with performance measurement  

---

## 🎯 PHASE 5 OBJECTIVES

### Primary Goals
1. **Enable multi-threaded execution** - Load and run 2 independent programs
2. **Verify thread isolation** - Each thread operates completely independently
3. **Measure performance** - IPC and cycle count with 2 threads
4. **Establish 2-thread baseline** - Reference point for Phase 6 optimization
5. **Identify issues** - Cross-thread hazards, resource contention, bottlenecks

### Success Metrics
- ✅ Both threads load and execute simultaneously
- ✅ Each thread runs correct program (no cross-thread interference)
- ✅ System completes without crashes or deadlocks
- ✅ Performance measurable (per-thread IPC, cycle count)
- ✅ 2-thread baseline established

---

## 📋 PHASE 5 TASK BREAKDOWN

### Task 1: Create Multi-Threaded Test Directory (1 hour)

**Goal**: Set up directory structure for 2-thread test programs

**What to Create**:

```bash
mkdir -p /Users/kushal/rsd_mp/Processor/Src/Verification/TestCode/Asm/MultiThread
```

**Files to Create**:

1. `Verification/TestCode/Asm/MultiThread/README.md`
   - Explain multi-thread test structure
   - Memory layout for each thread
   - How to add new tests

2. `Verification/TestCode/Asm/MultiThread/MemoryLayout.txt`
   ```
   Thread 0 Code:     0x1000 - 0x1FFF (4 KB)
   Thread 0 Data:     0x2000 - 0x2FFF (4 KB)
   Thread 1 Code:     0x3000 - 0x3FFF (4 KB)
   Thread 1 Data:     0x4000 - 0x4FFF (4 KB)
   Shared Region:     0x5000 - 0x5FFF (4 KB, for synchronization)
   
   Thread IDs:
   - Thread 0: Identified by CSR or boot register
   - Thread 1: Identified by CSR or boot register
   ```

3. `Verification/TestCode/Asm/MultiThread/ThreadInit.s`
   ```systemverilog
   // Common initialization code for both threads
   // Gets called by each thread with different parameters
   
   // Thread 0 setup
   .section .text.thread0_init
   thread0_init:
       // Set up thread 0 state
       // Jump to thread 0 code
       j thread0_main
   
   // Thread 1 setup  
   .section .text.thread1_init
   thread1_init:
       // Set up thread 1 state
       // Jump to thread 1 code
       j thread1_main
   ```

**Deliverables**:
- [ ] Directory created
- [ ] Memory layout documented
- [ ] README created with usage guide
- [ ] Thread initialization template created

---

### Task 2: Test Framework Modification (2 hours)

**Goal**: Enable test framework to load and run 2-thread programs

**Files to Modify**:

#### A. Verification/TestMain.sv

**Current**: Loads single test program  
**Required**: Load 2 separate programs (one for each thread)

**Changes Needed**:

1. **Add thread 1 program loader** (currently only loads thread 0)

```systemverilog
// Current: 
// mem.putData(testCode + offset, data);

// New:
// Add separate code sections for each thread
initial begin
    // Load Thread 0 code (0x1000)
    string testCode0 = "Verification/TestCode/Asm/MultiThread/Thread0.bin";
    
    // Load Thread 1 code (0x3000)  
    string testCode1 = "Verification/TestCode/Asm/MultiThread/Thread1.bin";
    
    // Load Thread 0 data section (0x2000)
    string testData0 = "Verification/TestCode/Asm/MultiThread/Thread0Data.bin";
    
    // Load Thread 1 data section (0x4000)
    string testData1 = "Verification/TestCode/Asm/MultiThread/Thread1Data.bin";
end
```

2. **Add PC initialization for both threads**

```systemverilog
// Current: Single PC register
// New: Per-thread PC initialization

// Thread 0: PC = 0x1000
// Thread 1: PC = 0x3000
```

3. **Add thread ID assignment**

```systemverilog
// Mechanism 1: Boot-time CSR write
// Each thread reads its ID from CSR and branches accordingly

// Mechanism 2: Hardware thread ID
// Processor provides thread ID at boot via hardware pins/signals

// Mechanism 3: PC-based detection
// If PC in 0x1000-0x1FFF → Thread 0
// If PC in 0x3000-0x3FFF → Thread 1
```

#### B. Verification/Dumper.sv

**Current**: Single-threaded trace output  
**Required**: Per-thread trace with clear identification

**Changes Needed**:

```systemverilog
// Current format:
// Cycle 100: PC=0x1234, Inst=ADD, ...

// New format:
// [T0] Cycle 100: PC=0x1234, Inst=ADD, ...
// [T1] Cycle 100: PC=0x5678, Inst=SUB, ...

// Add per-thread filtering in output:
// Show which thread each instruction belongs to
// Show thread ID in all output lines
```

**Implementation**:
- Add thread ID to trace structure
- Modify output formatter to include `[Tx]` prefix
- Filter output by thread if needed for debugging

#### C. Test Configuration Files

**Modify**: `Verification/TestCode/Makefile` or `Makefile.inc`

**Add**:
```makefile
# Multi-thread target
test_multithread: thread0_code thread1_code
	# Assemble both programs
	# Place in correct memory locations
	# Run verilator simulation
```

**Deliverables**:
- [ ] TestMain.sv supports 2 program loading
- [ ] Both PC and thread ID initialization working
- [ ] Dumper.sv shows per-thread output with [Tx] prefix
- [ ] Build system can compile 2-thread tests
- [ ] Tests can run with RSD_ENABLE_SMT enabled

---

### Task 3: Create 2-Thread Test Programs (1.5 hours)

**Goal**: Create 3 sets of test programs to verify multi-threaded execution

#### Test Set 1: Independent Execution

**File**: `Verification/TestCode/Asm/MultiThread/IndependentExecution/`

**Thread 0 Program** (`thread0.s`):
```systemverilog
.section .text.thread0_start
.align 2
.globl thread0_start

thread0_start:
    // Simple arithmetic operations (non-conflicting with thread 1)
    // Use registers r1-r4
    
    li r1, 100
    li r2, 200
    add r3, r1, r2      // r3 = 300
    
    li r4, 10
    mul r5, r3, r4      // r5 = 3000
    
    // Store result to thread 0 data area (0x2000)
    la r6, 0x2000
    sw r5, 0(r6)
    
    // Done - loop forever
loop:
    j loop
```

**Thread 1 Program** (`thread1.s`):
```systemverilog
.section .text.thread1_start
.align 2
.globl thread1_start

thread1_start:
    // Different arithmetic operations (different registers)
    // Use registers r7-r10
    
    li r7, 50
    li r8, 150
    sub r9, r8, r7      // r9 = 100
    
    li r10, 5
    div r11, r9, r10    // r11 = 20
    
    // Store result to thread 1 data area (0x4000)
    la r12, 0x4000
    sw r11, 0(r12)
    
    // Done - loop forever
loop:
    j loop
```

**Expected Behavior**:
- Both threads execute simultaneously
- Thread 0 calculates and stores 3000 at 0x2000
- Thread 1 calculates and stores 20 at 0x4000
- No cross-thread register interference
- System completes in ~200-300 cycles (rough estimate)

**Verification**:
- [ ] Thread 0 result correct: 3000 at 0x2000
- [ ] Thread 1 result correct: 20 at 0x4000
- [ ] Both threads visible in trace
- [ ] No register value corruption

#### Test Set 2: Load-Store Interaction

**File**: `Verification/TestCode/Asm/MultiThread/LoadStoreInteraction/`

**Thread 0 Program** (`thread0.s`):
```systemverilog
.section .text.thread0_start

thread0_start:
    // Write to shared region (0x5000)
    li r1, 0x1234
    la r2, 0x5000
    sw r1, 0(r2)        // Store 0x1234 at 0x5000
    
    // Read from thread 1 data area
    la r3, 0x4000
    lw r4, 0(r3)        // Load from 0x4000 (thread 1's data)
    
    // Store what we read
    la r5, 0x2000
    sw r4, 4(r5)        // Store at 0x2004
    
    j loop
loop:
    j loop
```

**Thread 1 Program** (`thread1.s`):
```systemverilog
.section .text.thread1_start

thread1_start:
    // Write to shared region (0x5000)
    li r6, 0x5678
    la r7, 0x5000
    sw r6, 4(r7)        // Store 0x5678 at 0x5004
    
    // Read from thread 0 data area
    la r8, 0x2000
    lw r9, 0(r8)        // Load from 0x2000 (thread 0's data)
    
    // Store what we read
    la r10, 0x4000
    sw r9, 4(r10)       // Store at 0x4004
    
    j loop
loop:
    j loop
```

**Expected Behavior**:
- Threads exchange data through memory
- Proper load-store ordering maintained
- Values transferred correctly across threads
- Memory system handles multi-threaded access

**Verification**:
- [ ] Thread 0 reads value written by Thread 1
- [ ] Thread 1 reads value written by Thread 0
- [ ] Memory consistency verified
- [ ] Ordering preserved

#### Test Set 3: Synchronization Attempt

**File**: `Verification/TestCode/Asm/MultiThread/BasicSync/`

**Thread 0 Program** (`thread0.s`):
```systemverilog
.section .text.thread0_start

thread0_start:
    // Perform work
    li r1, 100
    li r2, 200
    add r3, r1, r2
    
    // Signal completion at 0x5000
    li r4, 1
    la r5, 0x5000
    sw r4, 0(r5)
    
    // Wait for thread 1 (poll 0x5001)
wait_loop:
    la r6, 0x5000
    lw r7, 4(r6)        // Load from 0x5004
    beq r7, 0, wait_loop // Loop while 0
    
    // Continue
    j done
done:
    j done
```

**Thread 1 Program** (`thread1.s`):
```systemverilog
.section .text.thread1_start

thread1_start:
    // Perform work
    li r8, 50
    li r9, 150
    sub r10, r9, r8
    
    // Signal completion at 0x5004
    li r11, 1
    la r12, 0x5000
    sw r11, 4(r12)
    
    // Wait for thread 0 (poll 0x5000)
wait_loop:
    la r13, 0x5000
    lw r14, 0(r13)      // Load from 0x5000
    beq r14, 0, wait_loop // Loop while 0
    
    // Continue
    j done
done:
    j done
```

**Expected Behavior**:
- Threads synchronize via shared memory
- Both reach synchronization point
- No deadlock occurs
- System progresses correctly

**Verification**:
- [ ] Both threads reach synchronization
- [ ] No deadlock detected
- [ ] Proper memory consistency
- [ ] Threads can proceed after sync

**Deliverables**:
- [ ] IndependentExecution test working
- [ ] LoadStoreInteraction test working
- [ ] BasicSync test working
- [ ] All tests produce correct results
- [ ] All 3 test programs compile cleanly

---

### Task 4: Verify Processor Threading (1 hour)

**Goal**: Check if processor modules properly handle per-thread state

#### 4A: Commit Stage Review

**File**: `Pipeline/CommitStage.sv`

**Check**:
```
Does it handle per-thread retirement?
  - [ ] Per-thread active list pointers
  - [ ] Per-thread register releases
  - [ ] Per-thread CSR updates
  
Does recovery work per-thread?
  - [ ] One thread can flush without affecting other
  - [ ] Recovery pointers thread-specific
  - [ ] CSR state preserved per-thread
```

**Expected**: Already correct from Phase 3-4, but verify

#### 4B: Fetch Stage Review

**File**: `Pipeline/FetchStage/NextPCStage.sv`

**Check**:
```
Does it maintain per-thread PC?
  - [ ] Separate PC register per thread
  - [ ] Branch misprediction per thread
  - [ ] Thread-specific next PC logic

Does it fetch from correct address for each thread?
  - [ ] Thread 0 fetches from 0x1000+
  - [ ] Thread 1 fetches from 0x3000+
```

**Expected**: May need updates if PC not per-thread

#### 4C: CSR Handling

**File**: `Privileged/CSR_Unit.sv`

**Check**:
```
Are CSRs properly virtualized?
  - [ ] Thread-specific CSRs (sepc, stval, etc.)
  - [ ] Thread-private registers
  - [ ] CSR access control per-thread
```

**Expected**: May need verification and potential updates

**Deliverables**:
- [ ] Commit stage verified or updated
- [ ] Fetch stage verified or updated
- [ ] CSR handling verified or updated
- [ ] Per-thread state separation confirmed
- [ ] Document any changes made

---

### Task 5: Performance Monitoring Infrastructure (1 hour)

**Goal**: Add per-thread performance measurement capability

#### 5A: Create Instrumentation Signals

**File**: `Core.sv` or `Controller.sv`

**Add**:
```systemverilog
// Per-thread instruction counter
logic [63:0] instructionCount[THREAD_NUM];

// Per-thread cycle counter  
logic [63:0] cycleCount[THREAD_NUM];

// Per-thread stall counter
logic [63:0] stallCount[THREAD_NUM];

// Resource utilization metrics
logic [7:0] registerFileConflicts;
logic [7:0] cacheConflicts;
logic [7:0] executionUnitConflicts;
```

#### 5B: Tracking Logic

Add combinational logic to track:
1. **Instruction Retirement**: Count per thread
2. **Cycle Counting**: Increment every cycle per thread
3. **Stall Cycles**: Count when thread doesn't progress
4. **Resource Conflicts**: When multiple threads compete

```systemverilog
always_ff @(posedge clk) begin
    for (int t = 0; t < THREAD_NUM; t++) begin
        // Track cycles
        cycleCount[t] <= cycleCount[t] + 1;
        
        // Track instructions retired
        if (commit[t]) begin
            instructionCount[t] <= instructionCount[t] + commitNum[t];
        end
        
        // Track stalls
        if (!progress[t]) begin
            stallCount[t] <= stallCount[t] + 1;
        end
    end
end
```

#### 5C: Output Formatting

**Modify**: `Verification/Dumper.sv`

**Add**:
```systemverilog
// At end of simulation, print per-thread metrics
final begin
    for (int t = 0; t < THREAD_NUM; t++) begin
        $display("[Thread %0d] Instructions: %0d, Cycles: %0d, Stalls: %0d",
                 t, instructionCount[t], cycleCount[t], stallCount[t]);
        $display("[Thread %0d] IPC: %.3f",
                 t, (real)instructionCount[t] / (real)cycleCount[t]);
    end
end
```

**Deliverables**:
- [ ] Per-thread counters added to Core/Controller
- [ ] Tracking logic implemented
- [ ] Output formatting created
- [ ] Performance metrics measurable at end of test

---

### Task 6: Run Tests & Measure Performance (2 hours)

**Goal**: Execute all 3 test programs and measure results

#### 6A: Independent Execution Test

```bash
cd /Users/kushal/rsd_mp/Processor/Src

# Compile test programs
make compile_multithread_independent

# Run simulation
make run_multithread_independent 2>&1 | tee results/independent_execution.txt

# Verify output
grep -A 20 "Thread 0" results/independent_execution.txt
grep -A 20 "Thread 1" results/independent_execution.txt
```

**Expected Output**:
```
[T0] Cycle 100: ADD r3, r1, r2 = 300
[T1] Cycle 100: SUB r9, r8, r7 = 100
...
[Thread 0] Instructions: 10, Cycles: 250, IPC: 0.04
[Thread 1] Instructions: 10, Cycles: 250, IPC: 0.04
Total IPC (both threads): ~0.08
```

**Success Criteria**:
- [ ] Both threads execute
- [ ] Values correct (Thread 0: 3000, Thread 1: 20)
- [ ] No crashes or hangs
- [ ] Performance metrics available

#### 6B: Load-Store Interaction Test

```bash
make run_multithread_loadstore 2>&1 | tee results/load_store_interaction.txt

# Verify data passed correctly
# Thread 0 should read Thread 1's value
# Thread 1 should read Thread 0's value
```

**Expected Behavior**:
- Thread 0 reads: 20 (from Thread 1)
- Thread 1 reads: 3000 (from Thread 0)
- Memory values consistent
- Load-store ordering preserved

**Success Criteria**:
- [ ] Values transferred correctly
- [ ] Memory consistency maintained
- [ ] Proper ordering preserved

#### 6C: Basic Synchronization Test

```bash
make run_multithread_sync 2>&1 | tee results/basic_sync.txt

# Verify both threads reach synchronization point
# Check for deadlock (program stuck)
```

**Expected Behavior**:
- Both threads reach sync point
- Both complete without hang
- System progresses correctly

**Success Criteria**:
- [ ] No deadlock detected
- [ ] Both threads proceed
- [ ] Synchronization working

**Deliverables**:
- [ ] All 3 tests run successfully
- [ ] Results captured to files
- [ ] No crashes or hangs
- [ ] Performance metrics collected

---

### Task 7: Results Analysis & Documentation (1 hour)

**Goal**: Analyze results and document findings

#### 7A: Performance Analysis

**Create**: `Phase5_Performance_Results.md`

**Contents**:
```
## 2-Thread Performance Baseline

### Test 1: Independent Execution
- Thread 0: X instructions, Y cycles, IPC = Z
- Thread 1: X instructions, Y cycles, IPC = Z
- Total system IPC: Z (both threads combined)
- Comparison to single-thread: baseline was 0.985285

### Test 2: Load-Store Interaction
- Data transfer: Successful
- Memory consistency: Maintained
- Performance impact: +/- X%

### Test 3: Basic Synchronization  
- Synchronization: Working
- Deadlock: None detected
- Performance impact: +/- X%

## Resource Contention Analysis

### Register File
- Port conflicts: X events
- Impact on performance: +/- Y%

### Cache System
- Conflicts: X events
- Impact on performance: +/- Y%

### Execution Units
- Conflicts: X events
- Impact on performance: +/- Y%

## Conclusions

1. Multi-threaded execution: WORKING ✅
2. Thread isolation: VERIFIED ✅
3. Memory consistency: MAINTAINED ✅
4. Performance: DOCUMENTED ✅
```

#### 7B: Issue Report

**Create**: `Phase5_Issues_Found.md`

**Document any**:
- Crashes or hangs
- Incorrect results
- Performance anomalies
- Unexpected behaviors
- Recommendations for Phase 6

**Example Format**:
```
## Issue #1: [Title]
Severity: HIGH/MEDIUM/LOW
Description: What happened
Expected: What should happen
Impact: On what functionality
Fix: What needs to be done
Status: For next phase
```

#### 7C: Phase 5 Completion Report

**Create**: `PHASE5_COMPLETION_REPORT.md`

**Contents**:
1. Objectives met/not met
2. Tests passed/failed
3. Performance baseline established
4. Issues discovered
5. Recommendations for Phase 6
6. Timeline summary

**Deliverables**:
- [ ] Performance results documented
- [ ] Issues documented
- [ ] Phase 5 completion report created
- [ ] Ready for Phase 6 planning

---

## 📊 PHASE 5 TIMELINE

| Task | Time | Dependency |
|------|------|-----------|
| 1. Test directory & framework | 1 hour | Phase 4 complete |
| 2. Test framework modification | 2 hours | Task 1 done |
| 3. Create test programs | 1.5 hours | Task 2 done |
| 4. Verify processor threading | 1 hour | Task 3 done |
| 5. Performance instrumentation | 1 hour | Task 4 done |
| 6. Run tests & measure | 2 hours | Task 5 done |
| 7. Analysis & documentation | 1 hour | Task 6 done |
| **TOTAL** | **9.5 hours** | - |

**Parallelizable**: Tasks 2-4 can overlap  
**Realistic**: 8-9 hours with debugging

---

## 🎯 SUCCESS CRITERIA FOR PHASE 5

Phase 5 is COMPLETE when ALL of these are met:

- [ ] Both threads load and execute simultaneously
- [ ] All 3 test programs run successfully
- [ ] Independent execution test passes
- [ ] Load-store interaction test passes
- [ ] Basic synchronization test passes
- [ ] Per-thread performance metrics collected
- [ ] 2-thread baseline established
- [ ] No crashes or deadlocks
- [ ] Results documented
- [ ] Issues identified and recorded
- [ ] Phase 5 completion report created

**Current Status**: 0/11 = 0% (Ready to begin after Phase 4)

---

## 🚀 EXPECTED OUTCOMES

### If All Tests Pass ✅
- Multi-threaded processor confirmed working
- 2-thread baseline established
- Foundation solid for Phase 6+
- Next: Optimize resource sharing

### If Issues Found ⚠️
- Document thoroughly
- Identify root causes
- Plan fixes for Phase 6
- Retest after fixes
- Next: Phase 6 optimization

### Critical Issues ❌
- Should not occur if Phase 4 correct
- If found: Escalate and address immediately
- May require Phase 4 rework

---

## 📋 NEXT PHASES (PREVIEW)

**Phase 6**: Thread-Aware Cache System
- Per-thread cache optimization
- Cache coherency verification
- Performance improvement

**Phase 7**: Thread-Aware Branch Prediction
- Per-thread predictor state
- Separate prediction tables
- Better prediction accuracy

**Phase 8**: Dynamic Thread Scheduling
- Prioritization logic
- Load balancing
- Context switching

---

## 📞 RESOURCES & REFERENCE

**Key Files**:
- `PHASE5_REQUIREMENTS_ANALYSIS.md` - Detailed planning
- `PHASE4_COMPLETION_SUMMARY.md` - Phase 4 recap
- Test case templates in `Verification/TestCode/Asm/MultiThread/`

**Commands**:
```bash
# Compile multi-thread tests
make compile_multithread

# Run independent execution test
make run_multithread_independent

# Run all Phase 5 tests
make test_phase5

# View results
cat results/phase5_results.txt
```

---

## ✅ PHASE 5 READY CHECKLIST

Before starting Phase 5, verify:
- [ ] Phase 4 complete (baseline verified: 0.985285, 4621)
- [ ] No active compilation issues
- [ ] Test framework buildable
- [ ] Development environment stable
- [ ] Time available for full session (8-9 hours)

---

**Status**: READY FOR PHASE 5 AFTER PHASE 4  
**Confidence**: HIGH (all requirements identified, tasks well-scoped)  
**Risk**: MEDIUM (depends on Phase 4 correct implementation)  
**Next Action**: Complete Phase 4, then begin Phase 5  

**Phase 5 will prove the multi-threaded processor works! 🚀**
