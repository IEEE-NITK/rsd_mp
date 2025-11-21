# SMT Multi-Threading Test Guide

## Overview

This guide provides step-by-step instructions for testing the round-robin SMT implementation using the `TestSMT_MultiThread.sv` testbench.

---

## Test Environment Setup

### Prerequisites
```bash
cd /Users/kushal/rsd_mp/Processor/Src

# Verify CONF_THREAD_NUM is set to 2 in MicroArchConf.sv
grep "CONF_THREAD_NUM" MicroArchConf.sv
# Expected output: localparam CONF_THREAD_NUM = 2;
```

### Compilation

#### Using ModelSim/QuestaSim
```bash
# Compile SMT testbench
vsim -c -do "do Verification/compile_smt_test.do" 
```

#### Using Verilator
```bash
# Build with SMT testbench
make TESTBENCH=TestSMT_MultiThread
```

---

## Test 1: ThreadID Type System Verification

### Objective
Verify that ThreadID type is correctly defined and used throughout the design.

### Test Code
```verilog
// In TestSMT_MultiThread.sv, run verification at cycle 0:

// Check 1: ThreadID width
$display("THREAD_NUM = %d", THREAD_NUM);
$display("THREAD_NUM_BIT_WIDTH = %d", THREAD_NUM_BIT_WIDTH);
// Expected output for 2 threads:
// THREAD_NUM = 2
// THREAD_NUM_BIT_WIDTH = 1

// Check 2: Valid thread ID range
for (int t = 0; t < NUM_THREADS; t++) begin
    assert(t < (1 << THREAD_NUM_BIT_WIDTH)) 
        else $error("Thread %d out of range", t);
end
```

### Expected Results
- ThreadID width is 1 bit for 2 threads
- Valid thread IDs are 0 and 1
- All comparisons and arithmetic with ThreadID are correct

---

## Test 2: Round-Robin Fetch Thread Selection

### Objective
Verify that the fetch stage selects threads in round-robin order.

### Test Command
```bash
vsim TestSMT_MultiThread \
    -c \
    -do "run 1000; quit;" \
    -g MAX_TEST_CYCLES=1000
```

### Expected Output Pattern
```
[Cycle    0] PC: 0x00000000
[Cycle  100] PC: 0x00000100
[Cycle  200] PC: 0x00000200
...

Fetch Selection History:
  Thread 0 fetch selections: 500 (50.0%)
  Thread 1 fetch selections: 500 (50.0%)
```

### Verification Checklist
- [ ] Fetch selections alternate between Thread 0 and Thread 1
- [ ] Distribution is 50/50 for each thread (±10%)
- [ ] No thread is starved of fetch opportunities
- [ ] Round-robin pattern consistent across all cycles

### Script to Verify
```tcl
# In ModelSim/QuestaSim after simulation:
# Check NextPCStage.threadCounter and selectedTid signals
run -all

# Check threadCounter increments
add wave sim:main.main.core.npStage.threadCounter
add wave sim:main.main.core.npStage.port.selectedTid

# Verify round-robin pattern
examine sim:main.main.core.npStage.threadCounter @10000
# Should show: threadCounter = 10000 (incremented every cycle)

examine sim:main.main.core.npStage.port.selectedTid @10000
# Should alternate 0, 1, 0, 1, ...
```

---

## Test 3: ThreadID Propagation Through Pipeline

### Objective
Verify ThreadID flows correctly through all pipeline stages without loss or corruption.

### Test Implementation
The testbench periodically calls `VerifyThreadIDPropagation()`:

```verilog
// Monitors at every 100 cycles
if (cycle % 100 == 0 && cycle > 0) begin
    VerifyThreadIDPropagation();
end

// Verification checks:
// 1. Fetch Stage (nextStage[i].tid)
// 2. Decode Stage (nextStage[i].tid)
// 3. Rename Stage (nextStage[i].tid)
// 4. Dispatch Stage (Integer/Memory/FP entry tid)
```

