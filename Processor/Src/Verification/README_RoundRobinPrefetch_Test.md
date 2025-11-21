# SMT Round-Robin Prefetch Test

## Overview

This test suite verifies the round-robin prefetch behavior implemented in the SMT (Simultaneous Multi-Threading) dual-thread processor architecture. The test ensures that:

1. **Round-robin thread selection** works correctly in the fetch stage
2. **Per-thread instruction prefetching** maintains separate PC for each thread
3. **Memory initialization** (ROM and RAM) is correctly performed
4. **PC progression** is correct for each thread

## Test Files

### Main Test Module
- **`TestSMT_DualThreadRoundRobin.sv`**: Contains two testbenches:
  1. **`TestSMT_DualThreadRoundRobin`**: Original comprehensive test (lines 1-476)
  2. **`TestSMT_RoundRobinPrefetch`**: New focused prefetch test (lines 479+)

### Makefile
- **`Makefile.TestSMT_RoundRobinPrefetch.mk`**: Dedicated makefile for the prefetch test

## Test Architecture

### TestSMT_RoundRobinPrefetch Module

This module specifically tests the prefetch mechanisms:

#### Configuration
```
Thread 0: Starts at ROM (0x00000000)
Thread 1: Starts at RAM (0x80000000)
```

#### Key Components

1. **Memory Initialization**
   - Loads dummy RISC-V instructions to both ROM and RAM
   - Thread 0 gets: `addi x1, x1, 1` (instruction: 0x00108093)
   - Thread 1 gets: `addi x2, x1, 2` (instruction: 0x00208113)

2. **Round-Robin Monitoring**
   - Samples fetch stage every cycle
   - Records: Cycle number, thread ID, PC value
   - Tracks pattern violations

3. **Verification Tasks**
   - `LoadDummyProgram()`: Loads test instructions to memory
   - `InitializeThreadPCs()`: Initializes separate PCs for each thread
   - `VerifyMemoryInitialization()`: Validates ROM/RAM contents
   - `MonitorPrefetchBehavior()`: Monitors thread selection and PC progression
   - `GeneratePrefetchReport()`: Creates detailed test report

#### Output Reports

The test generates:
- **Console output**: Real-time test progress and summary
- **Report file**: `Verification/TestCode/SMT_DualThread/prefetch_roundrobin_report.txt`

Report includes:
- Configuration details
- Prefetch activity analysis
- Round-robin pattern verification
- PC progression tracking
- Sample prefetch sequences
- Pass/Fail summary

## How to Run

### Build and Run (Default)
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk
```

### Build Only
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk build
```

### Run Existing Build
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk run
```

### Clean Build Artifacts
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk clean
```

### Show Help
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk help
```

## Parameters

Override these parameters on the command line:

### MAX_TEST_CYCLES (default: 2000)
Number of simulation cycles to run
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk MAX_TEST_CYCLES=5000
```

### TEST_CODE (default: Verification/TestCode/SMT_DualThread)
Test code directory path
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk TEST_CODE=path/to/test
```

### DUMMY_DATA_FILE (default: Verification/DummyData.hex)
Dummy data initialization file
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk DUMMY_DATA_FILE=path/to/data.hex
```

### SHOW_PREFETCH_DEBUG (default: 0)
Enable prefetch debug output every 50 cycles
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk SHOW_PREFETCH_DEBUG=1
```

## Examples

### Basic test with defaults
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk
```

### Extended test with 5000 cycles
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk MAX_TEST_CYCLES=5000
```

### Build, then run with debug output
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk build
make -f Makefile.TestSMT_RoundRobinPrefetch.mk SHOW_PREFETCH_DEBUG=1 run
```

### Combine parameters
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk \
  MAX_TEST_CYCLES=3000 \
  SHOW_PREFETCH_DEBUG=1 \
  build

make -f Makefile.TestSMT_RoundRobinPrefetch.mk run
```

## Understanding the Output

### Console Output

1. **Loading Phase**
   ```
   ========== Loading Dummy Program ==========
   Thread 0 (ROM): Instructions loaded at 0x00000000
   Thread 1 (RAM): Instructions loaded at 0x80000000
   ```

2. **Memory Verification**
   ```
   ========== Verifying Memory Initialization ==========
   [✓] ROM Thread 0 code verified at 0x00000000
   [✓] RAM Thread 1 code verified at 0x80000000
   [✓] All memory initialization checks PASSED
   ```

3. **Test Execution**
   ```
   ========== SMT Round-Robin Prefetch Test Starting ==========
   Thread 0 Start PC: 0x00000000 (ROM)
   Thread 1 Start PC: 0x80000000 (RAM)
   Max Test Cycles: 2000
   [Cycle      0] Round-robin prefetch monitoring active
   ...
   ```

4. **Summary**
   ```
   ========== Prefetch Test Summary ==========
   Total prefetch operations: 2000
   Thread 0: 1000, Thread 1: 1000
   [✓] Round-robin pattern: ALTERNATING
   Report written to: Verification/TestCode/SMT_DualThread/prefetch_roundrobin_report.txt
   ```

### Report File Format

The report includes detailed metrics:

```
Configuration:
  Thread 0 PC Start (ROM): 0x00000000
  Thread 1 PC Start (RAM): 0x80000000
  Number of Threads: 2
  Test Duration: 2000 cycles

