# Phase 4 Quick Reference Card

**Status**: 3 Critical Bugs Found - Fixes Ready  
**Time to Fix**: 2.5 hours  
**Difficulty**: MEDIUM  

---

## 🎯 THE SITUATION (In 2 Minutes)

### What Works ✅
- All 5 resources implemented per-thread correctly
- Thread ID propagation complete
- Architecture sound

### What's Broken ❌
- LoadStoreUnitIF missing thread signals
- LoadQueue uses wrong thread for all allocations
- StoreQueue uses wrong thread for all allocations

### Why It Matters
Multi-threaded loads/stores get routed to wrong queues → data corruption

### How to Fix
Apply 4 changes to 4 files (exactly as specified below)

---

## 🔧 QUICK FIX GUIDE

### File 1: LoadStoreUnitIF.sv

**Location**: Lines 24-28 and Lines 76-78

**Change 1 - Add thread signals** (after line 27):
```systemverilog
`ifdef RSD_ENABLE_SMT
ThreadID allocateLoadQueueThread [ RENAME_WIDTH ];
ThreadID allocateStoreQueueThread [ RENAME_WIDTH ];
`endif
```

**Change 2 - Make queue status per-thread** (replace lines 76-78):
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

**Change 3 - Add recovery pointers** (after line 81):
```systemverilog
`ifdef RSD_ENABLE_SMT
input LoadQueueIndexPath loadQueueRecoveryTailPtr[THREAD_NUM];
input StoreQueueIndexPath storeQueueRecoveryTailPtr[THREAD_NUM];
`else
input LoadQueueIndexPath loadQueueRecoveryTailPtr;
input StoreQueueIndexPath storeQueueRecoveryTailPtr;
`endif
```

---

### File 2: LoadQueue.sv

**Location**: Lines 85-108 (and line 154)

**Key Change** - Rewrite allocation logic:

```systemverilog
// OLD (WRONG):
ThreadID currentThread = port.thread[0];
pushCount[currentThread] = 0;
for (int i = 0; i < RENAME_WIDTH; i++) begin
    if (tailPtr[currentThread] + pushCount[currentThread] < LOAD_QUEUE_ENTRY_NUM) ...
    pushCount[currentThread] += port.allocateLoadQueue[i];
end

// NEW (CORRECT):
for (int t = 0; t < THREAD_NUM; t++) pushCount[t] = 0;
for (int i = 0; i < RENAME_WIDTH; i++) begin
    ThreadID targetThread = port.allocateLoadQueueThread[i];  // Use per-allocation thread
    if (tailPtr[targetThread] + pushCount[targetThread] < LOAD_QUEUE_ENTRY_NUM) begin
        port.allocatedLoadQueuePtr[i] = tailPtr[targetThread] + pushCount[targetThread];
    end else begin
        port.allocatedLoadQueuePtr[i] = tailPtr[targetThread] + pushCount[targetThread] - LOAD_QUEUE_ENTRY_NUM;
    end
    pushCount[targetThread] += port.allocateLoadQueue[i];
end
for (int t = 0; t < THREAD_NUM; t++) push[t] = pushCount[t] > 0;
```

**Also fix** line 106 (allocatable check) to check all threads instead of one.

---

### File 3: StoreQueue.sv

**Location**: Lines 102-119 (and line 183)

**Key Change** - Same as LoadQueue (use port.allocateStoreQueueThread[i] instead of port.thread[0])

Replace:
```systemverilog
ThreadID currentThread = port.thread[0];
pushCount[currentThread] = 0;
```

With:
```systemverilog
for (int t = 0; t < THREAD_NUM; t++) pushCount[t] = 0;
for (int i = 0; i < RENAME_WIDTH; i++) begin
    ThreadID targetThread = port.allocateStoreQueueThread[i];  // Use per-allocation thread
    // ... (rest of logic same as LoadQueue)
end
```

---

### File 4: RenameStage.sv

**Location**: Lines 337-343

**Change** - Wire thread signals:

```systemverilog
// OLD:
for (int i = 0; i < RENAME_WIDTH; i++) begin
    loadStoreUnit.allocateLoadQueue[i] = update[i] && isLoad[i];
    loadStoreUnit.allocateStoreQueue[i] = update[i] && isStore[i];
