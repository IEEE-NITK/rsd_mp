# SMT Round-Robin Implementation - Complete Modifications Summary

## Overview
This document maps all modifications made in the round-robin scheduling commit (5305c6e) to support multi-threading across the processor pipeline.

---

## 1. FUNDAMENTAL TYPE DEFINITIONS

### BasicTypes.sv (Lines 12-17)
**Purpose**: Define ThreadID type system for SMT

```verilog
// Thread ID for SMT support
localparam THREAD_NUM = CONF_THREAD_NUM;
localparam THREAD_NUM_BIT_WIDTH = (THREAD_NUM > 1) ? $clog2(THREAD_NUM) : 1;
typedef logic [THREAD_NUM_BIT_WIDTH-1:0] ThreadID;
```

**Verification Points**:
- ✓ THREAD_NUM defined in MicroArchConf.sv (typically 2)
- ✓ THREAD_NUM_BIT_WIDTH correctly calculated (1 bit for 2 threads)
- ✓ ThreadID type used consistently across all modules

### MicroArchConf.sv
**Purpose**: Configure thread count

```
CONF_THREAD_NUM = 2  // Configurable parameter
```

**Verification Points**:
- ✓ Thread count is set to 2
- ✓ Can be modified for 4, 8 threads by changing this parameter

---

## 2. PIPELINE REGISTERS - ThreadID PROPAGATION

### PipelineTypes.sv
**Changes**: Added `ThreadID tid` field to all pipeline register structures

**Affected Register Types**:
1. **FetchStageRegPath** (Line ~79)
   - Field: `ThreadID tid`
   - Purpose: Carries thread ID from fetch to predecode stage

2. **PreDecodeStageRegPath** (Line ~90)
   - Field: `ThreadID tid`
   - Purpose: Maintains thread ID through instruction predecoding

3. **DecodeStageRegPath** (Line ~103)
   - Field: `ThreadID tid`
   - Purpose: Associates instruction with thread during decode

4. **RenameStageRegPath** (Line ~120)
   - Field: `ThreadID tid`
   - Purpose: Preserves thread identity during renaming

5. **DispatchStageRegPath** (Line ~133)
   - Field: `ThreadID tid`
   - Purpose: Routes instruction to correct scheduler port

6. **IntegerRegisterReadStageRegPath** (Line ~179)
   - Field: `ThreadID tid`
   - Purpose: Thread-aware register file access

7. **IntegerExecutionStageRegPath** (Line ~191)
   - Field: `ThreadID tid`
   - Purpose: Tags execution results with thread

**Verification Tests**:
- ✓ Each register path contains exactly one `ThreadID tid` field
- ✓ Thread ID is preserved through all pipeline stages
- ✓ No stage loses thread ID information

---

## 3. FETCH STAGE - ROUND-ROBIN THREAD SELECTION

### NextPCStage.sv (Lines 37-66)
**Purpose**: Implement round-robin thread selection at fetch

**Implementation Details**:
```verilog
// Thread round-robin selector
ThreadID currentThread;
integer threadCounter;  // Increments each cycle

always_comb begin
    currentThread = threadCounter % THREAD_NUM;
end

always_ff @(posedge clk) begin
    threadCounter <= threadCounter + 1;
end
```

**Key Points**:
- `threadCounter` increments every cycle
- `currentThread = threadCounter % THREAD_NUM` selects thread
- For 2 threads: alternates 0→1→0→1→...
- `port.selectedTid` output broadcasts selected thread

**Verification Tests**:
```
1. Check threadCounter increments every cycle
2. Verify currentThread cycles through valid thread IDs
3. Confirm output selectedTid matches currentThread
4. Validate round-robin pattern across multiple cycles
5. Test with stall conditions (ICache miss):
   - Counter should pause
   - Thread selection should remain stable
```

### NextPCStageIF.sv (Line 36)
**Changes**: Added interface signal

```verilog
ThreadID selectedTid;  // Output: Currently selected thread
```

