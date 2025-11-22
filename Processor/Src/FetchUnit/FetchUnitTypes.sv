package FetchUnitTypes;

    import MicroArchConf::*;
    import BasicTypes::*;
    import MemoryMapTypes::*;

    //
    // BTB
    //

    localparam BTB_ENTRY_NUM = CONF_BTB_ENTRY_NUM;

    // Entry: 1(valid)+BTB_TAG_WIDTH+BTB_CONTENTS_ADDR_WIDTH <= 18 bits
    // (fits in a single BRAM primitive on Xilinx).

    // Tag width, only lower bits are checked and the result may be approximate.
    localparam BTB_TAG_WIDTH = 4;

    // BTB stores BTB_CONTENTS_ADDR_WIDTH bits of target; upper bits come from the PC.
    localparam BTB_CONTENTS_ADDR_WIDTH = 13;

    localparam BTB_ENTRY_NUM_BIT_WIDTH = $clog2(BTB_ENTRY_NUM);
    typedef logic [BTB_ENTRY_NUM_BIT_WIDTH-1:0] BTB_IndexPath;
    typedef logic [BTB_CONTENTS_ADDR_WIDTH-1:0] BTB_AddrPath;
    typedef logic [BTB_TAG_WIDTH-1:0]          BTB_TagPath;

    localparam BTB_QUEUE_SIZE           = 32;
    localparam BTB_QUEUE_SIZE_BIT_WIDTH = $clog2(BTB_QUEUE_SIZE);
    typedef logic [BTB_QUEUE_SIZE_BIT_WIDTH-1:0] BTBQueuePointerPath;

    typedef struct packed // struct BTB_Entry
    {
        logic        valid;
        BTB_TagPath  tag;
        BTB_AddrPath data;
        logic        isCondBr;
        // NOTE: BTB is shared across threads; tid is not stored here.
    } BTB_Entry;

    typedef struct packed // struct BTBQueueEntry (for delayed BTB updates)
    {
        BTB_IndexPath btbWA;   // Write index (already decoded index)
        BTB_Entry     btbWV;   // BTB entry to be written
    } BTBQueueEntry;


    // --- BTB index / tag / addr helpers ---
    // Shared BTB, but index is tid-aware via XOR folding of tid into index.
    // Tag and stored target remain purely address-based.

    function automatic BTB_IndexPath ToBTB_Index(PC_Path pc);
        BTB_IndexPath base;
        BTB_IndexPath tid_mask;

        // Original index from PC address bits (ignoring low INSN_ADDR_BIT_WIDTH)
        base = pc.addr[
            BTB_ENTRY_NUM_BIT_WIDTH + INSN_ADDR_BIT_WIDTH - 1 :
            INSN_ADDR_BIT_WIDTH
        ];

        // Zero-extend tid and XOR into the index so each thread gets
        // its own "view" of the BTB entries.
        tid_mask = '0;
        tid_mask[THREAD_NUM_BIT_WIDTH-1:0] = pc.tid;

        return base ^ tid_mask;
    endfunction

    function automatic BTB_TagPath ToBTB_Tag(PC_Path pc);
        // Tag uses only address bits, not tid.
        return pc.addr[
            BTB_ENTRY_NUM_BIT_WIDTH + INSN_ADDR_BIT_WIDTH + BTB_TAG_WIDTH - 1 :
            BTB_ENTRY_NUM_BIT_WIDTH + INSN_ADDR_BIT_WIDTH
        ];
    endfunction

    function automatic BTB_AddrPath ToBTB_Addr(PC_Path pc);
        // Stored target bits (address-only).
        return pc.addr[
            INSN_ADDR_BIT_WIDTH + BTB_CONTENTS_ADDR_WIDTH - 1 :
            INSN_ADDR_BIT_WIDTH
        ];
    endfunction

    // Reconstruct full PC from BTB target and original PC high bits (address only),
    // and PRESERVE tid so prediction stays in the same thread.
    function automatic PC_Path ToRawAddrFromBTB_Addr(
        BTB_AddrPath addr,
        PC_Path      pc
    );
        PC_Path result;

        // No assignment pattern here → avoids the Verilator error.
        result.addr = {
            pc.addr[PC_WIDTH-1 : BTB_CONTENTS_ADDR_WIDTH + 2],
            addr[BTB_CONTENTS_ADDR_WIDTH-1 : 0],
            2'b0
        };

        result.tid  = pc.tid;  // keep the same thread

        return result;
    endfunction


    //
    // GShare
    //

    localparam BRANCH_GLOBAL_HISTORY_BIT_WIDTH = CONF_BRANCH_GLOBAL_HISTORY_BIT_WIDTH;
    typedef logic [BRANCH_GLOBAL_HISTORY_BIT_WIDTH-1 : 0] BranchGlobalHistoryPath;


    //
    // PHT
    //

    localparam PHT_ENTRY_NUM           = CONF_PHT_ENTRY_NUM;
    localparam PHT_ENTRY_NUM_BIT_WIDTH = $clog2(PHT_ENTRY_NUM);
    typedef logic [PHT_ENTRY_NUM_BIT_WIDTH-1:0] PHT_IndexPath;

    localparam PHT_ENTRY_WIDTH = 2;
    localparam PHT_ENTRY_MAX   = (1 << PHT_ENTRY_WIDTH) - 1;
    typedef logic [PHT_ENTRY_WIDTH-1:0] PHT_EntryPath;

    localparam PHT_QUEUE_SIZE           = 32;
    localparam PHT_QUEUE_SIZE_BIT_WIDTH = $clog2(PHT_QUEUE_SIZE);
    typedef logic [PHT_QUEUE_SIZE_BIT_WIDTH-1:0] PhtQueuePointerPath;

    typedef struct packed // struct PhtQueueEntry (for delayed PHT updates)
    {
        PHT_IndexPath phtWA;   // Write index (already decoded index)
        PHT_EntryPath phtWV;   // New counter value
    } PhtQueueEntry;


    //
    // Result / prediction (SMT-aware via PC_Path.tid)
    //

    typedef struct packed // struct BranchResult
    {
        PC_Path  brAddr;       // Address of executed branch (PC + tid)
        PC_Path  nextAddr;     // Next PC after branch
        logic    execTaken;    // Actual taken/not-taken
        logic    predTaken;    // Predicted taken/not-taken
        logic    isCondBr;     // Conditional branch?
        logic    mispred;      // Misprediction flag
        logic    valid;        // Entry valid

        BranchGlobalHistoryPath globalHistory; // History used at prediction
        PHT_EntryPath           phtPrevValue;  // PHT counter value used then
    } BranchResult;

    typedef struct packed // struct BranchPred
    {
        PC_Path  predAddr;     // Predicted next address (includes tid)
        logic    predTaken;    // Predicted taken/not-taken

        BranchGlobalHistoryPath globalHistory; // History used for this prediction
        PHT_EntryPath           phtPrevValue;  // PHT counter value used
    } BranchPred;

endpackage : FetchUnitTypes