### Expected Output
```
[✓] Thread ID propagation verified through all pipeline stages
```

### Failure Diagnosis
If ThreadID propagation fails:

1. **Check Fetch Stage**
```verilog
// In simulation waveform
add wave sim:main.main.core.ifStage.pipeReg[*].tid
add wave sim:main.main.core.ifStage.nextStage[*].tid
# Verify: nextStage[i].tid == pipeReg[i].tid
```

2. **Check Decode Stage**
```verilog
add wave sim:main.main.core.idStage.pipeReg[*].tid
add wave sim:main.main.core.idStage.nextStage[*].tid
# Verify ThreadID preserved
```

3. **Check Rename Stage**
```verilog
add wave sim:main.main.core.rnStage.pipeReg[*].tid
add wave sim:main.main.core.rnStage.nextStage[*].tid
# Verify ALEntry.tid assignment
```

---

## Test 4: Per-Thread Register Mapping (RMT)

### Objective
Verify register renaming is thread-aware with separate mappings per thread.

### Test Details

#### Check 1: RMT Addressing
```verilog
// Monitor RMT read addresses
add wave sim:main.main.core.renameLogic.rmt.rmtRA[*]
add wave sim:main.main.core.renameLogic.rmt.rmtRB[*]

// Thread 0 logical register 5 should map to different physical register
// than Thread 1 logical register 5

// Manual calculation:
// Thread 0, LogReg 5 → RMT[0][5] → PhyReg[X]
// Thread 1, LogReg 5 → RMT[1][5] → PhyReg[Y]
// Assertion: X != Y
```

#### Check 2: RMT Isolation
```verilog
// When Thread 0 commits a result to logical register 5:
// - Thread 0's RMT[0][5] updates
// - Thread 1's RMT[1][5] should NOT change

// Monitor in waveform:
add wave sim:main.main.core.renameLogic.rmt.regRMT.debugValue[0][5]
add wave sim:main.main.core.renameLogic.rmt.regRMT.debugValue[1][5]

// Verify these update independently
```

### Expected Results
- Each thread has independent logical-to-physical register mappings
- 32 logical registers × 2 threads = 64 RMT entries total
- Register allocation doesn't conflict between threads

---

## Test 5: Active List Thread Partitioning

### Objective
Verify Active List (ROB) is partitioned between threads without contention.

### Test Details

#### Check 1: AL Partitioning
```verilog
// Thread 0 uses first half of AL
// Thread 1 uses second half of AL

// Monitor heads and tails:
add wave sim:main.main.core.activeList.headPtr
add wave sim:main.main.core.activeList.tailPtr

// Verify Thread 0 entries are in range [0, AL_ENTRY_NUM/2)
// Verify Thread 1 entries are in range [AL_ENTRY_NUM/2, AL_ENTRY_NUM)
```

#### Check 2: Independent Commit
```verilog
// Each thread should commit from its partition

// Monitor commit signals per thread:
add wave sim:main.main.core.cmStage.commit[*]
add wave sim:main.main.core.cmStage.alReadData[*].tid

// For each committed instruction:
// Assert: if tid==0, then AL index < AL_ENTRY_NUM/2
// Assert: if tid==1, then AL index >= AL_ENTRY_NUM/2
```

### Expected Results
- No AL entry shared between threads
- Each thread independently advances through its partition
- No AL overflow for either thread (assuming balanced workload)

---

## Test 6: MSHR Thread Tracking in Cache

### Objective
Verify cache misses are properly tracked with thread information.

### Test Command
```bash
vsim TestSMT_MultiThread \
    -c \
    -do "run 1000; quit;" \
    -g MAX_TEST_CYCLES=1000 \
    2>&1 | grep "MSHR Monitor"
```