### FetchStage.sv (Lines 114, 160, 164, 177)
**Changes**: ThreadID propagation and output

```verilog
// Propagate thread ID from input to output
pipeReg[i].tid           // Input from previous stage
nextStage[i].tid = pipeReg[i].tid;  // Propagate forward
port.fetchThreadId[i] = nextStage[i].tid;  // Output array
```

### FetchStageIF.sv (Line 39)
**Interface Signal**:
```verilog
ThreadID fetchThreadId[FETCH_WIDTH];  // Output: Thread IDs of fetched instructions
```

---

## 4. BRANCH PREDICTION - PER-THREAD STATE

### FetchUnit/BranchPredictor.sv
**Changes**: Register structures and access patterns modified

**Key Modifications**:
- Branch predictor state accessed per-thread
- Thread ID extracted from fetch packets
- Per-thread history table indexing

### FetchUnit/Gshare.sv (Lines 152, 185)
**Purpose**: Global history with per-thread state

```verilog
// Per-thread history tracking
ThreadID currentThreadHistory;
currentThreadHistory = regBrGlobalHistory[port.fetchThreadID];
```

**Verification Tests**:
- ✓ Each thread maintains independent global history
- ✓ History updates are thread-specific
- ✓ No history cross-pollution between threads

### FetchUnit/Bimodal.sv
**Changes**: Per-thread predictor table access

### FetchUnit/BTB.sv (Lines 36-37, 91, 95, 121, 129)
**Purpose**: Thread-aware branch target buffer

**Implementation**:
```verilog
// Store thread ID along with fetch
ThreadID fetchTidReg[FETCH_WIDTH];
ThreadID nextFetchTidReg[FETCH_WIDTH];

// Pipeline thread ID
fetchTidReg <= nextFetchTidReg;

// Tag matching includes thread ID
if (btbRV[i].tid == fetchTidReg[i]) begin
    // BTB hit for this thread
end
```

**Verification Tests**:
- ✓ BTB entries tagged with thread ID
- ✓ BTB lookups filter by thread ID
- ✓ No stale BTB entries between threads

### FetchUnit/FetchUnitTypes.sv (Lines 44, 127, 141)
**Changes**: Added ThreadID fields to predictor structures

```verilog
typedef struct packed {
    // ... other fields ...
    ThreadID tid;  // Thread identifier
} BTBEntry;

typedef struct packed {
    // ... other fields ...
    ThreadID tid;
} BranchPredictorEntry;
```

---

## 5. PRE-DECODE TO DISPATCH STAGES - ThreadID PROPAGATION

### PreDecodeStage.sv
**Changes**: Simple thread ID pass-through

```verilog
// Propagate thread ID forward
nextStage[i].tid = pipeReg[i].tid;
```

### DecodeStage.sv (Line 290)
**Changes**: Thread ID preserved during instruction expansion

```verilog
// When instruction expands to multiple micro-ops
nextStage[i].tid = pipeReg[orgPickedInsnLane].tid;
```

**Verification Tests**:
- ✓ Thread ID maintained through multi-micro-op expansions
- ✓ All micro-ops from same RISC-V instruction get same TID

### RenameLogic/RenameLogicIF.sv (Line 17, 55)
**Interface Signals**:
```verilog
ThreadID tid[RENAME_WIDTH];          // Input
ThreadID rmtWriteReg_Tid[COMMIT_WIDTH];  // Output
```

### RenameStage.sv (Lines 345, 409)
**Changes**: Thread-aware register allocation

```verilog
// Create Active List entry with thread ID
alEntry[i].tid = pipeReg[i].tid;

// Dispatch to execution stage
nextStage[i].tid = pipeReg[i].tid;
```

### DispatchStage.sv (Lines 120, 156, 220, 247)
**Purpose**: Route instructions to per-thread scheduler queues

**Implementation**:
```verilog
// Integer execution queue
intEntry[i].tid = pipeReg[i].tid;

// Complex integer execution queue
complexEntry[i].tid = pipeReg[i].tid;

// Memory execution queue
memEntry[i].tid = pipeReg[i].tid;

// FP execution queue
fpEntry[i].tid = pipeReg[i].tid;
```