end

// NEW:
for (int i = 0; i < RENAME_WIDTH; i++) begin
    loadStoreUnit.allocateLoadQueue[i] = update[i] && isLoad[i];
    loadStoreUnit.allocateStoreQueue[i] = update[i] && isStore[i];
`ifdef RSD_ENABLE_SMT
    loadStoreUnit.allocateLoadQueueThread[i] = pipeReg[i].thread;
    loadStoreUnit.allocateStoreQueueThread[i] = pipeReg[i].thread;
`endif
end
```

---

## ✅ VERIFICATION CHECKLIST

After applying fixes:

```bash
# 1. Clean compile
cd /Users/kushal/rsd_mp/Processor/Src
rm -rf ../Project/Verilator/obj_dir
make -j4 all 2>&1 | tail -5

# Expected: "Build Successful" with 0 errors, 0 new warnings

# 2. Run baseline test
make run 2>&1 | grep "IPC\|Elapsed"

# Expected output:
# IPC (RISC-V instruction): 0.985285
# Elapsed cycles:        4621
```

---

## 📋 CHANGE SUMMARY

| File | Lines | Change | Type |
|------|-------|--------|------|
| LoadStoreUnitIF.sv | 28, 76-78, 82 | Add thread signals | Interface |
| LoadQueue.sv | 85-108, 154 | Fix thread routing | Logic |
| StoreQueue.sv | 102-119, 183 | Fix thread routing | Logic |
| RenameStage.sv | 341-342 | Wire signals | Connection |

**Total Lines Changed**: ~100 lines (mostly LoadQueue/StoreQueue)  
**Total Files Modified**: 4 files  
**Estimated Time**: 2.5 hours total  

---

## 🚨 CRITICAL POINTS

### Don't Forget
1. ✅ Make changes to ALL 4 files (not just LoadQueue)
2. ✅ Add ifdef blocks around all SMT-specific code
3. ✅ Wire thread signals in RenameStage (easy to forget)
4. ✅ Test compilation before baseline test

### Don't Do This
1. ❌ Don't change non-SMT (else) paths
2. ❌ Don't assume signals exist before checking
3. ❌ Don't skip the baseline test after fixing
4. ❌ Don't proceed to Phase 5 without verified baseline

---

## 📞 IF STUCK

**Compilation error**:
- Check LoadStoreUnitIF.sv changes were applied
- Verify all ifdef/else/endif blocks are balanced
- Look at error message - usually points to missing signal

**Baseline test doesn't match**:
- Run again (might be random variation)
- Check console output for any warnings
- Recompile from scratch if unsure

**Thread signal not found**:
- Verify RenameStage.sv changes applied
- Check signal names match exactly (case sensitive)
- Verify ifdef blocks match other signals

**Lost or confused**:
- Read PHASE4_FIXES_REQUIRED.md (detailed version)
- Read PHASE4_CRITICAL_ASSESSMENT.md (understanding)
- Check exact line numbers and code examples

---

## 🎯 EXPECTED RESULTS

**After fixes applied**:
```
✅ Compilation: Success (0 errors, 0 warnings)
✅ Baseline: IPC 0.985285, 4621 cycles
✅ Thread routing: Each thread allocates to own queue
✅ Ready for Phase 5: Multi-threaded testing
```

---

## ⏱️ TIME BREAKDOWN

- LoadStoreUnitIF.sv edits: 10 min
- LoadQueue.sv edits: 20 min
- StoreQueue.sv edits: 20 min
- RenameStage.sv edits: 5 min
- Compilation & test: 30 min
- Debugging (if needed): 30 min (hopefully 0)
- **Total: 2-2.5 hours**

---

## 🚀 NEXT AFTER THIS

Once baseline verified:
1. Create Phase 4 completion documents (optional, can skip)
2. Begin Phase 5: Multi-threaded test framework
3. Estimated Phase 5: 7-8 hours for 2-thread testing

---

**Print this page and keep it handy while making fixes**

Good luck! 🚀
