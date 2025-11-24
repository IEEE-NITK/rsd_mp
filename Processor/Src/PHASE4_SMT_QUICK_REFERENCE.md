# Phase 4 SMT - Quick Reference Card for Next Session

## TL;DR
Phase 5 blocked. Phase 4 SMT needs 2.5-3 hours of wiring fixes. Follow the 10-step plan below.

---

## The 10 Tasks (2.5-3 Hours Total)

### ✏️ Task 1: LoadStoreUnitIF.sv (5 min)
**File**: `/Users/kushal/rsd_mp/Processor/Src/LoadStoreUnit/LoadStoreUnitIF.sv`

**Change**: Lines 20-32, remove ifdef, always define thread fields

```systemverilog
// OLD (lines 20-32):
logic allocateLoadQueue [ RENAME_WIDTH ];
logic allocateStoreQueue [ RENAME_WIDTH ];
LoadQueueIndexPath allocatedLoadQueuePtr [ RENAME_WIDTH ];
StoreQueueIndexPath allocatedStoreQueuePtr [ RENAME_WIDTH ];

`ifdef RSD_ENABLE_SMT
    ThreadID allocateLoadQueueThread [ RENAME_WIDTH ];
    ThreadID allocateStoreQueueThread [ RENAME_WIDTH ];
`endif

// NEW (always define):
logic allocateLoadQueue [ RENAME_WIDTH ];
logic allocateStoreQueue [ RENAME_WIDTH ];
LoadQueueIndexPath allocatedLoadQueuePtr [ RENAME_WIDTH ];
StoreQueueIndexPath allocatedStoreQueuePtr [ RENAME_WIDTH ];

ThreadID allocateLoadQueueThread [ RENAME_WIDTH ];
ThreadID allocateStoreQueueThread [ RENAME_WIDTH ];
ThreadID thread [ COMMIT_WIDTH ];  // For execution context
```

---

### ✏️ Task 2: RenameLogicIF.sv (5 min)
**File**: Need to find/check this interface file

**Change**: Add `ThreadID releaseThread[COMMIT_WIDTH]` to indicate which thread is retiring

---

### ✏️ Task 3: ActiveListIF.sv (5 min)
**File**: Need to find/check this interface file

**Change**: Add `ThreadID thread[RENAME_WIDTH]` for per-thread operations

---

### ✏️ Task 4: RenameStage.sv (15 min)
**File**: `/Users/kushal/rsd_mp/Processor/Src/Pipeline/RenameStage.sv` around lines 342-343

**Current**:
```systemverilog
loadStoreUnit.allocateLoadQueueThread[i] = pipeReg[i].thread;
loadStoreUnit.allocateStoreQueueThread[i] = pipeReg[i].thread;
```

**Status**: Already coded, just need to verify it compiles correctly after Task 1

---

### ✏️ Task 5: RenameLogic.sv (30 min)
**File**: `/Users/kushal/rsd_mp/Processor/Src/RenameLogic/RenameLogic.sv`

**Issue**: Line 284+ uses `port.releaseThread[i]` which doesn't exist

**Fix**: Add `releaseThread` to interface (Task 2), then this code will work

**Expected code pattern**:
```systemverilog
for (int i = 0; i < COMMIT_WIDTH; i++) begin
    if (port.release[i]) begin
        // Use port.releaseThread[i] to identify thread
        // Return physical reg to that thread's free list
    end
end
```

---

### ✏️ Task 6: NextPCStage.sv (20 min)
**File**: `/Users/kushal/rsd_mp/Processor/Src/Pipeline/FetchStage/NextPCStage.sv` around line 238

**Issue**: `fetchThread` variable undefined (line 238: `nextStage[i].thread = fetchThread;`)

**Fix**: Implement round-robin thread selection

```systemverilog
// Add this logic:
`ifdef RSD_ENABLE_SMT
    // Simple round-robin: toggle between threads
    logic threadToggle;  // Track which thread to fetch from
    
    always_ff @(posedge clk) begin
        if (rst) threadToggle <= 0;
        else threadToggle <= ~threadToggle;
    end
    
    // Use toggle to select thread
    logic [THREAD_ID_BIT_WIDTH-1:0] fetchThread;
    assign fetchThread = threadToggle;  // 0 = Thread 0, 1 = Thread 1
    
    // Tag each fetched instruction
    for (int i = 0; i < FETCH_WIDTH; i++) begin
        nextStage[i].thread = fetchThread;
    end
`endif
```

---

### ✏️ Task 7: LoadQueue.sv (10 min)
**File**: `/Users/kushal/rsd_mp/Processor/Src/LoadStoreUnit/LoadQueue.sv`

**Status**: Code already has thread routing, just verify it compiles after Task 1

**Lines to check**: 95, 96, 99, 101 (already fixed to use expressions instead of variable declarations)

