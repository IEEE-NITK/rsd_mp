# Multi-Thread Test Programs

This directory contains test programs for verifying multi-threaded execution on the RSD processor.

## Directory Structure

- **IndependentExecution/**: Tests independent thread execution with no interaction
  - `thread0.s`: Thread 0 code
  - `thread1.s`: Thread 1 code
  
- **LoadStoreInteraction/**: Tests memory operations across threads
  - `thread0.s`: Thread 0 with load-store operations
  - `thread1.s`: Thread 1 with load-store operations
  
- **BasicSync/**: Tests basic synchronization via shared memory
  - `thread0.s`: Thread 0 with synchronization
  - `thread1.s`: Thread 1 with synchronization

## Memory Layout

See `MemoryLayout.txt` for detailed memory address assignments.

## How to Add New Tests

1. Create new directory under `MultiThread/`
2. Add `thread0.s` and `thread1.s` files
3. Update Makefile targets for compilation
4. Update test framework (TestMain.sv) to load new test
5. Run and verify results

## Test Execution

Tests are run via:
```bash
make run_multithread_independent
make run_multithread_loadstore
make run_multithread_sync
```

## Performance Metrics

Each test reports per-thread IPC and cycle count.
Compare against single-thread baseline (Phase 4: IPC = 0.985285).
