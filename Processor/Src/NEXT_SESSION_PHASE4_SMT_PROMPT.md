# Next Session Prompt: Complete Phase 4 SMT Infrastructure

## Context
Phase 4 SMT is 90% complete but blocked by 43 compilation errors. Thread data structures exist but thread routing signals aren't wired through the pipeline. This prompt guides you through 10 focused fixes to complete SMT.

**Estimated Time**: 2.5-3 hours  
**Goal**: Make `make all` compile with `RSD_ENABLE_SMT` enabled (0 errors)  
**Then**: Phase 5 can test multi-threaded execution

---

## Your Mission
Fix Phase 4 SMT wiring so that instructions carry thread IDs through the entire pipeline: Fetch → Rename → Execute → Commit

---

## Before You Start

1. Read this prompt fully
2. Understand the 10 tasks below
3. Follow them IN ORDER
4. Test compilation after every 2-3 tasks
5. Don't skip ahead

Expected compilation progress:
```
Start:     43 errors
After 1-3: 35-40 errors
After 4-6: 20-30 errors
After 7-9: 5-10 errors
After 10:  0 errors ✅
```

---

## TASK 1: LoadStoreUnitIF.sv - Thread Fields Always Defined
**File**: `LoadStoreUnit/LoadStoreUnitIF.sv`  
**Time**: 5 min  
**Goal**: Make thread fields always available (not behind ifdef)

**What to do**:
1. Open `LoadStoreUnit/LoadStoreUnitIF.sv`
2. Find lines 24-32 (the Allocation section)
3. Look for `#ifdef RSD_ENABLE_SMT` wrapping two ThreadID fields
4. **REMOVE the ifdef** - move the ThreadID declarations outside the ifdef
5. They should always be defined (whether SMT enabled or not)

**Code change**:
```systemverilog
// BEFORE (lines 24-32):
    logic allocateLoadQueue [ RENAME_WIDTH ];
    logic allocateStoreQueue [ RENAME_WIDTH ];
    LoadQueueIndexPath allocatedLoadQueuePtr [ RENAME_WIDTH ];
    StoreQueueIndexPath allocatedStoreQueuePtr [ RENAME_WIDTH ];

`ifdef RSD_ENABLE_SMT
    ThreadID allocateLoadQueueThread [ RENAME_WIDTH ];
    ThreadID allocateStoreQueueThread [ RENAME_WIDTH ];
`endif

// AFTER:
    logic allocateLoadQueue [ RENAME_WIDTH ];
    logic allocateStoreQueue [ RENAME_WIDTH ];
    LoadQueueIndexPath allocatedLoadQueuePtr [ RENAME_WIDTH ];
    StoreQueueIndexPath allocatedStoreQueuePtr [ RENAME_WIDTH ];
    
    // Always define thread fields (not conditional)
    ThreadID allocateLoadQueueThread [ RENAME_WIDTH ];
    ThreadID allocateStoreQueueThread [ RENAME_WIDTH ];
    ThreadID thread [ COMMIT_WIDTH ];  // For execution context
```

**Verify**: File saved, no syntax errors in editor

---

## TASK 2: Find and Update RenameLogicIF.sv
**File**: `RenameLogic/RenameLogicIF.sv` (find it)  
**Time**: 5 min  
**Goal**: Add releaseThread field

**What to do**:
1. Locate `RenameLogic/RenameLogicIF.sv`
2. Find the interface definition for RenameLogicIF
3. Look for release/retirement signals
4. Add this line near other release signals:
   ```systemverilog
   ThreadID releaseThread [ COMMIT_WIDTH ];  // Which thread is retiring
   ```

**Why**: RenameLogic.sv line 284 tries to use `port.releaseThread[i]` - this field must exist

**Verify**: Field added, file saved

---

## TASK 3: Find and Update ActiveListIF.sv
**File**: `RenameLogic/ActiveListIF.sv` (find it)  
**Time**: 5 min  
**Goal**: Add thread field

