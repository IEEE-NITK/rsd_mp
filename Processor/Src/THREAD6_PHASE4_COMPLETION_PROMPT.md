# Thread 6: Phase 4 Bug Fixes & Completion

**Objective**: Fix 3 critical blocking bugs and complete Phase 4 verification  
**Estimated Time**: 3-4 hours  
**Difficulty**: MEDIUM (exact specifications provided)  
**Success Criteria**: Baseline test passes with IPC 0.985285, 4621 cycles  

---

## 📋 WHAT WAS DISCOVERED (PREVIOUS THREAD)

Critical Assessment in Thread 5 identified **3 BLOCKING BUGS** preventing Phase 4 completion:

### BUG #1: LoadStoreUnitIF Missing Thread Signals
**Severity**: CRITICAL  
**Impact**: Load/Store queues cannot route allocations to correct thread  
**File**: `LoadStoreUnitIF.sv`  
**Cause**: Interface doesn't provide `ThreadID allocateLoadQueueThread[RENAME_WIDTH]`

### BUG #2: LoadQueue Wrong Thread Routing
**Severity**: CRITICAL  
**Impact**: Thread 1 allocations go to Thread 0 queue  
**File**: `LoadQueue.sv` (Line 88)  
**Cause**: Uses `port.thread[0]` only for all allocations

### BUG #3: StoreQueue Wrong Thread Routing
**Severity**: CRITICAL  
**Impact**: Thread 1 allocations go to Thread 0 queue  
**File**: `StoreQueue.sv` (Line 104)  
**Cause**: Uses `port.thread[0]` only for all allocations

---

## 🎯 YOUR MISSION

### Phase 1: Fix LoadStoreUnitIF.sv (30 minutes)

**Read These Files First**:
1. `PHASE4_FIXES_REQUIRED.md` - Section "Phase 4A"
2. `PHASE4_QUICK_REFERENCE_CARD.md` - File 1 section

**What to Do**:

Open: `/Users/kushal/rsd_mp/Processor/Src/LoadStoreUnit/LoadStoreUnitIF.sv`

**Change 1** - After line 27, add (inside ifdef RSD_ENABLE_SMT):
```systemverilog
`ifdef RSD_ENABLE_SMT
    ThreadID allocateLoadQueueThread [ RENAME_WIDTH ];
    ThreadID allocateStoreQueueThread [ RENAME_WIDTH ];
`endif
```

**Change 2** - Replace lines 76-78 with:
```systemverilog
`ifdef RSD_ENABLE_SMT
    StoreQueueIndexPath storeQueueHeadPtr[THREAD_NUM];
    StoreQueueCountPath storeQueueCount[THREAD_NUM];
    LoadQueueIndexPath loadQueueHeadPtr[THREAD_NUM];
`else
    StoreQueueIndexPath storeQueueHeadPtr;
    StoreQueueCountPath storeQueueCount;
    LoadQueueIndexPath loadQueueHeadPtr;
`endif
```

**Change 3** - After line 81, add:
```systemverilog
`ifdef RSD_ENABLE_SMT
    input LoadQueueIndexPath loadQueueRecoveryTailPtr[THREAD_NUM];
    input StoreQueueIndexPath storeQueueRecoveryTailPtr[THREAD_NUM];
`else
    input LoadQueueIndexPath loadQueueRecoveryTailPtr;
    input StoreQueueIndexPath storeQueueRecoveryTailPtr;
`endif
```

**Verify**:
- [ ] All changes applied
- [ ] All ifdef/else/endif properly paired
- [ ] No syntax errors visible
- [ ] Save file

---

### Phase 2: Fix LoadQueue.sv (45 minutes)

**Read These Files First**:
1. `PHASE4_FIXES_REQUIRED.md` - Section "Phase 4B"
2. `PHASE4_QUICK_REFERENCE_CARD.md` - File 2 section

**What to Do**:

Open: `/Users/kushal/rsd_mp/Processor/Src/LoadStoreUnit/LoadQueue.sv`

**Fix Location 1** - Lines 85-108 (the critical allocation logic)

**Delete** lines 85-108 and replace with:

