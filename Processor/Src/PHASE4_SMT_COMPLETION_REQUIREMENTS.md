# Phase 4 SMT Completion Requirements

**Status**: Phase 4 SMT incomplete - Phase 5 testing blocked  
**Root Cause**: Missing thread routing signals and interface field definitions  
**Action Required**: Complete Phase 4 SMT infrastructure before Phase 5  

---

## What SMT Actually Does (Clarification)

SMT is NOT true parallelism. It's **interleaved execution**:
- **Fetch Stage**: Round-robin fetch from Thread 0, then Thread 1, then Thread 0, etc.
- **Pipeline**: Both threads' instructions coexist in-flight simultaneously
- **Execute**: Instructions execute sequentially (one ALU, one load unit, etc.)
- **Commit**: Instructions retire sequentially (one thread at a time)

Result: Two instruction streams blended together in the pipeline for better utilization

---

## What Phase 4 Attempted to Do

Phase 4 added thread awareness to the processor:
- ✅ Per-thread PC registers (NextPCStage.sv)
- ✅ Per-thread register file structures
- ✅ Per-thread active list pointers
- ✅ Per-thread free lists
- ❌ **Thread routing signals** (INCOMPLETE)
- ❌ **Thread allocation wiring** (INCOMPLETE)

---

## Compilation Errors Analysis

### Error Category 1: Missing Thread Allocation Signals (14 errors)

**Locations**: LoadQueue.sv, StoreQueue.sv, RenameStage.sv  
**Root Cause**: Load/Store unit doesn't receive thread ID for each instruction  
**Impact**: Can't route loads/stores to correct thread's queue

**Fix Required**:
```systemverilog
// LoadStoreUnitIF needs to wire thread info when allocating
allocateLoadQueueThread[i] = pipeReg[i].thread;  // Which thread for this load?
allocateStoreQueueThread[i] = pipeReg[i].thread; // Which thread for this store?
```

**Missing Interface Fields**:
- LoadStoreUnitIF: `ThreadID allocateLoadQueueThread[RENAME_WIDTH]`
- LoadStoreUnitIF: `ThreadID allocateStoreQueueThread[RENAME_WIDTH]`
- LoadStoreUnitIF: `ThreadID thread[COMMIT_WIDTH]` (for execution thread context)

### Error Category 2: Per-Thread Active List Issues (8 errors)

**Locations**: ActiveList.sv, multiple lines  
**Root Cause**: ActiveListIF doesn't pass thread ID to active list for per-thread operations  
**Impact**: Can't track which thread owns which active list entry

**Fix Required**:
- Add `ThreadID thread[RENAME_WIDTH]` to port connections
- Update active list operations to use thread-specific pointers
- Wire thread information through all active list accesses

### Error Category 3: RMT Thread Tracking (3 errors)

**Locations**: RenameLogic.sv (line 284)  
**Root Cause**: Release mechanism doesn't know which thread is releasing registers  
**Impact**: Can't return freed physical registers to correct thread's free list

**Fix Required**:
```systemverilog
// RenameLogicIF needs:
ThreadID releaseThread[COMMIT_WIDTH];  // Which thread is retiring this instruction?
```

### Error Category 4: Fetch Stage Thread ID (1 error)

**Location**: NextPCStage.sv (line 238)  
**Root Cause**: Fetched instructions not tagged with thread ID  
**Impact**: Instructions lose thread identity immediately after fetch

**Fix Required**:
```systemverilog
// In NextPCStage - need to track which thread's PC we're using
logic [THREAD_ID_BIT_WIDTH-1:0] nextThread;  // Which thread are we fetching from?
nextStage[i].thread = nextThread;  // Tag instruction with its thread
```

### Error Category 5: Debug/Verification (2 errors)

**Location**: TestMain.sv  
**Root Cause**: Debug structure for active list changed  
**Impact**: Can't access debug information for verification

**Fix Required**:
- Update TestMain.sv to match new ActiveList internal structure
- Adjust debug port access based on new per-thread layout

---

## Detailed Implementation Requirements

### 1. Rename Stage Thread Routing (RenameStage.sv)

**Current**: 
```systemverilog
for (int i = 0; i < RENAME_WIDTH; i++) begin
    // Load/store allocation doesn't include thread info
    loadStoreUnit.allocateLoadQueue[i] = ...;
end
```

**Required Fix**:
```systemverilog
for (int i = 0; i < RENAME_WIDTH; i++) begin
    loadStoreUnit.allocateLoadQueueThread[i] = pipeReg[i].thread;
    loadStoreUnit.allocateStoreQueueThread[i] = pipeReg[i].thread;
    loadStoreUnit.allocateLoadQueue[i] = ...;
    loadStoreUnit.allocateStoreQueue[i] = ...;
end
```

**Why**: LoadQueue/StoreQueue need to know which thread owns the allocated entry

---

### 2. Load/Store Queue Thread Handling (LoadQueue.sv, StoreQueue.sv)

**Current State**: Code tries to use `port.allocateLoadQueueThread[i]` but interface doesn't properly expose it

**Required Fix**:

A. In LoadStoreUnitIF.sv - ensure these fields always exist:
```systemverilog
interface LoadStoreUnitIF(...);
    // Always define these (not just under ifdef)
    ThreadID allocateLoadQueueThread[RENAME_WIDTH];
    ThreadID allocateStoreQueueThread[RENAME_WIDTH];
    ThreadID thread[COMMIT_WIDTH];  // For execution context
    // ... rest of interface
endinterface
```

