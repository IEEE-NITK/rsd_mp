# Phase 4: CRITICAL FIXES REQUIRED

**Status**: 3 Blocking Bugs Found  
**Severity**: CRITICAL - System will not work correctly with SMT enabled  
**Time to Fix**: ~2 hours  
**Blocker for**: Phase 5 and beyond

---

## 🚨 CRITICAL BUGS

### BUG #1: LoadStoreUnitIF.sv Missing Thread Signals

**File**: `/Users/kushal/rsd_mp/Processor/Src/LoadStoreUnit/LoadStoreUnitIF.sv`

**Problem**: The interface doesn't carry thread information for load/store allocations. This prevents Load/StoreQueue from knowing which thread each allocation belongs to.

**Current Code** (Lines 20-28):
```systemverilog
// Allocation
logic allocatable;
logic loadQueueAllocatable;
logic storeQueueAllocatable;
logic allocateLoadQueue [ RENAME_WIDTH ];        // ❌ No thread info
logic allocateStoreQueue [ RENAME_WIDTH ];       // ❌ No thread info
LoadQueueIndexPath allocatedLoadQueuePtr [ RENAME_WIDTH ];
StoreQueueIndexPath allocatedStoreQueuePtr [ RENAME_WIDTH ];
```

**Fix**: Add thread signals after SMT ifdef:

```systemverilog
// Allocation
logic allocatable;
logic loadQueueAllocatable;
logic storeQueueAllocatable;
logic allocateLoadQueue [ RENAME_WIDTH ];
logic allocateStoreQueue [ RENAME_WIDTH ];
LoadQueueIndexPath allocatedLoadQueuePtr [ RENAME_WIDTH ];
StoreQueueIndexPath allocatedStoreQueuePtr [ RENAME_WIDTH ];

`ifdef RSD_ENABLE_SMT
// Thread ID for each allocation (added after line 27)
ThreadID allocateLoadQueueThread [ RENAME_WIDTH ];
ThreadID allocateStoreQueueThread [ RENAME_WIDTH ];
`endif
```

**Also Add**: Recovery signals for per-thread pointers (around line 76-78):

```systemverilog
// SQ status.
logic storeQueueEmpty;
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

**Also Add**: Recovery input pointers (after line 81):

```systemverilog
// Recover
logic busyInRecovery;

`ifdef RSD_ENABLE_SMT
// Recovery pointers from recovery manager
input LoadQueueIndexPath loadQueueRecoveryTailPtr[THREAD_NUM];
input StoreQueueIndexPath storeQueueRecoveryTailPtr[THREAD_NUM];
`else
input LoadQueueIndexPath loadQueueRecoveryTailPtr;
input StoreQueueIndexPath storeQueueRecoveryTailPtr;
`endif
```

---

### BUG #2: LoadQueue.sv Using Wrong Thread ID

**File**: `/Users/kushal/rsd_mp/Processor/Src/LoadStoreUnit/LoadQueue.sv`