**Verification Tests**:
- ✓ Each issue queue entry has correct thread ID
- ✓ Instructions routed to correct scheduler ports
- ✓ Thread affinity maintained from fetch to execute

---

## 6. REGISTER RENAMING - THREAD-INDEXED RMT

### RenameLogic/RMT.sv (Lines 72-115)
**Purpose**: Register Mapping Table with per-thread banking

**Key Function**:
```verilog
function automatic logic [...] GetBankedAddr(ThreadID tid, LRegNumPath logReg);
    // Thread-indexed address generation
    return {tid, logReg};  // Concatenate tid with logical register number
endfunction
```

**Implementation Details**:
- RMT entries are indexed by `{tid, logReg}`
- Thread 0 logical reg X maps to RMT[0][X]
- Thread 1 logical reg X maps to RMT[1][X]
- Prevents register aliasing between threads

**Verification Tests**:
```
1. Verify RMT address generation:
   - Assert: GetBankedAddr(0, 5) != GetBankedAddr(1, 5)
   
2. Check RMT updates are thread-specific:
   - Commit from Thread 0 should not affect Thread 1's mappings
   - Each thread's logical registers map to independent physical registers

3. Validate register allocation per-thread:
   - Thread 0 and Thread 1 should use different physical registers
   - No physical register contention between threads
```

### RenameLogic/RenameLogicIF.sv
**Interface Signals**:
```verilog
ThreadID tid[RENAME_WIDTH];              // RMT read port thread IDs
ThreadID rmtWriteReg_Tid[COMMIT_WIDTH];  // RMT write port thread IDs
```

### RenameLogic/RenameLogic.sv (Lines 129, 180, 185, 192, 194)
**Changes**: Thread ID passed through to RMT

```verilog
ThreadID rmtWriteReg_Tid[COMMIT_WIDTH];
// Thread ID from Active List entries
```

---

## 7. ACTIVE LIST (REORDER BUFFER) - THREAD-PARTITIONED

### RenameLogic/ActiveList.sv (Lines 73-77)
**Purpose**: Partitioned ROB with dedicated entries per thread

**Key Function**:
```verilog
function automatic ActiveListIndexPath GetPartitionedPtr(
    ThreadID tid, 
    ActiveListIndexPath localPtr
);
    // Static partitioning: split ROB in half
    if (tid == 0) 
        return localPtr;
    else 
        return localPtr + THREAD_PARTITION_SIZE;
endfunction
```

**Implementation Details**:
- Total AL_ENTRY_NUM entries split between threads
- Thread 0: entries 0 to (AL_ENTRY_NUM/2 - 1)
- Thread 1: entries (AL_ENTRY_NUM/2) to (AL_ENTRY_NUM - 1)
- Each thread has independent head/tail pointers

**Verification Tests**:
```
1. Verify AL partitioning:
   - Check thread 0 uses first half
   - Check thread 1 uses second half
   
2. Validate independent commit tracking:
   - Each thread commits independently
   - Thread 0 commits don't affect Thread 1's AL
   
3. Test thread isolation:
   - Exception in Thread 0 shouldn't flush Thread 1's entries
   - Branch misprediction in Thread 1 shouldn't rollback Thread 0
```

### RenameLogic/ActiveListIF.sv (Line 21)
**Interface Signal**:
```verilog
ThreadID pushTid;  // Thread ID for AL write
```

### RenameLogic/RenameLogicCommitter.sv (Lines 61, 123, 128, 131, 155-172)
**Changes**: Per-thread commit operations

```verilog
// Commit handling is per-thread indexed
activeList.popHeadNum[tid]  // Pop from thread-specific head
recovery[tid].flushAllInsns  // Thread-selective recovery
```

---

## 8. SCHEDULER - ISSUE QUEUE WITH THREAD TAGGING

### Scheduler/SchedulerTypes.sv (Lines 132, 178, 238, 269)
**Changes**: ThreadID added to all issue queue entry types

