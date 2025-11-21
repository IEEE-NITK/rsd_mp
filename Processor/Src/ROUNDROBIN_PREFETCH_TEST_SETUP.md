# Round-Robin Prefetch Test Setup Guide

## Overview

Complete test suite for verifying the round-robin prefetch behavior in the SMT (Simultaneous Multi-Threading) dual-thread processor. This guide covers:

1. Dummy data initialization file
2. Per-thread PC initialization with different memory addresses
3. Test execution and verification
4. Report generation and analysis

## Files Created/Modified

### 1. Dummy Data File
**File:** `Verification/DummyData.hex`
- **Purpose:** Initializes memory with dummy data before loading actual programs
- **Format:** 64-bit hexadecimal values (one per line)
- **Size:** 256 entries (covers DUMMY_HEX_ENTRY_NUM)
- **Pattern:** Repeating patterns for easy identification
  - 0x0000000000000000 through 0xFFFFFFFFFFFFFFFF (basic count)
  - Special patterns: 0xDEADBEEF, 0xCAFEBABE, etc.

### 2. Enhanced Testbench
**File:** `Verification/TestSMT_DualThreadRoundRobin.sv`

#### New Components Added:
1. **TestSMT_RoundRobinPrefetch Module** (lines 479+)
   - Focused prefetch verification
   - ROM/RAM separation testing
   - Round-robin pattern validation

2. **InitializePerThreadPCs() Task**
   - Forces different PC values for each thread during initialization
   - Thread 0: PC = 0x00000000 (ROM)
   - Thread 1: PC = 0x80000000 (RAM)
   - Handles PC compression via ToPC_FromAddr()
   - Releases forces to allow normal operation

3. **LoadDummyProgram() Task**
   - Loads simple test instructions to both threads
   - Thread 0: `addi x1, x1, 1` (0x00108093)
   - Thread 1: `addi x2, x1, 2` (0x00208113)

4. **VerifyMemoryInitialization() Task**
   - Validates ROM code loaded correctly
   - Validates RAM code loaded correctly
   - Reports initialization success/failure

5. **MonitorPrefetchBehavior() Task**
   - Records fetch activity per cycle
   - Tracks thread ID and PC values
   - Detects round-robin violations

6. **GeneratePrefetchReport() Task**
   - Creates detailed test report
   - Analyzes round-robin pattern accuracy
   - Validates PC progression per thread

### 3. Makefile
**File:** `Makefile.TestSMT_RoundRobinPrefetch.mk`
- Builds and runs the prefetch test
- Configurable parameters
- Automatic report generation

## Configuration Parameters

### Memory Layout
```
ROM Section (Thread 0):
  Logical: 0x00000000 - 0x00010000
  Thread 0 Instructions: 0x00000000

RAM Section (Thread 1):
  Logical: 0x80000000 - 0x80010000
  Thread 1 Instructions: 0x80000000
```

### Reset Vector
- **Default Reset Vector:** 0x00001000
- **Test Override:**
  - Thread 0 PC: 0x00000000 (ROM start)
  - Thread 1 PC: 0x80000000 (RAM start)

### PC Compression
The processor uses 19-bit compressed PC format:
```
ROM area:  PC[18:0] with bit[18]=0 for ROM (0x0_XXXXX)
RAM area:  PC[18:0] with bit[18]=1 for RAM (0x4_XXXXX or 0x1_XXXXX)

Conversion:
- Logical 0x00000000 → PC 0x00000 (ROM, MSB=0)
- Logical 0x80000000 → PC 0x10000 (RAM, MSB=1)
```

## Running the Tests

### Quick Test (500 cycles)
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk MAX_TEST_CYCLES=500
```

### Standard Test (2000 cycles - default)
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk
```

### Extended Test (5000 cycles)
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk MAX_TEST_CYCLES=5000
```

### With Debug Output
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk \
  MAX_TEST_CYCLES=1000 \
  SHOW_PREFETCH_DEBUG=1
```

### Build Only
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk build
```

### Run Existing Build
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk run
```

