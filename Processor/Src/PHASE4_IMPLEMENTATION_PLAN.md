# Phase 4 Implementation Plan - Per-Thread Resource Allocation

**Status**: Ready to begin  
**Prerequisites**: Bypass network fix (identified)  
**Baseline**: IPC 0.985285, cycles 4621 (MUST MAINTAIN)  
**Timeline**: ~6 hours total  

---

## Part 1: Prerequisite - Bypass Network Thread Safety Fix

### Task 1.1: Fix RegisterFile/BypassController.sv

**Problem**: Bypass network doesn't check thread, allowing cross-thread data forwarding

**Solution**: Add thread field to bypass control signals

**Steps**:

1. **Identify where thread information exists**:
   - Thread is available in execution stages (verified in Thread 1)
   - Need to propagate through bypass pipeline stages

2. **Modify BypassCtrlStage** (lines 24-47):
   ```systemverilog
   module BypassCtrlStage(
       input  logic clk, rst, 
       input  PipelineControll ctrl,
       input  BypassCtrlOperand in,
       input  ThreadID thread,      // ADD THIS
       output BypassCtrlOperand out,
       output ThreadID threadOut    // ADD THIS
   );
   ```

3. **Update BypassCtrlOperand struct** (lines 17-21):
   ```systemverilog
   typedef struct packed {
       PRegNumPath dstRegNum;
       logic writeReg;
       ThreadID thread;             // ADD THIS
   } BypassCtrlOperand;
   ```

4. **Modify SelectReg function** (lines 54-106):
   ```systemverilog
   function automatic BypassSelect SelectReg(
       input PRegNumPath regNum,
       logic read,
       ThreadID reqThread,          // ADD THIS
       BypassCtrlOperand intEX [...],
       ...
   );
   // In the loop:
   for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
       if (read && intEX[i].writeReg && 
           regNum == intEX[i].dstRegNum &&
           reqThread == intEX[i].thread) begin  // ADD THREAD CHECK
           ret.valid = TRUE;
           ...
       end
   end
   ```

5. **Update all SelectReg calls** (lines 154-182):
   ```systemverilog
   intBypassCtrl[i].rA = SelectReg(
       port.intPhySrcRegNumA[i], 
       port.intReadRegA[i],
       port.intThreadID[i],         // ADD THIS - need from interface
       intEX, intWB, memMA, memWB
   );
   ```

**Files to Modify**:
- RegisterFile/BypassController.sv
- RegisterFileIF.sv (may need thread field in interface)

**Test After**:
```bash
cd /Users/kushal/rsd_mp/Processor/Src
make clean && make all
make run
# Verify: IPC 0.985285, cycles 4621
```

**Estimated Time**: 30 min

---

## Part 2: Phase 4 Implementation - Per-Thread Resources

### Part 2a: Free Lists (Per-Thread)

**File**: RenameLogic/RenameLogic.sv (or dedicated free list module)

**Pattern**: Use RMT.sv template

**Steps**:

1. **Understand current free list**:
   - Allocate on rename, deallocate on issue
   - Separate lists for int, FP, etc.
   - Check how many free list modules exist

2. **Apply per-thread template**:
   ```systemverilog
   `ifdef RSD_ENABLE_SMT
       FreeListEntry freeList[THREAD_NUM][SIZE];
       FreeListIndexPath ptr[THREAD_NUM];
   `else
       FreeListEntry freeList[SIZE];
       FreeListIndexPath ptr;
   `endif
   ```

3. **Add thread check to allocation**:
   ```systemverilog
   we[t][i] = port.weIn[i] && (port.thread[i] == t);
   ```

4. **Compile and test**:
   ```bash
   make clean && make all && make run
   ```

**Estimated Time**: 45 min

---

### Part 2b: Active List (Per-Thread)

**File**: Likely in RenameLogic/ or separate ActiveList/

**Pattern**: Use RMT.sv template (or Variant B if FIFO structure)

**Steps**:

1. **Locate Active List file**:
   - Check RenameLogic/ directory
   - Check if separate ActiveList module exists
   - Understand current structure

2. **If simple array**:
   ```systemverilog
   `ifdef RSD_ENABLE_SMT
       ActiveListEntry al[THREAD_NUM][SIZE];
   `else
       ActiveListEntry al[SIZE];
   `endif
   ```