```verilog
typedef struct packed {
    // ... other fields ...
    ThreadID tid;  // Thread identifier
} IntIssueQueueEntry;

typedef struct packed {
    // ... other fields ...
    ThreadID tid;
} ComplexIssueQueueEntry;

typedef struct packed {
    // ... other fields ...
    ThreadID tid;
} MemIssueQueueEntry;

typedef struct packed {
    // ... other fields ...
    ThreadID tid;
} FPIssueQueueEntry;
```

### Scheduler/IssueQueue.sv (Lines 40, 271, 285)
**Purpose**: Track thread ID for each queued instruction

```verilog
ThreadID tidReg[ISSUE_QUEUE_ENTRY_NUM];  // Shadow array

// Capture thread ID on write
ThreadID t = port.intWriteData[i].tid;
tidReg[WRITE_INDEX] = t;
```

**Verification Tests**:
- ✓ All issue queue entries have valid thread IDs
- ✓ Thread ID persists until instruction completes
- ✓ No thread ID corruption in queue

### Scheduler/SelectLogic.sv
**Purpose**: Select from queue respecting thread

### Scheduler/WakeupLogic.sv
**Purpose**: Wake up instructions, maintaining thread context

### Scheduler/DestinationRAM.sv
**Purpose**: Map destination registers with thread awareness

### Scheduler/WakeupPipelineRegister.sv (Lines 41, 131-139, 300, 316, 333, 353, 373)
**Purpose**: Pipeline wakeup signals with thread tracking

**Key Structures**:
```verilog
typedef struct packed {
    // ... other fields ...
    ThreadID tid;  // Thread ID of writeback result
} WakeupSelectData;

// Per-thread flush counters
logic [FLUSH_COUNTER_WIDTH-1:0] flushCounter[NUM_THREADS];

// Per-thread flush range pointers
logic flush[NUM_THREADS];
logic [FLUSH_RANGE_WIDTH-1:0] flushHeadPtr[NUM_THREADS];
```

**Implementation**:
```verilog
// Extract thread ID from Active List pointer
function automatic ThreadID GetTidFromALPtr(ActiveListIndexPath ptr);
    return (ptr >= THREAD_PARTITION_SIZE) ? 1'b1 : 1'b0;
endfunction

// Use in wakeup results
ThreadID t = GetTidFromALPtr(resultPtr);
flushCounter[t]++;
```

**Verification Tests**:
- ✓ Wakeup signals include thread ID
- ✓ Per-thread flush counters updated correctly
- ✓ Flush operations don't cross thread boundaries

---

## 9. MEMORY DEPENDENCY PREDICTION - THREAD-INDEXED ACCESS

### Scheduler/MemoryDependencyPredictor.sv (Lines 56-72)
**Purpose**: Per-thread memory dependency tracking

**Key Function**:
```verilog
function automatic MDT_IndexPath GetThreadedMDTIndex(PC_Path pc, ThreadID tid);
    // XOR-based thread hashing
    return ToMDT_Index(pc) ^ (MDT_IndexPath'(tid) << 5);
endfunction

// Per-thread MDT access
ThreadID accessTid = port.memTid[i];
MDT_IndexPath mdtIdx = GetThreadedMDTIndex(port.pc[i], accessTid);
```

**Verification Tests**:
- ✓ MDT indexed by thread-qualified PC
- ✓ Memory hazard predictions are thread-specific
- ✓ No dependency mispredictions across threads

---

## 10. EXECUTION UNITS - INTEGER BACKEND

### IntegerBackEnd/IntegerIssueStage.sv (Lines 40-44, 70, 90-99, 113)
**Purpose**: Issue instructions with thread tracking

```verilog
ThreadID currentOpTid;
ThreadID opTid[INT_ISSUE_WIDTH];

// Extract thread ID from scheduler
opTid[i] = issuedData[i].tid;

// Use for recovery signaling
recovery.toRecoveryPhase[opTid[i]] = TRUE;

// Propagate forward
nextStage[i].tid = opTid[i];
```

