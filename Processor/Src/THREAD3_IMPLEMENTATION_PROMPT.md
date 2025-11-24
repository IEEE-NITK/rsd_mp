# THREAD 3 IMPLEMENTATION PROMPT

**Previous Thread**: Thread 2 (Critical File Analysis - COMPLETED)  
**Current Thread**: Thread 3 (Phase 4 Implementation - START HERE)  
**Next Thread**: Thread 4+ (Phase 5 and beyond)  

**Status**: Ready to implement Phase 4 with one prerequisite fix  
**Baseline to Maintain**: IPC 0.985285, 4621 cycles (CRITICAL)  
**Estimated Duration**: 5-6 hours total  

---

## 🎯 YOUR OBJECTIVE

Implement Phase 4: Per-thread resource allocation for SMT support.

**What to deliver**:
1. Fix bypass network thread safety (PREREQUISITE)
2. Implement per-thread Free Lists
3. Implement per-thread Active List
4. Implement per-thread Issue Queue
5. Implement per-thread Load Queue
6. Implement per-thread Store Queue
7. Verify baseline maintained: IPC 0.985285, 4621 cycles

**Success = all of above + baseline maintained**

---

## 📋 CONTEXT FROM PREVIOUS THREADS

### What Thread 1 Did (Completed)
- ✅ Verified Phase 1-3 correct
- ✅ Identified thread ID flows through pipeline to dispatch stage
- ✅ RMT.sv pattern proven working for per-thread resources
- ✅ Baseline confirmed: IPC 0.985285, 4621 cycles

### What Thread 2 Did (Completed)
- ✅ Analyzed 10 critical files
- ✅ Identified ONE BLOCKING ISSUE: Bypass network not thread-safe
- ✅ Made design decisions:
  - Issue Queue: Per-thread queues (not shared)
  - Load/Store Queues: Per-thread queues
  - Free Lists: RMT.sv pattern (per-thread)
  - Active List: RMT.sv pattern (per-thread)
  - Bypass: ADD THREAD CHECKING
  - Recovery: Keep global (compatible)
  - Controller: Keep global (acceptable)
- ✅ Created implementation plan (PHASE4_IMPLEMENTATION_PLAN.md)

### What You Must Do Now (This Thread)
1. Fix bypass network thread safety (prerequisite)
2. Implement per-thread resources
3. Test after each file
4. Maintain baseline throughout

---

## 🔴 CRITICAL PREREQUISITE: Bypass Network Fix

**MUST DO THIS FIRST - Do not skip**

**Problem**: Current bypass doesn't check thread, allows cross-thread data leakage
```
Thread 0 reads register 5 → Could receive Thread 1's value from bypass
This is DATA CORRUPTION
```

**Solution**: Add ThreadID field and thread checking to bypass pipeline

### Step-by-Step Bypass Fix

**File**: `/Users/kushal/rsd_mp/Processor/Src/RegisterFile/BypassController.sv`

**Changes Required**:

1. **Modify BypassCtrlOperand struct** (around line 17-21):
```systemverilog
typedef struct packed // struct BypassCtrlOperand
{
    PRegNumPath dstRegNum;
    logic writeReg;
    ThreadID thread;  // ADD THIS LINE
} BypassCtrlOperand;
```

2. **Update BypassCtrlStage module** (around line 24-47):
```systemverilog
module BypassCtrlStage(
    input  logic clk, rst, 
    input  PipelineControll ctrl,
    input  BypassCtrlOperand in, 
    input  ThreadID threadIn,  // ADD THIS
    output BypassCtrlOperand out,
    output ThreadID threadOut  // ADD THIS
);
    BypassCtrlOperand body;
    ThreadID bodyThread;  // ADD THIS
    
    always_ff@( posedge clk ) begin
        if( rst || ctrl.clear ) begin
            body.dstRegNum <= 0;
            body.writeReg  <= FALSE;
            bodyThread <= '0;  // ADD THIS
        end
        else if( ctrl.stall ) begin
            body <= body;
            bodyThread <= bodyThread;  // ADD THIS
        end
        else begin
            body <= in;
            bodyThread <= threadIn;  // ADD THIS
        end
    end
    
    assign out = body;
    assign threadOut = bodyThread;  // ADD THIS
endmodule
```

