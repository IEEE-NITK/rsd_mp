# TestSMT_MultiThread.sv - Quick Reference

## Overview
Comprehensive testbench for verifying all SMT multi-threading modifications in the round-robin commit.

## File Location
`/Users/kushal/rsd_mp/Processor/Src/Verification/TestSMT_MultiThread.sv`

---

## Running the Testbench

### Basic Run
```bash
cd /Users/kushal/rsd_mp/Processor/Src

# Compile and simulate (1000 cycles)
vsim TestSMT_MultiThread -c -do "run 1000; quit;" -g MAX_TEST_CYCLES=1000
```

### With Custom Parameters
```bash
vsim TestSMT_MultiThread -c \
    -do "run -all; quit;" \
    -g MAX_TEST_CYCLES=5000 \
    -g TEST_CODE="Verification/TestCode/Fibonacci" \
    -g RSD_LOG_FILE="output_kanata.log" \
    -g REG_CSV_FILE="output_registers.csv" \
    -g SHOW_SERIAL_OUT=0
```

### With Waveform Capture
```bash
vsim TestSMT_MultiThread -c \
    -do "run -all; quit;" \
    -g WAVE_LOG_FILE="smt_waveform.vcd"
```

---

## Monitoring Points

### 1. ThreadID Propagation
```verilog
// Add to waveform
add wave sim:main.main.core.ifStage.nextStage[*].tid
add wave sim:main.main.core.idStage.nextStage[*].tid
add wave sim:main.main.core.rnStage.nextStage[*].tid

// Expected: 0 or 1 in each stage
```

### 2. Thread Selection (Round-Robin)
```verilog
add wave sim:main.main.core.npStage.threadCounter
add wave sim:main.main.core.npStage.port.selectedTid
add wave sim:main.main.core.ifStage.port.fetchThreadId[*]

// Expected: selectedTid alternates 0→1→0→1...
```

### 3. MSHR Thread Tracking
```verilog
add wave sim:main.main.core.dCache.mshr[*].tid
add wave sim:main.main.core.dCache.mshr[*].valid

// Expected: tid == 0 or 1 for allocated MSHRs
```

### 4. Active List Partitioning
```verilog
add wave sim:main.main.core.activeList.headPtr
add wave sim:main.main.core.activeList.tailPtr
add wave sim:main.main.core.activeList.activeList.debugValue[*].tid

// Expected: Thread 0 < AL_ENTRY_NUM/2, Thread 1 >= AL_ENTRY_NUM/2
```

### 5. Register Mapping (RMT)
```verilog
add wave sim:main.main.core.renameLogic.rmt.regRMT.debugValue[0][*]
add wave sim:main.main.core.renameLogic.rmt.regRMT.debugValue[1][*]

// Expected: Different physical registers for Thread 0 vs Thread 1
```

### 6. Commit Thread Tracking
```verilog
add wave sim:main.main.core.cmStage.commit[*]
add wave sim:main.main.core.cmStage.alReadData[*].tid

// Expected: Both threads committing with equal frequency
```

---

## Verification Functions

### Core Monitoring Tasks

#### MonitorFetchStageThreadSelection()
Tracks round-robin thread selection at fetch stage.

**Outputs**:
- `fetchSelectionHistory[]` - Record of all fetch selections
- `threadStats[].instructionsFetched` - Count per thread
- `threadStats[].lastFetchedCycle` - Last fetch cycle per thread

**Expected**:
```
Fetch selections recorded: 500+
Thread 0 selections: ~50%
Thread 1 selections: ~50%
```

#### MonitorMSHRThreadTracking()
Tracks cache misses by thread.

**Outputs**:
- `mshrTracking[]` - MSHR allocation/completion records
- Console output: `[MSHR Monitor]` messages

**Expected**:
```
[MSHR Monitor] MSHR[0] allocated by Thread 0 at cycle 100
[MSHR Monitor] MSHR[0] (Thread 0) completed at cycle 115 (latency: 15 cycles)
```

#### MonitorCommitStage()
Counts committed instructions per thread.

**Outputs**:
- `threadStats[].instructionsCommitted` - Per-thread commit count
- `threadStats[].lastCommittedCycle` - Last commit cycle per thread

#### VerifyThreadIDPropagation()
Validates ThreadID flows through all pipeline stages.

**Outputs**:
- Console: `[✓] Thread ID propagation verified` or `[✗] Thread ID propagation FAILED`
- Warnings for any invalid thread IDs

**Runs**: Every 100 cycles automatically

#### VerifyRoundRobinSelection()
Analyzes fetch selection history for round-robin pattern.

**Outputs**:
```
[✓] Round-robin thread selection verified across 500 selections
  Thread 0: 250 fetch selections (50.0%)
  Thread 1: 250 fetch selections (50.0%)
```

#### GenerateTestReport()
Creates comprehensive test report file.