### IntegerBackEnd/IntegerRegisterReadStage.sv (Lines 110, 123, 173-176, 183)
**Purpose**: Thread-aware register file reads

```verilog
ThreadID opTid[INT_ISSUE_WIDTH];
// Extract and propagate thread IDs
```

### IntegerBackEnd/IntegerExecutionStage.sv (Lines 93, 155-162, 223, 275)
**Purpose**: Execute with thread tagging

```verilog
ThreadID opTid[INT_ISSUE_WIDTH];

// Tag branch results
brResult[i].tid = opTid[i];

// Propagate thread ID
nextStage[i].tid = opTid[i];
```

**Verification Tests**:
- ✓ Each execution unit tags results with source thread
- ✓ Branch results include thread ID for recovery routing
- ✓ Register writes target correct thread

### IntegerBackEnd/IntegerRegisterWriteStage.sv (Lines 65, 76, 82-85, 103)
**Purpose**: Write results with thread context

```verilog
ThreadID opTid[INT_ISSUE_WIDTH];

// Update Active List with thread
alWriteData[i].tid = iqData[i].tid;
```

---

## 11. EXECUTION UNITS - MEMORY BACKEND

### MemoryBackEnd/MemoryIssueStage.sv (Lines 46, 76, 94, 99-102, 120)
**Purpose**: Issue load/store with thread tracking

```verilog
ThreadID opTid[MEM_ISSUE_WIDTH];
opTid[i] = scheduler.memIssuedData[i].tid;
```

### MemoryBackEnd/MemoryRegisterReadStage.sv (Lines 87, 101, 151-154, 160)
**Purpose**: Thread-aware source operand reads

### MemoryBackEnd/MemoryTagAccessStage.sv (Lines 100, 340, 146, 254, 382, 416)
**Purpose**: Cache tag access with per-thread tracking

```verilog
ThreadID ldTid[LOAD_ISSUE_WIDTH];
ThreadID stTid[STORE_ISSUE_WIDTH];

// Assign to load/store records
ldTid[i] = opTid[i];
stTid[i] = opTid[i];
```

### MemoryBackEnd/MemoryExecutionStage.sv (Lines 70, 93, 96-99, 133, 238)
**Purpose**: Route loads/stores with thread ID

```verilog
ThreadID opTid[MEM_ISSUE_WIDTH];

// Pass to Load/Store Unit
loadStoreUnit.dcReadTid[i] = opTid[i];
loadStoreUnit.dcWriteTid = opTid[i];
```

### MemoryBackEnd/MemoryRegisterWriteStage.sv (Lines 61, 88, 91-94, 119)
**Purpose**: Write memory results with thread context

---

## 12. EXECUTION UNITS - FP & COMPLEX INTEGER

### FPBackEnd/FPExecutionStage.sv (Lines 56, 368, 387, 402)
**Purpose**: Multi-cycle FP execution with thread tracking

```verilog
typedef struct packed {
    ThreadID tid;
    // ... other fields ...
} LocalPipeReg;

// Initial stage
nextLocalPipeReg[i][0].tid = opTid[i];

// Pipeline stages
nextLocalPipeReg[i][j].tid = localPipeReg[i][j-1].tid;
```

### FPBackEnd/FPIssueStage.sv (Lines 125-126)
### FPBackEnd/FPRegisterReadStage.sv
### FPBackEnd/FPRegisterWriteStage.sv
**Changes**: Similar thread ID propagation

### ComplexIntegerBackEnd/ComplexIntegerExecutionStage.sv (Lines 278, 296, 309)
**Purpose**: Multi-cycle integer execution with thread tracking

---

## 13. LOAD-STORE UNIT - QUEUE THREAD TRACKING

### LoadStoreUnit/LoadStoreUnitIF.sv (Lines 41, 54, 98, 115)
**Interface Signals**:
```verilog
ThreadID executedLoadTid[LOAD_ISSUE_WIDTH];   // Input
ThreadID executedStoreTid[STORE_ISSUE_WIDTH]; // Input
ThreadID dcReadTid[LOAD_ISSUE_WIDTH];        // Output to cache
ThreadID dcWriteTid;                         // Output to cache
```