3. **Update SelectReg function** (around line 54-106):
Add `ThreadID reqThread` parameter and add thread checks:

```systemverilog
function automatic BypassSelect SelectReg( 
    input
        PRegNumPath regNum,
        logic read,
        ThreadID reqThread,  // ADD THIS
        BypassCtrlOperand intEX [ INT_ISSUE_WIDTH ],
        BypassCtrlOperand intWB [ INT_ISSUE_WIDTH ],
        BypassCtrlOperand memMA [ LOAD_ISSUE_WIDTH ],
        BypassCtrlOperand memWB [ LOAD_ISSUE_WIDTH ]
);
    BypassSelect ret;
    ret.valid = FALSE;
    ret.stg = BYPASS_STAGE_INT_EX;
    ret.lane.intLane = 0;
    ret.lane.memLane = 0;
    ret.lane.complexLane = 0; 
`ifdef RSD_MARCH_FP_PIPE
    ret.lane.fpLane = 0; 
`endif

    for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
        // CHANGE: Add thread check
        if ( read && intEX[i].writeReg && regNum == intEX[i].dstRegNum &&
             reqThread == intEX[i].thread ) begin  // ADD THREAD CHECK
            ret.valid = TRUE;
            ret.stg = BYPASS_STAGE_INT_EX;
            ret.lane.intLane = i;
            break;
        end
        // CHANGE: Add thread check
        if ( read && intWB[i].writeReg && regNum == intWB[i].dstRegNum &&
             reqThread == intWB[i].thread ) begin  // ADD THREAD CHECK
            ret.valid = TRUE;
            ret.stg = BYPASS_STAGE_INT_WB;
            ret.lane.intLane = i;
            break;
        end
    end
    
    for ( int i = 0; i < LOAD_ISSUE_WIDTH; i++ ) begin
        // CHANGE: Add thread check
        if ( read && memMA[i].writeReg && regNum == memMA[i].dstRegNum &&
             reqThread == memMA[i].thread ) begin  // ADD THREAD CHECK
            ret.valid = TRUE;
            ret.stg = BYPASS_STAGE_MEM_MA;
            ret.lane.memLane = i;
            break;
        end
        // CHANGE: Add thread check
        if ( read && memWB[i].writeReg && regNum == memWB[i].dstRegNum &&
             reqThread == memWB[i].thread ) begin  // ADD THREAD CHECK
            ret.valid = TRUE;
            ret.stg = BYPASS_STAGE_MEM_WB;
            ret.lane.memLane = i;
            break;
        end
    end
    
    return ret;
endfunction
```

4. **Update all SelectReg calls** (around line 149-186):
```systemverilog
always_comb begin
    for ( int i = 0; i < INT_ISSUE_WIDTH; i++ ) begin
        intRR[i].dstRegNum = port.intPhyDstRegNum[i];
        intRR[i].writeReg  = port.intWriteReg[i];
        intRR[i].thread = port.intThreadID[i];  // ADD THIS

        // Add reqThread parameter to all SelectReg calls
        intBypassCtrl[i].rA = SelectReg ( 
            port.intPhySrcRegNumA[i], 
            port.intReadRegA[i],
            port.intThreadID[i],  // ADD THIS
            intEX, intWB, memMA, memWB 
        );
        intBypassCtrl[i].rB = SelectReg ( 
            port.intPhySrcRegNumB[i], 
            port.intReadRegB[i],
            port.intThreadID[i],  // ADD THIS
            intEX, intWB, memMA, memWB 
        );
    end
    // ... similar changes for all other SelectReg calls ...
end
```

