# SMT (Simultaneous Multithreading) Implementation Status

## Overview
Converting the RSD processor from single-threaded to SMT with 2-4 simultaneous threads with full backward compatibility.

**Key Design Principle**: All changes are conditional on `RSD_ENABLE_SMT` macro. When not defined, the processor behaves identically to the original single-threaded version.

---

## ✓ COMPLETED PHASES

### Phase 1: Configuration & Type Definitions ✓ 
**Status**: DONE - Backward compatible

#### Files Modified:
- **MicroArchConf.sv**
  - Added `CONF_THREAD_NUM` (defaults to 1, can be set to 2 via RSD_ENABLE_SMT macro)
  - Added `CONF_THREAD_ID_BIT_WIDTH` (0 bits for single-thread, auto-calculated for multi-thread)
  - SMT configuration is completely macro-gated

- **BasicTypes.sv**
  - Added `ThreadID` type (conditional definition)
  - Single-threaded mode: `ThreadID = logic` (1 bit)
  - Multi-threaded mode: `ThreadID = logic [THREAD_ID_BIT_WIDTH-1:0]`

- **Makefiles/CoreSources.inc.mk**
  - Added documentation for `RSD_ENABLE_SMT` macro
  - Configuration is commented by default (single-threaded compatible)

#### Backward Compatibility: ✓ VERIFIED
- Default build (THREAD_NUM=1) produces identical results
- Test run: IPC 0.985285, cycles 4621 (baseline: 0.985285, 4621)

---

### Phase 2: Front-End (Fetch & PC Management) ✓
**Status**: DONE - Fully backward compatible

#### Files Modified:

##### PC.sv (Pipeline/FetchStage/PC.sv)
- **Multi-threaded path (ifdef RSD_ENABLE_SMT)**:
  - Generate block creates THREAD_NUM independent PC registers
  - Each thread has its own FlipFlopWE register
  - Round-robin thread selector (threadCounter)
  - `currentThread` output selects active thread each cycle

- **Single-threaded path (else)**:
  - Uses original single PC register
  - No currentThread signal
  - Identical to original implementation

##### NextPCStageIF.sv (Pipeline/FetchStage/NextPCStageIF.sv)
- **Conditional signals**:
  - SMT mode: `pcWE[THREAD_NUM]`, `pcOut[THREAD_NUM]`, `pcIn[THREAD_NUM]`, `currentThread`
  - Single-threaded: `pcWE`, `pcOut`, `pcIn` (scalar)

- **Conditional modports**:
  - Two sets of modports (one for each mode)
  - PC modport handles both modes correctly
  - ThisStage modport exposes currentThread only in SMT mode

##### NextPCStage.sv (Pipeline/FetchStage/NextPCStage.sv)
- **PC control logic**: Conditional arrays vs scalars
- **Branch prediction**: Selects PC based on currentThread (SMT) or always thread 0 (single-threaded)
- **PC update**: Conditional indexing for per-thread vs single PC
- **FetchStageRegPath**: Optional `thread` field added to pipeline register

#### Backward Compatibility: ✓ VERIFIED
- All changes wrapped in `#ifdef RSD_ENABLE_SMT`
- Default build (without macro) uses original code paths
- Test results identical: IPC 0.985285, 4621 cycles

---

## PLANNED PHASES

### Phase 3: Decode & Rename (IN PROGRESS)
**Goal**: Per-thread register mapping and instruction tagging

**Files to Modify**:
- **PreDecodeStage.sv**: Add thread ID to instruction
- **RenameLogic.sv**: Per-thread RMT (Register Mapping Tables)
- **ActiveList.sv**: Per-thread ROB entries
- **RenameLogicIF.sv**: Thread-aware interfaces

**Design Considerations**:
- Per-thread RMT allows independent logical→physical register mapping
- Thread context must be preserved through all pipeline stages
- Recovery logic must consider thread ID

---

### Phase 4: Execution Pipeline (PLANNED)
**Goal**: Thread context propagation through execution units

**Scope**:
- Thread ID in all pipeline registers
- Per-thread bypass networks (or unified with thread tagging)
- Thread-aware hazard detection