B. In LoadQueue.sv - fix variable declaration issue:
```systemverilog
// DON'T do this (Verilator error):
// ThreadID targetThread = port.allocateLoadQueueThread[i];

// DO this (direct expression):
tailPtr[port.allocateLoadQueueThread[i]] = ...;
```

---

### 3. Active List Thread Awareness (ActiveList.sv)

**Current**: Per-thread structures exist but interface doesn't wire thread info

**Required Fixes**:

A. In ActiveListIF.sv:
```systemverilog
interface ActiveListIF(...);
    // Add thread tracking to port
    ThreadID thread[RENAME_WIDTH];  // Which thread for these operations?
    // ... rest of interface
endinterface
```

B. In ActiveList.sv - use thread for allocation:
```systemverilog
`ifdef RSD_ENABLE_SMT
    for (int i = 0; i < RENAME_WIDTH; i++) begin
        int t = port.thread[i];  // Get thread for this instruction
        tailPtr[t] = (tailPtr[t] + 1) % ACTIVE_LIST_ENTRY_NUM;
    end
`else
    // Single-threaded version
`endif
```

---

### 4. Register Release Thread Tracking (RenameLogic.sv)

**Current**: No way to know which thread is releasing registers

**Required Fix**:

A. In RenameLogicIF.sv:
```systemverilog
interface RenameLogicIF(...);
    ThreadID releaseThread[COMMIT_WIDTH];  // Which thread for each retire?
    // ... rest of interface
endinterface
```

B. In RenameLogic.sv (around line 284):
```systemverilog
`ifdef RSD_ENABLE_SMT
    for (int i = 0; i < COMMIT_WIDTH; i++) begin
        if (port.release[i]) begin
            int t = port.releaseThread[i];  // Get thread
            // Return physical register to thread t's free list
            scalarFreeListCount[t] <= scalarFreeListCount[t] + 1;
        end
    end
`else
    // Single-threaded version
`endif
```

---

### 5. Fetch Stage Thread Scheduling (NextPCStage.sv)

**Current**: fetchThread variable undefined

**Required Fix**:

Implement round-robin thread selection:
```systemverilog
`ifdef RSD_ENABLE_SMT
    // Simple round-robin: alternate between threads each cycle
    logic threadSelectReg;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            threadSelectReg <= 0;
        end else begin
            threadSelectReg <= ~threadSelectReg;  // Toggle each cycle
        end
    end
    
    // Fetch from selected thread
    logic [THREAD_ID_BIT_WIDTH-1:0] fetchThread;
    assign fetchThread = threadSelectReg[0];  // Simple round-robin
    
    // Tag fetched instructions with thread
    for (int i = 0; i < FETCH_WIDTH; i++) begin
        nextStage[i].thread = fetchThread;
    end
`endif
```

---

### 6. Test Framework Updates (TestMain.sv)

**Required Changes**:
- Update `activeList.activeList.debugValue` access to match new structure
- May need to iterate per-thread for debug output
- Adjust for new per-thread layouts

---

## Implementation Order (Recommended)

1. **LoadStoreUnitIF.sv** - Add/expose thread fields (5 min)
2. **RenameLogicIF.sv** - Add releaseThread field (5 min)  
3. **ActiveListIF.sv** - Add thread field (5 min)
4. **RenameStage.sv** - Wire thread to LoadStoreUnit (15 min)
5. **RenameLogic.sv** - Fix register release per-thread (30 min)
6. **NextPCStage.sv** - Implement thread round-robin fetch (20 min)
7. **LoadQueue.sv** - Verify thread routing works (10 min)
8. **StoreQueue.sv** - Verify thread routing works (10 min)
9. **ActiveList.sv** - Fix per-thread operations (20 min)
10. **TestMain.sv** - Update debug access (20 min)
11. **Compile and verify** (30 min)

**Total Estimated Time**: 2.5-3 hours

---

## Compilation Test Plan

```bash
# After each major change
make all 2>&1 | grep "^%Error" | wc -l

# Expected progression:
# Start: 43 errors
# After step 1-3: 35-40 errors (interface fields added)
# After step 4-6: 20-30 errors (routing wired)
# After step 7-10: <5 errors (remaining debug issues)
# After step 11: 0 errors, successful build
```

---

## Verification After Phase 4 Completion

Once Phase 4 SMT wiring is complete:

```bash
# Enable SMT in Makefile
RSD_ENABLE_SMT = 1

# Compile
make all  # Should succeed with 0 errors

# Run baseline test
make run  # Should complete successfully
```

Then Phase 5 can proceed with actual multi-threaded testing:
- Both threads in pipeline simultaneously
- Instructions interleaved
- Per-thread performance measurable
- SMT benefits testable

---

## Summary

**What's Broken**: 43 compilation errors from incomplete thread signal wiring  
**Where**: 7 core files need thread field additions/fixes  
**Effort**: 2.5-3 hours of focused work  
**Payoff**: Enables Phase 5 multi-threaded testing and SMT validation  
**Risk**: Low (straightforward signal/field additions)  

**Next Step**: Apply fixes in recommended order, test compilation after each step

---

**Recommendation**: Complete this Phase 4 work before starting Phase 5, as Phase 5's entire purpose is to test this SMT infrastructure once it's working.
