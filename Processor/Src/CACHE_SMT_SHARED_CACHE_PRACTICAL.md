# Shared Cache SMT Support - Practical Implementation Guide

## Decision: Single Shared L1 Caches with ThreadID Tracking

**Tradeoff accepted:** Potential cache interference (extra misses) in exchange for **simpler implementation and less development time**.

---

## Architecture

```
Thread 0 ──┐                    Thread 1 ──┐
           │                               │
    ┌──────▼──────┐            ┌──────────▼─────┐
    │ NextPCStage │            │ NextPCStage    │
    │ (selects T) │            │ (selects T)    │
    └──────┬──────┘            └────────────────┘
           │                           │
           │ selectedTid               │
           │                           │
           └───────────────┬───────────┘
                           │
                    ┌──────▼──────┐
                    │ ICache       │
                    │ (SHARED)     │
                    │ + ThreadID   │
                    │ tracking     │
                    └──────┬──────┘
                           │
    ┌──────────────────────┼──────────────────────┐
    │                      │                      │
    │          ┌───────────▼────────────┐         │
    │          │ MemoryAccessController │         │
    │          └───────────┬────────────┘         │
    │                      │                      │
    └──────────────────────┼──────────────────────┘
                           │
                    ┌──────▼──────┐
                    │ DCache       │
                    │ (SHARED)     │
                    │ + ThreadID   │
                    │ tracking     │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ L2/Memory    │
                    └──────────────┘
```

**Single ICache, single DCache, ThreadID in MSHR entries only**

---

## Minimal Changes Required

### Only 3 Files Need Real Changes:

1. **CacheSystemTypes.sv** - Add ThreadID to structs (30 lines)
2. **DCache.sv** - Add tid field to MSHR (40 lines)
3. **DCacheIF.sv** - Add tid signals for MSHR allocation (10 lines)

### Optional (For fairness):

4. **ICache.sv** - Add per-thread miss tracking (30 lines) [RECOMMENDED]

---

## Detailed Changes

### 1. CacheSystemTypes.sv (CRITICAL)

Add ThreadID to these structs:

```systemverilog
// Before:
typedef struct packed {
    logic valid;
    MSHR_Phase phase;
    logic victimDirty;
    logic victimValid;
    // ... other fields
} MissStatusHandlingRegister;

// After:
typedef struct packed {
    logic valid;
    ThreadID tid;              // ← NEW: Which thread owns this MSHR entry
    MSHR_Phase phase;
    logic victimDirty;
    logic victimValid;
    // ... rest unchanged
} MissStatusHandlingRegister;
```

Also add to:
- `MemReadAccessReq` (for ICache miss requests)
- `MemAccessResult` (for routing responses)

**Total: ~30 lines to add**

### 2. DCacheIF.sv (EASY)

```systemverilog
// Add these inputs:
input  ThreadID  initMSHR_Tid[MSHR_NUM];        // Which thread allocates MSHR
input  ThreadID  dcFlushTid;                     // Which thread to flush

// Add to state:
output ThreadID  mshrTid[MSHR_NUM];             // Current thread owner
```

**Total: ~10 lines**

### 3. DCache.sv - DCacheMissHandler (MAIN WORK)

**In MSHR initialization:**
```systemverilog
if (port.initMSHR[i] && !flushMSHR_Allocation[i]) begin
    nextMSHR[i].valid = TRUE;
    nextMSHR[i].tid = port.initMSHR_Tid[i];     // ← NEW
    nextMSHR[i].newAddr = port.initMSHR_Addr[i];
    // ... rest unchanged
end
```

**In flush logic (MSHR_PHASE_FLUSH_*):**
```systemverilog
MSHR_PHASE_FLUSH_VICTIM_REQEUST: begin
    // Only flush MSHR entries for this thread
    if (mshr[i].tid == port.dcFlushTid || port.dcFlushAll) begin
        port.mshrCacheReq[i] = TRUE;
        // ... rest of flush logic
    end
end
```

**In memory request generation:**
```systemverilog
// Include thread ID in memory requests
port.mshrMemMuxIn[i].tid = mshr[i].tid;        // ← NEW (if MemoryPortMultiplexerIn has tid)
```

**Total: ~40 lines**

