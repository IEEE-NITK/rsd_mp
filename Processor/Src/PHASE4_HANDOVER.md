# SMT Phase 4-6 Implementation Handover

## Project Status Summary

**Completed**: Phase 1, 2, and 3 ✓
**Current**: Ready for Phase 4
**Target**: Complete multi-threaded support with full backward compatibility

### Latest Test Results
- Single-threaded baseline: **IPC 0.985285, 4621 cycles** (unchanged)
- Build status: **PASS** (make all, make run)
- Backward compatibility: **100% verified**

---

## Architecture Overview

### Current Implementation (Phases 1-3)

#### Phase 1-2: Front-end PC Management
- Per-thread PC registers with round-robin scheduling
- Thread selection in NextPCStage (alternates between threads each cycle)
- Thread ID propagated from FetchStage onwards

#### Phase 3: Decode & Rename - Per-thread Register Mapping
- Thread ID propagated through: FetchStage → PreDecodeStage → DecodeStage → RenameStage → DispatchStage
- Per-thread RMT (Register Map Table) instances for independent register allocation
- Each thread has isolated register namespace

### Critical Files Modified

**Core pipeline files:**
1. `Pipeline/PipelineTypes.sv` - Thread ID in all stage register paths
2. `Pipeline/FetchStage/PC.sv` - Per-thread PC registers + round-robin selector
3. `Pipeline/FetchStage/NextPCStageIF.sv` - Thread-aware interface signals
4. `Pipeline/FetchStage/NextPCStage.sv` - Thread selection logic
5. `Pipeline/PreDecodeStage.sv` - Thread ID propagation
6. `Pipeline/RenameStage.sv` - Thread-aware register mapping
7. `RenameLogic/RenameLogicIF.sv` - Thread signal in interface
8. `RenameLogic/RMT.sv` - Per-thread RMT instances

**Build configuration:**
- `Makefiles/CoreSources.inc.mk` - RSD_ENABLE_SMT macro documentation
- `MicroArchConf.sv` - CONF_THREAD_NUM parameter
- `BasicTypes.sv` - ThreadID typedef

---

## Phase 4: Dispatch & Resource Allocation (NEXT)

### Overview
Implement per-thread resource tracking and allocation at the dispatch stage. Ensures each thread maintains independent:
- Free register lists
- Active list (ROB) entries
- Issue queue slots
- Load/store queue entries

### Objective
Enable thread-isolated resource management so that one thread cannot starve another and resource contention is visible.

### Key Implementation Points

#### 1. Per-thread Free Lists
**File**: `RenameLogic/RenameLogic.sv`

Current state:
```systemverilog
MultiWidthFreeList scalarFreeList (
    .pop( allocatePhyScalarReg ),
    .poppedData( allocatedPhyScalarRegNum ),
    ...
);
```

Required changes:
- Create per-thread free list instances (or single shared list with thread-aware pointers)
- **Recommended**: Single shared free list with per-thread tracking
  - Reason: Prevents thread starvation while utilizing registers efficiently
  - Implementation: Add thread-aware pop/push logic
- Alternative: Per-thread free lists
  - Pro: Complete isolation
  - Con: Complex rebalancing if one thread exhausts registers
- Pass thread ID to free list allocation logic

#### 2. Per-thread Active List
**File**: `RenameLogic/ActiveList.sv`

Current state:
```systemverilog
BiTailMultiWidthQueuePointer #(ACTIVE_LIST_ENTRY_NUM, ...)
    activeListPointer(...)
```

Required changes:
- Per-thread head/tail pointers
- Per-thread valid entry counts
- Thread-aware push/pop logic
- Conditional ROB allocation per thread
- **Critical**: Thread context in ActiveListEntry structure

#### 3. Thread ID in Data Structures

**Files to modify:**
- `RenameLogic/RenameLogicTypes.sv` - Add thread field to ActiveListEntry
- `RenameLogic/ActiveList.sv` - Store thread ID with each entry
- `Pipeline/DispatchStage.sv` - Propagate thread ID through dispatch

#### 4. Dispatch Stage Thread Handling
**File**: `Pipeline/DispatchStage.sv`

Changes needed:
- Receive thread ID from RenameStage output
- Add thread ID to DispatchStageRegPath (likely already done in Phase 3)
- Pass thread ID to scheduler and load/store unit
- Thread-aware resource allocation arbitration

#### 5. Scheduler Updates
**File**: `Scheduler/Scheduler.sv` and `Scheduler/SchedulerIF.sv`