### Expected Output
```
[MSHR Monitor] MSHR[0] allocated by Thread 0 at cycle 100
[MSHR Monitor] MSHR[0] (Thread 0) completed at cycle 115 (latency: 15 cycles)
[MSHR Monitor] MSHR[1] allocated by Thread 1 at cycle 102
[MSHR Monitor] MSHR[1] (Thread 1) completed at cycle 118 (latency: 16 cycles)
...
```

### Verification Checklist
- [ ] Each MSHR entry records the thread that allocated it
- [ ] Thread ID persists from allocation to completion
- [ ] MSHR completion latencies are reasonable (10-50 cycles)
- [ ] No MSHR corruption across threads

### Advanced Check: Per-Thread Cache Flush
```verilog
// Simulate cache flush for Thread 0 only
// Verify: Only Thread 0 MSHRs are invalidated
// Verify: Thread 1 MSHRs continue in-flight

// In simulation:
// 1. Insert transaction: cacheFlushManagerIF.dcFlushTid = 0;
// 2. Monitor dcFlushTid in DCache
// 3. Verify only matching MSHR.tid entries are cleared
```

---

## Test 7: Branch Predictor Per-Thread State

### Objective
Verify branch prediction state is maintained independently per thread.

### Test Details

#### Check 1: BTB Thread Tagging
```verilog
// Monitor BTB entries
add wave sim:main.main.core.btb.btb.debugValue[*].tid

// Verify:
// - BTB entries have ThreadID field
// - BTB lookups match on both PC and ThreadID
// - No cross-thread BTB pollution
```

#### Check 2: Global History Separation
```verilog
// Monitor per-thread global history
add wave sim:main.main.core.brPred.gshare.regBrGlobalHistory[0]
add wave sim:main.main.core.brPred.gshare.regBrGlobalHistory[1]

// Verify:
// - Each thread maintains independent global history
// - History updates are thread-specific
// - Pattern is uncorrelated between threads
```

### Expected Results
- No cross-thread branch prediction pollution
- Each thread's predictor state is independent
- Similar branch prediction accuracy for both threads

---

## Test 8: Round-Robin Commit Arbitration

### Objective
Verify commit stage arbitrates between threads in round-robin fashion.

### Test Command
```bash
vsim TestSMT_MultiThread -c -do "run 2000; quit;" -g MAX_TEST_CYCLES=2000
```

### Expected Output
```
----- Per-Thread Statistics -----

Thread 0:
  Instructions Fetched:       1000
  Instructions Committed:      950
  ...
  Last Commit Cycle:          1998

Thread 1:
  Instructions Fetched:       1005
  Instructions Committed:      955
  ...
  Last Commit Cycle:          1997
```

### Verification Checklist
- [ ] Both threads make progress committing
- [ ] Commit distribution is relatively balanced (±10%)
- [ ] No thread is completely blocked
- [ ] Commit latency is reasonable

---

## Test 9: Memory System Thread Isolation

### Objective
Verify load/store units properly track thread information.

### Test Details

#### Check 1: Load Queue Thread Tracking
```verilog
// Monitor load queue entries
add wave sim:main.main.core.loadStoreUnit.loadQueue.debugValue[*].tid

// Verify:
// - Each load has correct thread ID
// - Load completion maintains thread context
```

#### Check 2: Store Queue Thread Tracking
```verilog
// Monitor store queue entries
add wave sim:main.main.core.loadStoreUnit.storeQueue.debugValue[*].tid

// Verify:
// - Each store has correct thread ID
// - Store-to-load forwarding respects thread ID
```

#### Check 3: Load-Store Hazard Detection
```verilog
// Store-load violation should respect thread

// Scenario:
// Thread 0: Store to address X
// Thread 0: Load from address X → Can forward
// Thread 1: Load from address X → Should NOT forward from Thread 0 store

// Monitor:
add wave sim:main.main.core.loadStoreUnit.loadQueue.debugValue[*].tid
add wave sim:main.main.core.loadStoreUnit.storeQueue.debugValue[*].tid
```