3. **If FIFO structure**:
   ```systemverilog
   `ifdef RSD_ENABLE_SMT
       ActiveListEntry data[THREAD_NUM][SIZE];
       IndexPath headPtr[THREAD_NUM];
       IndexPath tailPtr[THREAD_NUM];
   `else
       ActiveListEntry data[SIZE];
       IndexPath headPtr;
       IndexPath tailPtr;
   `endif
   ```

4. **Update pointer management**:
   ```systemverilog
   always_ff @(posedge clk) begin
   `ifdef RSD_ENABLE_SMT
       for (int t = 0; t < THREAD_NUM; t++) begin
           if (port.updateEn[t]) begin
               headPtr[t] <= port.nextHeadPtr[t];
           end
       end
   `else
       if (port.updateEn) begin
           headPtr <= port.nextHeadPtr;
       end
   `endif
   end
   ```

5. **Test**:
   ```bash
   make clean && make all && make run
   ```

**Estimated Time**: 60 min

---

### Part 2c: Issue Queue (Per-Thread Design)

**File**: Scheduler/IssueQueue.sv

**Pattern**: Replicate entire allocator and payload RAMs per-thread

**Steps**:

1. **Understand current structure**:
   - Free list allocator (lines 47-64)
   - Payload RAMs for each instruction type (lines 116-189)
   - Multiplexing of read/write ports

2. **Replicate allocator per-thread**:
   ```systemverilog
   `ifdef RSD_ENABLE_SMT
       MultiWidthFreeList iqFreeList[THREAD_NUM](...)
   `else
       MultiWidthFreeList iqFreeList(...)
   `endif
   ```

3. **Replicate payload RAMs**:
   ```systemverilog
   `ifdef RSD_ENABLE_SMT
       DistributedMultiPortRAM intPayloadRAM[THREAD_NUM](...)
       DistributedMultiPortRAM memPayloadRAM[THREAD_NUM](...)
   `else
       DistributedMultiPortRAM intPayloadRAM(...)
       DistributedMultiPortRAM memPayloadRAM(...)
   `endif
   ```

4. **Add thread multiplexing on dispatch**:
   ```systemverilog
   // Write to appropriate thread's queue
   ThreadID writeThread = port.writeThread[i];
   intPayloadRAM[writeThread].we[i] = port.write[i];
   intPayloadRAM[writeThread].wa[i] = port.writePtr[i];
   intPayloadRAM[writeThread].wv[i] = port.intWriteData[i];
   ```

5. **Add thread multiplexing on read**:
   ```systemverilog
   // Read from appropriate thread's queue
   ThreadID readThread = port.readThread[i];
   port.intIssuedData[i] = intPayloadRAM[readThread].rv[...];
   ```

6. **Test**:
   ```bash
   make clean && make all && make run
   ```

**Estimated Time**: 60 min

---

### Part 2d: Load Queue (Per-Thread)

**File**: LoadStoreUnit/LoadQueue.sv

**Pattern**: Use RMT.sv template

**Steps**:

1. **Identify core data structures**:
   - Head/tail pointers (lines 35-36)
   - Load queue entries array (line 83)
   - Queue pointer controller (lines 42-55)