```systemverilog
always_comb begin
    // Generate push signals - route each allocation to its correct thread
`ifdef RSD_ENABLE_SMT
    // Initialize all push counts to 0
    for (int t = 0; t < THREAD_NUM; t++) begin
        pushCount[t] = 0;
    end
    
    // Route each allocation to its correct thread
    for (int i = 0; i < RENAME_WIDTH; i++) begin
        ThreadID targetThread = port.allocateLoadQueueThread[i];
        
        if (tailPtr[targetThread] + pushCount[targetThread] < LOAD_QUEUE_ENTRY_NUM) begin
            port.allocatedLoadQueuePtr[i] = tailPtr[targetThread] + pushCount[targetThread];
        end else begin
            port.allocatedLoadQueuePtr[i] = 
                tailPtr[targetThread] + pushCount[targetThread] - LOAD_QUEUE_ENTRY_NUM;
        end
        pushCount[targetThread] += port.allocateLoadQueue[i];
    end
    
    // Generate push signals
    for (int t = 0; t < THREAD_NUM; t++) begin
        push[t] = pushCount[t] > 0;
    end

    // Check allocatable - any thread can allocate?
    port.loadQueueAllocatable = FALSE;
    for (int t = 0; t < THREAD_NUM; t++) begin
        if (curCount[t] <= LOAD_QUEUE_ENTRY_NUM - RENAME_WIDTH - 1) begin
            port.loadQueueAllocatable = TRUE;
        end
    end

    recovery.loadQueueHeadPtr[0] = headPtr[0];
    recovery.loadQueueHeadPtr[1] = headPtr[1];

`else
    // Single-threaded version (original code)
    pushCount = 0;
    for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
        if (tailPtr + pushCount < LOAD_QUEUE_ENTRY_NUM) begin
            port.allocatedLoadQueuePtr[i] = tailPtr + pushCount;
        end
        else begin
            // Out of range of load queue
            port.allocatedLoadQueuePtr[i] = 
                tailPtr + pushCount - LOAD_QUEUE_ENTRY_NUM;
        end
        pushCount += port.allocateLoadQueue[i];
    end
    push = pushCount > 0;

    // All entries are not used for avoiding head==tail problem.
    port.loadQueueAllocatable =
        (curCount <= LOAD_QUEUE_ENTRY_NUM - RENAME_WIDTH - 1) ? TRUE : FALSE;

    recovery.loadQueueHeadPtr = headPtr;
`endif
end
```

**Fix Location 2** - Line 154 (execution stage)

Find the line with: `ThreadID currentThread = port.thread[0];` in the execution logic  
Replace with per-thread execution routing (similar pattern to allocation)

**Verify**:
- [ ] Lines 85-108 completely replaced
- [ ] All ifdef/else/endif present
- [ ] Line 154 updated
- [ ] Save file

---

### Phase 3: Fix StoreQueue.sv (45 minutes)

**Read These Files First**:
1. `PHASE4_FIXES_REQUIRED.md` - Section "Phase 4C"
2. `PHASE4_QUICK_REFERENCE_CARD.md` - File 3 section

**What to Do**:

Open: `/Users/kushal/rsd_mp/Processor/Src/LoadStoreUnit/StoreQueue.sv`

**Fix Location 1** - Lines 102-119 (the critical allocation logic)

**Delete** lines 102-119 and replace with:

```systemverilog
always_comb begin
`ifdef RSD_ENABLE_SMT
    // Initialize all push counts to 0
    for (int t = 0; t < THREAD_NUM; t++) begin
        pushCount[t] = 0;
    end
    
    // Route each allocation to its correct thread
    for (int i = 0; i < RENAME_WIDTH; i++) begin
        ThreadID targetThread = port.allocateStoreQueueThread[i];
        
        if (tailPtr[targetThread] + pushCount[targetThread] < STORE_QUEUE_ENTRY_NUM) begin
            port.allocatedStoreQueuePtr[i] = tailPtr[targetThread] + pushCount[targetThread];
        end else begin
            port.allocatedStoreQueuePtr[i] = 
                tailPtr[targetThread] + pushCount[targetThread] - STORE_QUEUE_ENTRY_NUM;
        end
        pushCount[targetThread] += port.allocateStoreQueue[i];
    end
    
    // Generate push signals
    for (int t = 0; t < THREAD_NUM; t++) begin
        push[t] = pushCount[t] > 0;
    end

    // Check allocatable - any thread can allocate?
    port.storeQueueAllocatable = FALSE;
    for (int t = 0; t < THREAD_NUM; t++) begin
        if (curCount[t] <= STORE_QUEUE_ENTRY_NUM - RENAME_WIDTH - 1) begin
            port.storeQueueAllocatable = TRUE;
        end
    end
    
    port.storeQueueCount = curCount[0];  // TBD: Could be per-thread in future
    port.storeQueueEmpty = (curCount[0] == 0) && (curCount[1] == 0);

    recovery.storeQueueHeadPtr[0] = headPtr[0];
    recovery.storeQueueHeadPtr[1] = headPtr[1];

`else
    // Single-threaded version (original)
    pushCount = 0;
    for (int i = 0; i < RENAME_WIDTH; i++) begin
        if (tailPtr + pushCount < STORE_QUEUE_ENTRY_NUM) begin
            port.allocatedStoreQueuePtr[i] = tailPtr + pushCount;
        end
        else begin
            // Out of range of store queue
            port.allocatedStoreQueuePtr[i] = 
                tailPtr + pushCount - STORE_QUEUE_ENTRY_NUM;
        end
        pushCount += port.allocateStoreQueue[i];
    end
    push = pushCount > 0;

    port.storeQueueCount = curCount;
    port.storeQueueAllocatable =
        (curCount <= STORE_QUEUE_ENTRY_NUM - RENAME_WIDTH - 1) ? TRUE : FALSE;
    port.storeQueueEmpty = curCount == 0;

    recovery.storeQueueHeadPtr = headPtr;