---

### Phase 5: Memory System (PLANNED)
**Goal**: Per-thread load/store queues

**Scope**:
- Per-thread load queue
- Per-thread store queue
- Thread-aware memory dependency prediction
- Memory barrier handling between threads

---

### Phase 6: Commit Stage (PLANNED)
**Goal**: Per-thread commit logic

**Scope**:
- Per-thread commit arbitration
- Thread-aware exception handling
- Per-thread state recovery

---

## Building & Testing

### Single-Threaded Mode (Default - Backward Compatible)
```bash
cd Processor/Src
make all      # Builds without RSD_ENABLE_SMT
make run      # Runs simulation
```
**Expected**: Identical results to original processor

### Multi-Threaded Mode (Future)
```bash
# Update Makefiles/CoreSources.inc.mk
# Uncomment: +define+RSD_ENABLE_SMT

make clean
make all      # Builds with SMT enabled
make run      # Runs SMT simulation
```

---

## Backward Compatibility Verification

### Test Matrix
| Config | Files Modified | Build Status | Run Status | Results |
|--------|---|---|---|---|
| Original (no SMT) | 0 | ✓ | ✓ | Baseline |
| Phase 1 (Config) | 3 | ✓ | ✓ | Identical |
| Phase 2 (Front-End) | 3 | ✓ | ✓ | Identical |

### Performance Metrics (Single-Thread)
- IPC: 0.985285 (unchanged)
- Elapsed cycles: 4621 (unchanged)
- Test code: Verification/TestCode/Asm/FP
- Committed ops: 4553

---

## Architecture Notes

### Thread Interleaving Strategy
Currently using **round-robin fetch arbitration**:
- PC module increments `currentThread` each cycle
- Thread 0 → Thread 1 → Thread 0 (for 2-thread system)
- Simple, fair scheduling

**Future Enhancement**: 
- Priority-based scheduling
- Adaptive interleaving based on thread state
- Per-thread stall states

### Register Mapping Strategy (Planned)
- **Separate RMT per thread**: Each thread has independent logical→physical mappings
- **Shared physical register file**: All threads use unified physical register pool
- **Per-thread free lists**: Track physical registers free for each thread

### Memory Consistency
- **Weak consistency model**: Thread-local sequential consistency
- **Memory barriers**: Cross-thread synchronization via CSRs (future)
- **Load-store dependencies**: Per-thread + cross-thread ordering

---

## Known Limitations & TODOs

### Short-term (Phase 2 complete)
- [ ] Thread context not yet propagated past fetch stage
- [ ] No per-thread decode/rename yet
- [ ] No memory dependency awareness between threads
- [ ] No CSR separation per thread yet

### Medium-term (Phases 3-5)
- [ ] Single issue queue (shared between threads) - consider per-thread
- [ ] Cache coherency not implemented
- [ ] No thread priority scheduling yet
- [ ] Interrupt handling assumes single thread

### Long-term
- [ ] Performance profiling on SMT benchmarks
- [ ] Thread synchronization primitives
- [ ] NUMA-aware thread scheduling
- [ ] Power management per thread

---

## Development Notes

### Macro Convention
- `RSD_ENABLE_SMT`: Main macro to enable SMT features
- All conditional code uses `#ifdef RSD_ENABLE_SMT` / `#else` / `#endif`
- No runtime thread count changes (compile-time only)

### Coding Style
- Maintain indentation of original code
- Use comments to explain SMT-specific branches
- Keep single-threaded path as fast as possible (no overhead)

### Testing Strategy
1. Build without SMT → must work (backward compatibility)
2. Build with SMT (THREAD_NUM=1) → must work identically
3. Build with SMT (THREAD_NUM=2) → functional correctness
4. Performance comparison: SMT vs single-threaded

---

## References
- Makefile: `Processor/Src/Makefile`
- Build config: `Processor/Src/Makefiles/CoreSources.inc.mk`
- PC Module: `Processor/Src/Pipeline/FetchStage/PC.sv`
- NextPCStage: `Processor/Src/Pipeline/FetchStage/NextPCStage.sv`