5. **Update bypass pipeline stage instantiations** (around line 128-138):
```systemverilog
for ( genvar i = 0; i < INT_ISSUE_WIDTH; i++ ) begin : stgInt
    BypassCtrlStage stgIntRR( 
        clk, rst, ctrl.backEnd, 
        intRR[i], port.intThreadID[i],  // ADD thread input
        intEX[i], intThreadRR_EX[i]     // ADD thread output
    );
    BypassCtrlStage stgIntEX( 
        clk, rst, ctrl.backEnd, 
        intEX[i], intThreadRR_EX[i],  // ADD thread input
        intWB[i], intThreadEX_WB[i]   // ADD thread output
    );
end
```

**After modification**:
```bash
cd /Users/kushal/rsd_mp/Processor/Src
make clean
make all
make run

# Expected output:
# IPC (RISC-V instruction): 0.985285
# Elapsed cycles:        4621

# IF DIFFERENT: REVERT AND DEBUG
```

**Status**: Must complete before moving to Phase 4

---

## ✅ PHASE 4 IMPLEMENTATION

After bypass fix is verified, implement these 5 resources in order:

### RESOURCE 1: Free Lists (45 minutes)

**What**: Make free lists per-thread

**Where**: Identify free list module (likely in RenameLogic/ or separate module)

**How**: Apply RMT.sv pattern
1. Find free list data structure
2. Wrap with `ifdef RSD_ENABLE_SMT / else / endif`
3. Add THREAD_NUM dimension to array
4. In ifdef block, loop over threads and add thread check:
   ```systemverilog
   we[t][i] = weIn[i] && (thread[i] == t);
   ```
5. In else block, copy original logic unchanged

**Test After**:
```bash
make clean && make all
make run
# Verify: IPC 0.985285, cycles 4621
```

**Reference**: PHASE4_PATTERN_TEMPLATE.md (Template Variant A)

---

### RESOURCE 2: Active List (60 minutes)

**What**: Make active list per-thread

**Where**: Likely RenameLogic/ActiveList.sv or separate module

**How**: Apply RMT.sv pattern
1. Find active list structure (array or FIFO)
2. If simple array:
   ```systemverilog
   `ifdef RSD_ENABLE_SMT
       ActiveListEntry al[THREAD_NUM][SIZE];
       IndexPath ptr[THREAD_NUM];
   `else
       ActiveListEntry al[SIZE];
       IndexPath ptr;
   `endif
   ```
3. If FIFO structure (head/tail pointers):
   ```systemverilog
   `ifdef RSD_ENABLE_SMT
       data[THREAD_NUM][SIZE]
       headPtr[THREAD_NUM]
       tailPtr[THREAD_NUM]
   `else
       data[SIZE]
       headPtr
       tailPtr
   `endif
   ```
4. Update all array accesses to add thread dimension
5. Keep else clause unchanged

**Test After**:
```bash
make clean && make all
make run
# Verify: IPC 0.985285, cycles 4621
```

**Reference**: PHASE4_PATTERN_TEMPLATE.md (Variant B if FIFO)

---

### RESOURCE 3: Issue Queue (60 minutes)

**What**: Make issue queue per-thread

**Where**: `/Users/kushal/rsd_mp/Processor/Src/Scheduler/IssueQueue.sv`

**Design**: Per-thread allocators + per-thread payload RAMs

**How**:
1. **Allocator replication** (lines 47-64):
   ```systemverilog
   `ifdef RSD_ENABLE_SMT
       MultiWidthFreeList issueQueueFreeList[THREAD_NUM] (...)
   `else
       MultiWidthFreeList issueQueueFreeList (...)
   `endif
   ```

2. **Payload RAM replication** (lines 131-189):
   ```systemverilog
   `ifdef RSD_ENABLE_SMT
       DistributedMultiPortRAM intPayloadRAM[THREAD_NUM] (...)
       DistributedMultiPortRAM memPayloadRAM[THREAD_NUM] (...)
       // ... etc for all RAM types
   `else
       DistributedMultiPortRAM intPayloadRAM (...)
       DistributedMultiPortRAM memPayloadRAM (...)
       // ... etc original code unchanged
   `endif
   ```

3. **Thread multiplexing on dispatch**:
   Add logic to write to correct thread's queue based on `port.writeThread[i]`