---

### ✏️ Task 8: StoreQueue.sv (10 min)
**File**: `/Users/kushal/rsd_mp/Processor/Src/LoadStoreUnit/StoreQueue.sv`

**Status**: Same as LoadQueue - already modified, just verify

**Lines to check**: 111-117 (thread routing), 195-205 (thread context usage)

---

### ✏️ Task 9: ActiveList.sv (20 min)
**File**: `/Users/kushal/rsd_mp/Processor/Src/RenameLogic/ActiveList.sv`

**Changes Needed**:
1. Fix line 103-104 to use `port.thread[0]` for allocatable check
2. Fix line 115 to check thread membership
3. Fix line 348 to use `port.thread[0]`
4. Other per-thread operations using `port.thread`

**Pattern**: Already partially fixed. Verify all uses of thread-indexed arrays work.

---

### ✏️ Task 10: TestMain.sv (20 min)
**File**: `/Users/kushal/rsd_mp/Processor/Src/Verification/TestMain.sv`

**Issue**: Line 76 references changed internal structure
```
alHead = main.main.core.activeList.activeList.debugValue[ alHeadPtr ];
```

**Fix**: Update to match new ActiveList structure (may need to adjust path or iterate per-thread)

**Note**: This is for debug output, not critical for functionality, but good to fix

---

## Compilation Test Procedure

After each task (or every 2 tasks):
```bash
cd /Users/kushal/rsd_mp/Processor/Src

# Clean build
rm -rf ../Project/Verilator/obj_dir
make all 2>&1 | grep "^%Error" | wc -l

# Track progress:
# Start: 43 errors
# After 1-3: 35-40 errors
# After 4-6: 20-30 errors  
# After 7-10: <5 errors
# Final: 0 errors ✅
```

## Final Verification
```bash
# Enable SMT
# Edit: Makefiles/CoreSources.inc.mk
# Uncomment: +define+RSD_ENABLE_SMT

# Compile with SMT enabled
make all  # Should see: ==== Build Successful ====

# Run baseline test
make run  # Should complete without errors
```

---

## File Checklist

- [ ] Task 1: LoadStoreUnitIF.sv - thread fields always defined
- [ ] Task 2: RenameLogicIF.sv - releaseThread added
- [ ] Task 3: ActiveListIF.sv - thread field added
- [ ] Task 4: RenameStage.sv - thread wiring verified
- [ ] Task 5: RenameLogic.sv - register release per-thread
- [ ] Task 6: NextPCStage.sv - round-robin fetch implemented
- [ ] Task 7: LoadQueue.sv - verified compiles
- [ ] Task 8: StoreQueue.sv - verified compiles
- [ ] Task 9: ActiveList.sv - per-thread ops fixed
- [ ] Task 10: TestMain.sv - debug access updated
- [ ] Compilation test - 0 errors with RSD_ENABLE_SMT=1 ✅

---

## Key Concept Reminder

**SMT = Interleaved Execution**
- Fetch: Round-robin from Thread 0, Thread 1, Thread 0, Thread 1, ...
- Pipeline: Both threads' instructions in-flight simultaneously
- Execute: One instruction at a time (still sequential execution)
- Commit: Both threads' results committed sequentially

This means:
✅ Two instruction streams blended in pipeline  
❌ NOT truly parallel (one execution unit per instruction)  
✅ Better utilization when one thread stalls  
✅ Can measure per-thread performance

---

## Common Pitfalls to Avoid

1. **Don't use `ThreadID var = ...` in always_comb** - Use expressions instead
2. **Don't keep `#ifdef` in interface definitions** - Always define fields
3. **Don't forget thread field in every interface** - Add to all relevant IFs
4. **Don't skip debug updates** - TestMain.sv helps verify wiring

---

## Time Estimate Breakdown

| Task | Time |
|------|------|
| 1-3: Interface updates | 15 min |
| 4-6: Pipeline wiring | 55 min |
| 7-9: Queue/List updates | 40 min |
| 10: Debug updates | 20 min |
| Testing/troubleshooting | 30 min |
| **Total** | **2.5-3 hours** |

---

## Success Criteria

✅ RSD_ENABLE_SMT=1, `make all` returns 0 errors  
✅ `make run` completes baseline test successfully  
✅ IPC still ~0.985 (no regression)  
✅ Multi-threading infrastructure wired correctly  

Then: **Proceed with Phase 5 Multi-Threaded Testing**

---

## Questions Before Starting?

If anything is unclear:
1. Check PHASE4_SMT_COMPLETION_REQUIREMENTS.md for detailed explanation
2. Check THREAD7_SESSION_SUMMARY.md for technical analysis
3. Each task error category has detailed fix specification

---

**Ready to fix Phase 4? Let's complete SMT infrastructure! 🚀**
