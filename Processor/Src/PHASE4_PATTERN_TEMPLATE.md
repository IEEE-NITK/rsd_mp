# Phase 4 Implementation Pattern Template

**Based on**: RenameLogic/RMT.sv verification  
**Purpose**: Exact template to use for all Phase 4 per-thread resources

---

## THE PATTERN (From RMT.sv)

```systemverilog
//
// Template for Per-Thread Resource Implementation
// Based on RenameLogic/RMT.sv lines 41-185
//

import BasicTypes::*;

module ResourceName( ResourceNameIF.ResourceName port );

    // ============================================
    // SECTION 1: TYPE DEFINITIONS
    // ============================================
    
    typedef struct packed {
        // Your fields here
        logic [FIELD_WIDTH-1:0] field1;
        logic field2;
        // ... more fields ...
    } ResourceEntry;

    // ============================================
    // SECTION 2: DATA STRUCTURES
    // ============================================

`ifdef RSD_ENABLE_SMT
    // ========== MULTI-THREADED VERSION ==========
    
    // Per-thread resource arrays
    ResourceEntry data[THREAD_NUM][RESOURCE_SIZE];
    ResourceEntry tempData[THREAD_NUM][RESOURCE_SIZE];
    
    // Per-thread pointers/counters
    ResourceIndexPath ptr[THREAD_NUM];
    
    // Write signals per thread
    logic we[THREAD_NUM][WRITE_WIDTH];
    ResourceIndexPath wa[THREAD_NUM][WRITE_WIDTH];
    ResourceEntry wv[THREAD_NUM][WRITE_WIDTH];
    
    // Read signals per thread
    ResourceIndexPath ra[THREAD_NUM][READ_WIDTH];
    ResourceEntry rv[THREAD_NUM][READ_WIDTH];

`else
    // ========== SINGLE-THREADED VERSION (ORIGINAL) ==========
    
    // Single resource array (original code)
    ResourceEntry data[RESOURCE_SIZE];
    ResourceEntry tempData[RESOURCE_SIZE];
    
    ResourceIndexPath ptr;
    
    logic we[WRITE_WIDTH];
    ResourceIndexPath wa[WRITE_WIDTH];
    ResourceEntry wv[WRITE_WIDTH];
    
    ResourceIndexPath ra[READ_WIDTH];
    ResourceEntry rv[READ_WIDTH];

`endif

    // ============================================
    // SECTION 3: LOGIC IMPLEMENTATION
    // ============================================

    always_comb begin
    
`ifdef RSD_ENABLE_SMT
        // ========== MULTI-THREADED LOGIC ==========
        
        // Per-thread processing
        for (int t = 0; t < THREAD_NUM; t++) begin
            
            // Write logic for thread t
            for (int i = 0; i < WRITE_WIDTH; i++) begin
                if (!port.rst) begin
                    // Check if this write is for this thread
                    // CRITICAL: Only enable write for matching thread
                    we[t][i] = port.weIn[i] && (port.thread[i] == t);
                    wa[t][i] = port.waIn[i];
                    wv[t][i] = port.wvIn[i];
                    
                    // Write-to-write bypass (prevent duplicate writes in same cycle)
                    for (int j = 0; j < i; j++) begin
                        if (we[t][i] && wa[t][i] == wa[t][j]) begin
                            we[t][j] = FALSE;  // Cancel earlier write
                        end
                    end
                end
                else begin
                    // Reset initialization
                    we[t][i] = (i == 0 ? TRUE : FALSE);
                    wa[t][i] = port.rstAddr[i];
                    wv[t][i] = port.rstValue[i];
                end
            end
            
            // Read logic for thread t
            for (int i = 0; i < READ_WIDTH; i++) begin
                ra[t][i] = port.raIn[i];
            end
        end
        
        // Output reads from the appropriate thread
        for (int i = 0; i < READ_WIDTH; i++) begin
            ThreadID threadID = port.thread[i];
            
            // Read from thread-specific data
            rv[threadID][i] = data[threadID][ra[threadID][i]];
            
            // CRITICAL: Read-to-write bypass
            // Only forward from writes to SAME thread in same cycle
            for (int j = 0; j < i; j++) begin
                if (port.weIn[j] && (port.thread[j] == threadID)) begin
                    if (port.waIn[j] == port.raIn[i]) begin
                        // Forward the write value
                        rv[threadID][i] = port.wvIn[j];
                    end
                end
            end
        end
        
        // Assign outputs
        port.readOut = rv[port.thread[0]];  // Or appropriate thread index

`else
        // ========== SINGLE-THREADED LOGIC (ORIGINAL) ==========
        
        // Write logic (unchanged from original)
        for (int i = 0; i < WRITE_WIDTH; i++) begin
            if (!port.rst) begin
                we[i] = port.weIn[i];
                wa[i] = port.waIn[i];
                wv[i] = port.wvIn[i];
                
                // Write-to-write bypass
                for (int j = 0; j < i; j++) begin
                    if (we[i] && wa[i] == wa[j]) begin
                        we[j] = FALSE;
                    end
                end
            end
            else begin
                we[i] = (i == 0 ? TRUE : FALSE);
                wa[i] = port.rstAddr[i];
                wv[i] = port.rstValue[i];
            end
        end
        
        // Read logic (unchanged from original)
        for (int i = 0; i < READ_WIDTH; i++) begin
            ra[i] = port.raIn[i];
            rv[i] = data[ra[i]];
            
            // Read-to-write bypass
            for (int j = 0; j < i; j++) begin
                if (port.weIn[j]) begin
                    if (port.waIn[j] == port.raIn[i]) begin
                        rv[i] = port.wvIn[j];
                    end
                end
            end
        end
        
        // Assign outputs
        port.readOut = rv;