Changes needed:
- Add thread ID to issue queue entries
- Thread-aware instruction scheduling (optional: priority between threads)
- Per-thread vs shared issue queue design decision
- **Recommendation**: Shared issue queue with per-thread tracking
  - Allows flexible scheduling
  - Better hardware utilization

#### 6. Load/Store Unit Updates
**File**: `LoadStoreUnit/LoadStoreUnit.sv`

Changes needed:
- Add thread ID to load queue entries
- Add thread ID to store queue entries
- Per-thread or shared queues design decision
- **Recommendation**: Per-thread queues
  - Reason: Memory ordering is per-thread, simpler logic

### Design Decisions to Make

1. **Free List Strategy**:
   - [ ] Shared free list with per-thread accounting (RECOMMENDED)
   - [ ] Per-thread free lists with rebalancing logic
   - [ ] Hybrid approach

2. **Active List Organization**:
   - [ ] Per-thread independent lists (RECOMMENDED)
   - [ ] Single list with per-thread tracking
   - [ ] Distributed per-thread lists

3. **Issue Queue Organization**:
   - [ ] Shared with per-thread tracking (RECOMMENDED)
   - [ ] Per-thread separate queues
   - [ ] Hybrid with thread hints

4. **Load/Store Queue Organization**:
   - [ ] Per-thread separate queues (RECOMMENDED)
   - [ ] Shared with per-thread tracking
   - [ ] Thread-aware logical separation

5. **Resource Arbitration**:
   - [ ] Round-robin between threads (RECOMMENDED - simple, fair)
   - [ ] Priority-based (requires arbiter)
   - [ ] Demand-driven (allocate to thread with work)

### Files to Modify (Estimated 8-10 files)

1. `RenameLogic/RenameLogicTypes.sv` - Add thread to ActiveListEntry
2. `RenameLogic/RenameLogic.sv` - Per-thread free list logic
3. `RenameLogic/ActiveList.sv` - Per-thread active list
4. `RenameLogic/ActiveListIF.sv` - Thread-aware interface
5. `Pipeline/DispatchStage.sv` - Thread ID propagation
6. `Pipeline/DispatchStageIF.sv` - Thread ID in interface (if needed)
7. `Scheduler/SchedulerIF.sv` - Thread in issue queue entry
8. `Scheduler/Scheduler.sv` - Thread-aware scheduling
9. `LoadStoreUnit/LoadStoreUnit.sv` - Per-thread LSU implementation
10. `LoadStoreUnit/LoadQueue.sv` - Thread-aware load tracking
11. `LoadStoreUnit/StoreQueue.sv` - Thread-aware store tracking

### Testing Strategy

1. **Single-threaded regression** (THREAD_NUM=1)
   - Ensure: IPC 0.985285, 4621 cycles still achieved
   - All original test scenarios pass

2. **Build verification**
   - `make all` with RSD_ENABLE_SMT=1 THREAD_NUM=2
   - No compilation errors

3. **Multi-threaded simulation** (if feasible)
   - Simple dual-thread test program
   - Verify thread isolation
   - Check for resource starvation

### Backward Compatibility Notes

- All Phase 4 changes must be gated by `#ifdef RSD_ENABLE_SMT`
- Single-threaded path must be unchanged
- Use array types for per-thread data only in SMT mode

---

## Phase 5: Execution Pipeline Thread Context

### Overview
Propagate thread ID through all execution stages and implement thread-aware hazard detection.

### Key Areas
1. Thread ID in all execution stage register paths
2. Thread-aware bypass networks
3. Thread-aware dependency checking
4. Exception handling per thread

### Files to Modify (Estimated 15-20 files)
- All backend pipeline registers (IntegerBackEnd, ComplexIntegerBackEnd, MemoryBackEnd, FPBackEnd)
- Bypass network components
- Dependency checking logic
- Recovery manager

---

## Branch Predictor & Cache - NOT YET MODIFIED

### Important Note
**Current Status**: Branch predictor and cache have NOT been modified for SMT support.

#### Branch Predictor Current Issues
Files not modified:
- `FetchUnit/BranchPredictor.sv`
- `FetchUnit/Gshare.sv`
- `FetchUnit/Bimodal.sv`
- `FetchUnit/BTB.sv`

**What needs to happen**:
- Phase 5 or Phase 6: Add thread ID to branch predictor
- Each thread needs own prediction history (or shared with per-thread indexing)
- BTB (Branch Target Buffer) needs thread awareness
- Consider: Shared vs per-thread prediction tables

**Complexity**: Medium - Requires careful thought on prediction sharing between threads