2. **Replicate per-thread**:
   ```systemverilog
   `ifdef RSD_ENABLE_SMT
       LoadQueueEntry loadQueue[THREAD_NUM][LOAD_QUEUE_ENTRY_NUM];
       LoadQueueIndexPath headPtr[THREAD_NUM];
       LoadQueueIndexPath tailPtr[THREAD_NUM];
   `else
       LoadQueueEntry loadQueue[LOAD_QUEUE_ENTRY_NUM];
       LoadQueueIndexPath headPtr;
       LoadQueueIndexPath tailPtr;
   `endif
   ```

3. **Update queue pointer controller calls**:
   ```systemverilog
   `ifdef RSD_ENABLE_SMT
       SetTailMultiWidthQueuePointer queue[THREAD_NUM](
           .setTailPtr(recovery.loadQueueRecoveryTailPtr[t]),
           ...
       );
   `else
       SetTailMultiWidthQueuePointer queue(
           .setTailPtr(recovery.loadQueueRecoveryTailPtr),
           ...
       );
   `endif
   ```

4. **Update logic to handle per-thread**:
   - All array accesses add thread dimension: `loadQueue[threadID][index]`
   - Thread ID from dispatch stage (verified available)

5. **Test**:
   ```bash
   make clean && make all && make run
   ```

**Estimated Time**: 45 min

---

### Part 2e: Store Queue (Per-Thread)

**File**: LoadStoreUnit/StoreQueue.sv

**Pattern**: Use RMT.sv template

**Steps**:

1. **Identify data structures**:
   - Head/tail pointers (lines 49-50)
   - Address entry array (line 103)
   - Data entry array (lines 198+)
   - Queue pointer controller (lines 58-71)