4. **Thread multiplexing on read**:
   Add logic to read from correct thread's queue based on thread ID

**Critical**: In lines 242-245, ensure `selectedPtr` routing works with per-thread design

**Test After**:
```bash
make clean && make all
make run
# Verify: IPC 0.985285, cycles 4621
```

---

### RESOURCE 4: Load Queue (45 minutes)

**What**: Make load queue per-thread

**Where**: `/Users/kushal/rsd_mp/Processor/Src/LoadStoreUnit/LoadQueue.sv`

**How**: Apply RMT.sv pattern
1. Find LoadQueueEntry definition (around line 83)
2. Add per-thread dimension:
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
3. Update queue pointer controller for per-thread (lines 42-55)
4. Update all array accesses with thread dimension
5. Update recovery pointer setting: `recovery.loadQueueRecoveryTailPtr[t]`

**Test After**:
```bash
make clean && make all
make run
# Verify: IPC 0.985285, cycles 4621
```

**Reference**: PHASE4_PATTERN_TEMPLATE.md

---

### RESOURCE 5: Store Queue (45 minutes)

**What**: Make store queue per-thread

**Where**: `/Users/kushal/rsd_mp/Processor/Src/LoadStoreUnit/StoreQueue.sv`

**How**: Apply RMT.sv pattern
1. Find StoreQueueAddrEntry and StoreQueueDataEntry definitions (lines 42-43, 198+)
2. Add per-thread dimension:
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
3. Update queue pointer controller for per-thread (lines 58-71)
4. Update all array accesses with thread dimension
5. Update recovery pointer setting: `recovery.storeQueueRecoveryTailPtr[t]`

**Test After**:
```bash
make clean && make all
make run
# Verify: IPC 0.985285, cycles 4621
```

**Reference**: PHASE4_PATTERN_TEMPLATE.md

---

## 🔧 THE PATTERN (Copy This Template)

**IMPORTANT**: All modifications follow this exact pattern - DO NOT DEVIATE

```systemverilog
`ifdef RSD_ENABLE_SMT
    // ========== MULTI-THREADED VERSION ==========
    
    // Per-thread data structure
    ResourceEntry data[THREAD_NUM][SIZE];
    ResourceIndexPath ptr[THREAD_NUM];
    
    // Per-thread write signals
    logic we[THREAD_NUM][WRITE_WIDTH];
    ResourceIndexPath wa[THREAD_NUM][WRITE_WIDTH];
    ResourceEntry wv[THREAD_NUM][WRITE_WIDTH];
    
    // Per-thread read signals
    ResourceIndexPath ra[THREAD_NUM][READ_WIDTH];
    ResourceEntry rv[THREAD_NUM][READ_WIDTH];
    
    always_comb begin
        // Per-thread processing loop
        for (int t = 0; t < THREAD_NUM; t++) begin
            
            // Write logic
            for (int i = 0; i < WRITE_WIDTH; i++) begin
                // CRITICAL RULE 1: Check thread matches
                we[t][i] = port.weIn[i] && (port.thread[i] == t);
                wa[t][i] = port.waIn[i];
                wv[t][i] = port.wvIn[i];
                
                // Write-to-write bypass
                for (int j = 0; j < i; j++) begin
                    if (we[t][i] && wa[t][i] == wa[t][j]) begin
                        we[t][j] = FALSE;
                    end
                end
            end
            
            // Read logic
            for (int i = 0; i < READ_WIDTH; i++) begin
                ra[t][i] = port.raIn[i];
            end
        end
        
        // Output reads from appropriate thread
        for (int i = 0; i < READ_WIDTH; i++) begin
            // CRITICAL RULE 2: Extract thread once
            ThreadID threadID = port.thread[i];
            
            // Read from thread-specific data
            rv[threadID][i] = data[threadID][ra[threadID][i]];
            
            // CRITICAL RULE 3: Bypass only same thread
            for (int j = 0; j < i; j++) begin
                if (port.weIn[j] && (port.thread[j] == threadID)) begin
                    if (port.waIn[j] == port.raIn[i]) begin
                        rv[threadID][i] = port.wvIn[j];
                    end
                end
            end
        end
        
        port.readOut = rv[port.thread[0]];
    end
    
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int t = 0; t < THREAD_NUM; t++) begin
                ptr[t] <= '0;
            end
        end
        else begin
            for (int t = 0; t < THREAD_NUM; t++) begin
                if (port.updateEn[t]) begin
                    ptr[t] <= port.nextPtr[t];
                end
            end
        end
    end

