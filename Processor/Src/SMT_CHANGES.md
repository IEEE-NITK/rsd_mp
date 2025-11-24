# SMT (Simultaneous Multithreading) Implementation Plan

## Overview
Converting the RSD processor from single-threaded to SMT with 2-4 simultaneous threads.

## Phase 1: Configuration & Type Definitions (DONE)
- [x] Add CONF_THREAD_NUM and CONF_THREAD_ID_BIT_WIDTH to MicroArchConf.sv
- [x] Add ThreadID type to BasicTypes.sv

## Phase 2: Front-End (Fetch & PC Management)
### NextPCStage
- [ ] Add per-thread PC registers
- [ ] Thread selection logic for fetch
- [ ] Per-thread BTB and branch predictor
- [ ] Fetch arbitration logic to interleave threads

### ICache
- [ ] Add thread context to cache requests
- [ ] Potential: per-thread cache partitioning (optional)

## Phase 3: Decode & Rename
### Decoder
- [ ] Attach thread ID to decoded instructions
- [ ] Per-thread instruction decode

### RenameLogic
- [ ] Per-thread RMT (Register Mapping Table)
- [ ] Per-thread retirement RMT
- [ ] Thread-aware freelist management

### ActiveList
- [ ] Per-thread active list entries
- [ ] Thread context in ROB entries

## Phase 4: Execution Pipeline
### Issue Queue
- [ ] Per-thread issue tracking
- [ ] Thread-aware wakeup logic

### Register File
- [ ] Thread context in register file reads/writes
- [ ] Per-thread bypass network (or unified with thread tagging)

### Execution Units
- [ ] Thread ID propagation through all execution units
- [ ] Per-thread exception handling

## Phase 5: Memory System
### Load/Store Unit
- [ ] Per-thread load/store queues
- [ ] Thread-aware memory dependencies
- [ ] Per-thread memory dependency predictor

### DCache
- [ ] Thread context in cache operations
- [ ] Per-thread cache partitioning (optional)

## Phase 6: Commit Stage
### CommitStage
- [ ] Per-thread commit logic
- [ ] Per-thread exception recovery
- [ ] Thread-aware pipeline flush

## Phase 7: CSR & Privileged State
### CSR_Unit
- [ ] Per-thread CSR state
- [ ] Thread-aware interrupt handling
- [ ] Per-thread privilege mode

## Implementation Strategy

### Thread Interleaving Policy
Options:
1. **Round-robin**: Fetch alternates between threads
2. **Priority-based**: Fetch higher-priority thread
3. **Fine-grained**: Multiple instructions per thread per cycle

Recommended: Round-robin initially for simplicity

### Data Structure Updates
All pipeline stages need thread context (ThreadID) attached to:
- Instructions in flight
- Register operands
- Pipeline control signals
- Exception information

### Backward Compatibility
- Single-thread mode (TC=0) should work like original processor
- Configuration parameter determines thread count

## Verification Considerations
- Test each thread independently
- Test thread interactions (cache conflicts, memory dependencies)
- Test priority/arbitration logic
- Test exception handling per-thread
- Performance benchmarking

## Complexity Areas
1. **Rename Logic**: Most complex, need per-thread mapping tables
2. **Memory System**: Thread-aware load/store queue management
3. **Commit Stage**: Per-thread state reconstruction
4. **CSR State**: Per-thread privileged state