---

## Test 10: Execution Unit Thread Tagging

### Objective
Verify execution units properly tag results with thread information.

### Test Details

#### Check 1: Integer Result Tagging
```verilog
// Monitor integer writeback
add wave sim:main.main.core.intRwStage.nextStage[*].tid

// Verify:
// - Each writeback result has correct thread ID
// - Results are committed to correct thread's registers
```

#### Check 2: Memory Result Tagging
```verilog
// Monitor memory load completions
add wave sim:main.main.core.memRwStage.nextStage[*].tid

// Verify:
// - Load results carry correct thread ID
// - Results routed to correct thread's register file
```

---

## Test 11: Recovery and Exception Handling

### Objective
Verify exceptions and recovery are thread-specific.

### Test Scenario
Trigger a misspeculation in Thread 0 while Thread 1 is executing normally.

### Expected Behavior
```
Cycle 500: Thread 0 misspeculation detected
  → Thread 0 enters recovery phase
  → Thread 1 continues normal execution
Cycle 505: Thread 0 recovery completes
  → Both threads resume normal execution
  
Verification:
- Thread 0's pipeline is flushed
- Thread 1's in-flight instructions are NOT flushed
- No register state corruption
```

### Test Code
```verilog
// Monitor recovery state per thread
add wave sim:main.main.core.recoveryManager.regState[0]
add wave sim:main.main.core.recoveryManager.regState[1]

// When a branch mispredict occurs:
// Only the affected thread's state changes
```

---

## Test 12: CSR Access Isolation

### Objective
Verify each thread has independent CSR state.

### Test Details

#### Check 1: Per-Thread CSR Registers
```verilog
// Monitor CSR registers per thread
add wave sim:main.main.core.csrUnit.csrReg[0].mstatus
add wave sim:main.main.core.csrUnit.csrReg[1].mstatus

// Verify:
// - Each thread can read/write CSR independently
// - mstatus updates don't affect other thread's mstatus
```

#### Check 2: CSR Access Routing
```verilog
// Monitor CSR access
add wave sim:main.main.core.csrUnit.port.csrAccessTid

// Verify:
// - CSR reads return data for correct thread
// - CSR writes update correct thread's registers
```

---

## Performance Measurements

### Test 13: IPC Per Thread

### Objective
Measure instruction throughput for each thread.

### Expected Results
For balanced dual-thread workload:
- Thread 0 IPC: 1.5-2.0 instructions/cycle
- Thread 1 IPC: 1.5-2.0 instructions/cycle
- Combined: 3.0-4.0 instructions/cycle

For single-thread workload:
- Active thread IPC: should match single-thread baseline
- Inactive thread IPC: 0

### Test 13: Cache Miss Rate Per Thread

### Expected Results
```
Thread 0 I$ Misses: 50% of total
Thread 1 I$ Misses: 50% of total
Thread 0 D$ Misses: 50% of total
Thread 1 D$ Misses: 50% of total
```

(Within ±15% variance due to instruction sequence differences)

---

## Regression Testing

### Test 14: Single-Thread Regression

### Objective
Verify SMT modifications don't degrade single-thread performance.

### Test Command
```bash
# Modify MicroArchConf.sv:
# localparam CONF_THREAD_NUM = 1;

# Run baseline test
vsim TestSMT_MultiThread \
    -c \
    -do "run 1000; quit;" \
    -g TEST_CODE="Verification/TestCode/Fibonacci"
```

### Expected Results
- Single-thread IPC should match pre-SMT baseline (±5%)
- No performance regression
- All tests pass

### Comparison Metrics
```
CONF_THREAD_NUM=1 Baseline:
  Cycles: 1000
  Instructions Committed: 950
  IPC: 0.95

CONF_THREAD_NUM=2 Single-Thread Mode:
  Cycles: 1000
  Instructions Committed: 950
  IPC: 0.95
  
Regression: < 1%  ✓
```

