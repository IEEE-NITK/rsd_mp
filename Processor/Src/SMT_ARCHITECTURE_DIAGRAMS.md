# SMT Architecture Diagrams & Visual Overview

---

## 1. Complete SMT Data Flow (Phase 1-4 Complete)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         FETCH STAGE (NextPCStage.sv)                     │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Thread 0 PC ─┐                                                          │
│               ├─→ PC Mux ──→ predNextPC ──→ Instruction Fetch           │
│  Thread 1 PC ─┘                                                          │
│                                                                          │
│                           currentThread (TBD Phase 5)                   │
│                           = Which thread to fetch from                  │
│                                                                          │
│  Output: Instruction + thread = { opcode, ThreadID=0|1 }              │
└──────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────┐
│                    PRE-DECODE & DECODE STAGES                           │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Instruction + ThreadID ──→ Decode Logic (thread passed through)       │
│                                                                          │
│  Output: OpInfo + ThreadID                                              │
└──────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────┐
│                    RENAME STAGE (RenameStage.sv)                        │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Instruction + ThreadID ──→ ┌─────────────────────────────┐             │
│                             │ RenameLogic (per-thread RMT) │            │
│                             │  ThreadID = 0:              │            │
│                             │  RMT[0]: log→phys mapping   │            │
│                             │  Free List[0]               │            │
│                             │                             │            │
│                             │  ThreadID = 1:              │            │
│                             │  RMT[1]: log→phys mapping   │            │
│                             │  Free List[1]               │            │
│                             └─────────────────────────────┘            │
│                                      ↓                                  │
│                  Phys Registers (isolated per thread)                   │
│                                                                          │
│  Also routes to:                                                         │
│  ┌──────────────────────────────┐ ┌────────────────────────────┐       │
│  │ LoadStoreUnit                │ │ ActiveList                 │       │
│  │ allocateLoadQueueThread[i]   │ │ thread[i] (which thread)   │       │
│  │ allocateStoreQueueThread[i]  │ │                            │       │
│  │ → Per-thread queue alloc     │ │ → Per-thread tracking      │       │
│  └──────────────────────────────┘ └────────────────────────────┘       │
│                                                                          │
│  Output: Renamed Instruction + ThreadID + Queue Pointers               │
└──────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────┐
│                    EXECUTE STAGES (per-thread queues)                   │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Load Queue[0] ──→ Execute ──→ Load Results (Thread 0)                 │
│  Load Queue[1] ──→ Execute ──→ Load Results (Thread 1)                 │
│                                                                          │
│  Store Queue[0] ──→ Execute ──→ Store Results (Thread 0)               │
│  Store Queue[1] ──→ Execute ──→ Store Results (Thread 1)               │
│                                                                          │
│  (Other pipelines: INT, FP, MUL/DIV - similar per-thread routing)      │
│                                                                          │
│  Output: Results + ThreadID + ActiveList Pointer                       │
└──────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────┐
│                    COMMIT STAGE (RenameLogicCommitter.sv)               │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ActiveList[0] (head entries) ──→ Thread 0 can retire?                │
│  ActiveList[1] (head entries) ──→ Thread 1 can retire?                │
│                                                                          │
│  Per thread: popHeadNum[t], popTailNum[t]                             │
│                                                                          │
│  For each retiring instruction:                                         │
│    1. Read from appropriate thread's active list                       │
│    2. Get ThreadID from activeList.readDataThread[i]                  │
│    3. Release physical register to thread's free list:                │
│       freeList[ThreadID].push(phyReleasedReg)                         │
│                                                                          │
│  Output: Released registers back to per-thread free lists              │
└──────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌──────────────────────────────────────────────────────────────────────────┐
│                        RETIREMENT (Cycle repeats)                       │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Thread 0 instructions committed ──→ RMT[0] updated, reg released      │
│  Thread 1 instructions committed ──→ RMT[1] updated, reg released      │
│                                                                          │
│  *** Both threads proceed independently ***                             │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Per-Thread Register Mapping (Isolation Mechanism)

