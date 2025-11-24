# 🚀 SMT Implementation - Phase 3 Complete - START HERE

## Welcome!

You are inheriting a working SMT implementation that is 50% complete (Phases 1-3 done). Everything you need is documented below.

---

## ⚡ Quick Facts

| Metric | Value |
|--------|-------|
| **Project** | RSD Processor SMT Implementation |
| **Phase Completed** | 1, 2, 3 ✓ |
| **Phase Next** | 4 (Dispatch & Resource Allocation) |
| **Status** | ✓ COMPLETE & VERIFIED |
| **Baseline Performance** | IPC 0.985285, 4621 cycles |
| **Backward Compatibility** | 100% ✓ |
| **Code Quality** | No errors, no warnings ✓ |

---

## 📖 What to Read (In This Order)

### 1️⃣ **Right Now** (15 min)
Read this file to understand what was done and what you need to do next.

### 2️⃣ **Before Starting Phase 4** (30 min)
```
README_NEXT_SESSION.md      ← Getting started with Phase 4
```

### 3️⃣ **While Planning Phase 4** (30 min)
```
PHASE4_HANDOVER.md          ← Complete Phase 4 specification
BRANCH_PREDICTOR_CACHE_ANALYSIS.md  ← Answers to system questions
```

### 4️⃣ **While Implementing Phase 4** (Reference)
```
SMT_PHASE3_COMPLETION.md    ← Implementation patterns
RenameLogic/RMT.sv          ← Code examples (lines 45-185)
```

### 5️⃣ **For Navigation/Reference**
```
HANDOVER_INDEX.md           ← Complete document index
DELIVERY_SUMMARY.txt        ← What was delivered
```

---

## 🎯 One Minute Summary

**What was built**: Per-thread register mapping (Register Map Table) that allows each thread to have independent logical→physical register mapping. Phase 3 adds thread ID to every pipeline stage from fetch through dispatch.

**How it works**: Thread ID generated in FetchStage (round-robin), flows through PreDecode → Decode → Rename stages. At RenameStage, each thread uses separate RMT instance for register allocation.

**What's working**: Single-threaded mode (THREAD_NUM=1) produces identical results to baseline (IPC 0.985285, 4621 cycles).

**What's next**: Phase 4 implements per-thread resource allocation (free lists, active list, issue queue, load/store queue).

---

## ✅ Verification (2 minutes)

Before you do anything, verify the baseline works:

```bash
cd /Users/kushal/rsd_mp/Processor/Src
make clean
make all
make run
```

**Expected output**:
```
IPC (RISC-V instruction): 0.985285
Elapsed cycles: 4621
- Verilator: $finish at ...
```

If you see this, **you're good to go!** ✓

---

## 📊 What Was Done (Phases 1-3)

### Phase 1-2: Front-end PC Management
- ✓ Per-thread PC registers with round-robin scheduling
- ✓ Thread ID available from FetchStage onwards

### Phase 3: Decode & Rename - Per-thread Register Mapping  
- ✓ Thread ID propagated through PreDecodeStage → DecodeStage → RenameStage → DispatchStage
- ✓ Per-thread Register Map Table (RMT) instances
- ✓ Thread-aware register read/write logic
- ✓ 100% backward compatible

---

## 📁 Key Files to Know

### Code Files Modified in Phase 3
```
Pipeline/PipelineTypes.sv       - ThreadID added to all stage registers
Pipeline/PreDecodeStage.sv      - Thread ID propagation
Pipeline/RenameStage.sv         - Thread to RenameLogic passing
RenameLogic/RenameLogicIF.sv   - Thread signal in interface
RenameLogic/RMT.sv              - Per-thread RMT instances (main change)
```

### Critical Reference Files
```
RenameLogic/RMT.sv (lines 45-185)  ← Study this for patterns!
Pipeline/FetchStage/PC.sv            ← Per-thread resource example
```

### Configuration Files (Already Updated)
```
MicroArchConf.sv            - CONF_THREAD_NUM parameter
BasicTypes.sv               - ThreadID type definition
Makefiles/CoreSources.inc.mk - RSD_ENABLE_SMT macro
```

---

## 🎯 What You Need to Do (Phase 4)

### High-level Goal
Implement per-thread resource allocation at the dispatch stage:
- Per-thread Free Lists (register allocation)
- Per-thread Active List (ROB entries)
- Thread-aware Issue Queue
- Per-thread Load/Store Queue

### Files to Modify (~8-10 files)
1. `RenameLogic/RenameLogicTypes.sv`
2. `RenameLogic/RenameLogic.sv`
3. `RenameLogic/ActiveList.sv`
4. `RenameLogic/ActiveListIF.sv`
5. `Pipeline/DispatchStage.sv`
6. `Scheduler/Scheduler.sv`
7. `Scheduler/SchedulerIF.sv`
8. `LoadStoreUnit/LoadStoreUnit.sv`

### Estimated Timeline
- **Reading**: 1-2 hours
- **Planning**: 30-45 minutes
- **Implementation**: 4-5 hours
- **Testing**: 1-2 hours
- **Documentation**: 30 minutes
- **Total**: ~1-2 days of work

