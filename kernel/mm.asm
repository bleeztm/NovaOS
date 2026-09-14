; NovaOS kernel/mm.asm - physical bitmap allocator + bump kmalloc
; Bitmap at phys 0x150000 (16KB -> tracks 512MB in 4KB pages, 1 bit/page).
; Low memory is identity-mapped by stage2, so absolute addresses work.
; Heap: bump allocator from 2MB. No free() in v0.1 (documented).

PMM_BITMAP    equ 0x150000
PMM_BITMAP_SZ equ 16384
PAGE_SIZE     equ 4096

; RDI = BootInfo*. Parses UEFI-style map, frees usable RAM, reserves low 2MB.
pmm_init:
    push rbx
    push rcx
    push rdx
    push rsi
    push r8
    push r9
    push rdi
    ; clear bitmap = all reserved
    mov rdi, PMM_BITMAP
    mov rcx, PMM_BITMAP_SZ/8
    xor eax, eax
    rep stosq
    mov qword [heap_end], 0x200000
    pop rdi                                ; RDI = BootInfo*
    mov rsi, [rdi+32]                      ; mmap addr
    mov rcx, [rdi+40]                      ; count
    mov r8, [rdi+48]                       ; entry size
    test rcx, rcx
    jz .fallback
    test rsi, rsi
    jz .fallback
    cmp r8, 24
    jb .fallback
.walk:
    push rcx
    push rsi
    mov rax, [rsi+0]                       ; base
    mov rdx, [rsi+8]                       ; len
    mov ebx, [rsi+16]                      ; type (1=usable)
    cmp ebx, 1
    jne .next
    call pmm_mark_free_range
.next:
    pop rsi
    add rsi, r8
    pop rcx
    dec rcx
    jnz .walk
    jmp .reserve_low
.fallback:                                 ; no map: free 2MB..8MB
    mov rax, 0x200000
    mov rdx, 0x600000
    call pmm_mark_free_range
.reserve_low:                              ; reserve 0..2MB (boot code, bitmap, heap anchor)
    mov rax, 0x0
    mov rdx, 0x200000
    call pmm_mark_used_range
    pop r9
    pop r8
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; set bit for page index in RAX
pmm_bit_set:
    push rdx
    push rcx
    push rax
    mov rdx, rax
    shr rdx, 3
    and eax, 7
    mov cl, al
    mov al, 1
    shl al, cl
    or [PMM_BITMAP+rdx], al
    pop rax
    pop rcx
    pop rdx
    ret

; clear bit for page index in RAX
pmm_bit_clear:
    push rdx
    push rcx
    push rax
    mov rdx, rax
    shr rdx, 3
    and eax, 7
    mov cl, al
    mov al, 1
    shl al, cl
    not al
    and [PMM_BITMAP+rdx], al
    pop rax
    pop rcx
    pop rdx
    ret

; mark range free: RAX=base phys, RDX=len bytes
pmm_mark_free_range:
    push rax
    push rcx
    shr rax, 12
    mov rcx, rdx
    shr rcx, 12
    test rcx, rcx
    jnz .go
    mov rcx, 1
.go:
.loop:
    test rcx, rcx
    jz .done
    push rax
    push rcx
    call pmm_bit_clear
    pop rcx
    pop rax
    inc rax
    dec rcx
    jmp .loop
.done:
    pop rcx
    pop rax
    ret

; mark range used: RAX=base, RDX=len
pmm_mark_used_range:
    push rax
    push rcx
    shr rax, 12
    mov rcx, rdx
    shr rcx, 12
    test rcx, rcx
    jnz .go
    mov rcx, 1
.go:
.loop:
    test rcx, rcx
    jz .done
    push rax
    push rcx
    call pmm_bit_set
    pop rcx
    pop rax
    inc rax
    dec rcx
    jmp .loop
.done:
    pop rcx
    pop rax
    ret

; alloc one 4KB page -> RAX (0 = OOM). First-fit byte scan.
pmm_alloc_page:
    push rcx
    push rdx
    push rsi
    xor eax, eax                           ; byte index
.scan:
    cmp eax, PMM_BITMAP_SZ
    jae .oom
    mov dl, [PMM_BITMAP+rax]
    cmp dl, 0xFF
    je .next
    mov esi, eax
    xor ecx, ecx
.bit:
    test dl, 1
    jz .found
    shr dl, 1
    inc ecx
    cmp ecx, 8
    jb .bit
    jmp .next
.found:                                    ; page = byte*8 + bit
    mov eax, esi
    shl eax, 3
    add eax, ecx
    push rax
    call pmm_bit_set
    pop rax
    shl rax, 12
    pop rsi
    pop rdx
    pop rcx
    ret
.next:
    inc eax
    jmp .scan
.oom:
    xor eax, eax
    pop rsi
    pop rdx
    pop rcx
    ret

; kmalloc: bump allocator, 16-aligned. RCX=size -> RAX=ptr. No free in v0.1.
kmalloc:
    mov rax, [heap_end]
    add rax, 15
    and rax, -16                           ; 16-byte align
    lea rdx, [rax+rcx]
    mov [heap_end], rdx
    ret

; stats: RAX=free pages, RDX=total pages
pmm_stats:
    push rcx
    push rsi
    xor eax, eax
    xor esi, esi
.cnt:
    cmp esi, PMM_BITMAP_SZ
    jae .done
    movzx ecx, byte [PMM_BITMAP+rsi]
    xor ecx, 0xFF
    ; popcount byte in ECX via 4 shifts
    mov edx, ecx
    shr edx, 1
    and edx, 0x55
    sub ecx, edx
    mov edx, ecx
    shr edx, 2
    and edx, 0x33
    and ecx, 0x33
    add ecx, edx
    mov edx, ecx
    shr edx, 4
    add ecx, edx
    and ecx, 0x0F
    add eax, ecx
    inc esi
    jmp .cnt
.done:
    mov rdx, PMM_BITMAP_SZ*8
    pop rsi
    pop rcx
    ret

heap_end dq 0x200000
