# Next Session: Getting Started with Phase 4

## Welcome! 👋

This document tells you everything you need to know to continue the SMT implementation from where Phase 3 left off.

### TL;DR
- **Previous work**: Phases 1-3 complete (PC management + register mapping)
- **Current baseline**: IPC 0.985285, 4621 cycles (THREAD_NUM=1)
- **Your task**: Phase 4 (Dispatch & Resource Allocation)
- **Timeline**: Start with ~2-3 days of implementation work
- **Status**: All previous phases verified working, backward compatible ✓

---

## Quick Start (5 minutes)

### 1. Verify Current State
```bash
cd Processor/Src
make clean
make all
make run
```
**Expected output**: 
```
IPC (RISC-V instruction): 0.985285
Elapsed cycles: 4621
```
If you get this, you're good to go! ✓

### 2. Read Key Documents
Priority order:
1. This file (5 min)
2. `PHASE4_HANDOVER.md` (10 min) - Complete Phase 4 plan
3. `BRANCH_PREDICTOR_CACHE_ANALYSIS.md` (5 min) - Answers about branch predictor & cache
4. `SMT_PHASE3_COMPLETION.md` (10 min) - How Phase 3 was implemented

Total: ~30 minutes to understand everything

### 3. Understand the Architecture (15 minutes)
Open and skim these files:
- `Pipeline/PipelineTypes.sv` - See how ThreadID is added to pipeline
- `RenameLogic/RMT.sv` - See per-thread pattern (lines 45-85 especially)
- `Pipeline/FetchStage/PC.sv` - See how per-thread resources work

---

## Architecture Quick Recap

### What's Already Done (Phases 1-3)

```
FetchStage: Per-thread PC with round-robin selection
    ↓
PreDecodeStage: Thread ID propagated
    ↓
DecodeStage: Thread ID propagated
    ↓
RenameStage: Per-thread RMT (Register Map Table)
    ↓
DispatchStage: Ready for Phase 4 (resource allocation)
```

### What You're Building (Phase 4)

```
DispatchStage:
  ├─ Per-thread Free Lists (register allocation)
  ├─ Per-thread Active List (ROB management)
  ├─ Thread-aware Issue Queue
  └─ Per-thread Load/Store Queue
```

---

## Phase 4 Overview

### Goal
Implement thread-isolated resource allocation at dispatch stage.

### Key Components to Modify
1. `RenameLogic/RenameLogicTypes.sv` - Add thread to ActiveListEntry
2. `RenameLogic/ActiveList.sv` - Per-thread active list
3. `RenameLogic/RenameLogic.sv` - Per-thread free lists
4. `Pipeline/DispatchStage.sv` - Thread propagation (maybe already done?)
5. `Scheduler/Scheduler.sv` - Thread awareness in issue queue
6. `LoadStoreUnit/LoadStoreUnit.sv` - Per-thread LSU

### Design Decisions (Must make before coding)

Choose your approach for each:

1. **Free Lists**: Shared with per-thread pointers OR per-thread separate
2. **Active List**: Separate lists per thread OR single list with per-thread tracking
3. **Issue Queue**: Shared with per-thread hints OR per-thread separate
4. **Load/Store Queue**: Per-thread separate (recommended) OR shared with tracking

**Recommendation**: Read PHASE4_HANDOVER.md section "Design Decisions to Make"

---

## Code Patterns to Follow

### Pattern 1: Conditional Data Structures
```systemverilog
`ifdef RSD_ENABLE_SMT
    // Multi-threaded version
    SomeType data[THREAD_NUM][SIZE];
`else
    // Single-threaded version (original)
    SomeType data[SIZE];
`endif
```

### Pattern 2: Per-thread Logic
```systemverilog
`ifdef RSD_ENABLE_SMT
    for (int t = 0; t < THREAD_NUM; t++) begin
        // Per-thread logic for thread t
    end
`else
    // Original single-threaded logic
`endif
```

### Pattern 3: Thread-indexed Access
```systemverilog
ThreadID threadID = input.thread;
output[i] = data[threadID][index];  // Access thread-specific data
```

### Pattern 4: Write Gating by Thread
```systemverilog
writeEnable[t] = globalWrite && (threadID == t);
```

All these patterns already used in Phase 3! Check RMT.sv (lines 45-185) for examples.

---

## Testing Strategy

### Single-threaded Regression Test
After each file modification:
```bash
make clean
make all
make run
```
**Must still produce**: IPC 0.985285, 4621 cycles

If not, you've broken something! Revert and debug.

### Build Test
```bash
RSD_ENABLE_SMT=1 THREAD_NUM=2 make all
```
Should compile with no errors (even if simulation might not work yet)

---

## File-by-File Implementation Plan