### Design Decisions to Make
Before coding, decide:
1. Free lists: Shared vs per-thread?
2. Active list: Separate lists vs shared?
3. Issue queue: Shared vs per-thread?
4. Load/Store queue: Shared vs per-thread?

**Recommendation**: Read PHASE4_HANDOVER.md "Design Decisions" section before choosing.

---

## 🔍 How the Current System Works

### Thread Flow Through Pipeline
```
FetchStage (Phase 2)
  ├─ Round-robin selector picks thread
  ├─ Per-thread PC register
  └─ Thread ID attached to instruction
       ↓
PreDecodeStage (Phase 3)
  └─ Propagates thread ID
       ↓
DecodeStage (Phase 3)
  └─ Propagates thread ID
       ↓
RenameStage (Phase 3)
  ├─ Receives thread ID from input
  ├─ Passes thread ID to RenameLogic
  └─ RenameLogic uses thread ID to select which RMT instance
       ↓
RMT (Register Map Table - Phase 3)
  ├─ Per-thread RMT instances
  ├─ Thread 0 maps log→phys registers independently
  └─ Thread 1 maps log→phys registers independently
       ↓
DispatchStage (Ready for Phase 4)
  └─ Thread ID available for resource allocation
```

### Key Architecture Pattern
Every per-thread resource follows this pattern:
```systemverilog
`ifdef RSD_ENABLE_SMT
    // Multi-threaded version
    SomeData data[THREAD_NUM][SIZE];
    for (int t = 0; t < THREAD_NUM; t++) begin
        // Per-thread logic
    end
`else
    // Single-threaded version (original)
    SomeData data[SIZE];
    // Original logic
`endif
```

See RenameLogic/RMT.sv lines 45-185 for real example.

---

## 🧪 Testing Strategy

After each file you modify in Phase 4:
```bash
make clean && make all && make run
# MUST produce: IPC 0.985285, 4621 cycles
```

**If it fails**: You've broken the single-threaded path. Revert and debug.

---

## ❓ Frequently Asked Questions

### Q: Are branch predictor and cache modified for SMT?
**A**: No. Read BRANCH_PREDICTOR_CACHE_ANALYSIS.md - they work fine as-is, and enhancements are optional Phase 5-6 work.

### Q: What code patterns should I follow?
**A**: Look at RenameLogic/RMT.sv lines 45-185 - it has all the patterns you need.

### Q: Will my changes break something?
**A**: Only if you modify the single-threaded path. Always verify with `make run` after each file.

### Q: How do I know if I'm doing it right?
**A**: If single-threaded still produces IPC 0.985285, 4621 cycles, you're on the right track.

### Q: What if I get stuck?
**A**: Read PHASE4_HANDOVER.md again - it's comprehensive and covers all scenarios.

---

## 📋 Before You Start Coding

Verify you have checked all these:
- [ ] Read START_HERE.md (this file)
- [ ] Verified baseline: `make run` → IPC 0.985285, 4621 cycles ✓
- [ ] Read README_NEXT_SESSION.md
- [ ] Read PHASE4_HANDOVER.md
- [ ] Reviewed RenameLogic/RMT.sv (reference implementation)
- [ ] Decided on Phase 4 design approach (shared vs per-thread)
- [ ] Understand conditional compilation pattern
- [ ] Have version control or backup ready

---

## 🚀 Next Steps

### Immediate (Next 30 min)
1. Verify baseline works: `make run`
2. Read README_NEXT_SESSION.md (15 min)
3. Read PHASE4_HANDOVER.md (20 min)

### Before Coding (Next 45 min)
4. Review design decisions in PHASE4_HANDOVER.md
5. Decide your approach for each resource type
6. Skim RenameLogic/RMT.sv for code patterns
7. Create implementation plan

### Implementation (4-5 hours)
8. Start with Step 1: RenameLogicTypes.sv
9. Regression test after each file
10. Continue through Step 6
11. Verify multi-threaded builds

### Finish (30 min)
12. Update documentation
13. Create PHASE4_COMPLETION.md report

---

## 📞 Key Documents at a Glance

| Document | Purpose | Read Time |
|----------|---------|-----------|
| **START_HERE.md** | This file - overview | 10 min |
| **README_NEXT_SESSION.md** | Getting started Phase 4 | 15 min |
| **PHASE4_HANDOVER.md** | Complete spec | 30 min |
| **BRANCH_PREDICTOR_CACHE_ANALYSIS.md** | System design Q&A | 15 min |
| **HANDOVER_INDEX.md** | Full document index | 5 min |
| **SMT_PHASE3_COMPLETION.md** | Reference implementation | 15 min |
| **DELIVERY_SUMMARY.txt** | What was delivered | 10 min |

---

## ✨ You're Ready!

Everything you need is here:
- ✓ Working Phase 1-3 implementation
- ✓ Clear specification for Phase 4 (PHASE4_HANDOVER.md)
- ✓ Code patterns and examples (RMT.sv)
- ✓ Testing procedures (regression test)
- ✓ Complete documentation

**Start with**: README_NEXT_SESSION.md

**Questions?** All answers are in these documents - use HANDOVER_INDEX.md to find what you need.

Good luck! 🚀

---

**Last Updated**: November 24, 2025
**Status**: Phase 1-3 Complete, Phase 4 Ready
**Baseline**: Verified ✓