```
                    SINGLE LOGICAL REGISTER (e.g., x1)
                            │
                    ┌───────┴───────┐
                    ↓               ↓
              Thread 0 RMT    Thread 1 RMT
              (Register Map)  (Register Map)
                    │               │
                    ↓               ↓
              Physical Reg 5   Physical Reg 25
              (Read/Write)     (Read/Write)
              (isolated)       (isolated)


EXAMPLE FLOW:
─────────────

Thread 0 executes: add x1, x2, x3
  └─→ RMT[0][x1] → lookup → Phys Reg 5 ✓
  └─→ RMT[0][x2] → lookup → Phys Reg 10 ✓
  └─→ RMT[0][x3] → lookup → Phys Reg 15 ✓
  └─→ Result written to Phys Reg 5 (dedicated to Thread 0)

Simultaneously: Thread 1 executes: add x1, x4, x5
  └─→ RMT[1][x1] → lookup → Phys Reg 25 ✓
  └─→ RMT[1][x4] → lookup → Phys Reg 30 ✓
  └─→ RMT[1][x5] → lookup → Phys Reg 35 ✓
  └─→ Result written to Phys Reg 25 (dedicated to Thread 1)

KEY PROPERTY:
──────────────
Physical Reg 5 (used by Thread 0) ≠ Physical Reg 25 (used by Thread 1)
→ No cross-thread contamination
→ Complete register isolation
→ Achieved through RMT, not hardware duplication
```

---

## 3. Active List Per-Thread Structure

```
                        ACTIVE LIST MEMORY
                (64 entries, 2 per-thread instances)
                            │
                    ┌───────┴───────┐
                    ↓               ↓
          Thread 0 Active List  Thread 1 Active List
          ┌─────────────────┐  ┌─────────────────┐
          │  Entry 0  │     │  │  Entry 0  │     │
          │  Entry 1  │     │  │  Entry 1  │     │
          │  Entry 2  │     │  │  Entry 2  │     │
          │  ...      │     │  │  ...      │     │
          │  Entry 63 │     │  │  Entry 63 │     │
          └─────────────────┘  └─────────────────┘
                │                   │
          ┌─────┴──────┐       ┌─────┴──────┐
          ↓            ↓       ↓            ↓
      headPtr[0]  tailPtr[0] headPtr[1]  tailPtr[1]
       │             │        │             │
    Oldest ──→    Next ──→  Oldest ──→   Next ──→
   retired      allocated  retired     allocated
   instruction  location   instruction  location


OPERATION EXAMPLE:
──────────────────
Cycle 1:
  Allocate to Thread 0: tailPtr[0] = 0 → Entry 0
  Allocate to Thread 1: tailPtr[1] = 0 → Entry 0 (different memory!)

Cycle 2:
  Allocate to Thread 0: tailPtr[0] = 1 → Entry 1
  Allocate to Thread 1: tailPtr[1] = 1 → Entry 1 (different memory!)

...

Cycle 10:
  Thread 0 commits: pop from headPtr[0]
    → Read Entry 0 of Thread 0's list
    → headPtr[0] advances
  
  Thread 1 commits: pop from headPtr[1]
    → Read Entry 0 of Thread 1's list
    → headPtr[1] advances

KEY PROPERTY:
──────────────
Each thread's active list is completely separate
→ Independent instruction tracking
→ No interference between commit operations
→ Per-thread recovery possible
```

---

## 4. Load/Store Queue Separation