`else
    // ========== SINGLE-THREADED VERSION (ORIGINAL UNCHANGED) ==========
    
    ResourceEntry data[SIZE];
    ResourceIndexPath ptr;
    
    logic we[WRITE_WIDTH];
    ResourceIndexPath wa[WRITE_WIDTH];
    ResourceEntry wv[WRITE_WIDTH];
    
    ResourceIndexPath ra[READ_WIDTH];
    ResourceEntry rv[READ_WIDTH];
    
    // CRITICAL RULE 4: COPY ORIGINAL LOGIC EXACTLY - NO MODIFICATIONS
    always_comb begin
        for (int i = 0; i < WRITE_WIDTH; i++) begin
            we[i] = port.weIn[i];
            wa[i] = port.waIn[i];
            wv[i] = port.wvIn[i];
            
            for (int j = 0; j < i; j++) begin
                if (we[i] && wa[i] == wa[j]) begin
                    we[j] = FALSE;
                end
            end
        end
        
        for (int i = 0; i < READ_WIDTH; i++) begin
            ra[i] = port.raIn[i];
            rv[i] = data[ra[i]];
            
            for (int j = 0; j < i; j++) begin
                if (port.weIn[j]) begin
                    if (port.waIn[j] == port.raIn[i]) begin
                        rv[i] = port.wvIn[j];
                    end
                end
            end
        end
        
        port.readOut = rv;
    end
    
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            ptr <= '0;
        end
        else begin
            if (port.updateEn) begin
                ptr <= port.nextPtr;
            end
        end
    end

`endif
```

**CRITICAL RULES** (Don't break these):
1. ✅ **Thread Check for Writes**: `we[t][i] = weIn[i] && (thread[i] == t);`
2. ✅ **Extract Thread Once**: `ThreadID threadID = port.thread[i];`
3. ✅ **Bypass Same Thread Only**: `if (port.thread[j] == threadID)`
4. ✅ **Preserve Original**: Copy original to else clause UNCHANGED
5. ✅ **Loop Structure**: Outer loop for THREAD_NUM, inner for WIDTH

---

## 📊 IMPLEMENTATION CHECKLIST

### Before Starting:
- [ ] Read this prompt completely
- [ ] Read PHASE4_QUICK_REFERENCE.md
- [ ] Read PHASE4_IMPLEMENTATION_PLAN.md
- [ ] Understand baseline: IPC 0.985285, cycles 4621

### Part 1: Prerequisite (MUST DO FIRST)
- [ ] Read detailed bypass fix steps above
- [ ] Modify RegisterFile/BypassController.sv
  - [ ] Add ThreadID to BypassCtrlOperand struct
  - [ ] Add ThreadID to BypassCtrlStage module
  - [ ] Add reqThread parameter to SelectReg function
  - [ ] Add thread checks in SelectReg loops
  - [ ] Update all SelectReg calls with thread parameter
  - [ ] Update bypass pipeline instantiations
- [ ] Compile: `make clean && make all`
- [ ] Test: `make run`
- [ ] Verify: IPC 0.985285, cycles 4621 (CRITICAL)

### Part 2: Phase 4 Implementation
- [ ] Free Lists
  - [ ] Locate free list module/code
  - [ ] Apply RMT.sv pattern (ifdef block)
  - [ ] Compile: `make clean && make all`
  - [ ] Test: `make run`
  - [ ] Verify: IPC 0.985285, cycles 4621
  
- [ ] Active List
  - [ ] Locate active list code
  - [ ] Apply RMT.sv pattern (ifdef block)
  - [ ] Compile: `make clean && make all`
  - [ ] Test: `make run`
  - [ ] Verify: IPC 0.985285, cycles 4621
  
- [ ] Issue Queue
  - [ ] Open Scheduler/IssueQueue.sv
  - [ ] Replicate free list allocator per-thread
  - [ ] Replicate payload RAMs per-thread
  - [ ] Add thread multiplexing on dispatch
  - [ ] Add thread multiplexing on read
  - [ ] Compile: `make clean && make all`
  - [ ] Test: `make run`
  - [ ] Verify: IPC 0.985285, cycles 4621
  
- [ ] Load Queue
  - [ ] Open LoadStoreUnit/LoadQueue.sv
  - [ ] Apply RMT.sv pattern (ifdef block)
  - [ ] Add per-thread dimension to all arrays
  - [ ] Update queue pointer controller
  - [ ] Update recovery pointer routing
  - [ ] Compile: `make clean && make all`
  - [ ] Test: `make run`
  - [ ] Verify: IPC 0.985285, cycles 4621
  
- [ ] Store Queue
  - [ ] Open LoadStoreUnit/StoreQueue.sv
  - [ ] Apply RMT.sv pattern (ifdef block)
  - [ ] Add per-thread dimension to all arrays
  - [ ] Update queue pointer controller
  - [ ] Update recovery pointer routing
  - [ ] Compile: `make clean && make all`
  - [ ] Test: `make run`
  - [ ] Verify: IPC 0.985285, cycles 4621

### Part 3: Final Verification
- [ ] Full integration test: `make clean && make all && make run`
- [ ] Verify baseline exactly: IPC 0.985285, cycles 4621
- [ ] All files compile without errors
- [ ] All files compile without warnings
- [ ] Review all changes follow RMT.sv pattern
- [ ] No cross-thread logic found
- [ ] No hardcoded assumptions about single thread

---

## 🧪 TESTING COMMANDS

After each file modification:

```bash
cd /Users/kushal/rsd_mp/Processor/Src