### LoadStoreUnit/LoadStoreUnitTypes.sv (Lines 171, 189)
**Changes**: ThreadID added to queue entries

```verilog
typedef struct packed {
    ThreadID tid;
    // ... other fields ...
} LoadQueueEntry;

typedef struct packed {
    ThreadID tid;
    // ... other fields ...
} StoreQueueAddrEntry;
```

### LoadStoreUnit/LoadQueue.sv (Lines 127, 210)
**Purpose**: Track thread for each load in-flight

```verilog
// Capture thread ID
loadQueue[...].tid <= port.executedLoadTid[i];

// Use for dependency checking
// Store-load violation detection with thread matching
if (storeQueue[...].tid == port.executedStoreTid[i]) begin
    // Potential violation
end
```

### LoadStoreUnit/StoreQueue.sv (Lines 124, 281)
**Purpose**: Track thread for each store in-flight

```verilog
// Capture thread ID
storeQueue[...].tid <= port.executedStoreTid[i];

// Forward data with thread check
if (storeQueue[...].tid == matchingLoadTid) begin
    // Forward store data to load
end
```

**Verification Tests**:
- ✓ Load and store queues tagged with thread
- ✓ Store-load forwarding respects thread ID
- ✓ Memory hazard detection accounts for threads

---

## 14. CACHE SYSTEM - MSHR THREAD TRACKING

### Cache/CacheSystemTypes.sv (Lines 137, 325, 332)
**Purpose**: ThreadID in MSHR structures

```verilog
typedef struct packed {
    ThreadID tid;           // ← MSHR thread owner
    // ... other fields ...
} MissStatusHandlingRegister;
```

**Verification Tests**:
- ✓ MSHR field size matches THREAD_NUM_BIT_WIDTH
- ✓ MSHR entries correctly tagged with thread

### Cache/DCacheIF.sv (Lines 102, 107, 126)
**Interface Signals**:
```verilog
ThreadID initMSHR_Tid[MSHR_NUM];  // Input: Thread ID for new MSHR allocation
ThreadID mshrTid[MSHR_NUM];       // Output: Current thread owner of each MSHR
ThreadID dcFlushTid;              // Input: Thread ID for selective flush
```

### Cache/DCache.sv (Lines 1135, 1181, 1202, 1207, 1220, 1456, 1492)
**Implementation Details**:

```verilog
// Internal signal
ThreadID portInitMSHR_Tid[MSHR_NUM];

// Load path: extract thread from load request
portInitMSHR_Tid[m] = lsu.dcReadTid[i];

// Store path: extract thread from store request
portInitMSHR_Tid[m] = lsu.dcWriteTid;

// Initialize MSHR with thread ID
nextMSHR[i].tid = port.initMSHR_Tid[i];

// Flush: selective flush based on thread
if (port.dcFlushTid == MSHR_tid) begin
    nextMSHR[i].valid = 1'b0;
end
```

**Verification Tests**:
```
1. MSHR allocation with thread ID:
   - Load from Thread 0 → MSHR.tid = 0
   - Load from Thread 1 → MSHR.tid = 1
   
2. Per-thread cache invalidation:
   - Flush with dcFlushTid=0 invalidates only Thread 0 MSHRs
   - Flush with dcFlushTid=1 invalidates only Thread 1 MSHRs
   
3. MSHR completion tracking:
   - Record which thread's load completed
   - Validate thread-specific MSHR occupancy
```

---

## 15. PRIVILEGED REGISTERS (CSR) - THREAD-BANKED

### Privileged/CSR_UnitIF.sv (Line 30)
**Interface Signal**:
```verilog
ThreadID csrAccessTid;  // Which thread is accessing CSR
```

### Privileged/CSR_Unit.sv (Lines 55-66)
**Purpose**: Per-thread CSR register space