`endif
    end
    
    // ============================================
    // SECTION 4: SEQUENTIAL LOGIC (IF NEEDED)
    // ============================================
    
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            // Reset per-thread or single pointers
`ifdef RSD_ENABLE_SMT
            for (int t = 0; t < THREAD_NUM; t++) begin
                ptr[t] <= '0;
            end
`else
            ptr <= '0;
`endif
        end
        else begin
            // Update logic
`ifdef RSD_ENABLE_SMT
            for (int t = 0; t < THREAD_NUM; t++) begin
                if (port.updateEn[t]) begin
                    ptr[t] <= port.nextPtr[t];
                end
            end
`else
            if (port.updateEn) begin
                ptr <= port.nextPtr;
            end
`endif
        end
    end

endmodule : ResourceName
```

---

## CRITICAL RULES (From RMT.sv Analysis)

### Rule 1: Thread Check for Writes
```systemverilog
// ALWAYS include thread check:
we[t][i] = port.weIn[i] && (port.thread[i] == t);
//                          ^^^^^^^^^^^^^^^^^^^^^^^^^
//                          MUST CHECK THREAD MATCH
```

**Why**: Prevents cross-thread writes, ensures thread isolation.

---

### Rule 2: Extract Thread ID Before Use
```systemverilog
// ALWAYS extract threadID once at start:
ThreadID threadID = port.thread[i];

// Then use in array indexing:
rv[threadID][...] = data[threadID][...];
//  ^^^^^^^^         ^^^^ ^^^^^^^^
//  Use extracted ID everywhere
```

**Why**: Cleaner code, avoids repeated port lookups, easier to verify.

---

### Rule 3: Bypass Only Within Same Thread
```systemverilog
// Check thread match BEFORE forwarding:
if (port.weIn[j] && (port.thread[j] == threadID)) begin
//                  ^^^^^^^^^^^^^^^^^^^^^^^^^^
//                  MUST MATCH THREAD
    if (port.waIn[j] == port.raIn[i]) begin
        rv[threadID][i] = port.wvIn[j];
    end
end
```

**Why**: Prevents cross-thread data leakage, ensures correctness.

---

### Rule 4: Preserve Original in Else
```systemverilog
`ifdef RSD_ENABLE_SMT
    // Multi-threaded version with per-thread logic
    for (int t = 0; t < THREAD_NUM; t++) begin
        // ... per-thread code ...
    end
`else
    // Original single-threaded code (UNCHANGED)
    // Copy exact original logic here
`endif
```

**Why**: Guarantees backward compatibility, 100% identical single-threaded behavior.

---

### Rule 5: Loop Structure
```systemverilog
// Multi-threaded outer loop:
for (int t = 0; t < THREAD_NUM; t++) begin
    // Inner loop for WIDTH:
    for (int i = 0; i < WRITE_WIDTH; i++) begin
        // Access: data[t][index]
        we[t][i] = ...;
    end
end
```

**Why**: Generates all thread instances, scales with THREAD_NUM parameter.

---

## APPLICATION CHECKLIST

For each Phase 4 resource (Free List, Active List, Load Queue, Store Queue):

- [ ] **Step 1**: Copy template above
- [ ] **Step 2**: Replace ResourceEntry with actual type
- [ ] **Step 3**: Replace RESOURCE_SIZE with actual size
- [ ] **Step 4**: Add necessary signals (depends on resource)
- [ ] **Step 5**: Implement multi-threaded logic (lines under `ifdef RSD_ENABLE_SMT`)
- [ ] **Step 6**: Copy original logic to else clause unchanged
- [ ] **Step 7**: Verify all 5 Rules applied
- [ ] **Step 8**: Test: `make clean && make all && make run`
- [ ] **Step 9**: Verify: IPC must be 0.985285, cycles must be 4621

---

## TEMPLATE VARIANTS

### Variant A: Simple Array with Per-Thread Pointers
**Best for**: Free Lists, Load Queue, Store Queue

```systemverilog
`ifdef RSD_ENABLE_SMT
    ResourceEntry data[THREAD_NUM][SIZE];
    ResourceIndexPath ptr[THREAD_NUM];
`else
    ResourceEntry data[SIZE];
    ResourceIndexPath ptr;
`endif
```