**What to do**:
1. Locate `RenameLogic/ActiveListIF.sv`
2. Find the interface definition for ActiveListIF
3. Look for allocation/dispatch signals
4. Add this line:
   ```systemverilog
   ThreadID thread [ RENAME_WIDTH ];  // Which thread for these operations
   ```

**Why**: ActiveList.sv uses `port.thread[0]` and `port.thread[i]` throughout - this field must exist

**Verify**: Field added, file saved

---

## TASK 4: RenameStage.sv - Verify Thread Wiring
**File**: `Pipeline/RenameStage.sv`  
**Time**: 15 min  
**Goal**: Ensure thread info flows to LoadStoreUnit

**What to do**:
1. Open `Pipeline/RenameStage.sv`
2. Find lines 340-345 (look for `allocateLoadQueue` assignment)
3. You should see:
   ```systemverilog
   loadStoreUnit.allocateLoadQueueThread[i] = pipeReg[i].thread;
   loadStoreUnit.allocateStoreQueueThread[i] = pipeReg[i].thread;
   ```
4. If these lines exist and compile, you're good
5. If missing, add them in the loop where `allocateLoadQueue` is assigned

**What this does**: Tells LoadStoreUnit which thread owns each load/store instruction

**Verify**: Lines present, logic looks correct

---

## TASK 5: RenameLogic.sv - Fix Register Release per Thread
**File**: `RenameLogic/RenameLogic.sv`  
**Time**: 30 min  
**Goal**: Use releaseThread to return freed registers to correct thread's free list

**What to do**:
1. Open `RenameLogic/RenameLogic.sv`
2. Find line 284 (search for `port.releaseThread`)
3. This code should exist or need fixing:
   ```systemverilog
   for (int i = 0; i < COMMIT_WIDTH; i++) begin
       if (port.release[i]) begin
           // Use port.releaseThread[i] to identify which thread
           // Return physical register to that thread's free list
       end
   end
   ```
4. Verify the logic uses `port.releaseThread[i]` to index into thread-specific free lists
5. If code tries to use undefined `currentThread` variable, remove it and use `port.releaseThread[i]` directly

**What this does**: Ensures freed registers go back to the right thread's pool

**Verify**: Code compiles, uses releaseThread correctly

---

## TASK 6: NextPCStage.sv - Implement Round-Robin Thread Fetch
**File**: `Pipeline/FetchStage/NextPCStage.sv`  
**Time**: 20 min  
**Goal**: Implement simple round-robin thread selection for fetch