**Implementation**:
```verilog
ThreadID accTid = port.csrAccessTid;

// CSR registers indexed by thread
CSRRegisterSet csrReg[NUM_THREADS];

// Per-thread status, interrupts, etc.
csrReg[accTid].mstatus
csrReg[accTid].mip
csrReg[accTid].mie
```

**Verification Tests**:
- ✓ Each thread has independent CSR state
- ✓ CSR modifications don't affect other threads
- ✓ Interrupts and exceptions routed to correct thread

---

## 16. RECOVERY & COMMIT - THREAD-SELECTIVE

### Recovery/RecoveryManager.sv (Lines 46-47, 50)
**Purpose**: Per-thread recovery management

```verilog
// Per-thread recovery state
RecoveryManagerStatePath regState[NUM_THREADS];
logic toRecoveryPhase[NUM_THREADS];
```

### Recovery/RecoveryManagerIF.sv (Lines 34, 55-63, 77-90, 100)
**Interface Signals**:
```verilog
// Per-thread recovery arrays
logic flushAllInsns[NUM_THREADS];
logic inRecoveryAL[NUM_THREADS];
logic renameLogicRecoveryRMT[NUM_THREADS];
```

### Pipeline/CommitStage.sv (Lines 195-213)
**Purpose**: Round-robin commit arbitration between threads

**Implementation**:
```verilog
// Per-thread tracking
typedef struct packed {
    // ... fields ...
} ThreadCommitState;

ThreadCommitState threadState[NUM_THREADS];

// Thread selection for commit
ThreadID selectedThread;
integer threadSelectPointer;  // Round-robin pointer

// Round-robin arbitration
always_comb begin
    selectedThread = (threadSelectPointer + iteration) % NUM_THREADS;
end
```

**Verification Tests**:
- ✓ Each thread commits independently
- ✓ Round-robin commit arbitration verified
- ✓ Thread-specific recovery doesn't affect other threads
- ✓ Misspeculation in one thread doesn't rollback other thread

---

## VERIFICATION CHECKLIST

### 1. Type System Verification
- [ ] ThreadID type defined in BasicTypes.sv
- [ ] THREAD_NUM_BIT_WIDTH correctly calculated
- [ ] ThreadID used consistently across all modules

### 2. Thread Selection Verification
- [ ] NextPCStage implements round-robin selection
- [ ] threadCounter increments every cycle
- [ ] selectedTid output matches expected thread
- [ ] Stalls maintain thread consistency

### 3. Pipeline Propagation Verification
- [ ] All register types have ThreadID tid field
- [ ] ThreadID propagates through all stages
- [ ] No stage loses thread information
- [ ] Multi-cycle instructions preserve thread ID

### 4. Fetch Stage Verification
- [ ] FetchStage outputs correct ThreadIDs
- [ ] BTB entries tagged with thread
- [ ] Per-thread branch history maintained
- [ ] Per-thread BHT state isolated

### 5. Decode/Rename Verification
- [ ] DecodeStage preserves thread ID
- [ ] RenameStage propagates thread ID
- [ ] RMT accesses are thread-indexed
- [ ] No register aliasing between threads

### 6. Active List Verification
- [ ] Thread 0 uses first half of entries
- [ ] Thread 1 uses second half of entries
- [ ] Independent commit per thread
- [ ] Thread-selective recovery

### 7. Scheduler Verification
- [ ] Issue queue entries tagged with thread
- [ ] Per-thread wakeup tracking
- [ ] Memory dependency prediction per-thread
- [ ] Flush operations respect thread boundaries

### 8. Execution Unit Verification
- [ ] Integer backend tagged with thread
- [ ] Memory backend tracked per-thread
- [ ] FP backend propagates thread ID
- [ ] Complex integer backend thread-aware

### 9. Load/Store Verification
- [ ] Load queue entries have thread ID
- [ ] Store queue entries have thread ID
- [ ] Store-load forwarding respects thread
- [ ] Memory dependency detection per-thread

