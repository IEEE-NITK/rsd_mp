# Phase 5: Multi-Threaded Testing - Quick Start Guide

**Prerequisites**: Phase 4 SMT infrastructure complete (✅ DONE)

---

## Current Status

All thread routing signals are in place and verified:
- ✅ Load/Store unit thread allocation
- ✅ Register release per-thread tracking  
- ✅ Active list per-thread operations
- ✅ Fetch stage thread tagging
- ✅ Zero compilation errors
- ✅ Baseline tests passing

---

## What's Ready for Phase 5

### 1. Per-Thread Structures (Already Implemented)

**In NextPCStage.sv:**
- `port.pcOut[THREAD_NUM]` - Per-thread program counters
- `port.currentThread` - Currently fetching thread
- Per-thread PC updates for each thread

**In ActiveList.sv:**
- `headPtr[THREAD_NUM]` - Per-thread head pointers
- `tailPtr[THREAD_NUM]` - Per-thread tail pointers  
- `count[THREAD_NUM]` - Per-thread entry counts
- Per-thread queue pointer management

**In LoadStoreUnit:**
- `allocateLoadQueueThread[]` - Thread for each load
- `allocateStoreQueueThread[]` - Thread for each store
- `loadQueueHeadPtr[THREAD_NUM]` - Per-thread queue pointers
- `storeQueueHeadPtr[THREAD_NUM]` - Per-thread queue pointers

**In RegisterFile/RenameLogic:**
- `scalarFreeListCount[THREAD_NUM]` - Per-thread free register tracking
- `releaseThread[]` - Thread of retiring instructions

---

## What Still Needs Implementation in Phase 5

### 1. Thread Scheduling (HIGH PRIORITY)

**Where**: `NextPCStage.sv` or new `ThreadScheduler.sv`

**What to implement**:
- Round-robin fetch scheduling between threads
- Simple approach: toggle `port.currentThread` each cycle
  ```systemverilog
  logic threadSelectReg;
  always_ff @(posedge clk) begin
      if (rst) threadSelectReg <= 0;
      else threadSelectReg <= ~threadSelectReg;
  end
  assign port.currentThread = threadSelectReg[0];
  ```

**Files to check**:
- `PC.sv` - How currentThread is generated
- `NextPCStageIF.sv` - currentThread output port

### 2. Active List Thread Tracking (MEDIUM PRIORITY)

**Where**: `ActiveList.sv` - `readDataThread` output

**Current**: Set to 0 always  
**Needed**: Track which thread owns each read entry

**Implementation**:
- Need to know which thread's active list is being read from
- Requires knowing commit thread context
- Can defer detailed threading logic; simple baseline: track from push operation

### 3. Test Case Creation (HIGH PRIORITY)

**Where**: `Verification/TestCode/Asm/` - Create multi-threaded tests

**What to test**:
1. **Basic SMT**: Two threads executing independently
2. **Thread Isolation**: Verify registers don't cross threads
3. **Queue Separation**: Verify each thread has separate load/store queues
4. **IPC Improvement**: Measure improvement vs single-threaded
5. **Hazard Handling**: Memory dependencies within and across threads

**Test structure**:
```asm
; Thread 0 code
; Simple loop: add, load, store

; Thread 1 code  
; Different operations: multiply, branch

; Synchronization point (if needed)
```

### 4. Performance Measurement (MEDIUM PRIORITY)

**Where**: `Debug/PerformanceCounter.sv` or `Verification/TestMain.sv`

**Metrics to add**:
- Per-thread instruction count
- Per-thread cycle count
- Per-thread IPC
- Thread utilization (% cycles both threads active)
- Cache miss rates per thread

---

## How to Verify Phase 5 is Working

### Step 1: Compile with SMT enabled
```bash
# Already enabled in Makefile
make clean
make all
# Should still get: ==== Build Successful ====
```

### Step 2: Run with SMT enabled
```bash
make run
# Should see test pass with baseline metrics
```

### Step 3: Create first multi-thread test
1. Copy existing test: `Verification/TestCode/Asm/FP`
2. Modify to include per-thread code sections
3. Add thread 0 and thread 1 sections with `RSD_THREAD 0/1` markers (if test infrastructure supports)

### Step 4: Verify thread separation
- Check that thread 0 and thread 1 instructions are interleaved
- Verify no register collisions between threads
- Measure IPC with both threads active

---

## Key Files to Monitor in Phase 5

| File | Purpose | Status |
|------|---------|--------|
| `NextPCStage.sv` | Fetch stage thread selection | ✅ Ready (needs scheduling logic) |
| `ActiveList.sv` | Per-thread active lists | ✅ Ready (needs thread tracking) |
| `LoadQueue.sv` | Per-thread load queue | ✅ Ready |
| `StoreQueue.sv` | Per-thread store queue | ✅ Ready |
| `RenameLogic.sv` | Per-thread register mapping | ✅ Ready |
| `PC.sv` | Per-thread PC management | ✅ Ready (check currentThread generation) |
| `Core.sv` | Top-level integration | ⚠️ May need thread scheduling wiring |

---

## Checklist for Phase 5

- [ ] Implement thread scheduling (round-robin or advanced)
- [ ] Verify per-thread PC updates work correctly
- [ ] Create first multi-thread test case
- [ ] Verify thread instruction interleaving in trace
- [ ] Add per-thread performance counters
- [ ] Measure IPC improvement with SMT
- [ ] Verify register isolation (no cross-thread pollution)
- [ ] Test exception/recovery with multiple threads
- [ ] Document SMT feature validation
- [ ] Baseline performance benchmarking

---

## Expected Phase 5 Outcomes

✅ **Working SMT processor** with:
- Both threads executing simultaneously in pipeline
- Proper per-thread resource management
- IPC improvement over single-threaded baseline
- Verified thread isolation and correctness
- Complete documentation of SMT implementation

**Estimated time**: 2-3 hours for thread scheduling + testing

---

## Reference: Thread Flow Through Pipeline

```
Fetch → Tag with port.currentThread
  ↓
Decode → Carry thread through
  ↓
Rename → Use thread for:
  - Load/store allocation
  - Active list operation
  - Register release
  ↓
Execute → Thread info in active list entry
  ↓
Commit → Use thread for:
  - Free list management
  - Register release per thread
  ↓
Retire → Both threads independently managed
```

All connection points are now wired and verified. Ready to add scheduling logic!
