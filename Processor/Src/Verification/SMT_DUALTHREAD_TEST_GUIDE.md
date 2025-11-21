# SMT Dual-Thread Round-Robin Test Guide

## Overview

This guide provides instructions for running the `TestSMT_DualThreadRoundRobin.sv` testbench, which specifically verifies:

1. **Round-robin fetch selection** between two threads
2. **Correct PC initialization** for each thread
3. **ThreadID propagation** with corresponding PCs
4. **Per-thread instruction execution** from different memory locations

---

## Test Setup

### Files Created

1. **Testbench**: `TestSMT_DualThreadRoundRobin.sv`
   - Specialized for dual-thread round-robin verification
   - Monitors fetch stage thread selection
   - Verifies PC consistency per thread
   - Generates detailed round-robin report

2. **Test Code (Hex)**: `Verification/TestCode/SMT_DualThread/code.hex`
   - Simple RISC-V instructions for both threads
   - Thread 0 code at 0x00000000 (ROM)
   - Thread 1 code at 0x80000000 (RAM)
   - No external dependencies needed

3. **Report Output**: `Verification/TestCode/SMT_DualThread/round_robin_report.txt`
   - Detailed analysis of fetch pattern
   - PC progression verification
   - Round-robin accuracy metrics

---

## Quick Start

### 1. Compile

```bash
cd /Users/kushal/rsd_mp/Processor/Src

# Compile testbench
vsim -c -compile TestSMT_DualThreadRoundRobin.sv
```

### 2. Run Basic Test (500 cycles)

```bash
vsim TestSMT_DualThreadRoundRobin -c \
    -do "run 500; quit;" \
    -g MAX_TEST_CYCLES=500
```

### 3. Check Results

```bash
# View console output
cat smt_test_output.log

# View detailed report
cat Verification/TestCode/SMT_DualThread/round_robin_report.txt
```

---

## Thread Configuration

### Thread 0 (ROM)
- **Start PC**: 0x00000000
- **Memory Range**: 0x00000000 - 0x000003FF (1KB)
- **Code**:
  - Load immediate into x1 (value 10)
  - Add x1 + x1 → x2
  - Add immediate to x2 → x3
  - Store x3 to memory
  - Loop back

### Thread 1 (RAM)
- **Start PC**: 0x80000000
- **Memory Range**: 0x80000000 - 0x800003FF (1KB)
- **Code**:
  - Load immediate into x10 (value 42)
  - Add x10 + x10 → x11
  - Add immediate to x11 → x12
  - Store x12 to memory
  - Loop back

---

## Test Execution Sequence

### Expected Behavior

```
Cycle 0:  Thread 0 selected → Fetch from PC 0x00000000
Cycle 1:  Thread 1 selected → Fetch from PC 0x80000000
Cycle 2:  Thread 0 selected → Fetch from PC 0x00000004 (next instruction)
Cycle 3:  Thread 1 selected → Fetch from PC 0x80000004 (next instruction)
Cycle 4:  Thread 0 selected → Fetch from PC 0x00000008
Cycle 5:  Thread 1 selected → Fetch from PC 0x80000008
...
```

### Key Verifications

1. **Round-Robin Pattern**
   ```
   Cycles 0-1: Thread 0 → Thread 1
   Cycles 2-3: Thread 0 → Thread 1
   Cycles 4-5: Thread 0 → Thread 1
   ```
   ✓ Pattern should repeat consistently

2. **PC Progression (Thread 0)**
   ```
   Cycle 0: PC = 0x00000000
   Cycle 2: PC = 0x00000004
   Cycle 4: PC = 0x00000008
   ...
   ```
   ✓ PC should increment by 4 bytes per two cycles (thread has every other cycle)

3. **PC Progression (Thread 1)**
   ```
   Cycle 1: PC = 0x80000000
   Cycle 3: PC = 0x80000004
   Cycle 5: PC = 0x80000008
   ...
   ```
   ✓ PC should increment similarly, with thread 1 offset

4. **ThreadID Matching**
   ```
   If selectedTid == 0: PC should be in range [0x00000000, 0x80000000)
   If selectedTid == 1: PC should be in range [0x80000000, ...]
   ```
   ✓ PC should match the selected thread

---

## Running Different Test Variants