### 10. Cache System Verification
- [ ] MSHR entries tagged with thread
- [ ] Cache flush is thread-selective
- [ ] Per-thread MSHR occupancy tracked
- [ ] No MSHR corruption across threads

### 11. CSR Verification
- [ ] CSR registers banked by thread
- [ ] Per-thread CSR access verified
- [ ] CSR modifications thread-isolated
- [ ] Interrupts routed correctly

### 12. Recovery Verification
- [ ] Per-thread recovery state machines
- [ ] Branch misprediction recovery per-thread
- [ ] Exception handling per-thread
- [ ] Flush operations thread-selective

### 13. Commit Verification
- [ ] Round-robin commit arbitration
- [ ] Per-thread commit tracking
- [ ] Independent progress per thread
- [ ] No commit ordering issues

---

## Testing Recommendations

### Unit Tests
1. Test each module in isolation with thread parameter variations
2. Verify ThreadID calculations for different THREAD_NUM values
3. Test RMT and AL address generation functions

### Integration Tests
1. Multi-threaded instruction stream with independent code sequences
2. Synchronization points between threads
3. Memory sharing and cache effects
4. Interrupt and exception handling

### Functional Tests
1. Round-robin fetch pattern verification
2. Per-thread performance metrics
3. Cache statistics per thread
4. IPC measurement per thread

### Performance Tests
1. Single-thread regression (verify no slowdown)
2. Dual-thread scaling
3. Cache miss rates per thread
4. Memory bus utilization

---

## Files Changed Summary

**Total Files Modified: 78**
**Total Lines Changed: ~3500 inserted, ~2700 deleted**

### Core Category Files (15 files)
- BasicTypes.sv
- PipelineTypes.sv
- MicroArchConf.sv
- CacheSystemTypes.sv

### Front-End (8 files)
- FetchStage/NextPCStage.sv, NextPCStageIF.sv
- FetchStage/FetchStage.sv, FetchStageIF.sv
- FetchUnit/BranchPredictor.sv, BTB.sv, Gshare.sv, Bimodal.sv

### Decode/Rename (7 files)
- PreDecodeStage.sv
- DecodeStage.sv, DecodeStageIF.sv
- RenameStage.sv, RenameStageIF.sv
- RenameLogic/RMT.sv, RenameLogicIF.sv

### Active List (3 files)
- RenameLogic/ActiveList.sv, ActiveListIF.sv
- RenameLogic/RenameLogicCommitter.sv

### Scheduler (5 files)
- Scheduler/SchedulerTypes.sv, IssueQueue.sv
- Scheduler/WakeupPipelineRegister.sv
- Scheduler/MemoryDependencyPredictor.sv

### Execution Units (15 files)
- IntegerBackEnd (4 files): Issue, RegisterRead, Execution, RegisterWrite stages
- MemoryBackEnd (5 files): Issue, RegisterRead, TagAccess, Execution, RegisterWrite stages
- FPBackEnd (3 files): Issue, RegisterRead, Execution stages
- ComplexIntegerBackEnd (3 files)

### Load/Store (3 files)
- LoadStoreUnit/LoadQueue.sv, StoreQueue.sv
- LoadStoreUnitIF.sv, LoadStoreUnitTypes.sv

### Cache (3 files)
- Cache/DCache.sv, DCacheIF.sv
- Cache/CacheSystemTypes.sv

### Privileged (3 files)
- Privileged/CSR_Unit.sv, CSR_UnitIF.sv
- Privileged/InterruptController.sv

### Recovery & Commit (4 files)
- Recovery/RecoveryManager.sv, RecoveryManagerIF.sv
- Pipeline/CommitStage.sv

### Documentation (10+ README files)
- CACHE_SMT_README.md
- CACHE_SMT_SHARED_CACHE_PRACTICAL.md
- README files for each major module

---

## References

For detailed implementation information, see:
- `SMT_IMPLEMENTATION_PROGRESS.md` - Progress tracking
- `CACHE_SMT_README.md` - Cache-specific SMT implementation
- Per-module README files in each subdirectory
- Source code comments in modified files