---

## Error Detection and Debugging

### Common Issues

#### Issue 1: ThreadID Mismatch
```
[ThreadID Prop] Invalid thread ID 2 in Fetch Stage lane 0
```
**Cause**: ThreadID value out of range

**Debug**:
```verilog
// Check thread selection
add wave sim:main.main.core.npStage.threadCounter
add wave sim:main.main.core.npStage.port.selectedTid

// Verify: selectedTid is always 0 or 1
assert(selectedTid < THREAD_NUM)
```

#### Issue 2: Lost ThreadID in Pipeline
```
[ThreadID Prop] Invalid thread ID 15 in Decode Stage lane 0
```
**Cause**: ThreadID not propagated from previous stage

**Debug**:
```verilog
// Check intermediate connections
add wave sim:main.main.core.pdStage.nextStage[*].tid
add wave sim:main.main.core.idStage.pipeReg[*].tid

// Find where tid goes undefined
```

#### Issue 3: RMT Address Collision
```
Both threads accessing same RMT entry
```
**Debug**:
```verilog
// Monitor RMT addresses
add wave sim:main.main.core.renameLogic.rmt.rmtRA[*]

// Verify: GetBankedAddr function working correctly
// Thread 0 addresses should differ from Thread 1 addresses
```

---

## Automated Test Script

### Running All Tests
```bash
#!/bin/bash

echo "Running SMT Verification Tests..."

# Test 1: Compilation
echo "[Test 1] Compilation..."
make clean
make -j4
if [ $? -ne 0 ]; then
    echo "FAILED: Compilation"
    exit 1
fi

# Test 2: ThreadID verification
echo "[Test 2] ThreadID Verification..."
vsim -c -do "source Verification/run_smt_tests.do; quit;" 2>&1 | \
    grep -E "(PASSED|FAILED|ThreadID)"

# Test 3: Full simulation
echo "[Test 3] Full SMT Simulation..."
vsim TestSMT_MultiThread -c -do "run 5000; quit;" \
    -g MAX_TEST_CYCLES=5000 \
    -g TEST_CODE="Verification/TestCode/Fibonacci" \
    -g RSD_LOG_FILE="Verification/TestCode/Fibonacci/smt_kanata.log" \
    2>&1 | tee smt_test_log.txt

# Test 4: Parse results
echo "[Test 4] Parsing Results..."
grep -E "(Instructions|Cycles|IPC)" smt_test_log.txt

echo "All tests completed. Check smt_test_log.txt for details."
```

---

## Expected Test Results Summary

### Quick Check
```bash
# Run minimal test to verify basic functionality
vsim TestSMT_MultiThread -c -do "run 100; quit;" -g MAX_TEST_CYCLES=100

# Expected output:
# [Cycle   10] PC: 0x...
# [✓] Thread ID propagation verified
# [MSHR Monitor] MSHR[0] allocated by Thread 0
# ...
# ========== SMT Test Summary ==========
# Total Instructions Fetched:   50-100
# Total Instructions Committed: 40-90
```

### Full Test
```bash
vsim TestSMT_MultiThread -c -do "run -all; quit;" -g MAX_TEST_CYCLES=10000

# Check output files
cat Verification/TestCode/Fibonacci/smt_test_report.txt
# Should show:
# - Per-thread statistics
# - Fetch pattern analysis (50/50 split)
# - MSHR thread tracking
# - Overall performance metrics
```

---

## Conclusion

This test guide provides comprehensive verification of all SMT modifications. Run tests in order:

1. **Unit Tests** (1-5): Verify individual components
2. **Integration Tests** (6-10): Verify system interaction
3. **Performance Tests** (11-13): Measure throughput
4. **Regression Tests** (14): Verify no degradation

**All tests passing → SMT implementation is correct ✓**