### Extended Test (1000 cycles)
```bash
vsim TestSMT_DualThreadRoundRobin -c \
    -do "run 1000; quit;" \
    -g MAX_TEST_CYCLES=1000
```

### With Waveform Capture
```bash
vsim TestSMT_DualThreadRoundRobin -c \
    -do "run -all; quit;" \
    -g WAVE_LOG_FILE="round_robin_waves.vcd"
```

### With Console Output
```bash
vsim TestSMT_DualThreadRoundRobin -c \
    -do "run 500; quit;" \
    -g MAX_TEST_CYCLES=500 \
    -g SHOW_SERIAL_OUT=1
```

---

## Test Report Interpretation

### Example Report Output

```
=================================================
SMT Round-Robin Fetch Test Report
=================================================

Configuration:
  Thread 0 Start PC: 0x00000000
  Thread 1 Start PC: 0x80000000
  Number of Threads: 2
  Test Duration: 500 cycles

----- Fetch Pattern Analysis -----
Total fetch cycles recorded: 500

Round-robin pattern accuracy: 498/500 (99.6%)

----- PC Verification -----
Thread 0 first fetch PC: 0x00000000
Thread 1 first fetch PC: 0x80000000

PC Error Analysis:
  Thread 0 PC errors: 0
  Thread 1 PC errors: 0

----- Sample Fetch Sequence -----
Cycle   0: Thread 0, PC = 0x00000000
Cycle   1: Thread 1, PC = 0x80000000
Cycle   2: Thread 0, PC = 0x00000004
Cycle   3: Thread 1, PC = 0x80000004
Cycle   4: Thread 0, PC = 0x00000008
Cycle   5: Thread 1, PC = 0x80000008
...

=================================================
Test Summary
=================================================
STATUS: PASSED ✓
- Round-robin pattern verified
- PC consistency verified for both threads
=================================================
```

### Key Metrics

**Round-robin pattern accuracy**: Should be > 99%
- Measures if thread selection alternates correctly
- Minor deviations possible due to stalls/flushes

**PC Error Analysis**: Should both be 0
- Verifies PC stays within thread's address space
- Thread 0: PC should be < 0x80000000
- Thread 1: PC should be >= 0x80000000

**Thread 0 PC Progression**: 0x00000000 → 0x00000xxx
- Should start at configured address
- Should increment monotonically

**Thread 1 PC Progression**: 0x80000000 → 0x8000xxxx
- Should start at configured address
- Should increment monotonically

---

## Verification Checkpoints

### Checkpoint 1: Thread Selection
```
Expected: selectedTid alternates 0, 1, 0, 1, ...
Check: npStageIF.port.selectedTid signal
```

### Checkpoint 2: Fetch Thread ID
```
Expected: fetchThreadId[i] matches selectedTid when valid
Check: ifStageIF.port.fetchThreadId[*]
```

### Checkpoint 3: PC Correctness
```
Expected: pcOut[0] starts at 0x00000000, pcOut[1] starts at 0x80000000
Check: npStageIF.port.pcOut[*]
```

### Checkpoint 4: Instruction Propagation
```
Expected: nextStage[i].tid reflects selected thread
Check: ifStage.nextStage[*].tid values in waveform
```

---

## Debugging Failed Tests

### Issue: Round-robin pattern breaks
**Cause**: Thread selection logic issue in NextPCStage

**Debug**:
```verilog
// Monitor thread counter
add wave sim:main.main.core.npStage.threadCounter
add wave sim:main.main.core.npStage.port.selectedTid

// Verify counter increments every cycle
// selectedTid should alternate 0 → 1 → 0 → 1
```

**Fix**: Check NextPCStage.sv for `threadCounter` increment logic

### Issue: PC not progressing correctly
**Cause**: PC module not updating properly

**Debug**:
```verilog
// Monitor PC updates
add wave sim:main.main.core.pc.pcReg[0]
add wave sim:main.main.core.pc.pcReg[1]

// Should increment every other cycle
// Thread 0 increments on cycles 0, 2, 4, ...
// Thread 1 increments on cycles 1, 3, 5, ...
```

**Fix**: Verify PC write enable (pcWE) is per-thread

### Issue: ThreadID not propagating
**Cause**: FetchStage not copying selectedTid