# Compile
make clean
make all

# Test
make run

# Expected output format:
# ... simulation output ...
# IPC (RISC-V instruction): 0.985285
# Elapsed cycles:        4621
```

**IF BASELINE CHANGES**:
1. Note the IPC and cycle count
2. Revert the last file modified
3. Re-test to confirm baseline returns
4. Debug the problematic code
5. Identify the logic error
6. Fix the issue
7. Test again
8. Only then move forward

**NEVER commit code that changes baseline**

---

## 🚨 COMMON MISTAKES (Don't Make These!)

❌ **Mistake 1: Forgetting thread check on writes**
```systemverilog
// WRONG:
we[t][i] = port.weIn[i];  // No thread check!

// CORRECT:
we[t][i] = port.weIn[i] && (port.thread[i] == t);
```

❌ **Mistake 2: Cross-thread bypass**
```systemverilog
// WRONG:
rv[i] = port.wvIn[j];  // No thread check!

// CORRECT:
if (port.thread[j] == threadID) begin
    rv[i] = port.wvIn[j];
end
```

❌ **Mistake 3: Modifying else clause**
```systemverilog
// WRONG:
`else
    we[i] = port.weIn[i];
    wa[i] = port.waIn[i];  // These are ORIGINAL code!
    wv[i] = port.wvIn[i];  // Can't modify!

// CORRECT:
`else
    // EXACT copy of original (no changes):
    for (int i = 0; i < WRITE_WIDTH; i++) begin
        we[i] = port.weIn[i];
        wa[i] = port.waIn[i];
        wv[i] = port.wvIn[i];
    end
`endif
```

❌ **Mistake 4: Not extracting thread**
```systemverilog
// WRONG - repeated lookups:
rv[port.thread[i]][0] = data[port.thread[i]][...];
rv[port.thread[i]][1] = data[port.thread[i]][...];

// CORRECT - extract once:
ThreadID threadID = port.thread[i];
rv[threadID][0] = data[threadID][...];
rv[threadID][1] = data[threadID][...];
```

