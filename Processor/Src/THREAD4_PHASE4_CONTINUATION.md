# Thread 4: Phase 4 Implementation Continuation

**Previous Status**: Bypass network thread safety fix COMPLETE ✅  
**Current Baseline**: IPC 0.985285, 4621 cycles (VERIFIED MAINTAINED)  
**Time Available**: ~6 hours  
**Objective**: Implement per-thread resource allocation (Free Lists, Active List, Issue Queue, Load/Store Queues)  

---

## 🎯 YOUR MISSION

Implement 5 per-thread resource allocators in this exact order:

1. **Free Lists** (Scalar & FP) - 45 min
2. **Active List** - 60 min  
3. **Issue Queue** - 90 min
4. **Load Queue** - 60 min
5. **Store Queue** - 60 min

**Success Criteria**: All 5 implemented, baseline maintained (IPC 0.985285, 4621 cycles)

---

## 📋 QUICK REFERENCE: THE PATTERN

From RenameLogic/RMT.sv (lines 41-185), every resource follows this exact structure:

```systemverilog
`ifdef RSD_ENABLE_SMT
    // ========== MULTI-THREADED VERSION ==========
    // Per-thread arrays
    SomeEntry data[THREAD_NUM][SIZE];
    SomeIndex ptr[THREAD_NUM];
    
    // Per-thread logic (outer loop over threads)
    for (int t = 0; t < THREAD_NUM; t++) begin
        // Per-thread write logic
        for (int i = 0; i < WRITE_WIDTH; i++) begin
            // CRITICAL: Check thread matches
            we[t][i] = weIn[i] && (port.thread[i] == t);
            wa[t][i] = weIn[i];
            wv[t][i] = weIn[i];
        end
        
        // Per-thread read logic
        for (int i = 0; i < READ_WIDTH; i++) begin
            ra[t][i] = raIn[i];
        end
    end
    
    // Thread-aware outputs (extract thread once)
    for (int i = 0; i < READ_WIDTH; i++) begin
        ThreadID threadID = port.thread[i];
        rv[threadID][i] = data[threadID][ra[threadID][i]];
        
        // CRITICAL: Only bypass within same thread
        for (int j = 0; j < i; j++) begin
            if (port.writeThread[j] == threadID) begin
                if (port.writeAddr[j] == port.readAddr[i]) begin
                    rv[threadID][i] = port.writeValue[j];
                end
            end
        end
    end