**What to do**:
1. Open `Pipeline/FetchStage/NextPCStage.sv`
2. Find line 238 (error about `fetchThread` undefined)
3. Before that line, implement thread selection:
   ```systemverilog
   `ifdef RSD_ENABLE_SMT
       // Round-robin thread selection (simple toggle each cycle)
       logic threadSelector;
       always_ff @(posedge clk) begin
           if (rst) threadSelector <= 0;
           else threadSelector <= ~threadSelector;  // Toggle between 0 and 1
       end
       
       // Select which thread to fetch from
       logic [THREAD_ID_BIT_WIDTH-1:0] fetchThread;
       assign fetchThread = threadSelector;
       
       // Tag fetched instructions with thread ID
       for (int i = 0; i < FETCH_WIDTH; i++) begin
           nextStage[i].thread = fetchThread;
       end
   `else
       // Single-threaded version (no thread assignment needed)
   `endif
   ```
4. Remove or fix the line that was using undefined `fetchThread`

**What this does**: Alternates fetch between threads (T0, T1, T0, T1, ...) and tags instructions with their source thread

**Verify**: Code compiles, fetchThread properly defined

---

## TASK 7: LoadQueue.sv - Verify Thread Routing
**File**: `LoadStoreUnit/LoadQueue.sv`  
**Time**: 10 min  
**Goal**: Ensure load queue allocation routes to correct thread

**What to do**:
1. Open `LoadStoreUnit/LoadQueue.sv`
2. Check lines 95-101 (the allocation loop)
3. You should see expressions like:
   ```systemverilog
   tailPtr[port.allocateLoadQueueThread[i]] + pushCount[port.allocateLoadQueueThread[i]]
   ```
4. These are already corrected (variable declarations removed)
5. Just verify no undefined variables exist
6. Lines should directly reference `port.allocateLoadQueueThread[i]`

**What this does**: Routes each load allocation to the correct thread's queue

**Verify**: Code uses port.allocateLoadQueueThread, no undefined variables

---

## TASK 8: StoreQueue.sv - Verify Thread Routing
**File**: `LoadStoreUnit/StoreQueue.sv`  
**Time**: 10 min  
**Goal**: Ensure store queue allocation routes to correct thread

**What to do**:
1. Open `LoadStoreUnit/StoreQueue.sv`
2. Check lines 111-117 (allocation loop)
3. Similar to LoadQueue, should use `port.allocateStoreQueueThread[i]` directly
4. Verify no undefined variables

**What this does**: Routes each store allocation to the correct thread's queue

**Verify**: Code uses port.allocateStoreQueueThread, compiles cleanly

---

## TASK 9: ActiveList.sv - Fix Per-Thread Operations
**File**: `RenameLogic/ActiveList.sv`  
**Time**: 20 min  
**Goal**: Fix active list to properly use per-thread pointers

**What to do**:
1. Open `RenameLogic/ActiveList.sv`
2. Find all uses of `port.thread[0]` and `port.thread[i]` (should be several)
3. Lines 103, 104, 115, 348, 498, 516, 575, 590 area should have these
4. Verify they're using the thread field correctly:
   ```systemverilog
   // Example (line 103):
   port.allocatable = (count[port.thread[0]] <= ACTIVE_LIST_ENTRY_NUM - RENAME_WIDTH);
   ```
5. If you see undefined `currentThread` variable, change it to use `port.thread[0]` instead
6. Check for removed `ThreadID currentThread = ...` declarations - they should be gone

**What this does**: Ensures active list tracks per-thread pointers correctly

**Verify**: All per-thread operations use port.thread correctly, no undefined variables

---

## TASK 10: TestMain.sv - Update Debug Access
**File**: `Verification/TestMain.sv`  
**Time**: 20 min  
**Goal**: Update debug structure access for new ActiveList layout

**What to do**:
1. Open `Verification/TestMain.sv`
2. Find line 76 (error about activeList.activeList.debugValue)
3. The ActiveList internal structure may have changed with per-thread support
4. Either:
   - Update the path to match new structure, OR
   - Comment out/remove this debug code if it's not critical
5. The line probably looks like:
   ```systemverilog
   alHead = main.main.core.activeList.activeList.debugValue[ alHeadPtr ];
   ```
6. If it's causing errors, investigate ActiveList.sv structure and adjust path accordingly

**Note**: This is debug-only, not critical for functionality

**Verify**: No errors on this line, or debug code removed

---

## Compilation Checkpoint

**After Task 10, DO THIS**:

```bash
cd /Users/kushal/rsd_mp/Processor/Src

# Enable SMT in configuration
# Edit: Makefiles/CoreSources.inc.mk
# Find: #define+RSD_ENABLE_SMT (commented out)
# Change to: +define+RSD_ENABLE_SMT (uncommented)

# Clean and compile
rm -rf ../Project/Verilator/obj_dir
make all 2>&1 | tail -20
```

**Expected result**:
```
==== Build Successful ====
```

**If errors remain**:
- Count errors: `make all 2>&1 | grep "^%Error" | wc -l`
- Review error messages against task descriptions
- Ensure all 10 tasks completed correctly

---

## Final Verification

Once compilation succeeds:

```bash
# Run baseline test (make sure nothing broke)
make run +MAX_TEST_CYCLES=10000 +TEST_CODE=Verification/TestCode/Asm/FP