**Problem**: Line 88 uses `port.thread[0]` (first instruction's thread) for ALL allocations. If thread 0 and thread 1 both allocate simultaneously, thread 1's allocation goes to thread 0's queue.

**Current Code** (Lines 85-108):
```systemverilog
always_comb begin
    // Generate push signals.
`ifdef RSD_ENABLE_SMT
    ThreadID currentThread = port.thread[0];  // ❌ WRONG - only thread 0
    pushCount[currentThread] = 0;
    for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
        if (tailPtr[currentThread] + pushCount[currentThread] < LOAD_QUEUE_ENTRY_NUM) begin
            port.allocatedLoadQueuePtr[i] = tailPtr[currentThread] + pushCount[currentThread];
        end
        else begin
            port.allocatedLoadQueuePtr[i] = 
                tailPtr[currentThread] + pushCount[currentThread] - LOAD_QUEUE_ENTRY_NUM;
        end
        pushCount[currentThread] += port.allocateLoadQueue[i];
    end
    // ...
`endif
```

**Fix**: Use per-allocation thread ID:

```systemverilog
always_comb begin
    // Generate push signals.
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
        end
        else begin
            port.allocatedLoadQueuePtr[i] = 
                tailPtr[targetThread] + pushCount[targetThread] - LOAD_QUEUE_ENTRY_NUM;
        end
        pushCount[targetThread] += port.allocateLoadQueue[i];
    end
    
    // Generate push signals for each thread that has allocations
    for (int t = 0; t < THREAD_NUM; t++) begin
        push[t] = pushCount[t] > 0;
    end

    // Check allocatable for current thread - need to track all threads
    // For now, check if any thread can allocate
    logic anyAllocatable;
    anyAllocatable = FALSE;
    for (int t = 0; t < THREAD_NUM; t++) begin
        if (curCount[t] <= LOAD_QUEUE_ENTRY_NUM - RENAME_WIDTH - 1) begin
            anyAllocatable = TRUE;
        end
    end
    port.loadQueueAllocatable = anyAllocatable;

    recovery.loadQueueHeadPtr[0] = headPtr[0];
    recovery.loadQueueHeadPtr[1] = headPtr[1];
`endif
```

**Also Fix**: Line 154 (execution stage):

Replace:
```systemverilog
ThreadID currentThread = port.thread[0];
```

With per-load-issue logic that routes to correct thread based on execution thread.

---

### BUG #3: StoreQueue.sv Using Wrong Thread ID

**File**: `/Users/kushal/rsd_mp/Processor/Src/LoadStoreUnit/StoreQueue.sv`

**Problem**: Same as BUG #2 - Line 104 uses `port.thread[0]` for ALL allocations

**Current Code** (Lines 102-119):
```systemverilog
always_comb begin
`ifdef RSD_ENABLE_SMT
    ThreadID currentThread = port.thread[0];  // ❌ WRONG
    pushCount[currentThread] = 0;
    for (int i = 0; i < RENAME_WIDTH; i++) begin
        if (tailPtr[currentThread] + pushCount[currentThread] < STORE_QUEUE_ENTRY_NUM) begin
            port.allocatedStoreQueuePtr[i] = tailPtr[currentThread] + pushCount[currentThread];
        end
        // ...
        pushCount[currentThread] += port.allocateStoreQueue[i];
    end
    // ...
`endif
```

**Fix**: Use per-allocation thread ID (same pattern as LoadQueue BUG #2):

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
        end
        else begin
            port.allocatedStoreQueuePtr[i] = 
                tailPtr[targetThread] + pushCount[targetThread] - STORE_QUEUE_ENTRY_NUM;
        end
        pushCount[targetThread] += port.allocateStoreQueue[i];
    end
    
    // Generate push signals for each thread
    for (int t = 0; t < THREAD_NUM; t++) begin
        push[t] = pushCount[t] > 0;
    end

    // Need to pick a current thread for queue count output
    // For now, use thread 0 (will need thread-aware dispatch in future)
    port.storeQueueCount = curCount[0];  // TBD: Should be per-thread
    
    // Check if ANY thread can allocate
    logic anyAllocatable;
    anyAllocatable = FALSE;
    for (int t = 0; t < THREAD_NUM; t++) begin
        if (curCount[t] <= STORE_QUEUE_ENTRY_NUM - RENAME_WIDTH - 1) begin
            anyAllocatable = TRUE;
        end
    end
    port.storeQueueAllocatable = anyAllocatable;
    
    port.storeQueueEmpty = (curCount[0] == 0) && (curCount[1] == 0);

    recovery.storeQueueHeadPtr[0] = headPtr[0];
    recovery.storeQueueHeadPtr[1] = headPtr[1];
`endif
```

**Also Fix**: Line 183 (execution stage) - same as LoadQueue

---

## 🔌 ALSO NEEDED: RenameStage.sv Connection

**File**: `/Users/kushal/rsd_mp/Processor/Src/Pipeline/RenameStage.sv`

**Problem**: The thread ID signals we added to the interface need to be wired up in RenameStage

**Location**: Lines 337-343

**Current Code**:
```systemverilog
for ( int i = 0; i < RENAME_WIDTH; i++ ) begin
    loadStoreUnit.allocateLoadQueue[i] = update[i] && isLoad[i];
    loadStoreUnit.allocateStoreQueue[i] = update[i] && isStore[i];

    nextStage[i].loadQueuePtr = loadStoreUnit.allocatedLoadQueuePtr[i];
    nextStage[i].storeQueuePtr = loadStoreUnit.allocatedStoreQueuePtr[i];
end
```

**Fix**: Add thread ID wiring:

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

---

## 📋 FIX CHECKLIST

### Step 1: Update LoadStoreUnitIF.sv (30 min)
- [ ] Add `ThreadID allocateLoadQueueThread [ RENAME_WIDTH ];` 
- [ ] Add `ThreadID allocateStoreQueueThread [ RENAME_WIDTH ];`
- [ ] Make `storeQueueHeadPtr` and `storeQueueCount` per-thread
- [ ] Make `loadQueueHeadPtr` per-thread
- [ ] Add recovery input pointers (loadQueueRecoveryTailPtr, storeQueueRecoveryTailPtr)
- [ ] Update all modports that use these signals
- [ ] Verify no syntax errors

### Step 2: Update LoadQueue.sv (45 min)
- [ ] Fix allocation logic to use per-thread routing
- [ ] Use `port.allocateLoadQueueThread[i]` for each allocation
- [ ] Initialize `pushCount[t]` per thread
- [ ] Fix allocatable check to be thread-aware
- [ ] Update recovery head pointer output
- [ ] Fix execution stage thread routing (line 154)
- [ ] Verify syntax

### Step 3: Update StoreQueue.sv (45 min)
- [ ] Fix allocation logic to use per-thread routing
- [ ] Use `port.allocateStoreQueueThread[i]` for each allocation
- [ ] Initialize `pushCount[t]` per thread
- [ ] Fix allocatable check
- [ ] Update recovery head pointer output
- [ ] Fix execution stage thread routing (line 183)
- [ ] Verify syntax

### Step 4: Update RenameStage.sv (15 min)
- [ ] Wire `allocateLoadQueueThread[i]` from `pipeReg[i].thread`
- [ ] Wire `allocateStoreQueueThread[i]` from `pipeReg[i].thread`
- [ ] Verify connections

### Step 5: Compilation & Testing (30 min)
- [ ] Full clean build: `make clean && make -j4 all`
- [ ] Check for 0 errors, 0 new warnings
- [ ] Run baseline: `make run`
- [ ] Verify IPC 0.985285, 4621 cycles

---

## 🎯 EXPECTED RESULTS AFTER FIXES

### Before Fixes
```
❌ LoadQueue/StoreQueue cannot differentiate which thread allocations belong to
❌ Thread 1 allocations mixed with Thread 0 allocations
❌ System will crash or produce wrong results with SMT enabled
```

### After Fixes
```
✅ Each allocation carries thread ID information
✅ Load/Store queues route allocations to correct per-thread FIFO
✅ Thread isolation maintained at resource level
✅ Baseline: IPC 0.985285, 4621 cycles (maintained)
✅ Ready for Phase 5 multi-threaded testing
```

---

## ⏱️ TIME ESTIMATE

- LoadStoreUnitIF.sv: 30 minutes
- LoadQueue.sv: 45 minutes
- StoreQueue.sv: 45 minutes
- RenameStage.sv: 15 minutes
- Testing & Verification: 30 minutes
- **Total: ~2.5 hours**

---

## 🚀 CRITICAL PATH

1. **Update interface first** (must be done before other changes compile)
2. **Update Load/StoreQueue.sv** (will need interface signals)
3. **Wire RenameStage.sv** (needs interface signals to exist)
4. **Compile and test**

Do NOT proceed to Phase 5 until ALL 3 bugs are fixed and baseline is verified.