----- Prefetch Activity Analysis -----
Total prefetch operations: 2000

Thread 0 prefetches: 1000
Thread 1 prefetches: 1000
Thread 0/1 ratio: 0.50

----- Round-Robin Pattern -----
Pattern Status: [✓] ALTERNATING

----- PC Progression -----
Thread 0 PC range: 0x00000000 to 0x00000038
Thread 1 PC range: 0x80000000 to 0x80000038
```

## Verification Checks

### 1. Round-Robin Pattern Verification
- Checks that threads alternate in fetch selection
- Counts violations (consecutive same-thread selections)
- Reports pattern accuracy percentage

### 2. PC Progression Verification
- Validates Thread 0 PC stays in ROM range (0x0 - 0x7FFFFFFF)
- Validates Thread 1 PC stays in RAM range (0x80000000+)
- Ensures PC increments properly (4 bytes per instruction)

### 3. Memory Initialization Verification
- Confirms Thread 0 code loaded at ROM address
- Confirms Thread 1 code loaded at RAM address
- Validates instruction values match expected opcodes

### 4. Per-Thread Isolation
- Verifies each thread maintains separate PC
- Ensures thread selection alternates correctly
- Confirms no cross-thread interference

## Expected Results

### Successful Test
```
STATUS: PASSED ✓
- Round-robin alternation verified
- PC progression validated
- Memory initialization confirmed
```

### Debug Checklist

If the test fails, verify:

1. **Memory Module**
   - `InitializeMemory()` function works
   - `FillDummyData()` function works
   - Memory read/write operations functional

2. **Fetch Stage**
   - `NextPCStage` round-robin selection logic
   - PC output arrays correctly indexed by thread
   - `selectedTid` signal propagation

3. **Thread Configuration**
   - `NUM_THREADS` set to 2
   - Thread IDs 0 and 1 properly handled
   - PC initialization per thread

4. **Instruction Format**
   - RISC-V instruction encoding correct
   - addi x1, x1, 1 = 0x00108093
   - addi x2, x1, 2 = 0x00208113

## Integration with CI/CD

Add to your continuous integration:

```bash
# Run quick smoke test (500 cycles)
make -f Makefile.TestSMT_RoundRobinPrefetch.mk MAX_TEST_CYCLES=500

# Run full test (5000 cycles)
make -f Makefile.TestSMT_RoundRobinPrefetch.mk MAX_TEST_CYCLES=5000

# Check report for PASSED status
grep "STATUS: PASSED" Verification/TestCode/SMT_DualThread/prefetch_roundrobin_report.txt
```

## Troubleshooting

### Build Issues
- Ensure `Makefiles/CoreSources.inc.mk` exists
- Check Verilator installation: `which verilator`
- Verify all source files are accessible

### Simulation Issues
- Check memory initialization with `SHOW_PREFETCH_DEBUG=1`
- Verify PC values in report match expected ranges
- Check for round-robin violations

### Report Generation
- Verify test code directory exists
- Check file permissions for report generation
- Ensure sufficient disk space for trace files

## Related Tests

- **`TestSMT_DualThreadRoundRobin`** (Original): Tests full dual-thread behavior with commit tracking
- **`Makefile.TestSMT_DualThread.mk`**: Original test makefile
- **SMT_MODIFICATIONS_SUMMARY.md**: Details of all SMT modifications

## References

- `Pipeline/FetchStage/NextPCStage.sv`: Round-robin selection logic
- `Memory/Memory.sv`: Memory module implementation
- `BasicTypes.sv`: ThreadID type definition
- `MicroArchConf.sv`: NUM_THREADS configuration

## Future Enhancements

Potential improvements to the test:

1. **Instruction Variations**: Load different instruction sequences per thread
2. **Branch Testing**: Test with branch instructions to verify per-thread BHT
3. **Cache Testing**: Verify per-thread cache behavior
4. **Performance Metrics**: Add IPC tracking per thread
5. **Edge Cases**: Test stalls, flushes, and exceptions per thread