**Output File**: `{TEST_CODE}/smt_test_report.txt`

**Contents**:
```
=================================================
SMT Multi-Threading Test Report
=================================================

Test Duration: 1000 cycles
Number of Threads: 2
Number of MSHR Entries: 8

----- Per-Thread Statistics -----

Thread 0:
  Instructions Fetched:       1000
  Instructions Committed:      950
  Cache Load Misses:           150
  ...

Thread 1:
  Instructions Fetched:        950
  Instructions Committed:      925
  ...

----- MSHR Thread Tracking -----
Thread 0 MSHR allocations: 75
Thread 1 MSHR allocations: 73
```

---

## Statistics Tracked

### Per-Thread Metrics (ThreadStatistics struct)
```verilog
struct {
    integer instructionsFetched;      // Total fetched
    integer instructionsIssued;        // Total issued to schedulers
    integer instructionsExecuted;      // Total executed
    integer instructionsCommitted;     // Total committed
    integer cacheLoadMisses;           // D$ load misses
    integer cacheStoreMisses;          // D$ store misses
    integer branchPredictionMisses;    // Branch misp count
    logic lastFetchedThread;           // Last thread fetched
    integer lastFetchedCycle;          // When last fetched
    integer lastCommittedCycle;        // When last committed
} threadStats[NUM_THREADS];
```

### Overall Counters
```verilog
numCommittedRISCV_Op      // Total RISC-V instructions
numCommittedMicroOp       // Total micro-ops
cycle                     // Current simulation cycle
fetchSelectionHistoryIdx  // Fetch selections recorded
```

### MSHR Tracking (MSHRTrackingEntry struct)
```verilog
struct {
    logic valid;                       // Entry allocated
    ThreadID tid;                      // Allocating thread
    integer allocationCycle;           // When allocated
    integer completionCycle;           // When completed
    logic completed;                   // Completion status
} mshrTracking[MSHR_NUM];
```

---

## Expected Output Format

### Console Output Example
```
========== SMT Multi-Threading Test Starting ==========
Number of Threads: 2
Max Test Cycles: 1000
========================================================

[Cycle    100] PC: 0x00000100
[Cycle    200] PC: 0x00000200
[Cycle    300] PC: 0x00000300

[MSHR Monitor] MSHR[0] allocated by Thread 0 at cycle 345
[MSHR Monitor] MSHR[0] (Thread 0) completed at cycle 360 (latency: 15 cycles)

[✓] Thread ID propagation verified through all pipeline stages

[MSHR Monitor] MSHR[1] allocated by Thread 1 at cycle 350
...

[✓] Round-robin thread selection verified across 500 selections
  Thread 0 fetch selections: 250 (50.0%)
  Thread 1 fetch selections: 250 (50.0%)

========== SMT Test Summary ==========
Total Instructions Fetched:   1000
Total Instructions Committed: 950
Test Report written to: Verification/TestCode/Fibonacci/smt_test_report.txt

========== Final Statistics ==========
Num of I$ misses: 50
Num of D$ load misses: 150
Num of D$ store misses: 25
Num of memory dependency prediction misses: 10
Num of branch prediction misses: 20
Num of committed RISC-V-ops: 900
Num of committed micro-ops: 950
IPC (RISC-V instruction): 0.90
IPC (micro-op): 0.95
Elapsed cycles: 1000
========================================
```

---

## Report File Format

### File Location
```
{TEST_CODE}/smt_test_report.txt
```

### Example Report
```
=================================================
SMT Multi-Threading Test Report
=================================================

Test Duration: 1000 cycles
Number of Threads: 2
Number of MSHR Entries: 8

----- Per-Thread Statistics -----

Thread 0:
  Instructions Fetched:        500
  Instructions Committed:      475
  Cache Load Misses:            75
  Cache Store Misses:           12
  Branch Pred Misses:           10
  Last Fetch Cycle:            999
  Last Commit Cycle:           998

Thread 1:
  Instructions Fetched:        500
  Instructions Committed:      475
  Cache Load Misses:            75
  Cache Store Misses:           12
  Branch Pred Misses:            9
  Last Fetch Cycle:            998
  Last Commit Cycle:           997

----- Overall Statistics -----
Total Instructions Fetched:   1000
Total Instructions Committed: 950
I$ Misses:                     25
D$ Load Misses:               150
D$ Store Misses:               24
Branch Pred Misses:            19
Memory Dep Pred Misses:        15

----- Fetch Pattern Analysis -----
Total Fetch Selections Recorded: 500
  Thread 0 fetch selections: 250 (50.0%)
  Thread 1 fetch selections: 250 (50.0%)

----- MSHR Thread Tracking -----
Thread 0 MSHR allocations: 75
Thread 1 MSHR allocations: 75

=================================================
Report Generated at Simulation End
=================================================
```

---

## Debugging Tips

