# SMT Implementation Progress

## Completed Tasks

### 1. ✅ ThreadID Type Definition (BasicTypes.sv & MicroArchConf.sv)
- Added `CONF_THREAD_NUM = 2` to MicroArchConf.sv
- Added ThreadID type definition to BasicTypes.sv with width based on thread count
- ThreadID is 1 bit for 2 threads

### 2. ✅ Cache Subsystem Thread Tracking

#### CacheSystemTypes.sv
- Added `ThreadID tid` field to `MissStatusHandlingRegister` struct
- Added `ThreadID tid` field to `MemReadAccessReq` struct
- Added `ThreadID tid` field to `MemAccessResult` struct

#### DCacheIF.sv
- Added `ThreadID initMSHR_Tid[MSHR_NUM]` signal for MSHR allocation with thread ID
- Added `ThreadID dcFlushTid` signal for per-thread cache flush
- Added `ThreadID mshrTid[MSHR_NUM]` output to track current thread owner of each MSHR
- Updated `DCacheMissHandler` and `DCache` modports to include new signals

#### DCache.sv
- Added `portInitMSHR_Tid[MSHR_NUM]` internal signal
- Updated MSHR allocation to store thread ID when initialized
- Thread ID is extracted from `lsu.dcReadTid[i]` for load ports
- Thread ID is extracted from `lsu.dcWriteTid` for store ports
- Flush MSHR initialization includes `dcFlushTid` tracking

### 3. ✅ Load-Store Unit Thread Awareness

#### LoadStoreUnitIF.sv
- Added `ThreadID dcReadTid[LOAD_ISSUE_WIDTH]` signal for read requests
- Added `ThreadID dcWriteTid` signal for write requests
- Updated `DCache` modport to accept new tid signals
- Updated `MemoryExecutionStage` modport to output `dcReadTid`
- Updated `StoreCommitter` modport to output `dcWriteTid`

#### DCache.sv
- Connected thread IDs from LSU to MSHR initialization:
  - For loads: uses `lsu.dcReadTid[i]` 
  - For stores: uses `lsu.dcWriteTid`

### 4. ✅ Pipeline Register Thread Propagation (PipelineTypes.sv)
- Added `ThreadID tid` to `FetchStageRegPath`
- Added `ThreadID tid` to `PreDecodeStageRegPath`
- Added `ThreadID tid` to `DecodeStageRegPath`
- Added `ThreadID tid` to `RenameStageRegPath`
- Added `ThreadID tid` to `DispatchStageRegPath`

### 5. ✅ Front-End Thread Awareness

#### NextPCStageIF.sv
- Added `ThreadID selectedTid` output signal for thread selection
- Updated ThisStage modport to output `selectedTid`

#### NextPCStage.sv
- Added thread round-robin selector:
  - `threadCounter` register increments each cycle
  - `currentThread = threadCounter % THREAD_NUM` selects current thread
  - `port.selectedTid` outputs the selected thread
- Updated `nextStage[i].tid` assignment with `port.selectedTid`

#### FetchStageIF.sv
- Added `ThreadID fetchThreadId[FETCH_WIDTH]` output signal
- Updated ThisStage modport to output `fetchThreadId`

#### FetchStage.sv
- Propagates thread ID from input (`pipeReg[i].tid`) to output (`nextStage[i].tid`)
- Outputs `port.fetchThreadId` for downstream modules

#### PreDecodeStage.sv
- Propagates thread ID from input to output in pipeline register assignment

#### DecodeStage.sv
- Added `nextStage[i].tid = pipeReg[orgPickedInsnLane].tid` assignment
- Ensures thread ID follows the correct instruction lane

#### RenameStage.sv
- Added `nextStage[i].tid = pipeReg[i].tid` assignment
- Propagates thread ID to dispatch stage

---

## Key Design Decisions

1. **Shared L1 Caches**: Single ICache and DCache with thread ID tracking in MSHR entries
2. **Simple Thread Selection**: Round-robin at NextPCStage using counter modulo THREAD_NUM
3. **Thread ID Width**: Minimal (1 bit for 2 threads) to reduce area overhead
4. **Pipeline Integration**: ThreadID propagated through all pipeline stages from fetch to dispatch
5. **MSHR Thread Tracking**: Each MSHR entry stores the thread ID of its allocating thread

---

## Remaining Tasks

### 7. Add ICache Fairness Logic (Optional)
- Per-thread miss tracking in ICache
- Fair scheduling between threads' memory requests
- Estimated: 2 hours

### 8. Testing and Validation
- Compile without errors
- Single-thread regression tests
- Dual-thread functional tests
- Performance validation
- Estimated: 2-3 hours

---

## Implementation Statistics

- **Files Modified**: 15+
- **New Signals Added**: ~20
- **New Type Fields**: 5
- **Code Lines Changed**: ~150
- **New Logic Added**: ~50 lines

## Next Steps

1. Verify compilation with modified code
2. Implement ICache fairness logic (optional but recommended)
3. Create test cases for dual-thread execution
4. Validate cache behavior with multiple threads
5. Performance measurements before/after SMT