### Clean Build
```bash
make -f Makefile.TestSMT_RoundRobinPrefetch.mk clean
```

## Test Execution Flow

```
1. Initialize Memory
   └─ Load DummyData.hex (dummy fill)
   └─ Load test code for Thread 0 and Thread 1

2. Load Test Programs
   └─ Thread 0 ROM: Simple instruction sequence
   └─ Thread 1 RAM: Different instruction sequence

3. Initialize Thread PCs
   └─ Thread 0 PC = 0x00000000
   └─ Thread 1 PC = 0x80000000

4. Verify Memory Initialization
   └─ Check ROM code loaded
   └─ Check RAM code loaded

5. Run Simulation (Monitor Prefetch)
   └─ Sample fetch stage every cycle
   └─ Track thread selection and PC progression
   └─ Record round-robin pattern

6. Generate Report
   └─ Analyze round-robin accuracy
   └─ Verify PC progression
   └─ Report PASS/FAIL status
```

## Test Report Output

### Console Output Example
```
========== Loading Dummy Program ==========
Thread 0 (ROM): Instructions loaded at 0x00000000
Thread 1 (RAM): Instructions loaded at 0x80000000
==========================================

========== Setting Per-Thread PC Values ==========
Thread 0 PC forced to: 0x00000000 (ROM)
Thread 1 PC forced to: 0x80000000 (RAM)
PC values released for normal operation
===================================================

========== Verifying Memory Initialization ==========
[✓] ROM Thread 0 code verified at 0x00000000
[✓] RAM Thread 1 code verified at 0x80000000
[✓] All memory initialization checks PASSED
======================================================

========== SMT Round-Robin Prefetch Test Starting ==========
Thread 0 Start PC: 0x00000000 (ROM)
Thread 1 Start PC: 0x80000000 (RAM)
Max Test Cycles: 2000
===========================================================

[Cycle      0] Round-robin prefetch monitoring active
...
[Cycle   1950] Round-robin prefetch monitoring active

========== Prefetch Test Summary ==========
Total prefetch operations: 2000
Thread 0: 1000, Thread 1: 1000
[✓] Round-robin pattern: ALTERNATING
Report written to: Verification/TestCode/SMT_DualThread/prefetch_roundrobin_report.txt
==========================================

========== Final Statistics ===========
Total Prefetch Samples: 2000
Total Prefetch Operations: 2000
Round-Robin Violations: 0
Elapsed Cycles: 2000
========================================
```

### Report File Format
**Location:** `Verification/TestCode/SMT_DualThread/prefetch_roundrobin_report.txt`

```
=================================================
SMT Round-Robin Prefetch Test Report
=================================================

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

----- Sample Prefetch Sequence (first 20) -----
[  0] Cycle    0: Thread 0, PC = 0x00000000
[  1] Cycle    1: Thread 1, PC = 0x80000000
[  2] Cycle    2: Thread 0, PC = 0x00000004
[  3] Cycle    3: Thread 1, PC = 0x80000004
...

=================================================
Test Summary
=================================================
STATUS: PASSED ✓
- Round-robin alternation verified
- PC progression validated
- Memory initialization confirmed
=================================================
```

## Verification Checks

### 1. Memory Initialization Check
- ✓ ROM contains expected Thread 0 code
- ✓ RAM contains expected Thread 1 code
- ✓ Addresses match configured regions

### 2. PC Initialization Check
- ✓ Thread 0 PC starts at 0x00000000
- ✓ Thread 1 PC starts at 0x80000000
- ✓ PC values maintained after release

### 3. Round-Robin Pattern Check
- ✓ Threads alternate: T0 → T1 → T0 → T1
- ✓ No consecutive same-thread selections
- ✓ Pattern accuracy ≥ 99%

### 4. PC Progression Check
- ✓ Thread 0 PC increases monotonically
- ✓ Thread 1 PC increases monotonically
- ✓ PC increments by 4 bytes per instruction
- ✓ No cross-thread PC corruption