# Expected: Test completes, shows IPC ≈ 0.985 (similar to Phase 4 baseline)
```

If test runs successfully:
- ✅ Phase 4 SMT infrastructure complete
- ✅ Ready for Phase 5 multi-threaded testing

---

## Troubleshooting Guide

### Error: "Can't find definition of 'allocateLoadQueueThread'"
- **Cause**: Task 1 not done or incomplete
- **Fix**: Re-check LoadStoreUnitIF.sv lines 24-32, ensure ThreadID fields not in ifdef

### Error: "Can't find definition of 'releaseThread'"
- **Cause**: Task 2 not done
- **Fix**: Add `ThreadID releaseThread[COMMIT_WIDTH]` to RenameLogicIF.sv

### Error: "Can't find definition of 'thread' in dotted variable"
- **Cause**: Task 3 not done or variables declared in always_comb
- **Fix**: Ensure `ThreadID thread[RENAME_WIDTH]` in ActiveListIF.sv, use expressions not variables

### Error: "fetchThread undefined"
- **Cause**: Task 6 not done
- **Fix**: Implement thread selector logic and assign fetchThread before using it

### Error: "currentThread undefined"
- **Cause**: Old variable declaration still present from Phase 4
- **Fix**: Remove lines with `ThreadID currentThread = ...` declarations, use expressions instead

### Compilation hangs
- **Cause**: Usually normal, Verilator is slow
- **Fix**: Wait 5-10 minutes, or increase machine resources

---

## Success Checklist

Before declaring success:

- [ ] Task 1: LoadStoreUnitIF.sv thread fields always defined
- [ ] Task 2: RenameLogicIF.sv has releaseThread field
- [ ] Task 3: ActiveListIF.sv has thread field
- [ ] Task 4: RenameStage.sv wires thread to LoadStoreUnit
- [ ] Task 5: RenameLogic.sv uses releaseThread correctly
- [ ] Task 6: NextPCStage.sv implements round-robin fetch
- [ ] Task 7: LoadQueue.sv compiles with thread routing
- [ ] Task 8: StoreQueue.sv compiles with thread routing
- [ ] Task 9: ActiveList.sv uses port.thread correctly
- [ ] Task 10: TestMain.sv debug access updated
- [ ] Compilation: `make all` produces 0 errors with RSD_ENABLE_SMT=1
- [ ] Verification: `make run` completes baseline test successfully

---

## What Comes Next

Once this is complete:
1. ✅ Phase 4 SMT infrastructure finished
2. 🚀 Phase 5 Multi-threaded testing begins
3. Test framework loads 2 programs simultaneously
4. Measure per-thread performance
5. Validate thread scheduling and isolation

---

## Reference Documents Available

If you get stuck:
- `PHASE4_SMT_COMPLETION_REQUIREMENTS.md` - Detailed technical specs
- `THREAD7_SESSION_SUMMARY.md` - Full analysis
- `PHASE4_SMT_QUICK_REFERENCE.md` - Quick lookup table

---

## Timeline

| Task | Time | Running Total |
|------|------|---------------|
| 1: LoadStoreUnitIF | 5 min | 5 min |
| 2: RenameLogicIF | 5 min | 10 min |
| 3: ActiveListIF | 5 min | 15 min |
| 4: RenameStage | 15 min | 30 min |
| 5: RenameLogic | 30 min | 60 min |
| 6: NextPCStage | 20 min | 80 min |
| 7: LoadQueue | 10 min | 90 min |
| 8: StoreQueue | 10 min | 100 min |
| 9: ActiveList | 20 min | 120 min |
| 10: TestMain | 20 min | 140 min |
| Compilation/test | 30 min | 170 min |
| **TOTAL** | **~2.5-3 hours** | |

---

## You've Got This! 🚀

This is straightforward wiring work. Follow the 10 tasks in order, test along the way, and Phase 4 SMT will be complete.

Then Phase 5 can test multi-threaded execution with:
- 2 threads fetching round-robin
- Instructions in-flight simultaneously
- Per-thread scheduling and resource tracking
- Real multi-threading performance measurement

**Start with Task 1. You're about to complete Phase 4!**