### 4. ICache.sv (OPTIONAL - RECOMMENDED for fairness)

To prevent one thread's misses from starving the other:

```systemverilog
// Add per-thread state:
logic regMissValid[THREAD_NUM], nextMissValid[THREAD_NUM];
ICacheIndexPath regMissIndex[THREAD_NUM], nextMissIndex[THREAD_NUM];
ICacheTagPath regMissTag[THREAD_NUM], nextMissTag[THREAD_NUM];
MemAccessSerial regSerial[THREAD_NUM], nextSerial[THREAD_NUM];

// In miss phase machine:
ICACHE_PHASE_MISS_READ_MEM_REQUEST: begin
    // Service whichever thread has oldest miss (priority)
    ThreadID activeMissThread = selectOldestMiss();
    
    if (cacheSystem.icMemAccessReqAck.ack) begin
        nextMissValid[activeMissThread] = FALSE;
        nextSerial[activeMissThread] = cacheSystem.icMemAccessReqAck.serial;
    end
end
```

**Total: ~30 lines (optional but improves fairness)**

---

## Integration Points (Quick)

### LoadStoreUnit → DCache

Add thread ID to load/store execution:

```systemverilog
// In LoadStoreUnitIF.sv - pass through from LSU:
ThreadID executedLoadTid[LOAD_ISSUE_WIDTH];
ThreadID executedStoreTid[STORE_ISSUE_WIDTH];

// In DCache.sv instantiation point:
// Extract tid from LSU and pass to MSHR allocation:
port.initMSHR_Tid[i] = executedLoadTid[i];  // For load MSHR
```

### Recovery → Cache Flush

```systemverilog
// Recovery manager signals:
output ThreadID recoveryTid;
output logic recoveryFlush;

// Cache flush manager receives:
input ThreadID cacheFlushTid;
input logic cacheFlushAll;  // TRUE = flush both, FALSE = flush cacheFlushTid only

// CacheFlushManager sends:
port.dcFlushTid = cacheFlushTid;
port.dcFlushAll = cacheFlushAll;
```

---

## Minimal CacheSystemIF Changes

```systemverilog
// Current struct - ADD ONE FIELD:
typedef struct packed {
    logic valid;
    PhyAddrPath addr;
    ThreadID tid;           // ← NEW
} MemReadAccessReq;

typedef struct packed {
    logic valid;
    MemAccessSerial serial;
    DCacheLinePath data;
    ThreadID tid;           // ← NEW (for response routing)
} MemAccessResult;
```

That's it for ICache. For DCache, thread ID is carried in MSHR (not passed separately).

---

## Simple Checklist

### Absolute Minimum (Core Only)

- [ ] **CacheSystemTypes.sv**: Add `ThreadID tid` to `MissStatusHandlingRegister`
- [ ] **CacheSystemTypes.sv**: Add `ThreadID tid` to `MemReadAccessReq`
- [ ] **CacheSystemTypes.sv**: Add `ThreadID tid` to `MemAccessResult`
- [ ] **DCacheIF.sv**: Add `ThreadID initMSHR_Tid[MSHR_NUM]` input
- [ ] **DCache.sv**: In MSHR init: `nextMSHR[i].tid = port.initMSHR_Tid[i];`
- [ ] **DCache.sv**: In flush: check `mshr[i].tid == flushTid` before flushing
- [ ] **LoadStoreUnit**: Pass thread ID to DCache MSHR allocation

**Time: ~4-6 hours**

### Recommended (Add Fairness)

- [ ] **ICache.sv**: Add `regMissValid[THREAD_NUM]` array
- [ ] **ICache.sv**: Add `regMissIndex[THREAD_NUM]` array
- [ ] **ICache.sv**: Add `regMissTag[THREAD_NUM]` array
- [ ] **ICache.sv**: Add `regSerial[THREAD_NUM]` array
- [ ] **ICache.sv**: Implement fairness: serve oldest thread's miss

**Additional time: ~3-4 hours**

**Total: 7-10 hours for shared cache (vs 50+ for per-thread)**

---

## Implementation Order

1. **Update types** (CacheSystemTypes.sv) - 30 min
2. **Update DCache interfaces** (DCacheIF.sv) - 20 min
3. **Update MSHR initialization** (DCache.sv) - 30 min
4. **Add flush filtering** (DCache.sv) - 30 min
5. **Connect LoadStoreUnit** - 1 hour
6. **Optional: ICache fairness** (ICache.sv) - 2 hours
7. **Test** - 2-3 hours