### Issue: ThreadID not propagating
```
[ThreadID Prop] Invalid thread ID 2 in Fetch Stage lane 0

Solution:
1. Check NextPCStage.threadCounter increments
2. Verify: currentThread = threadCounter % THREAD_NUM
3. Check port.selectedTid assignment
4. Verify FetchStage assigns: nextStage[i].tid = pipeReg[i].tid
```

### Issue: MSHR not tracking thread
```
[MSHR Monitor] MSHR[0] allocated by Thread X at cycle Y
[MSHR Monitor] MSHR[0] (Thread ?) completed at cycle Z

Solution:
1. Check DCache.portInitMSHR_Tid signal
2. Verify MSHR initialization: nextMSHR[i].tid = port.initMSHR_Tid[i]
3. Check LoadStoreUnit outputs dcReadTid, dcWriteTid
```

### Issue: Unequal fetch distribution
```
Thread 0 fetch selections: 400 (66.7%)
Thread 1 fetch selections: 200 (33.3%)

Solution:
1. Check if one thread is stalling
2. Verify threadCounter increments during stalls
3. Check if recovery is affecting one thread
```

### Issue: Thread ID corruption in pipeline
```
Add wave signals for all tid fields in register path
Trace backwards from error point to find where tid is lost

add wave sim:main.main.core.*.pipeReg[*].tid
add wave sim:main.main.core.*.nextStage[*].tid
```

---

## Performance Analysis

### Ideal Results (Balanced Load)
```
Thread 0: 1.5-2.0 IPC
Thread 1: 1.5-2.0 IPC
Fetch Distribution: 50% ± 10%
MSHR Distribution: 50% ± 10%
Commit Distribution: 50% ± 10%
```

### Regression Check
```
Single-thread IPC (with CONF_THREAD_NUM=2 but one thread running):
  Should be ≤ 5% slower than CONF_THREAD_NUM=1 baseline
```

---

## Quick Verification Checklist

- [ ] ThreadID type defined (BasicTypes.sv, THREAD_NUM_BIT_WIDTH=1)
- [ ] NextPCStage round-robin works (selectedTid alternates 0→1→0→1)
- [ ] ThreadID propagates through all stages (Fetch→Decode→Rename→Execute)
- [ ] RMT is per-thread (Thread 0 registers ≠ Thread 1 registers)
- [ ] Active List partitioned (Thread 0 < AL_ENTRY_NUM/2, Thread 1 ≥)
- [ ] MSHR tracks thread (mshr[i].tid captured and maintained)
- [ ] BTB per-thread (branch history independent)
- [ ] Commit is per-thread (both threads making progress)
- [ ] Cache flush is selective (dcFlushTid controls which thread)
- [ ] No performance regression (single-thread mode ≤ 5% slower)

---

## Command Line Options

### MAX_TEST_CYCLES
Default: 100
Range: 10-1000000
Example: `-g MAX_TEST_CYCLES=5000`

### TEST_CODE
Default: "Verification/TestCode/Fibonacci"
Example: `-g TEST_CODE="Verification/TestCode/factorial"`

### SHOW_SERIAL_OUT
Default: 0 (minimal output)
Options: 0 or 1
Example: `-g SHOW_SERIAL_OUT=1`

### ENABLE_PC_GOAL
Default: 1 (stop at PC_GOAL)
Options: 0 or 1
Example: `-g ENABLE_PC_GOAL=0`

### RSD_LOG_FILE
Default: none (no Kanata log)
Example: `-g RSD_LOG_FILE="output.log"`

### REG_CSV_FILE
Default: none (no register CSV)
Example: `-g REG_CSV_FILE="registers.csv"`

### WAVE_LOG_FILE
Default: none (no waveform)
Example: `-g WAVE_LOG_FILE="waves.vcd"`

---

## Integration with CI/CD

### Run in Continuous Integration
```bash
#!/bin/bash
set -e

# Compile
make clean && make -j4

# Run SMT tests
vsim TestSMT_MultiThread -c -do "run -all; quit;" \
    -g MAX_TEST_CYCLES=5000 \
    -g TEST_CODE="Verification/TestCode/Fibonacci" \
    -g RSD_LOG_FILE="ci_kanata.log"

# Check results
if grep -q "\[✓\]" smt_test_log.txt; then
    echo "SMT Verification: PASSED"
    exit 0
else
    echo "SMT Verification: FAILED"
    exit 1
fi
```

---

## References

- **SMT_MODIFICATIONS_SUMMARY.md** - Complete list of all modifications
- **SMT_TEST_GUIDE.md** - Detailed test procedures
- **SMT_IMPLEMENTATION_PROGRESS.md** - Implementation status
- **CACHE_SMT_README.md** - Cache SMT details
- **Core.sv** - Main processor core
- **Main_Zynq.sv** - Top-level wrapper
- **TestMain.sv** - Original single-thread testbench (reference)