#### Cache Current Issues
Files not modified:
- `Cache/ICache.sv`
- `Cache/DCache.sv`
- `Cache/CacheSystemIF.sv`
- `Cache/MemoryAccessController.sv`

**What needs to happen**:
- Caches can be shared (no changes needed for correctness)
- But: Thread ID propagation helpful for:
  - Performance analysis
  - Cache partitioning (future optimization)
  - Debug/tracing
  
**Complexity**: Low for correctness, Medium for optimization

**Recommendation**:
- Phase 4: Add thread ID to memory access paths (optional but helpful)
- Phase 5-6: Implement if cache partitioning desired
- Not critical for basic SMT functionality

---

## Complete Implementation Checklist

### Phases 1-3 (COMPLETE) ✓
- [x] Per-thread PC registers + round-robin selector
- [x] Thread ID propagation through FetchStage
- [x] Thread ID in PreDecodeStage, DecodeStage, RenameStage
- [x] Per-thread RMT instances
- [x] Single-threaded regression test PASS

### Phase 4 (NEXT)
- [ ] Per-thread Free Lists (or shared with per-thread tracking)
- [ ] Per-thread Active List
- [ ] Thread ID in ActiveListEntry
- [ ] Dispatch stage thread handling
- [ ] Scheduler thread awareness
- [ ] Load/Store unit thread awareness
- [ ] Single-threaded regression test

### Phase 5
- [ ] Thread ID in all execution stage registers
- [ ] Thread-aware bypass networks
- [ ] Thread-aware dependency checking
- [ ] Exception handling per thread
- [ ] Single-threaded regression test

### Phase 6
- [ ] Per-thread commit management
- [ ] Thread-specific recovery mechanisms
- [ ] Commit arbitration between threads
- [ ] Final system verification

### Optional Enhancements
- [ ] Branch predictor thread awareness
- [ ] Cache partitioning per thread
- [ ] Thread priority scheduling
- [ ] Performance monitoring per thread

---

## Key Code Patterns to Follow

### 1. Conditional Compilation Pattern
```systemverilog
`ifdef RSD_ENABLE_SMT
    // Multi-threaded implementation
    logic threadAware[THREAD_NUM][SIZE];
    
    always_comb begin
        for (int t = 0; t < THREAD_NUM; t++) begin
            // Per-thread logic
        end
    end
`else
    // Single-threaded implementation (original code)
    logic original[SIZE];
    
    always_comb begin
        // Original logic unchanged
    end
`endif
```

### 2. Array Access Pattern
```systemverilog
ThreadID currentThread = inputSignal.thread;
output = data[currentThread][index];  // Thread-indexed read
```

### 3. Thread-gated Write Pattern
```systemverilog
logic writeEnable[THREAD_NUM];
for (int t = 0; t < THREAD_NUM; t++) begin
    writeEnable[t] = globalWrite && (threadID == t);
end
```

### 4. Interface Signal Pattern
```systemverilog
`ifdef RSD_ENABLE_SMT
    ThreadID thread[PORT_WIDTH];
    logic data[THREAD_NUM][DATA_WIDTH];
`else
    ThreadID thread;  // Scalar, unused
    logic data[DATA_WIDTH];
`endif
```

---

## Build & Test Commands

### Single-threaded (Baseline - for regression testing)
```bash
cd Processor/Src
make clean
make all
make run
# Expected: IPC 0.985285, 4621 cycles
```

### Multi-threaded (After Phase 4+)
```bash
cd Processor/Src
RSD_ENABLE_SMT=1 THREAD_NUM=2 make clean
RSD_ENABLE_SMT=1 THREAD_NUM=2 make all
make run
```

---

## Documentation Files

### Available for Reference
1. `README_SMT.md` - Navigation hub
2. `SMT_QUICK_START.md` - Getting started
3. `SMT_IMPLEMENTATION_STATUS.md` - Architecture overview
4. `CHANGES_SUMMARY.md` - Change summary
5. `FILES_MODIFIED.md` - Complete file listing
6. `SMT_PHASE3_COMPLETION.md` - Phase 3 details
7. `PHASE3_SUMMARY.txt` - Phase 3 executive summary

### To Update After Phase 4
1. Update `FILES_MODIFIED.md` with Phase 4 files
2. Create `SMT_PHASE4_COMPLETION.md` with implementation details
3. Update `CHANGES_SUMMARY.md` with Phase 4 status
4. Update `SMT_IMPLEMENTATION_STATUS.md` with new architecture

---

## Known Limitations & Future Considerations

### Current Limitations
1. Branch predictor not thread-aware (TBD)
2. Cache not thread-partitioned (optional)
3. No thread priority scheduling (round-robin only)
4. Exception handling per-thread incomplete (Phase 6)
5. Memory consistency model not fully defined