```
              LOAD & STORE QUEUE MEMORY
            (32 entries, 2 per-thread instances)
                        │
                ┌───────┴───────┐
                ↓               ↓
        Thread 0 Load Queue   Thread 1 Load Queue
        ┌─────────────────┐   ┌─────────────────┐
        │ Load Entry 0    │   │ Load Entry 0    │
        │ Load Entry 1    │   │ Load Entry 1    │
        │ ...             │   │ ...             │
        │ Load Entry 31   │   │ Load Entry 31   │
        └─────────────────┘   └─────────────────┘
                │                   │
           tailPtr[0]           tailPtr[1]
           headPtr[0]           headPtr[1]


ALLOCATION FLOW:
────────────────
Rename Stage:
  Instruction for Thread 0: addi r5, sp, -8  (implicit load prep)
    └─→ allocateLoadQueueThread[i] = 0 ✓
    └─→ Use tailPtr[0] to allocate entry
    └─→ Return allocatedLoadQueuePtr[i] for this instruction

  Instruction for Thread 1: addi r10, sp, -4 (implicit load prep)
    └─→ allocateLoadQueueThread[i] = 1 ✓
    └─→ Use tailPtr[1] to allocate entry
    └─→ Return allocatedLoadQueuePtr[i] for this instruction


EXECUTION FLOW:
───────────────
Memory Execute Stage:
  For each load from Thread 0:
    └─→ Look up in Load Queue[0] using thread-specific pointer
    └─→ Execute load from cache/memory
    └─→ Store result in Load Queue[0] entry

  For each load from Thread 1:
    └─→ Look up in Load Queue[1] using thread-specific pointer
    └─→ Execute load from cache/memory
    └─→ Store result in Load Queue[1] entry

KEY PROPERTY:
──────────────
Load Queue[0] ≠ Load Queue[1] (separate memory)
→ No queue contention
→ Loads from different threads don't conflict
→ Independent memory operations
→ Each thread sees its own memory sequence
```

---

## 5. Thread Scheduling Point (Phase 5 - To Be Implemented)

```
            *** CRITICAL DECISION POINT (Phase 5) ***

                    currentThread Selector
                            │
                ┌───────────┴───────────┐
                │  (To be implemented)  │
                └───────────┬───────────┘
                            │
                    Simple Options:
                            │
            ┌───────────────┼───────────────┐
            ↓               ↓               ↓
        Round-Robin    Priority-Based   Stall-Aware
        
        cycle[0]     loadCount[0]   isStalled[0]
           │             │              │
           ↓             ↓              ↓
        0→1→0→1       Compare      Prefer non-stalled
        Deterministic  Adaptive      Smart


SIMPLE ROUND-ROBIN (Recommended Phase 5 Start):
────────────────────────────────────────────────
logic [0:0] threadSelectReg;

always_ff @(posedge clk) begin
    if (rst) threadSelectReg <= 0;
    else threadSelectReg <= !threadSelectReg;
end

assign port.currentThread = threadSelectReg;

Result:
  Cycle 0: currentThread = 0 → Fetch from PC[0]
  Cycle 1: currentThread = 1 → Fetch from PC[1]
  Cycle 2: currentThread = 0 → Fetch from PC[0]
  ...

This ensures:
  ✓ Both threads fetched equally
  ✓ Deterministic for debugging
  ✓ Simple to verify
  ✓ Good baseline for performance


IMPACT ON FETCH STREAM:
───────────────────────
Fetch Queue Layout (interleaved):

Instruction 0 (Thread 0): add x1, x2, x3
Instruction 1 (Thread 1): mul x5, x6, x7
Instruction 2 (Thread 0): lw x10, 0(sp)
Instruction 3 (Thread 1): sub x8, x9, x10
Instruction 4 (Thread 0): addi x1, x1, 1
Instruction 5 (Thread 1): sw x8, 0(sp)
...

Both threads' instructions coexist in pipeline!
```

---

## 6. Full Pipeline Thread Tracking