## Troubleshooting

### Issue: Memory Initialization Fails
**Symptoms:** "[✗] ROM Thread 0 code mismatch"
**Solutions:**
1. Check DummyData.hex file exists
2. Verify memory module initialization functions
3. Check memory read/write operations
4. Verify instruction encoding (0x00108093)

### Issue: PC Initialization Fails
**Symptoms:** PC values don't match expected addresses
**Solutions:**
1. Check PC register bank generation (PC.sv)
2. Verify force/release syntax in testbench
3. Check PC_WIDTH and compression logic
4. Verify thread count (NUM_THREADS = 2)

### Issue: Round-Robin Pattern Fails
**Symptoms:** "[✗] Round-robin pattern: NON-ALTERNATING"
**Solutions:**
1. Check NextPCStage round-robin logic
2. Verify threadCounter increment
3. Check stall handling in arbitration
4. Verify selectedTid signal propagation

### Issue: PC Progression Incorrect
**Symptoms:** PC doesn't increment or jumps unexpectedly
**Solutions:**
1. Check instruction length (4 bytes)
2. Verify branch prediction isn't affecting test
3. Check recovery/exception logic
4. Verify PC update mechanism

## Performance Metrics

### Expected Results (2000 cycles)
- Total prefetch samples: 2000
- Thread 0 prefetches: ~1000
- Thread 1 prefetches: ~1000
- Thread 0/1 ratio: 0.50 ± 0.02
- Round-robin violations: 0
- Pattern accuracy: >99%

### Benchmark (on typical hardware)
- Build time: 30-60 seconds
- Simulation time: 5-15 seconds
- Report generation: <1 second

## Integration with CI/CD

### GitLab CI Example
```yaml
test_round_robin_prefetch:
  stage: test
  script:
    - cd Processor/Src
    - make -f Makefile.TestSMT_RoundRobinPrefetch.mk MAX_TEST_CYCLES=1000
    - grep "STATUS: PASSED" Verification/TestCode/SMT_DualThread/prefetch_roundrobin_report.txt
  artifacts:
    paths:
      - Processor/Src/Verification/TestCode/SMT_DualThread/prefetch_roundrobin_report.txt
```

## Related Documentation

- `README_RoundRobinPrefetch_Test.md` - Detailed test guide
- `Pipeline/FetchStage/README_fetch.md` - Fetch stage architecture
- `SMT_MODIFICATIONS_SUMMARY.md` - All SMT modifications
- `Memory/MemoryMapTypes.sv` - Memory map configuration
- `Pipeline/FetchStage/NextPCStage.sv` - Round-robin arbitration

## References

### Key Modules
- `PC.sv` - Per-thread PC register bank
- `NextPCStage.sv` - Round-robin thread selection and PC update
- `Memory.sv` - Memory module with initialization
- `ResetController.sv` - Reset sequence controller

### Key Parameters
- `NUM_THREADS = 2` - Dual-thread configuration
- `PC_WIDTH = 19` - Compressed PC width
- `INSN_RESET_VECTOR = 0x00001000` - Default reset vector
- `MEMORY_ENTRY_BIT_NUM = 64` - Memory entry width

## Future Enhancements

1. **Advanced Instruction Sequences**
   - Load different instruction patterns per thread
   - Test with branch instructions
   - Test with loads/stores

2. **Extended Testing**
   - Per-thread cache behavior
   - Per-thread branch prediction
   - Exception handling per thread
   - Performance counter tracking

3. **Stress Testing**
   - Long-running tests (10,000+ cycles)
   - Multiple memory regions
   - Cache contention analysis

4. **Coverage Analysis**
   - Code coverage metrics
   - Instruction coverage
   - Branch coverage

## Contact & Support

For issues or questions regarding this test setup, refer to:
- `SMT_INTERFACE_VERIFICATION.md` - Interface verification
- `SMT_IMPLEMENTATION_PROGRESS.md` - Implementation status
- `README_SMT_TESTING.md` - General SMT testing guide