### Step 1: Type Definitions (EASY)
**File**: `RenameLogic/RenameLogicTypes.sv`

**What to do**:
- Add `ThreadID thread` field to `ActiveListEntry` struct
- Make conditional: only present when `RSD_ENABLE_SMT`

**Time**: 5 minutes
**Risk**: Very low
**Regression test after**: Yes

### Step 2: Active List (MEDIUM)
**File**: `RenameLogic/ActiveList.sv`

**What to do**:
- Implement per-thread head/tail pointers
- Add thread ID when allocating entries
- Thread-aware push/pop logic

**Time**: 30-45 minutes
**Risk**: Medium (complex pointer logic)
**Regression test after**: Yes

### Step 3: Free Lists (MEDIUM)
**File**: `RenameLogic/RenameLogic.sv`

**What to do**:
- Decide: shared or per-thread free lists
- Implement chosen strategy
- Pass thread ID to allocation logic

**Time**: 45 minutes
**Risk**: Medium (tracking logic)
**Regression test after**: Yes

### Step 4: Dispatch Stage (EASY)
**File**: `Pipeline/DispatchStage.sv`

**What to do**:
- Check if thread ID is already propagated (probably from Phase 3)
- If not, add propagation
- Pass thread ID to downstream modules

**Time**: 10-15 minutes
**Risk**: Very low
**Regression test after**: Yes

### Step 5: Scheduler (MEDIUM)
**File**: `Scheduler/Scheduler.sv` and `Scheduler/SchedulerIF.sv`

**What to do**:
- Add thread ID to issue queue entries
- Implement thread-aware scheduling
- Maintain shared issue queue (per-thread tracking)

**Time**: 45 minutes
**Risk**: Medium
**Regression test after**: Yes

### Step 6: Load/Store Unit (MEDIUM)
**File**: `LoadStoreUnit/LoadStoreUnit.sv`

**What to do**:
- Add thread ID to load queue entries
- Add thread ID to store queue entries
- Per-thread allocation/deallocation

**Time**: 45 minutes
**Risk**: Medium
**Regression test after**: Yes

---

## Common Pitfalls & How to Avoid Them

### Pitfall 1: Forgetting Conditional Compilation
**Symptom**: Single-threaded build fails
**Cause**: `#ifdef RSD_ENABLE_SMT` blocks not closed properly
**Fix**: Count `#ifdef` - `#else` - `#endif` pairs
**Check**: Search for unmatched `#endif` or `#else`

### Pitfall 2: Thread Index Out of Bounds
**Symptom**: Simulation crash or undefined behavior
**Cause**: Using `threadID` as array index without checking bounds
**Fix**: Verify `ThreadID` is always < `THREAD_NUM`
**Test**: Run with THREAD_NUM=1 first (thread must be 0)

### Pitfall 3: Modified Single-threaded Path
**Symptom**: IPC changed from 0.985285
**Cause**: Accidentally changed original code path
**Fix**: Check that single-threaded path is identical to before
**Verify**: Diff against Phase 3 version

### Pitfall 4: Interface Mismatches
**Symptom**: Compilation error about interface signal count
**Cause**: Added signal to one modport but not all
**Fix**: Add to all relevant modports (or move outside ifdef)
**Example**: If adding thread to RenameLogic, add to RenameStage too

### Pitfall 5: Incomplete Per-thread Initialization
**Symptom**: One thread works, other has undefined behavior
**Cause**: Forgot to initialize per-thread data structures
**Fix**: Initialize all per-thread arrays in reset
**Check**: Look for `always_ff @ (posedge clk) if (rst)`

---

## Key Reference Points

### Files to Understand First (in order)
1. **RenameLogic/RMT.sv** (lines 45-85) - Per-thread pattern
2. **Pipeline/FetchStage/PC.sv** - Per-thread resources
3. **RenameLogic/ActiveListIndexTypes.sv** - Index types used

### Documentation to Reference
1. `PHASE4_HANDOVER.md` - Complete specification
2. `SMT_PHASE3_COMPLETION.md` - Implementation details
3. `BRANCH_PREDICTOR_CACHE_ANALYSIS.md` - System design Q&A

### Build Command Reference
```bash
# Single-threaded baseline (must always pass)
make clean && make all && make run

# Multi-threaded build test (won't run yet, just compilation)
RSD_ENABLE_SMT=1 THREAD_NUM=2 make all

# Check specific file compiles
RSD_ENABLE_SMT=1 THREAD_NUM=2 make RenameLogic/ActiveList.sv
```

---

## Success Criteria for Phase 4