```
INSTRUCTION JOURNEY THROUGH PIPELINE WITH THREAD TAGGING:

Fetch Stage:
  │
  ├─ Thread 0 instruction: { opcode=ADD, thread=0 }
  │
  ├─ Thread 1 instruction: { opcode=MUL, thread=1 }
  │
  ↓
Decode Stage:
  │
  ├─ Thread 0: { opInfo=..., thread=0 }
  │
  ├─ Thread 1: { opInfo=..., thread=1 }
  │
  ↓
Rename Stage:
  │
  ├─ Thread 0: { physRegs=..., activeListPtr=..., thread=0 }
  │           (used RMT[0] and Active List[0])
  │
  ├─ Thread 1: { physRegs=..., activeListPtr=..., thread=1 }
  │           (used RMT[1] and Active List[1])
  │
  ↓
Dispatch Stage:
  │
  ├─ Thread 0: { issueQueuePtr=..., thread=0 }
  │
  ├─ Thread 1: { issueQueuePtr=..., thread=1 }
  │
  ↓
Execute Stages:
  │
  ├─ Thread 0: { result=..., activeListPtr=..., thread=0 }
  │
  ├─ Thread 1: { result=..., activeListPtr=..., thread=1 }
  │
  ↓
Commit Stage:
  │
  ├─ Thread 0 retiring: Read Active List[0], release to Free List[0]
  │
  ├─ Thread 1 retiring: Read Active List[1], release to Free List[1]
  │
  ↓
Complete!


KEY INVARIANT:
───────────────
Once an instruction is tagged with ThreadID at Fetch,
that ThreadID determines ALL operations for that instruction:
  - Which RMT to use (RMT[thread])
  - Which queue to allocate to (Queue[thread])
  - Which active list to update (AL[thread])
  - Which free list to release to (FL[thread])
```

---

## 7. Exception Handling With Multiple Threads

```
            NORMAL EXECUTION (Both threads)
                    │
        ┌───────────┼───────────┐
        ↓           ↓           ↓
    Thread 0     Thread 1   Other stages
    exec: OK     exec: OK
        │           │
        └───────────┴───────────┘
                    │
                    ↓
            (EXCEPTION OCCURS in Thread 1)
                    │
        ┌───────────┴───────────┐
        ↓           ↓
    Thread 0     Thread 1
    continues    EXCEPTION!
                    │
                    ↓
            Recovery Manager:
            - Identifies Thread 1 triggered fault
            - Saves Thread 1 state
            - Loads Thread 1 recovery PC
            - Thread 0 UNAFFECTED continues
                    │
        ┌───────────┼───────────┐
        ↓           ↓           ↓
    Thread 0     Thread 1   Continue
    progresses   recovers    pipeline


EXCEPTION ISOLATION:
────────────────────
Key Principle:
  Exception in Thread 1 does NOT affect Thread 0's pipeline

Implementation:
  1. Recovery PC per thread: recoveredPC[THREAD_NUM]
  2. ActiveList pop per thread: popHeadNum[THREAD_NUM]
  3. Free list release per thread: freeListRelease[THREAD_NUM]
  
Result:
  ✓ Thread 1 can be flushed and recover
  ✓ Thread 0 continues normal execution
  ✓ No pipeline deadlock
  ✓ True thread isolation maintained
```

---

## 8. Phase 5 Expected Execution Timeline