---

## Expected Behavior

### Performance Impact

- **Cache hit rate**: May decrease 5-10% due to thread interference
- **Latency**: Unchanged (<1 cycle overhead from thread ID)
- **Throughput**: Potentially lower due to more misses
- **Acceptable**: For SMT prototype, this is OK

### Fairness

**Without ICache fairness update:**
- One thread's constant misses may delay other thread's misses
- Acceptable for initial implementation

**With ICache fairness update:**
- Both threads' misses get served fairly
- Better balance, closer to ideal

---

## Testing Strategy

### Minimal Testing
1. Single thread (regression) - should work unchanged
2. Both threads fetching - verify no crashes
3. Load/store with both threads - verify correctness

### Better Testing
4. Cache hit rates - measure before/after
5. Fairness - verify both threads make progress
6. Flush correctness - thread recovery works

---

## What You DON'T Need to Do

✓ Don't duplicate ICache/DCache modules
✓ Don't create per-thread interfaces
✓ Don't implement complex arbitration
✓ Don't modify FetchStage or Fetch logic
✓ Don't change cache array structures

---

## Quick Reference: Changes by File

| File | Lines | Work | Effort |
|------|-------|------|--------|
| CacheSystemTypes.sv | ~30 | Add tid to structs | 30 min |
| DCacheIF.sv | ~10 | Add tid signals | 20 min |
| DCache.sv | ~40 | MSHR tid + flush check | 1 hour |
| ICache.sv | ~30 | Optional: per-thread tracking | 2 hours |
| LSU connection | ~10 | Pass tid to MSHR allocation | 1 hour |
| Testing | - | Single/multi-thread tests | 2-3 hours |
| **TOTAL** | ~120 | **Shared cache with tid** | **7-10 hours** |

---

## Code Template: Key Changes

### Template 1: MSHR Allocation

```systemverilog
// DCache.sv - DCacheMissHandler
if (port.initMSHR[i] && !flushMSHR_Allocation[i]) begin
    nextMSHR[i].valid = TRUE;
    nextMSHR[i].tid = port.initMSHR_Tid[i];      // ← ADD THIS
    nextMSHR[i].newAddr = port.initMSHR_Addr[i];
    nextMSHR[i].newValid = FALSE;
    // ... rest unchanged
end
```

### Template 2: Flush Check

```systemverilog
// DCache.sv - flush phases
if (port.dcFlushing) begin
    if (port.dcFlushAll || mshr[i].tid == port.dcFlushTid) begin
        // Proceed with flush for this MSHR
        port.mshrCacheReq[i] = TRUE;
        // ...
    end
    // else: don't flush this entry (different thread)
end
```

### Template 3: Response Routing (ICache)

```systemverilog
// ICache.sv - handle per-thread misses
if (cacheSystem.icMemAccessResult.valid) begin
    // Find which thread this response is for
    for (int t = 0; t < THREAD_NUM; t++) begin
        if (cacheSystem.icMemAccessResult.serial == regSerial[t]) begin
            // This response is for thread t
            nextMissValid[t] = FALSE;
            break;
        end
    end
end
```

---

## Caveats & Notes

1. **Cache Interference**: Unavoidable with shared cache. Accept it.
2. **Fairness**: Without ICache changes, one thread may dominate. Optional improvement.
3. **Serial Numbers**: Already present in existing code, just need to use them.
4. **Thread ID Width**: 1 bit for 2 threads (minimal area)
5. **Memory Bandwidth**: Not a problem - shared cache doesn't increase bandwidth pressure

---

## Summary

**Shared cache approach:**
- ✓ Minimal code changes (~120 lines)
- ✓ 7-10 hours of work
- ✓ Reuses all existing cache logic
- ✓ Simpler testing
- ✗ Potential 5-10% miss rate increase
- ✗ Possible fairness issues without careful design

**Acceptable tradeoff for prototype SMT implementation.**

Proceed with implementation order above. Start with CacheSystemTypes.sv type changes, then DCacheIF.sv, then DCache.sv modifications.

Good luck!