`else
    // ========== SINGLE-THREADED VERSION (ORIGINAL - UNCHANGED) ==========
    // Copy original code exactly here
    SomeEntry data[SIZE];
    SomeIndex ptr;
    // ... rest of original code unchanged ...
`endif
```

**The 5 Critical Rules:**
1. ✅ Thread check for writes: `we[t][i] = weIn[i] && (port.thread[i] == t);`
2. ✅ Extract thread once: `ThreadID threadID = port.thread[i];`
3. ✅ Bypass same thread only: `if (port.thread[j] == threadID)`
4. ✅ Preserve original in else: Copy original logic unchanged
5. ✅ Loop structure: Outer loop for THREAD_NUM, inner for WIDTH

---

## 📝 IMPLEMENTATION ORDER & CHECKLIST

### RESOURCE 1: Free Lists (45 minutes)

**File**: `/Users/kushal/rsd_mp/Processor/Src/RenameLogic/RenameLogic.sv`

**What to do**:
```
[ ] Open RenameLogic.sv
[ ] Find scalarFreeList instantiation (around line 43-60)
[ ] Find scalarFPFreeList instantiation (around line 63-81)
[ ] Wrap both with `ifdef RSD_ENABLE_SMT / else / endif`
[ ] In ifdef block, create array of free lists: scalarFreeList[THREAD_NUM]
[ ] In ifdef block, create array of free lists: scalarFPFreeList[THREAD_NUM]
[ ] Copy original instantiation to else block unchanged
[ ] Update allocation logic (line ~55, 75) to select correct thread's free list
[ ] Update deallocation logic (line ~58, 78) to select correct thread's free list
[ ] Update count logic (line ~53, 73) to track per-thread counts
[ ] Test: make clean && make all && make run
[ ] Verify: IPC 0.985285, cycles 4621
```

**Key Lines to Modify**:
- Lines 43-81: Free list instantiations
- Lines 49-60: scalarFreeList port connections
- Lines 69-80: scalarFPFreeList port connections
- Line 159: Allocatable check (update to use per-thread counts)

**Result After**:
```
scalarFreeList[THREAD_NUM] - one allocator per thread for scalar regs
scalarFPFreeList[THREAD_NUM] - one allocator per thread for FP regs
scalarFreeListCount[THREAD_NUM] - track count per thread
scalarFPFreeListCount[THREAD_NUM] - track count per thread
```

---

### RESOURCE 2: Active List (60 minutes)

**File**: `/Users/kushal/rsd_mp/Processor/Src/RenameLogic/ActiveList.sv`

**What to do**:
```
[ ] Open ActiveList.sv
[ ] Read entire file (it's a FIFO with head/tail pointers)
[ ] Find data array (probably around line ~50-80)
[ ] Find head/tail pointer definitions
[ ] Find queue controller (SetTailMultiWidthQueuePointer instantiation)
[ ] Wrap entire data structure and controller with ifdef block
[ ] Create per-thread arrays: activeListEntry[THREAD_NUM][SIZE]
[ ] Create per-thread pointers: headPtr[THREAD_NUM], tailPtr[THREAD_NUM]
[ ] In ifdef block, instantiate queue controller for each thread
[ ] Update write logic (allocation) to use correct thread's pointers
[ ] Update read logic (deallocation) to use correct thread's pointers
[ ] Update recovery logic to handle per-thread head/tail pointers
[ ] Test: make clean && make all && make run
[ ] Verify: IPC 0.985285, cycles 4621
```

**Pattern for FIFO (Variant B from template)**:
```systemverilog
`ifdef RSD_ENABLE_SMT
    ActiveListEntry data[THREAD_NUM][ACTIVE_LIST_SIZE];
    ActiveListIndex headPtr[THREAD_NUM];
    ActiveListIndex tailPtr[THREAD_NUM];
    
    // Per-thread queue controllers
    SetTailMultiWidthQueuePointer #(...) queueCtrl[THREAD_NUM](
        .clk(port.clk),
        .rst(port.rst),
        .pop(port.releaseActiveList),
        .popCount(port.releaseActiveListCount),
        .push(push),
        .pushCount(pushCount),
        .headPtr(headPtr),
        .tailPtr(tailPtr),
        // ... other signals thread-aware
    );
`else
    // Original code unchanged
`endif
```

**Result After**:
```
activeListEntry[THREAD_NUM][SIZE] - FIFO per thread
headPtr[THREAD_NUM] - head pointer per thread
tailPtr[THREAD_NUM] - tail pointer per thread
Queue allocation/deallocation - per-thread aware
```

---

### RESOURCE 3: Issue Queue (90 minutes)

**File**: `/Users/kushal/rsd_mp/Processor/Src/Scheduler/IssueQueue.sv`

**What to do**:
```
[ ] Open IssueQueue.sv
[ ] This is complex: has allocator (MultiWidthFreeList) and payload RAMs
[ ] Read entire file to understand structure
[ ] Find MultiWidthFreeList instantiation (allocator)
[ ] Find DistributedMultiPortRAM instantiations (payload: intPayloadRAM, memPayloadRAM, etc.)
[ ] Wrap BOTH allocator and RAMs with ifdef block
[ ] In ifdef block:
    [ ] Create issueQueueFreeList[THREAD_NUM] - allocator per thread
    [ ] Create intPayloadRAM[THREAD_NUM] - payload RAM per thread
    [ ] Create memPayloadRAM[THREAD_NUM] - payload RAM per thread
    [ ] Create other payload RAMs per thread (complexPayloadRAM, fpPayloadRAM if present)
[ ] Update allocation logic to dispatch to correct thread's free list
[ ] Update read logic to dispatch to correct thread's RAMs
[ ] Update write logic to dispatch to correct thread's RAMs
[ ] Update recovery logic for per-thread pointer recovery
[ ] Test: make clean && make all && make run
[ ] Verify: IPC 0.985285, cycles 4621
```

**Key Structure in IssueQueue**:
- Free list (allocator) at ~line 47-64
- intPayloadRAM at ~line 131-150
- memPayloadRAM at ~line 155-174
- Other RAMs below
- Dispatch selection at ~line 242-245

**Important Note**: Issue queue allocation/dispatch likely checks `selectedPtr` logic. Make sure to route reads/writes based on thread ID.

**Result After**:
```
issueQueueFreeList[THREAD_NUM] - allocator per thread
intPayloadRAM[THREAD_NUM] - payload storage per thread
memPayloadRAM[THREAD_NUM] - payload storage per thread
[other RAMs][THREAD_NUM] - similarly replicated
```

---

### RESOURCE 4: Load Queue (60 minutes)

**File**: `/Users/kushal/rsd_mp/Processor/Src/LoadStoreUnit/LoadQueue.sv`

**Prerequisites**:
- [ ] Must first update LoadStoreUnitIF.sv to add thread signals

**Update LoadStoreUnitIF.sv**:
```
[ ] Open LoadStoreUnitIF.sv
[ ] Find LoadQueue interface section (around line 100-150)
[ ] Add thread ID signals:
    input ThreadID executeLoadThread[LOAD_ISSUE_WIDTH];
    input ThreadID allocateLoadQueueThread[RENAME_WIDTH];
[ ] Update recovery section for per-thread pointers:
    input LoadQueueIndexPath loadQueueRecoveryTailPtr[THREAD_NUM];
    output LoadQueueIndexPath loadQueueHeadPtr[THREAD_NUM];
```

**Update LoadQueue.sv**:
```
[ ] Open LoadQueue.sv
[ ] Find head/tail pointers (lines ~35-36)
[ ] Find queue controller instantiation (lines ~42-55)
[ ] Find loadQueue data array (line ~83)
[ ] Apply per-thread pattern:
    [ ] headPtr[THREAD_NUM], tailPtr[THREAD_NUM]
    [ ] loadQueue[THREAD_NUM][LOAD_QUEUE_ENTRY_NUM]
    [ ] Queue controller instantiation per thread
[ ] Update allocation logic (lines ~61-75) for per-thread
[ ] Update store-load ordering detection (lines ~178-188) for per-thread
[ ] Update violation detection (lines ~207-240) for per-thread
[ ] Update recovery (lines ~51, 77) for per-thread
[ ] Test: make clean && make all && make run
[ ] Verify: IPC 0.985285, cycles 4621
```

**Result After**:
```
headPtr[THREAD_NUM] - head pointer per thread
tailPtr[THREAD_NUM] - tail pointer per thread
loadQueue[THREAD_NUM][LOAD_QUEUE_ENTRY_NUM] - entries per thread
Load allocation/execution - per-thread aware
```

---

### RESOURCE 5: Store Queue (60 minutes)

**File**: `/Users/kushal/rsd_mp/Processor/Src/LoadStoreUnit/StoreQueue.sv`

**Prerequisites**:
- [ ] Must first update LoadStoreUnitIF.sv to add thread signals

**Update LoadStoreUnitIF.sv**:
```
[ ] Open LoadStoreUnitIF.sv (if not already updated in Resource 4)
[ ] Find StoreQueue interface section
[ ] Add thread ID signals:
    input ThreadID executeStoreThread[STORE_ISSUE_WIDTH];
    input ThreadID allocateStoreQueueThread[RENAME_WIDTH];
[ ] Update recovery section for per-thread pointers:
    input StoreQueueIndexPath storeQueueRecoveryTailPtr[THREAD_NUM];
    output StoreQueueIndexPath storeQueueHeadPtr[THREAD_NUM];
```

**Update StoreQueue.sv**:
```
[ ] Open StoreQueue.sv
[ ] Find addr and data queue structures (around line ~40-45)
[ ] Find head/tail pointers (around line ~50-55)
[ ] Find queue controller instantiation
[ ] Apply per-thread pattern similar to LoadQueue
[ ] Update allocation logic for per-thread
[ ] Update store execution logic for per-thread
[ ] Update recovery for per-thread
[ ] Test: make clean && make all && make run
[ ] Verify: IPC 0.985285, cycles 4621
```

**Result After**:
```
headPtr[THREAD_NUM] - head pointer per thread
tailPtr[THREAD_NUM] - tail pointer per thread
storeQueue[THREAD_NUM][STORE_QUEUE_SIZE] - entries per thread
Store allocation/execution - per-thread aware
```

---

## 🧪 TESTING AFTER EACH RESOURCE

```bash
cd /Users/kushal/rsd_mp/Processor/Src

# After each resource:
make clean
make all
make run

# MUST see:
# IPC (RISC-V instruction): 0.985285
# Elapsed cycles:        4621

# If NOT exact match:
#   1. Note the actual values
#   2. git checkout <modified_file>
#   3. Re-test to confirm baseline returns
#   4. Debug the logic error
#   5. Fix and test again
#   NEVER commit code that changes baseline
```

---

## 📊 TIMELINE ESTIMATE

| Resource | Time | Cumulative | Status |
|----------|------|-----------|--------|
| Free Lists | 45 min | 45 min | ⏳ |
| Active List | 60 min | 1:45 | ⏳ |
| Issue Queue | 90 min | 3:15 | ⏳ |
| Load Queue | 60 min | 4:15 | ⏳ |
| Store Queue | 60 min | 5:15 | ⏳ |
| Testing/Buffer | 45-60 min | 6:00 | ⏳ |

**Total**: 5-6 hours for Phase 4 completion

---

## 🚨 CRITICAL RULES (Don't Break These)

1. ✅ **Thread check for writes**: `we[t][i] = weIn[i] && (port.thread[i] == t);`
2. ✅ **Extract thread once**: `ThreadID threadID = port.thread[i];`
3. ✅ **Bypass same thread only**: `if (port.thread[j] == threadID)`
4. ✅ **Preserve original**: Copy original code to else clause UNCHANGED
5. ✅ **Maintain baseline**: Every test must show IPC 0.985285, cycles 4621

---

## 📚 REFERENCE FILES

**Must read first**:
- PHASE4_PARTIAL_COMPLETION.md - Current status (this thread)
- RenameLogic/RMT.sv - Verified working pattern (lines 41-185)
- PHASE4_PATTERN_TEMPLATE.md - Code patterns and examples
- PHASE4_QUICK_REFERENCE.md - Quick lookup

**While implementing**:
- Keep RMT.sv visible in second editor window
- Copy pattern structure exactly
- Follow the ifdef/else pattern consistently

---

## ✅ SUCCESS CHECKLIST

After completing all 5 resources:

- [ ] Free Lists: Per-thread allocators (Scalar & FP)
- [ ] Active List: Per-thread FIFO
- [ ] Issue Queue: Per-thread allocator + RAMs
- [ ] Load Queue: Per-thread queue + allocation logic
- [ ] Store Queue: Per-thread queue + allocation logic
- [ ] All files compile without errors
- [ ] All files compile without warnings
- [ ] `make run` succeeds
- [ ] Baseline exactly maintained: IPC 0.985285, 4621 cycles
- [ ] All per-thread logic follows RMT.sv pattern
- [ ] All else clauses contain original unchanged code
- [ ] No cross-thread data access possible

**Phase 4 Complete When**: All items above are ✅

---

## 🎯 IF YOU RUN OUT OF TIME

If 6 hours isn't enough to complete all 5 resources:

1. **Priority 1** (MUST DO): Free Lists & Active List (easiest)
2. **Priority 2** (SHOULD DO): Issue Queue (more complex)
3. **Priority 3** (NICE TO HAVE): Load/Store Queues (require interface changes)

At end of thread:
- Document what was completed
- Document what remains
- Create new prompt for next thread

---

## 📞 NOTES FOR YOU

- **You have working examples**: RMT.sv shows exactly what to do
- **Bypass fix is done**: No cross-thread data leakage possible
- **Baseline is stable**: Every test confirms IPC 0.985285, 4621 cycles
- **Pattern is proven**: This approach works (RMT.sv verification complete)
- **You got this**: Follow the template, test after each file, maintain baseline

**Start with Free Lists. The pattern is simple and will build confidence.**

---

**Good luck! You know what to do. Follow the pattern, test often, maintain baseline. 🚀**