```
BEFORE Phase 5 (Current - Single Thread):

Cycle: 0   1   2   3   4   5   6   7   8   9  10
       │   │   │   │   │   │   │   │   │   │   │
Fetch: I0  I1  I2  I3  I4  I5  I6  I7  I8  I9 I10
       │   │   │   │   │   │   │   │   │   │   │
       └─→ Decode
           │   │
           └─→ Rename
               │   │
               └─→ Execute
                   │   │
                   └─→ Commit

Result: Only Thread 0 instructions in pipeline
        IPC: ~1.0 (one instruction per cycle average)


AFTER Phase 5 (With Thread Scheduling):

Cycle: 0   1   2   3   4   5   6   7   8   9  10
       │   │   │   │   │   │   │   │   │   │   │
Thread:0   1   0   1   0   1   0   1   0   1   0
Fetch: T0  T1  T0  T1  T0  T1  T0  T1  T0  T1  T0
       I0  I0' I1  I1' I2  I2' I3  I3' I4  I4' I5
       │   │   │   │   │   │   │   │   │   │   │
       └─→ Decode
           │   │   │   │   │   │   │   │   │
           └─→ Rename
               │   │   │   │   │   │   │   │
               └─→ Execute
                   │   │   │   │   │   │   │
                   └─→ Commit

Result: Thread 0 and Thread 1 instructions both in pipeline
        IPC: ~1.7 (two instructions per cycle average!)
        Speedup: ~1.7x improvement


EXAMPLE EXECUTION (First 10 Cycles):
─────────────────────────────────────
Cycle  currentThread  Fetch      Pipeline State
────────────────────────────────────────────────────
  0        0         T0:add     Pipeline: [T0:add]
  1        1         T1:mul     Pipeline: [T0:add, T1:mul]
  2        0         T0:lw      Pipeline: [T0:add, T1:mul, T0:lw]
  3        1         T1:sub     Pipeline: [T0:add, T1:mul, T0:lw, T1:sub]
  4        0         T0:addi    Pipeline: [T0:add, T1:mul, T0:lw, T1:sub, T0:addi]
  5        1         T1:sw      Pipeline: [T0:add*, T1:mul, T0:lw, T1:sub, T0:addi, T1:sw]
  6        0         T0:and     Pipeline: [T0:add*, T1:mul*, T0:lw, T1:sub, T0:addi, T1:sw, T0:and]
  7        1         T1:or      Pipeline: [T0:add*, T1:mul*, T0:lw*, T1:sub, T0:addi, T1:sw, T0:and, T1:or]
  8        0         T0:xor     Pipeline: [T0:add*, T1:mul*, T0:lw*, T1:sub*, T0:addi, T1:sw, T0:and, T1:or, T0:xor]
  9        1         T1:beq     Pipeline: [T0:add*, T1:mul*, T0:lw*, T1:sub*, T0:addi*, T1:sw, T0:and, T1:or, T0:xor, T1:beq]
 10        0         T0:jalr    Pipeline: [T0:add*, T1:mul*, T0:lw*, T1:sub*, T0:addi*, T1:sw*, T0:and, T1:or, T0:xor, T1:beq, T0:jalr]

* = committed to memory/registers

Observations:
  ✓ Both threads' instructions in pipeline simultaneously
  ✓ Interleaved fetch (0, 1, 0, 1, ...)
  ✓ Instructions from both threads commit
  ✓ Total throughput improved
```

---

## 9. Performance Scaling Model

```
                PERFORMANCE IMPROVEMENT WITH SMT

                    IPC (Instructions Per Cycle)
                            │
                       2.0  │        ┌─ Perfect Scaling (both threads busy)
                            │       /│
                       1.7  │      / │ ◄─ Phase 5 Target (1.73x)
                            │     /  │
                       1.4  │    /   │
                            │   /    │  Independent Threads (no conflicts)
                       1.2  │  /     │
                            │ /      │
                       1.0  │/       │  Single-threaded baseline
                            └───────────────────────────────────
                            0   0.2  0.4  0.6  0.8  1.0
                          Fraction of Thread 1 Active Time


WHY SCALING ISN'T PERFECT (2x):
─────────────────────────────────
1. Both threads stall together on shared resources
   - Memory hierarchy (shared L2/L3 cache)
   - Memory bandwidth
   - Branch predictor bandwidth
   
2. Commit stage cannot sustain 2x throughput
   - Commit width typically < 2x issue width
   - Not every cycle both threads can commit
   
3. Active list can become bottleneck
   - Limited by commit bandwidth
   - Both threads compete for commits


EXPECTED SPEEDUP RANGES:
─────────────────────────
Best case (independent workloads):      1.8x - 2.0x
Good case (moderate overlap):            1.5x - 1.7x  ◄─ Target Phase 5
Fair case (some conflicts):             1.2x - 1.5x
Poor case (highly contending):          1.0x - 1.2x


FACTORS AFFECTING SPEEDUP:
──────────────────────────
✓ Independent memory access patterns → Higher speedup
✓ Different execution pipelines in use → Higher speedup
✓ Cache misses in one thread while other progresses → Higher speedup

✗ Both threads contending for cache → Lower speedup
✗ Both threads waiting for memory → Lower speedup
✗ Both threads executing dependent instructions → Lower speedup
```

---

**Visual diagrams complete. Reference these when explaining SMT to others!**
