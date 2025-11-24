# Phase 4 Quick Reference - One Page Summary

**Status**: GO (prerequisite fix required)  
**Baseline**: IPC 0.985285, 4621 cycles  
**Timeline**: 5-6 hours total  

---

## Critical Decision Table

| Component | Decision | Implementation | Time |
|-----------|----------|-----------------|------|
| **Issue** | Per-thread queues | Replicate allocator + RAMs per thread | 60m |
| **Load Q** | Per-thread | Apply RMT.sv pattern | 45m |
| **Store Q** | Per-thread | Apply RMT.sv pattern | 45m |
| **Free Lists** | Per-thread | Apply RMT.sv pattern | 45m |
| **Active List** | Per-thread | Apply RMT.sv pattern | 60m |
| **Bypass** | ADD THREAD CHECK | Fix BypassController.sv | 30m |
| **Recovery** | Keep global | No changes needed | 0m |
| **Controller** | Keep global | No changes needed | 0m |

**Total Implementation**: ~6 hours

---

## Critical Issue: Bypass Network

**Problem**: Cross-thread data leakage possible
```
Thread 0 reads r5 → Could get Thread 1's value
```

**Fix Location**: RegisterFile/BypassController.sv

**Required Changes**:
1. Add ThreadID field to BypassCtrlOperand struct
2. Add ThreadID to BypassCtrlStage pipeline stages
3. Add thread check in SelectReg() function: `&& (reqThread == intEX[i].thread)`
4. Propagate thread through all SelectReg calls

**Status**: Identified, fix designed, ready to implement

---

## Files to Modify (Priority Order)

### 1. RegisterFile/BypassController.sv (FIRST - Prerequisite)
- Add thread field to struct
- Add thread to pipeline stages
- Add thread checks in SelectReg()
- Est: 30 min
- **Must do before Phase 4**

### 2. Free Lists (RMT.sv Pattern)
- `ifdef RSD_ENABLE_SMT` wrapper
- Add THREAD_NUM dimension
- Add thread check: `we[t][i] && (port.thread[i] == t)`
- Est: 45 min

### 3. Active List (RMT.sv Pattern)
- `ifdef RSD_ENABLE_SMT` wrapper
- Per-thread pointers
- Per-thread logic
- Est: 60 min

### 4. Issue Queue (Per-Thread Design)
- Replicate free list allocator per thread
- Replicate payload RAMs per thread
- Add thread multiplexing
- Est: 60 min

### 5. Load Queue (RMT.sv Pattern)
- Per-thread entries and pointers
- Thread dimension on all accesses
- Update recovery signal routing
- Est: 45 min

### 6. Store Queue (RMT.sv Pattern)
- Per-thread entries and pointers
- Thread dimension on all accesses
- Update recovery signal routing
- Est: 45 min

---

## The Pattern (Copy This)

```systemverilog
`ifdef RSD_ENABLE_SMT
    // ===== PER-THREAD VERSION =====
    
    // Data structure with thread dimension
    ResourceEntry data[THREAD_NUM][SIZE];
    IndexPath ptr[THREAD_NUM];
    
    // Always add thread check for writes
    for (int t = 0; t < THREAD_NUM; t++) begin
        for (int i = 0; i < WIDTH; i++) begin
            // CRITICAL: Check thread matches
            we[t][i] = port.weIn[i] && (port.thread[i] == t);
            wa[t][i] = port.waIn[i];
            wv[t][i] = port.wvIn[i];
        end
    end
    
    // Extract thread once for reads
    ThreadID threadID = port.thread[i];
    rv[threadID][i] = data[threadID][ra[threadID][i]];
    
    // CRITICAL: Bypass only same thread
    if (port.thread[j] == threadID) begin
        rv[threadID][i] = port.wvIn[j];
    end
    
