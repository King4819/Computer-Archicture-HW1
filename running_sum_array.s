.data
array: .word 0x411d0000, 0xc2c80000, 0x426b0000
length: .word 3

print_newline: .string "\n"


.text
main:
    la s0, array
    
    lw s2, length

    #################### convert fp32 to bf16 ####################

    lw a0, 0(s0)
    jal ra, fp32_to_bf16      
    sw a1, 0(s0)

    lw a0, 4(s0)
    jal ra, fp32_to_bf16      
    sw a1, 4(s0)

    lw a0, 8(s0)
    jal ra, fp32_to_bf16      
    sw a1, 8(s0)
    


    #################### do running sum ####################

    lw t0, 0(s0)
    lw t1, 4(s0)
    jal ra, bf16_add
    sw t1, 4(s0)

    lw t0, 4(s0)
    lw t1, 8(s0)
    jal ra, bf16_add
    sw t1, 8(s0)

    lw t0, 8(s0)
    lw t1, 12(s0)
    jal ra, bf16_add
    sw t1, 12(s0)


    #################### print and finish ####################

    lw a0, 0(s0)
    li a7, 34
    ecall

    la a0, print_newline
    li a7, 4
    ecall

    lw a0, 4(s0)
    li a7, 34
    ecall
    
    la a0, print_newline
    li a7, 4
    ecall

    lw a0, 8(s0)
    li a7, 34
    ecall

    li a7, 10
    ecall


fp32_to_bf16:
    addi sp, sp, -8           # Allocate stack space for local variables (ra and a0)
    sw ra, 4(sp)              # Save return address (ra) on the stack
    sw a0, 0(sp)              # Save input argument (a0) on the stack

    mv t0, a0                 # t0 = a0

    li t1, 0x7fffffff         # t1 = 0x7fffffff
    and t1, t0, t1            # t1 = t0 & 0x7fffffff
    li t2, 0x7f800000         # t2 = 0x7f800000
    
    bge t2, t1, Else          # if 0x7f800000 >= t0 & 0x7fffffff, goto Else
    srli t1, t0, 16           # t1 = t0 >> 16
    ori t1, t1, 64            # t1 = t1 | 64
    mv a1, t1                 # a1 = t1
    j Exit                    # goto Exit;

    Else:
        srli t1, t0, 16       # t1 = t0 >> 16
        andi t1, t1, 1        # t1 = t1 & 1
        li t2, 0x7fff         # t2 = 0x7fff
        add t1, t1, t2        # t1 = t1 + t2
        add t1, t1, t0        # t1 = t1 + t0
        srli t1, t1, 16       # t1 = t1 >> 16
        mv a1, t1             # a1 = t1
        ret                   # return

    Exit:
        lw ra, 4(sp)          # Restore ra on stack
        lw a0, 0(sp)          # Restore a0 on stack
        addi sp, sp, 8        # Restore stack
        ret                   # return


clz:
    # 
    addi sp, sp, -4
    sh t0, 0(sp)
    sh t2, 2(sp)

    # x |= (x >> 1)
    srli t1, t0, 1
    or t0, t0, t1

    # x |= (x >> 2)
    srli t1, t0, 2
    or t0, t0, t1

    # x |= (x >> 4)
    srli t1, t0, 4
    or t0, t0, t1

    # x |= (x >> 8)
    srli t1, t0, 8
    or t0, t0, t1

    # x -= ((x >> 1) & 0x5555)
    srli t1, t0, 1
    li t2, 0x5555
    and t1, t1, t2
    sub t0, t0, t1

    # x = ((x >> 2) & 0x3333) + (x & 0x3333)
    srli t1, t0, 2
    li t2, 0x3333
    and t1, t1, t2
    and t0, t0, t2
    add t0, t0, t1

    # x = ((x >> 4) + x) & 0x0f0f
    srli t1, t0, 4
    add t0, t0, t1
    li t2, 0x0f0f
    and t0, t0, t2

    # x += (x >> 8)
    srli t1, t0, 8
    add t0, t0, t1

    # return (16 - (x & 0x7f))
    andi t0, t0, 0x7f
    xori t0, t0, -1
    addi t1, t0, 17

    # 
    lh t0, 0(sp)
    lh t2, 2(sp)
    addi sp, sp 4
    ret


bf16_add:
    addi sp, sp, -4
    sw ra, 0(sp)

    # exp1
    slli t2, t0, 17
    srli t2, t2, 24

    # exp2
    slli t3, t1, 17
    srli t3, t3, 24
    blt t2, t3, swap

    # t2 = exp, t4 = shift amount
    sub t4, t2, t3
    j cal

swap: 
    # swap t0 and t1
    mv t4, t0
    mv t0, t1
    mv t1, t4

    # t2 = exp, t4 = v
    sub t4, t3, t2
    mv t2, t3

cal:
    # t3 = sign
    srli t3, t0, 15

    # t5 = 0 -> add, t5 = 1 -> sub
    xor t5, t0, t1
    srli t5, t5, 15

    # t0 = t0_mant
    andi t0, t0, 127
    ori, t0, t0, 128

    # t1 = t1_mant
    andi t1, t1, 127
    ori t1, t1, 128
    srl t1, t1, t4
    
    # decide add or sub
    beqz t5, add_operation

    # t0 = mant
    sub t0, t0, t1

    j normalize

add_operation:
    add t0, t0, t1

normalize:
    # t1 = lz
    call clz
    li t4, 8
    addi t1, t1, -8

    # normalize exp
    sub t2, t2, t1

    # t1 = |t1|
    srai t4, t1, 4
    xor t1, t1, t4    
    srli t4, t4, 31
    add t1, t1, t4

    # 
    beqz t4, shift_left
    srl t0, t0, t1
    
    j finish

shift_left:
    sll t0, t0, t1

finish:
    addi t0, t0, -128
    slli t3, t3, 15
    slli t2, t2, 7
    or t1, t0, t2
    or t1, t1, t3
    
    lw ra, 0(sp)
    addi sp, sp, 4
    ret
