.file "quicksort_smt.s"
    .attribute arch, "rv32im"
    .attribute unaligned_access, 0
    .attribute stack_align, 16

    .section .data
    .align 4

    # --- Synchronization Flags ---
    # 0 = Wait, 1 = Go/Done
    .globl flag_t1_start
    .globl flag_t1_done
flag_t1_start:  .word 0
flag_t1_done:   .word 0

    # --- Shared Task Data for Thread 1 ---
t1_low:         .word 0
t1_high:        .word 0

    # --- The Array to Sort ---
    .globl sort_array
sort_array:
    .word 45, 12, 89, 33, 21, 1, 56, 99
    .word 2, 15, 67, 34, 22, 11, 90, 105
    # Array Length = 16 (indices 0 to 15)

    .section .text
    .align 4
    .globl main_thread0
    .globl main_thread1

# ====================================================================
# MAIN THREAD 0: Performs initial partition, delegates right half to T1
# ====================================================================
main_thread0:
    addi    sp, sp, -16
    sw      ra, 12(sp)

    # 1. Perform Initial Partition on range [0, 15]
    la      a0, sort_array  # Base address
    li      a1, 0           # Low index
    li      a2, 15          # High index
    call    partition       # Returns pivot index in a0

    # Pivot is now in a0. Let's call it 'p'.
    # We give Thread 1 the range [p+1, 15]
    # We keep the range [0, p-1]

    # 2. Prepare Task for Thread 1 (Right Half)
    la      t0, t1_low
    addi    t1, a0, 1       # t1 = p + 1
    sw      t1, 0(t0)       # Store t1_low

    la      t0, t1_high
    li      t2, 15          # High is always 15 for the first split
    sw      t2, 0(t0)       # Store t1_high

    # 3. Signal Thread 1 to Start
    fence   w, w            # Ensure data is written before flag
    la      t0, flag_t1_start
    li      t1, 1
    sw      t1, 0(t0)       # flag_t1_start = 1

    # 4. Sort Left Half (Thread 0 work)
    # Range: [0, p-1]
    la      a0, sort_array
    li      a1, 0           # Low
    # a2 needs to be p-1. (p is currently in old a0 return val, let's recover)
    # Actually, a0 still holds 'p' from the partition return.
    addi    a2, a0, -1      # High = p - 1
    call    quicksort_recursive

    # 5. Wait for Thread 1 to finish (Synchronization)
wait_for_t1:
    la      t0, flag_t1_done
    lw      t1, 0(t0)
    beqz    t1, wait_for_t1 # Spin if 0

    # 6. Done
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

# ====================================================================
# MAIN THREAD 1: Waits for signal, then sorts its assigned range
# ====================================================================
main_thread1:
    addi    sp, sp, -16
    sw      ra, 12(sp)

    # 1. Spin-wait for start signal
spin_start:
    la      t0, flag_t1_start
    lw      t1, 0(t0)
    beqz    t1, spin_start

    fence   r, r            # Ensure we see the data updates

    # 2. Load assigned range
    la      t0, t1_low
    lw      a1, 0(t0)       # a1 = low
    la      t0, t1_high
    lw      a2, 0(t0)       # a2 = high
    la      a0, sort_array  # a0 = Base address

    # 3. Perform Sort
    call    quicksort_recursive

    # 4. Signal Completion
    fence   w, w
    la      t0, flag_t1_done
    li      t1, 1
    sw      t1, 0(t0)

    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

# ====================================================================
# RECURSIVE QUICKSORT (Standard Implementation)
# Args: a0 (base), a1 (low), a2 (high)
# ====================================================================
quicksort_recursive:
    # Check Base Case: if (low >= high) return
    bge     a1, a2, qs_return

    # Prologue: Save state
    addi    sp, sp, -20
    sw      ra, 16(sp)
    sw      s0, 12(sp)      # Save Base Address
    sw      s1, 8(sp)       # Save Low
    sw      s2, 4(sp)       # Save High
    sw      s3, 0(sp)       # Save Pivot

    mv      s0, a0          # Move args to safe registers
    mv      s1, a1
    mv      s2, a2

    # Partition
    # a0, a1, a2 are already set correctly
    call    partition
    mv      s3, a0          # s3 = pivot index 'p'

    # Recursive Call Left: quicksort(arr, low, p-1)
    mv      a0, s0
    mv      a1, s1
    addi    a2, s3, -1      # high = p - 1
    call    quicksort_recursive

    # Recursive Call Right: quicksort(arr, p+1, high)
    mv      a0, s0
    addi    a1, s3, 1       # low = p + 1
    mv      a2, s2
    call    quicksort_recursive

    # Epilogue
    lw      s3, 0(sp)
    lw      s2, 4(sp)
    lw      s1, 8(sp)
    lw      s0, 12(sp)
    lw      ra, 16(sp)
    addi    sp, sp, 20

qs_return:
    ret

# ====================================================================
# PARTITION FUNCTION (Lomuto partition scheme)
# Args: a0 (base addr), a1 (low index), a2 (high index)
# Returns: a0 (pivot index)
# ====================================================================
partition:
    addi    sp, sp, -24
    sw      s0, 20(sp) # pivot value
    sw      s1, 16(sp) # i
    sw      s2, 12(sp) # j
    sw      s3, 8(sp)  # high index
    sw      s4, 4(sp)  # base address
    sw      ra, 0(sp)

    mv      s4, a0     # s4 = base
    mv      s3, a2     # s3 = high

    # pivot = arr[high]
    slli    t0, s3, 2  # offset = high * 4
    add     t0, s4, t0 # addr = base + offset
    lw      s0, 0(t0)  # s0 = pivot value

    # i = low - 1
    addi    s1, a1, -1

    # for (j = low; j < high; j++)
    mv      s2, a1     # j = low
partition_loop:
    bge     s2, s3, partition_end_loop # if j >= high, break

    # Load arr[j]
    slli    t0, s2, 2
    add     t0, s4, t0
    lw      t1, 0(t0)  # t1 = arr[j]

    # if (arr[j] < pivot)
    bge     t1, s0, partition_next_iter

    # i++
    addi    s1, s1, 1

    # swap(&arr[i], &arr[j])
    # Prepare arguments for swap: address of arr[i], address of arr[j]
    slli    t2, s1, 2
    add     a0, s4, t2 # &arr[i]
    slli    t3, s2, 2
    add     a1, s4, t3 # &arr[j]
    call    swap

partition_next_iter:
    addi    s2, s2, 1
    j       partition_loop

partition_end_loop:
    # swap(&arr[i + 1], &arr[high])
    addi    t0, s1, 1  # i + 1
    slli    t2, t0, 2
    add     a0, s4, t2 # &arr[i+1]
    slli    t3, s3, 2
    add     a1, s4, t3 # &arr[high]
    call    swap

    # return (i + 1)
    addi    a0, s1, 1

    lw      ra, 0(sp)
    lw      s4, 4(sp)
    lw      s3, 8(sp)
    lw      s2, 12(sp)
    lw      s1, 16(sp)
    lw      s0, 20(sp)
    addi    sp, sp, 24
    ret

# ====================================================================
# SWAP FUNCTION
# Args: a0 (pointer to A), a1 (pointer to B)
# ====================================================================
swap:
    lw      t0, 0(a0)
    lw      t1, 0(a1)
    sw      t1, 0(a0)
    sw      t0, 0(a1)
    ret
