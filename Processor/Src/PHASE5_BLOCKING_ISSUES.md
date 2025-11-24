# Phase 5 Blocking Issues Report

**Date**: November 24, 2025  
**Status**: BLOCKED - Cannot proceed with Phase 5 testing  
**Root Cause**: Phase 4 SMT infrastructure incomplete

---

## Summary

Phase 5 cannot proceed because the RSD_ENABLE_SMT feature from Phase 4 has incomplete wiring and field definitions. When attempting to enable SMT in the build configuration, 21 compilation errors occur across multiple modules.

---

## Critical Missing Components

### 1. LoadQueue.sv - Missing Thread Allocation Field
```
Error: Can't find definition of 'allocateLoadQueueThread'
Location: LoadStoreUnit/LoadQueue.sv:95
Status: CRITICAL - Blocks load queue thread assignment
```

**What's missing**: LoadQueueIF should define `allocateLoadQueueThread` as an output signal for thread-aware load queue allocation.

### 2. StoreQueue.sv - Missing Thread Allocation Field  
```
Error: Can't find definition of 'allocateStoreQueueThread'
Location: LoadStoreUnit/StoreQueue.sv:111
Status: CRITICAL - Blocks store queue thread assignment
```

**What's missing**: StoreQueueIF should define `allocateStoreQueueThread` as an output signal for thread-aware store queue allocation.

### 3. RenameLogic.sv - Missing Thread Release Field
```
Error: Can't find definition of 'releaseThread'
Location: RenameLogic/RenameLogic.sv:284
Status: CRITICAL - Blocks per-thread register release
```

**What's missing**: RenameLogicIF should define `releaseThread` to track which thread is releasing physical registers.

### 4. ActiveList.sv - Missing Thread Fields
```
Error: Can't find definition of 'thread' in dotted variable
Location: Multiple lines (103, 104, 115, 348, 498, etc.)
Status: CRITICAL - Blocks per-thread active list operations
```

**What's missing**: The interface definition for ActiveListIF likely doesn't include per-thread `thread` signals in the port connections.

### 5. RMT.sv - Undefined Variables
```
Error: Can't find definition of 'thread' in port
Location: RenameLogic/RMT.sv:100, 136, 163  
Error: ThreadID variable declared in always_comb
Status: CRITICAL - Blocks thread-aware RMT
```

**What's missing**: RMT interface needs thread signals and proper variable declaration support.

### 6. NextPCStage.sv - Missing Variable
```
Error: Can't find definition of variable: 'fetchThread'
Location: Pipeline/FetchStage/NextPCStage.sv:238
Status: CRITICAL - Blocks per-thread PC generation
```

**What's missing**: NextPCStage needs to properly set thread ID for fetched instructions.

### 7. RenameStage.sv - Missing Signal Connections
```
Error: Can't find definition of 'allocateLoadQueueThread'
Error: Can't find definition of 'allocateStoreQueueThread'
Location: Pipeline/RenameStage.sv:342-343
Status: CRITICAL - Blocks thread assignment to LSU
```

**What's missing**: RenameStage needs to wire thread information to LoadStoreUnit allocation signals.

### 8. TestMain.sv - Incomplete Debug Access
```
Error: Can't find definition of 'activeList' in dotted scope
Location: Verification/TestMain.sv:76
Status: MODERATE - Debug visibility issue
```

**What's missing**: Debug structure for accessing internal active list state changed in Phase 4.

---

## Impact Assessment

### Severity: CRITICAL
- Cannot compile with RSD_ENABLE_SMT enabled
- Single-threaded builds (RSD_ENABLE_SMT disabled) compile successfully
- Phase 5 testing is completely blocked

### Scope of Work Required
- **Files to complete**: ~8 core modules
- **Estimated effort**: 4-6 hours for full implementation
- **Risk**: Medium (depends on Phase 4 design decisions)

---

## Required Actions

### Option A: Complete Phase 4 SMT Implementation (Recommended)
1. Update LoadQueueIF.sv to add `allocateLoadQueueThread` signals
2. Update StoreQueueIF.sv to add `allocateStoreQueueThread` signals  
3. Update RenameLogicIF.sv to add `releaseThread` signals
4. Update ActiveListIF.sv to include per-thread port connections
5. Fix RMT.sv thread signal wiring
6. Complete NextPCStage.sv thread initialization
7. Update RenameStage.sv to wire thread signals to LSU
8. Update TestMain.sv for new debug structure

**Timeline**: 4-6 hours  
**Then proceed with Phase 5**: 8-10 hours

### Option B: Disable SMT and Run Single-Threaded Phase 5 Tests
- Accept RSD_ENABLE_SMT remains disabled (current state)
- Modify Phase 5 tests to be single-threaded simulation with timing comparison
- Measure relative performance vs Phase 4 baseline
- Document multi-threaded infrastructure needs for future phases

**Timeline**: 2 hours  
**Result**: Limited testing value - won't prove multi-threading works

---

## Compilation Status Check

**Current (SMT Disabled)**:
```bash
$ make all  
# Compiles: 0 errors, 0 warnings ✓
```

**Attempted (SMT Enabled)**:
```bash
$ RSD_ENABLE_SMT=1 make all
# Fails: 21 errors ✗
```

---

## Recommended Path Forward

### Phase 5 Continuation Decision

**CHOICE 1: Complete SMT Implementation**
- Go back to Phase 4 framework
- Systematically implement missing SMT wiring
- Complete all 21 compilation errors
- Then run Phase 5 tests with full multi-threading support
- Better long-term: proves architecture works correctly

**CHOICE 2: Modify Phase 5 Scope** 
- Keep SMT disabled for now
- Create single-threaded test framework verification
- Focus on TestMain.sv modifications for dual program loading
- Use creative solutions to simulate multi-threading effects
- Less ideal: won't truly test multi-threading

---

## Next Steps

1. **Decision**: Which path to take (Complete Phase 4 or Modify Phase 5)?
2. **If Path A**: Start Phase 4 SMT completion
3. **If Path B**: Redesign Phase 5 tests for single-threaded simulation

---

**Blocking Status**: ⛔ CANNOT PROCEED WITH PHASE 5 AS PLANNED

**Recommendation**: Complete SMT Phase 4 implementation before Phase 5 testing to ensure multi-threading actually works.