✓ All 6 file modifications complete
✓ Single-threaded regression test passes (IPC 0.985285, 4621 cycles)
✓ Multi-threaded build compiles without errors
✓ Code follows existing patterns (checkout RMT.sv for style)
✓ All conditional blocks properly closed
✓ No changes to original single-threaded paths
✓ Documentation updated (FILES_MODIFIED.md, CHANGES_SUMMARY.md)

---

## Estimated Timeline

| Task | Time | Notes |
|------|------|-------|
| Read documentation | 30 min | Do before coding |
| Step 1: Type definitions | 5 min | Quick, low risk |
| Regression test | 2 min | Should pass immediately |
| Step 2: Active List | 45 min | Careful with pointer logic |
| Regression test | 2 min | Must pass |
| Step 3: Free Lists | 45 min | Design decision needed first |
| Regression test | 2 min | Must pass |
| Step 4: Dispatch Stage | 15 min | May already be done |
| Regression test | 2 min | Must pass |
| Step 5: Scheduler | 45 min | Complex logic |
| Regression test | 2 min | Must pass |
| Step 6: LSU | 45 min | Complex logic |
| Regression test | 2 min | Must pass |
| Documentation | 30 min | Update files, create report |
| **TOTAL** | **~4.5 hours** | Over 2-3 days of work |

---

## Getting Help

### If you're stuck:
1. **Check the pattern**: Look at RMT.sv for similar implementation
2. **Check the build error**: Read error message carefully, search for the issue
3. **Check the regression test**: See if single-threaded still works (isolates problem)
4. **Check Phase 3 changes**: Review how similar feature was added
5. **Ask questions**: Review PHASE4_HANDOVER.md "Design Decisions" section

### If single-threaded regression fails:
1. Find which modification broke it (binary search)
2. Review that file's changes
3. Check for modifications to non-SMT code path
4. Revert and retry more carefully

---

## Checklist Before You Start

- [ ] Read this file (README_NEXT_SESSION.md)
- [ ] Read PHASE4_HANDOVER.md (main specification)
- [ ] Read BRANCH_PREDICTOR_CACHE_ANALYSIS.md (answer to your Q)
- [ ] Verified baseline: `make run` produces IPC 0.985285, 4621 cycles
- [ ] Decided on design approach (shared vs per-thread for each resource)
- [ ] Understood the code patterns (conditional compilation)
- [ ] Reviewed RMT.sv to see reference implementation
- [ ] Set up version control or backup (optional but recommended)

---

## After Phase 4 is Done

1. Verify single-threaded baseline one more time
2. Compile multi-threaded version (THREAD_NUM=2)
3. Create PHASE4_COMPLETION.md documenting changes
4. Update FILES_MODIFIED.md with Phase 4 files
5. Update CHANGES_SUMMARY.md with Phase 4 status
6. Plan Phase 5 (thread through execution pipeline)
7. Pass to next person or continue to Phase 5

---

## Quick Reference: Where Things Are

**Thread ID flows through**:
```
PC.sv → NextPCStage.sv → FetchStage → PreDecodeStage → DecodeStage 
→ RenameStage → RMT.sv → DispatchStage → Scheduler → (Phase 5: Execution)
```

**Per-thread resources**:
- PC: `FetchStage/PC.sv` ✓ Done
- RMT: `RenameLogic/RMT.sv` ✓ Done
- Free Lists: `RenameLogic/RenameLogic.sv` ← Phase 4
- Active List: `RenameLogic/ActiveList.sv` ← Phase 4
- Issue Queue: `Scheduler/Scheduler.sv` ← Phase 4
- LSU: `LoadStoreUnit/LoadStoreUnit.sv` ← Phase 4

**Configuration**:
- Thread count: `MicroArchConf.sv` (CONF_THREAD_NUM)
- Thread type: `BasicTypes.sv` (ThreadID typedef)
- Macro: `Makefiles/CoreSources.inc.mk` (RSD_ENABLE_SMT)

---

## One More Thing

If at any point the design seems unclear, refer back to:

**Question**: "How should I implement X?"
**Answer**: Look at how RMT.sv implements per-thread access (lines 45-185)

Every pattern you need is already demonstrated in Phase 3! Just follow the same structure and you'll be fine.

---

## You've Got This! 

Phase 4 is straightforward if you follow the patterns. Good luck, and remember:
- **Test often** (regression test after each file)
- **Follow patterns** (look at RMT.sv)
- **Read errors** (they usually tell you exactly what's wrong)
- **Commit regularly** (version control is your friend)

Questions? Review the documents in this order:
1. PHASE4_HANDOVER.md
2. SMT_PHASE3_COMPLETION.md
3. RenameLogic/RMT.sv (code reference)

---

**Session Ready**: YES ✓
**Baseline Verified**: YES ✓
**Documentation Complete**: YES ✓
**Good to Start Phase 4**: YES ✓

Happy coding! 🚀