`endif
end
```

**Fix Location 2** - Line 183 (execution stage)

Find the line with: `ThreadID currentThread = port.thread[0];` in the execution logic  
Replace with per-thread execution routing

**Verify**:
- [ ] Lines 102-119 completely replaced
- [ ] All ifdef/else/endif present
- [ ] Line 183 updated
- [ ] Save file

---

### Phase 4: Wire RenameStage.sv (15 minutes)

**Read These Files First**:
1. `PHASE4_FIXES_REQUIRED.md` - Section "Phase 4D"
2. `PHASE4_QUICK_REFERENCE_CARD.md` - File 4 section

**What to Do**:

Open: `/Users/kushal/rsd_mp/Processor/Src/Pipeline/RenameStage.sv`

**Fix Location** - Lines 337-343

**Replace**:
```systemverilog
for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
    loadStoreUnit.allocateLoadQueue[i] = update[i] && isLoad[i];
    loadStoreUnit.allocateStoreQueue[i] = update[i] && isStore[i];

    nextStage[i].loadQueuePtr = loadStoreUnit.allocatedLoadQueuePtr[i];
    nextStage[i].storeQueuePtr = loadStoreUnit.allocatedStoreQueuePtr[i];
end
```

**With**:
```systemverilog
for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
    loadStoreUnit.allocateLoadQueue[i] = update[i] && isLoad[i];
    loadStoreUnit.allocateStoreQueue[i] = update[i] && isStore[i];

`ifdef RSD_ENABLE_SMT
    loadStoreUnit.allocateLoadQueueThread[i] = pipeReg[i].thread;
    loadStoreUnit.allocateStoreQueueThread[i] = pipeReg[i].thread;
`endif

    nextStage[i].loadQueuePtr = loadStoreUnit.allocatedLoadQueuePtr[i];
    nextStage[i].storeQueuePtr = loadStoreUnit.allocatedStoreQueuePtr[i];
end
```

**Verify**:
- [ ] Signal assignments added correctly
- [ ] ifdef block present and complete
- [ ] Save file

---

### Phase 5: Compile & Test (30 minutes)

**Compilation**:
```bash
cd /Users/kushal/rsd_mp/Processor/Src
rm -rf ../Project/Verilator/obj_dir
make -j4 all 2>&1 | tail -30
```

**Expected Result**:
- Last line: `==== Build Successful ====`
- Zero compilation errors
- Zero new warnings

**If Compilation Fails**:
1. Read error message carefully
2. Check that all changes were applied
3. Verify all ifdef/else/endif blocks are balanced
4. Look for typos in signal names
5. Re-read PHASE4_FIXES_REQUIRED.md for exact syntax

**Baseline Test**:
```bash
make run 2>&1 | grep "IPC\|Elapsed"
```

**Expected Output**:
```
IPC (RISC-V instruction): 0.985285
Elapsed cycles:        4621
```

**If Test Fails**:
1. Check compilation output for warnings
2. Verify all 4 files have all changes applied
3. Check for typos in thread signal names (case-sensitive!)
4. Re-compile from scratch: `make clean && make all`
5. If still failing, check THREAD5_EXECUTIVE_SUMMARY.md troubleshooting section

---

### Phase 6: Documentation (1 hour - Optional)

If time permits, create these files:

**File 1**: `PHASE4_COMPLETION_SUMMARY.md`
- What was implemented
- What bugs were fixed
- Verification results
- Ready for Phase 5

**File 2**: `PHASE4_QUICK_START.md`
- Quick reference for Phase 4 implementation
- How to enable SMT
- What changed and what didn't

**File 3**: Update `DOCUMENTATION_INDEX.md`
- Add Phase 4 section
- Link to all Phase 4 documents

---

## ✅ SUCCESS CHECKLIST

Before moving to Phase 5, verify ALL of these:

**Code Changes**:
- [ ] LoadStoreUnitIF.sv - All 3 changes applied
- [ ] LoadQueue.sv - Lines 85-108 replaced + Line 154 fixed
- [ ] StoreQueue.sv - Lines 102-119 replaced + Line 183 fixed
- [ ] RenameStage.sv - Lines 337-343 updated with thread signals

**Syntax Verification**:
- [ ] All ifdef/else/endif blocks balanced
- [ ] No mismatched quotes or brackets
- [ ] All signal names spelled correctly
- [ ] Indentation consistent

**Compilation**:
- [ ] Compilation succeeds
- [ ] Zero errors in output
- [ ] Zero new warnings
- [ ] "Build Successful" message appears

**Functional Verification**:
- [ ] Baseline test runs without crashing
- [ ] IPC exactly 0.985285
- [ ] Elapsed cycles exactly 4621
- [ ] No warnings during test execution

**Documentation** (Optional):
- [ ] Phase 4 completion summary created (if time permits)
- [ ] DOCUMENTATION_INDEX.md updated (if time permits)

---

## 🚨 CRITICAL NOTES

### DO THIS
✅ Apply changes EXACTLY as specified  
✅ Verify all changes before testing  
✅ Compile cleanly before baseline test  
✅ Match exact line numbers and code  
✅ Use provided code examples exactly  

### DON'T DO THIS
❌ Don't modify non-SMT (else) paths  
❌ Don't skip any of the 4 files  
❌ Don't assume signals exist before applying interface changes  
❌ Don't change anything except what's specified  
❌ Don't skip the baseline test  

### IF STUCK
1. Re-read PHASE4_FIXES_REQUIRED.md (detailed version)
2. Check PHASE4_QUICK_REFERENCE_CARD.md (syntax examples)
3. Look at PHASE4_CRITICAL_ASSESSMENT.md (understanding)
4. Verify line numbers match current file (lines may have shifted)

---

## 📈 EXPECTED TIMELINE

| Task | Time | Blocker |
|------|------|---------|
| LoadStoreUnitIF.sv | 30 min | YES |
| LoadQueue.sv | 45 min | YES |
| StoreQueue.sv | 45 min | YES |
| RenameStage.sv | 15 min | YES |
| Compilation & test | 30 min | YES |
| Documentation | 60 min | NO |
| **TOTAL** | **245 min** | **4 hours max** |

---

## 🎯 AFTER PHASE 4 COMPLETION

Once baseline test passes and all changes verified:

1. You have completed Phase 4 ✅
2. Ready to proceed to Phase 5: Multi-threaded testing
3. Phase 5 will use the verified baseline: IPC 0.985285, 4621 cycles
4. Next goal: Run 2 threads simultaneously and measure performance

---

## 📞 REFERENCE FILES

All needed for context:
- `PHASE4_CRITICAL_ASSESSMENT.md` - Deep understanding of bugs
- `PHASE4_FIXES_REQUIRED.md` - Exact fix specifications
- `PHASE4_QUICK_REFERENCE_CARD.md` - Quick syntax reference
- `PHASE4_STATUS_ASSESSMENT.md` - Progress tracking
- `THREAD5_EXECUTIVE_SUMMARY.md` - Overview and troubleshooting

---

## 🏁 FINAL GOAL

**Phase 4 is DONE when**:
- [x] Implementation complete (from Thread 5)
- [ ] All 3 bugs fixed (this thread)
- [ ] Code compiles with 0 errors, 0 warnings
- [ ] Baseline test passes: IPC 0.985285, 4621 cycles
- [ ] Ready for Phase 5

**You have everything you need.** This is achievable in 3-4 hours with the exact specifications provided.

---

**Status**: READY TO EXECUTE  
**Confidence**: HIGH  
**Next Phase**: Phase 5 Multi-threaded Testing  

**Let's finish Phase 4 and move on to Phase 5! 🚀**