2. **Replicate per-thread**:
   ```systemverilog
   `ifdef RSD_ENABLE_SMT
       StoreQueueAddrEntry storeQueue[THREAD_NUM][STORE_QUEUE_ENTRY_NUM-1:0];
       StoreQueueDataEntry sqReadData[THREAD_NUM][LOAD_ISSUE_WIDTH + 1];
       StoreQueueIndexPath headPtr[THREAD_NUM];
       StoreQueueIndexPath tailPtr[THREAD_NUM];
   `else
       StoreQueueAddrEntry storeQueue[STORE_QUEUE_ENTRY_NUM-1:0];
       StoreQueueDataEntry sqReadData[LOAD_ISSUE_WIDTH + 1];
       StoreQueueIndexPath headPtr;
       StoreQueueIndexPath tailPtr;
   `endif
   ```

3. **Update all accesses with thread dimension**

4. **Update recovery pointer setting**:
   ```systemverilog
   .setTailPtr(recovery.storeQueueRecoveryTailPtr[t])
   ```

5. **Test**:
   ```bash
   make clean && make all && make run
   ```

**Estimated Time**: 45 min

---

## Part 3: Integration & Testing

### Task 3.1: Full Integration Test

```bash
cd /Users/kushal/rsd_mp/Processor/Src
make clean
make all
make run
```

**Expected Output**:
```
IPC (RISC-V instruction): 0.985285
Elapsed cycles:        4621
```

**If baseline changes**:
1. Check modifications didn't introduce bugs
2. Review thread checking logic
3. Revert suspected file and test incrementally
4. DO NOT commit changes that affect baseline

### Task 3.2: Per-Thread Verification

**Not implemented yet, but design prepared for**:
- Thread ID should flow through all modified modules
- Each thread should access its own resources
- No cross-thread interference
- Recovery should work per-thread

---

## Implementation Checklist

### Prerequisite Phase:
- [ ] Read critical files analysis (CRITICAL_FILES_ANALYSIS_THREAD2.md)
- [ ] Understand bypass issue and fix
- [ ] Modify BypassController.sv
- [ ] Verify baseline: `make run` → IPC 0.985285, cycles 4621

### Phase 4 Implementation:
- [ ] Free Lists - Apply RMT.sv pattern
  - [ ] Code modification
  - [ ] Compilation: `make clean && make all`
  - [ ] Test: `make run`
  - [ ] Verify baseline maintained

- [ ] Active List - Apply RMT.sv pattern
  - [ ] Code modification
  - [ ] Compilation
  - [ ] Test
  - [ ] Verify baseline

- [ ] Issue Queue - Per-thread design
  - [ ] Code modification
  - [ ] Compilation
  - [ ] Test
  - [ ] Verify baseline

- [ ] Load Queue - Apply RMT.sv pattern
  - [ ] Code modification
  - [ ] Compilation
  - [ ] Test
  - [ ] Verify baseline

- [ ] Store Queue - Apply RMT.sv pattern
  - [ ] Code modification
  - [ ] Compilation
  - [ ] Test
  - [ ] Verify baseline

### Final Verification:
- [ ] All files compile without warnings
- [ ] `make run` succeeds
- [ ] Output: IPC 0.985285, cycles 4621 (exactly)
- [ ] Git status: all changes tracked
- [ ] Create Phase 4 summary document

---

## Success Criteria

✅ **Must Have**:
1. Code compiles without errors
2. Code compiles without warnings
3. `make run` executes successfully
4. Baseline maintained: IPC 0.985285, cycles 4621
5. All critical files modified follow RMT.sv pattern
6. Bypass network has thread checking

⚠️ **Important Notes**:
- Single-threaded execution must work identically
- No modification to compilation flags beyond `RSD_ENABLE_SMT`
- All changes must be backward compatible

---

## Troubleshooting Guide

### If compilation fails:
1. Check syntax in modified files
2. Verify `ifdef/else/endif` blocks are balanced
3. Ensure all array accesses have correct dimensions
4. Check for typos in new variable names

### If baseline changes (IPC or cycles different):
1. Revert last file modified
2. Test again
3. Find problematic code
4. Review thread checking logic
5. May need to adjust interface or signals

### If test hangs:
1. Likely deadlock in per-thread logic
2. Check for circular dependencies
3. Verify recovery signals work with per-thread resources
4. Review thread multiplexing logic

---

## Timeline

**Prerequisite Fix**: 30 min
- Fix bypass network thread safety
- Verify baseline

**Phase 4 Implementation**: ~4-5 hours
- Free Lists: 45 min
- Active List: 60 min
- Issue Queue: 60 min
- Load Queue: 45 min
- Store Queue: 45 min
- Integration testing: 30-60 min

**Total**: ~5-6 hours

---

## Next Steps After Phase 4

Once Phase 4 is complete (per-thread resources, baseline maintained):

1. **Phase 5** (future threads):
   - Per-thread instruction scheduling
   - Per-thread execution units
   - Independent stall/clear per thread
   - Multi-threaded correctness verification

2. **Validation**:
   - Run multi-threaded benchmarks
   - Verify performance improvement
   - Check for any cross-thread issues

3. **Documentation**:
   - Update design documents
   - Create per-thread resource diagram
   - Document thread ID flow through pipeline

---

## Pattern Reference

All modifications follow the **RMT.sv Pattern** (verified working):

```systemverilog
`ifdef RSD_ENABLE_SMT
    // Per-thread version
    ResourceEntry data[THREAD_NUM][SIZE];
    IndexPath ptr[THREAD_NUM];
    
    for (int t = 0; t < THREAD_NUM; t++) begin
        // Per-thread logic
        we[t][i] = port.weIn[i] && (port.thread[i] == t);
        rv[threadID][i] = data[threadID][...];
    end
`else
    // Original single-threaded version (unchanged)
    ResourceEntry data[SIZE];
    IndexPath ptr;
    
    // Original logic unchanged
`endif
```

**Remember**: Don't deviate from this pattern without justification.

---

## Critical Rules (Don't Forget!)

1. ✅ **Thread Check for Writes**: `we[t][i] && (port.thread[i] == t)`
2. ✅ **Extract Thread ID Once**: `ThreadID threadID = port.thread[i]`
3. ✅ **Bypass Within Same Thread**: `if (port.thread[j] == threadID)`
4. ✅ **Preserve Original in Else**: Copy original code exactly to else clause
5. ✅ **Loop Structure**: Outer loop for THREAD_NUM, inner for width

---

**Status**: Ready to begin Phase 4  
**Prerequisite**: Bypass fix must be done first  
**Expected Outcome**: Per-thread RMT, Active List, Issue Queue, Load/Store Queues with baseline maintained  

Good luck with Phase 4! 🚀
