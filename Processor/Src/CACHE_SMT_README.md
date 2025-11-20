# Cache SMT Support - Implementation Guide

## Decision: Shared L1 Caches with ThreadID Tracking

**Architecture:** Single ICache + Single DCache + ThreadID in MSHR entries
**Time estimate:** 7-10 hours
**Complexity:** Low (only ~85 lines of actual code changes)

---

## Documentation Files

### 1. **CACHE_SMT_QUICK_START.txt** ⭐ START HERE
Concise step-by-step implementation guide with exact line numbers and code snippets.
- **Read time:** 5 minutes
- **Use for:** During implementation (copy/paste reference)
- **Format:** Terminal-friendly, direct instructions

### 2. **CACHE_SMT_SHARED_CACHE_PRACTICAL.md** 
Practical guide explaining the architecture, changes needed, and rationale.
- **Read time:** 15 minutes
- **Use for:** Understanding scope before starting
- **Format:** Detailed explanation with sections on integration and testing

---

## Quick Implementation Path

### Step-by-Step (7-10 hours total)

```
1. Read CACHE_SMT_QUICK_START.txt                          (5 min)
2. CacheSystemTypes.sv - Add ThreadID to 3 structs         (30 min)
3. DCacheIF.sv - Add 2 tid signals                          (20 min)
4. DCache.sv - Add MSHR tid tracking and flush logic        (1 hour)
5. LoadStoreUnit - Connect thread IDs to MSHR allocation   (1 hour)
6. (Optional) ICache.sv - Add fairness logic               (2 hours)
7. Test: Single-thread regression + dual-thread functional (2-3 hours)
```

---

## Key Changes Summary

### What You're Adding:
- ThreadID field to MSHR entries
- Thread ID extraction when MSHR allocated
- Thread ID checking during cache flush
- Thread ID passing from LSU to DCache

### What You're NOT Changing:
- ICache.sv structure (except optional fairness)
- DCache.sv core logic
- Cache array implementations
- Memory system architecture

---

## Files to Modify

| File | Changes | Time |
|------|---------|------|
| CacheSystemTypes.sv | Add 3 tid fields to structs | 30 min |
| DCacheIF.sv | Add 2 tid signals | 20 min |
| DCache.sv | Add tid to MSHR init + flush checks | 1 hour |
| LoadStoreUnit* | Connect thread IDs | 1 hour |
| ICache.sv (optional) | Per-thread miss tracking | 2 hours |

*Exact file depends on your LSU implementation

---

## Starting Point

1. Open **CACHE_SMT_QUICK_START.txt**
2. Start with Step 1: CacheSystemTypes.sv
3. Follow steps 1-6 in order
4. Reference **CACHE_SMT_SHARED_CACHE_PRACTICAL.md** if you need context

---

## Expected Outcome

- ✓ Single-thread tests pass (regression)
- ✓ Dual-thread tests compile and run
- ✓ Both threads allocate MSHR entries independently
- ✓ Thread-selective cache flush works
- ✗ 5-10% more cache misses than single-threaded (acceptable)

---

## Questions During Implementation?

Check **CACHE_SMT_SHARED_CACHE_PRACTICAL.md** sections:
- "Integration Points (Quick)" - for connection questions
- "Testing Strategy" - for testing approach
- "Code Template" - for actual code patterns

---

Done! Start reading CACHE_SMT_QUICK_START.txt now.