❌ **Mistake 5: Changing baseline**
```
make run shows:
  IPC: 0.984000  ✗ WRONG (was 0.985285)
  
Action: REVERT and DEBUG - DO NOT COMMIT
```

---

## 📚 REFERENCE DOCUMENTS

Located in: `/Users/kushal/rsd_mp/Processor/Src/`

**Read First**:
- PHASE4_QUICK_REFERENCE.md - One-page quick ref while coding
- GO_NO_GO_DECISION.txt - Why Phase 4 is approved

**While Implementing**:
- PHASE4_PATTERN_TEMPLATE.md - Code pattern (copy/paste template)
- PHASE4_IMPLEMENTATION_PLAN.md - Detailed procedures

**For Details**:
- CRITICAL_FILES_ANALYSIS_THREAD2.md - Technical analysis why per-thread works
- THREAD2_ANALYSIS_SUMMARY.md - Summary of findings

**From Thread 1**:
- RenameLogic/RMT.sv - EXACT pattern to follow (lines 41-185)
- PHASE3_VERIFICATION_REPORT.md - Thread 1 findings

---

## 📱 QUICK NAVIGATION

**"Where do I start?"**
→ Apply bypass fix (detailed steps above)

**"What pattern do I use?"**
→ PHASE4_PATTERN_TEMPLATE.md (copy/paste template provided)

**"What's the bypass fix?"**
→ Detailed steps in "CRITICAL PREREQUISITE" section above

**"How do I test?"**
→ Section "TESTING COMMANDS" - run make clean && make all && make run

**"What if baseline changes?"**
→ Section "TESTING COMMANDS" - revert and debug

**"What order do I implement?"**
→ Bypass fix → Free Lists → Active List → Issue Queue → Load Queue → Store Queue

**"Which file first?"**
→ RegisterFile/BypassController.sv (bypass fix - MUST BE FIRST)

---

## ✅ SUCCESS CRITERIA

After completing Phase 4:

1. ✅ Bypass network has thread checking
2. ✅ Free Lists are per-thread (RMT.sv pattern)
3. ✅ Active List is per-thread (RMT.sv pattern)
4. ✅ Issue Queue is per-thread
5. ✅ Load Queue is per-thread (RMT.sv pattern)
6. ✅ Store Queue is per-thread (RMT.sv pattern)
7. ✅ Code compiles without errors
8. ✅ Code compiles without warnings
9. ✅ `make run` succeeds
10. ✅ Baseline maintained: **IPC 0.985285, cycles 4621** (exactly)
11. ✅ All per-thread logic follows RMT.sv pattern
12. ✅ No cross-thread data leakage possible

---

## 📈 TIMELINE ESTIMATE

```
Bypass fix:              30 min
Free Lists:              45 min
Active List:             60 min
Issue Queue:             60 min
Load Queue:              45 min
Store Queue:             45 min
Integration testing:     30-60 min
────────────────────────────
Total:                   5-6 hours
```

---

## 🎯 WHAT TO DO NEXT (After This Thread)

Once Phase 4 is complete:
1. Document what was implemented
2. Verify all per-thread resources work correctly
3. Consider Phase 5 (thread-aware execution)
4. Extend per-thread controller if needed
5. Add thread-aware scheduling/execution units

---

## 🔗 FINAL NOTES

- **DO NOT SKIP the bypass fix** - It's critical for correctness
- **TEST AFTER EACH FILE** - Don't batch changes
- **MAINTAIN BASELINE** - If it changes, revert and debug
- **FOLLOW THE PATTERN** - Don't deviate from RMT.sv template
- **READ REFERENCE DOCS** - They exist for a reason

**You have everything you need. Execute the plan and Phase 4 will be complete.**

---

**Status**: Ready to implement Phase 4  
**Time Available**: ~6 hours  
**Baseline Target**: IPC 0.985285, 4621 cycles  
**Success Definition**: All per-thread resources implemented + baseline maintained  

**Good luck! 🚀**