**Debug**:
```verilog
// Check if tid is assigned
add wave sim:main.main.core.ifStage.nextStage[*].tid

// Should match selectedTid when instruction is valid
```

**Fix**: Verify `nextStage[i].tid = pipeReg[i].tid` assignment

### Issue: PC addresses mixed between threads
**Cause**: Thread 0 fetching from Thread 1's address space or vice versa

**Debug**:
```verilog
// Check PC range validity
add wave sim:main.main.core.npStage.port.selectedTid
add wave sim:main.main.core.npStage.port.pcOut[0]
add wave sim:main.main.core.npStage.port.pcOut[1]

// When selectedTid=0, pcOut[0] should be < 0x80000000
// When selectedTid=1, pcOut[1] should be >= 0x80000000
```

**Fix**: Check if NextPCStage is routing PC updates correctly per thread

---

## Advanced Analysis

### Counting Thread Switches
```bash
# Extract from report
grep "Round-robin pattern accuracy" round_robin_report.txt
```

### Analyzing PC Jump Patterns
```bash
# Check for unexpected PC resets (branch misses)
grep "Thread 0, PC = 0x00000000" round_robin_report.txt | wc -l
grep "Thread 1, PC = 0x80000000" round_robin_report.txt | wc -l
```

### Measuring Thread Fairness
```bash
# Compare time each thread spends executing
# Should be approximately equal
```

---

## Expected Test Results

### Success Criteria

✓ **Round-robin pattern accuracy** > 95%
✓ **PC errors** = 0 for both threads
✓ **Thread 0 PC range** = [0x00000000, 0x80000000)
✓ **Thread 1 PC range** = [0x80000000, ...)
✓ **Committed instructions** > 0 (both threads executing)

### Typical Output
```
========== Round-Robin Test Summary ==========
Round-robin accuracy: 498/500 (99.6%)
Thread 0 PC errors: 0
Thread 1 PC errors: 0
Report written to: Verification/TestCode/SMT_DualThread/round_robin_report.txt
============================================

========== Final Statistics ==========
Total Fetches Recorded: 500
Num of committed RISC-V-ops: 150
Num of committed micro-ops: 175
IPC (RISC-V instruction): 0.30
IPC (micro-op): 0.35
Elapsed cycles: 500
========================================
```

---

## Performance Notes

### Execution Time
- 500 cycles: ~5-10 seconds
- 1000 cycles: ~10-20 seconds
- 5000 cycles: ~1-2 minutes

### Memory Usage
- Testbench: ~100MB
- Waveforms (with -g WAVE_LOG_FILE): +500MB

---

## Troubleshooting Common Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| Compile errors | "Undefined signal" | Check interface definitions in *IF.sv files |
| No output file | Report file not created | Check TEST_CODE path is accessible |
| Wrong PC values | PC not in expected range | Verify thread configuration in testbench |
| Low instruction count | IPC near zero | Check if pipeline is stalling/flushing excessively |
| Pattern breaks randomly | Round-robin accuracy < 90% | Look for unexpected flushes in recovery logic |

---

## Next Steps

1. **Run Basic Test**
   - Execute 500-cycle test
   - Verify round-robin pattern

2. **Analyze Results**
   - Check report for PC consistency
   - Verify no PC errors

3. **Extended Testing**
   - Run 1000+ cycle tests
   - Verify sustained round-robin behavior

4. **Performance Measurement**
   - Compare IPC between single-thread and dual-thread
   - Analyze cache behavior per thread

5. **Stress Testing**
   - Run tests with different starting addresses
   - Test with actual dual-thread workloads

---

## Files Reference

| File | Purpose |
|------|---------|
| TestSMT_DualThreadRoundRobin.sv | Main testbench |
| code.hex | Test program code |
| round_robin_report.txt | Test results |
| SMT_DUALTHREAD_TEST_GUIDE.md | This document |

---

## Questions?

Refer to:
- `SMT_MODIFICATIONS_SUMMARY.md` - Implementation details
- `SMT_INTERFACE_VERIFICATION.md` - Interface signal details
- `TESTBENCH_QUICKREF.md` - Testbench command reference
- Per-module README files - Specific module documentation

---

**Test is ready to verify round-robin prefetch with dual-thread setup.**