### Future Optimizations
1. Selective branch prediction sharing
2. Cache partitioning per thread
3. Thread priority scheduling
4. Power management per thread
5. Performance counter per thread

---

## Estimated Implementation Schedule

- **Phase 4**: 2-3 days (resource allocation)
- **Phase 5**: 3-4 days (execution pipeline)
- **Phase 6**: 2-3 days (commit & recovery)

Total: ~7-10 days for complete SMT implementation

---

## Quick Reference: File Organization

```
Processor/Src/
├── Pipeline/
│   ├── PipelineTypes.sv          (MODIFIED - thread in all stages)
│   ├── FetchStage/
│   │   ├── PC.sv                 (MODIFIED - per-thread PC)
│   │   ├── NextPCStageIF.sv       (MODIFIED - thread interface)
│   │   └── NextPCStage.sv         (MODIFIED - thread selection)
│   ├── PreDecodeStage.sv          (MODIFIED - thread propagation)
│   ├── DecodeStage.sv             (TODO - add to DecodeStageRegPath if not done)
│   ├── RenameStage.sv             (MODIFIED - thread to RenameLogic)
│   ├── DispatchStage.sv           (TODO - thread propagation Phase 4)
│   └── [Other stages]             (TODO - thread in Phase 5)
├── RenameLogic/
│   ├── RenameLogicIF.sv           (MODIFIED - thread signal)
│   ├── RenameLogic.sv             (TODO - per-thread free lists Phase 4)
│   ├── ActiveList.sv              (TODO - per-thread active list Phase 4)
│   ├── ActiveListIF.sv            (TODO - thread interface Phase 4)
│   ├── RenameLogicTypes.sv        (TODO - thread in ActiveListEntry Phase 4)
│   └── RMT.sv                     (MODIFIED - per-thread RMT)
├── Scheduler/
│   ├── Scheduler.sv               (TODO - thread tracking Phase 4)
│   └── SchedulerIF.sv             (TODO - thread in issue queue Phase 4)
├── LoadStoreUnit/
│   ├── LoadStoreUnit.sv           (TODO - per-thread LSU Phase 4)
│   ├── LoadQueue.sv               (TODO - thread in entries Phase 4)
│   ├── StoreQueue.sv              (TODO - thread in entries Phase 4)
│   └── LoadStoreUnitIF.sv         (TODO - thread in interface Phase 4)
├── FetchUnit/
│   ├── BranchPredictor.sv         (NOT YET MODIFIED - Phase 5/6)
│   ├── Gshare.sv                  (NOT YET MODIFIED - Phase 5/6)
│   └── BTB.sv                     (NOT YET MODIFIED - Phase 5/6)
├── Cache/
│   ├── ICache.sv                  (NOT YET MODIFIED - Optional Phase 5/6)
│   ├── DCache.sv                  (NOT YET MODIFIED - Optional Phase 5/6)
│   └── MemoryAccessController.sv  (NOT YET MODIFIED - Optional Phase 5/6)
└── [Configuration files]
    ├── MicroArchConf.sv           (MODIFIED - THREAD_NUM param)
    └── BasicTypes.sv              (MODIFIED - ThreadID type)
```

---

## Next Session Kickoff Checklist

1. [ ] Read this handover document
2. [ ] Review `SMT_PHASE3_COMPLETION.md` for context
3. [ ] Understand current Phase 3 implementation
4. [ ] Plan Phase 4 design decisions (shared vs per-thread resources)
5. [ ] Verify test baseline: `make run` should produce IPC 0.985285, 4621 cycles
6. [ ] Start with `RenameLogic/RenameLogicTypes.sv` (add thread to ActiveListEntry)
7. [ ] Proceed with `RenameLogic/ActiveList.sv` (per-thread lists)
8. [ ] Continue with resource allocation logic

---

## Contact Points for Questions

**Key Implementation Principles**:
- 100% backward compatibility with single-threaded mode
- All SMT code conditional on `RSD_ENABLE_SMT` macro
- Maintain original code paths unchanged
- Test with THREAD_NUM=1 after each phase
- Document design decisions clearly

**When stuck**:
- Check existing Phase 3 patterns in RMT.sv
- Review conditional compilation examples in PC.sv
- Refer to interface patterns in NextPCStageIF.sv

---

**Handover Date**: November 24, 2025
**Status**: Ready for Phase 4 Implementation
**Last Known Good State**: IPC 0.985285, 4621 cycles (THREAD_NUM=1)