### Variant B: FIFO with Per-Thread Head/Tail
**Best for**: Active List (if going per-thread)

```systemverilog
`ifdef RSD_ENABLE_SMT
    ResourceEntry data[THREAD_NUM][SIZE];
    ResourceIndexPath headPtr[THREAD_NUM];
    ResourceIndexPath tailPtr[THREAD_NUM];
`else
    ResourceEntry data[SIZE];
    ResourceIndexPath headPtr;
    ResourceIndexPath tailPtr;
`endif
```

### Variant C: Shared Array with Thread ID Field
**Alternative to per-thread** (not recommended, but viable):

```systemverilog
typedef struct packed {
    // ... existing fields ...
`ifdef RSD_ENABLE_SMT
    ThreadID thread;  // ADD THIS
`endif
} ResourceEntry;

// Keep single array
ResourceEntry data[SIZE];

// But check thread on read/write
if (port.thread[i] == data[index].thread) begin
    // Can access this entry
end
```

**Note**: More complex logic, not recommended. Follow per-thread pattern.

---

## EXACT COMMAND SEQUENCE FOR PHASE 4

### For Each Resource (Free Lists first):

```bash
# 1. Open resource file in editor
nano RenameLogic/RenameLogic.sv  # or LoadStoreUnit/LoadStoreUnit.sv, etc.

# 2. Copy template above
# 3. Apply rules 1-5
# 4. Review code

# 5. Compile
make clean && make all

# 6. Test
make run

# 7. Verify output
# Must see:
#   IPC (RISC-V instruction): 0.985285
#   Elapsed cycles:        4621

# 8. If not, revert and debug
# DO NOT commit changes that change baseline performance

# 9. Commit when verified
git add RenameLogic/RenameLogic.sv
git commit -m "Phase 4: Add per-thread free lists"
```

---

## COMMON MISTAKES (Don't Make These)

### ❌ Mistake 1: Forgetting Thread Check
```systemverilog
// WRONG:
we[t][i] = port.weIn[i];  // No thread check!

// CORRECT:
we[t][i] = port.weIn[i] && (port.thread[i] == t);
```

### ❌ Mistake 2: Cross-Thread Bypass
```systemverilog
// WRONG:
rv[i] = port.wvIn[j];  // No thread check!

// CORRECT:
if (port.thread[j] == threadID) begin
    rv[i] = port.wvIn[j];  // Only within same thread
end
```

### ❌ Mistake 3: Modifying Else Clause
```systemverilog
// WRONG:
`else
    // Original code PLUS modifications
    we[i] = port.weIn[i];
    wa[i] = port.waIn[i];
    // ✗ Can't modify - breaks compatibility!

// CORRECT:
`else
    // EXACT copy of original (no changes)
    for (int i = 0; i < WRITE_WIDTH; i++) begin
        we[i] = port.weIn[i];
        wa[i] = port.waIn[i];
    end
`endif
```

### ❌ Mistake 4: Forgetting Thread Extraction
```systemverilog
// WRONG - repeated lookups:
rv[port.thread[i]][0] = data[port.thread[i]][...];
rv[port.thread[i]][1] = data[port.thread[i]][...];
rv[port.thread[i]][2] = data[port.thread[i]][...];

// CORRECT - extract once:
ThreadID threadID = port.thread[i];
rv[threadID][0] = data[threadID][...];
rv[threadID][1] = data[threadID][...];
rv[threadID][2] = data[threadID][...];
```

### ❌ Mistake 5: Changing Baseline
```
make run shows:
  IPC: 0.984000  ✗ WRONG (was 0.985285)
  
Action: REVERT and DEBUG
DO NOT COMMIT
```

---

## SUCCESS CRITERIA

After applying pattern to a resource:

1. ✅ Code compiles without errors
2. ✅ Code compiles without warnings  
3. ✅ `make run` completes successfully
4. ✅ Output shows: IPC 0.985285, cycles 4621 (exactly)
5. ✅ All 5 rules verified in code
6. ✅ Thread ID field present in ifdef block
7. ✅ Original code in else block (unchanged)
8. ✅ No cross-thread logic

---

## REFERENCE

**Exact file to study**: `RenameLogic/RMT.sv`
**Lines to study**: 41-185
**Pattern location**: Lines 41-86 (structure), 92-185 (logic)

---

## TIMELINE ESTIMATE

Using this template:

| Task | Time | Cumulative |
|------|------|-----------|
| Free Lists | 45 min | 45 min |
| Active List | 60 min | 1:45 |
| Issue Queue | 30 min | 2:15 |
| Load Queue | 45 min | 3:00 |
| Store Queue | 45 min | 3:45 |
| Testing | 1-2 hours | 5:45 |

**Total**: 5-6 hours for Phase 4

---

## FINAL NOTES

✅ This template is proven (used in RMT.sv)
✅ This pattern scales to all resources  
✅ This approach maintains backward compatibility
✅ This method ensures thread safety

**Do not deviate from this pattern without strong justification.**

---

**Good luck with Phase 4!**