`else
    // ===== SINGLE-THREADED VERSION (ORIGINAL UNCHANGED) =====
    
    ResourceEntry data[SIZE];
    IndexPath ptr;
    
    // Original code here - do NOT modify this
    we[i] = port.weIn[i];
    wa[i] = port.waIn[i];
    wv[i] = port.wvIn[i];
    
    rv[i] = data[ra[i]];
    
    if (port.weIn[j]) begin
        rv[i] = port.wvIn[j];
    end
    
`endif
```

---

## Testing After Each File

```bash
make clean && make all
make run
# Must see: IPC (RISC-V instruction): 0.985285
#          Elapsed cycles:        4621
```

**If baseline changes**:
1. Revert last file
2. Find the problem
3. Fix and test again
4. DO NOT COMMIT if baseline changes

---

## Common Mistakes (Don't Do These!)

❌ **Mistake 1**: Forgetting thread check
```systemverilog
we[t][i] = port.weIn[i];  // WRONG - no thread check!
```

❌ **Mistake 2**: Cross-thread bypass
```systemverilog
if (we[j]) rv[i] = wv[j];  // WRONG - no thread check!
```

❌ **Mistake 3**: Modifying else clause
```systemverilog
`else
    data[SIZE] = 0;  // WRONG - modifies original!
    we[i] = port.weIn[i] && !something;  // WRONG!
`endif
```

❌ **Mistake 4**: Not extracting thread
```systemverilog
rv[port.thread[i]][0] = data[port.thread[i]][...];
rv[port.thread[i]][1] = data[port.thread[i]][...];  // Repeated lookups!
```

---

## Success Checklist

- [ ] Bypass network fix: Thread check added
- [ ] Baseline verified after bypass fix
- [ ] Free Lists: Per-thread implemented
- [ ] Baseline verified
- [ ] Active List: Per-thread implemented
- [ ] Baseline verified
- [ ] Issue Queue: Per-thread implemented
- [ ] Baseline verified
- [ ] Load Queue: Per-thread implemented
- [ ] Baseline verified
- [ ] Store Queue: Per-thread implemented
- [ ] Baseline verified
- [ ] Final integration test: All systems work together
- [ ] Baseline maintained: IPC 0.985285, cycles 4621

---

## Compilation Commands

```bash
# In /Users/kushal/rsd_mp/Processor/Src

# After each modification:
make clean
make all
make run

# Expected output:
# ... simulation output ...
# IPC (RISC-V instruction): 0.985285
# Elapsed cycles:        4621

# If error, check:
1. Syntax (mismatched ifdef/else/endif)
2. Array dimensions (forgot THREAD_NUM?)
3. Variable names (typos?)
4. Logic (correct thread checks?)
```

---

## Key Signals to Understand

### Thread ID Flow
- Thread ID comes from decode stage (verified Thread 1)
- Flows through pipeline to execution stages
- Needed in: Bypass, Load/Store issue, Resource allocation

### Bypass Network
- Searches execution stages for matching register
- Must also check thread matches
- Four stages: INT_EX, INT_WB, MEM_MA, MEM_WB

### Resource Allocation
- Free lists: Allocate on rename, deallocate on issue
- Load/Store queues: Allocate on rename, deallocate on commit
- Issue queue: Allocate on dispatch, deallocate on issue

### Recovery
- Signals per-thread operations to flush
- All per-thread resources have recovery support
- Load/Store queues already support per-thread tail pointers

---

## In Case of Problems

**Problem**: Compilation error
- Check for syntax errors in ifdef blocks
- Ensure arrays have correct dimensions [THREAD_NUM][index]
- Verify parentheses and semicolons

**Problem**: Baseline changes (IPC/cycles different)
- Likely logic error in implementation
- Revert last file and debug
- Check thread checking logic
- May need to adjust how thread ID flows

**Problem**: Test hangs
- Likely deadlock in recovery/pointer logic
- Check recovery signal timing
- Verify pointer updates per-thread
- May need to separate per-thread pointer updates

**Solution**: Always revert to baseline and debug incrementally

---

## Reference Files

**Pattern Template**: PHASE4_PATTERN_TEMPLATE.md
**Detailed Plan**: PHASE4_IMPLEMENTATION_PLAN.md
**Analysis**: CRITICAL_FILES_ANALYSIS_THREAD2.md
**Go Decision**: GO_NO_GO_DECISION.txt

---

## Quick Facts

- **SMT Enable Flag**: `RSD_ENABLE_SMT` (in ifdef)
- **Thread Count**: `THREAD_NUM` (typically 2)
- **Base Pattern**: RMT.sv (proven working)
- **Baseline**: IPC 0.985285, cycles 4621 (MUST MAINTAIN)
- **Blocking Issue**: 1 (bypass network fix - 30 min)
- **Total Effort**: ~6 hours
- **Risk Level**: LOW (pattern proven, fix well-defined)

---

## Next Steps

1. ✅ Read this quick reference (5 min)
2. ✅ Read PHASE4_IMPLEMENTATION_PLAN.md (15 min)
3. ⏳ Apply bypass network fix (30 min)
4. ⏳ Verify baseline: `make run`
5. ⏳ Implement Free Lists (45 min)
6. ⏳ Implement Active List (60 min)
7. ⏳ Implement Issue Queue (60 min)
8. ⏳ Implement Load Queue (45 min)
9. ⏳ Implement Store Queue (45 min)
10. ⏳ Final integration test

**Total Time**: ~6 hours from start to completion

---

## Remember

✅ **Always test after each file**
✅ **Always maintain baseline IPC 0.985285, 4621 cycles**
✅ **Always follow RMT.sv pattern exactly**
✅ **Always add thread check for writes: `we[t][i] && (port.thread[i] == t)`**
✅ **Always extract thread once: `ThreadID threadID = port.thread[i]`**
✅ **Always check thread for bypass: `if (port.thread[j] == threadID)`**

---

**Status**: Ready to begin Phase 4  
**Next**: Apply bypass fix and implement resources  
**Expected Completion**: 6 hours  

Let's go! 🚀
