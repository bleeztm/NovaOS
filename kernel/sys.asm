; NovaOS kernel/sys.asm - COM1 serial, PIT timer, RTC, PC speaker, power
; All port I/O. Called from entry.asm; tick counter drives uptime + APIC fallback.

COM1 equ 0x3F8

; ---- serial ----
serial_init:
    push rax
    push rdx
    mov dx, COM1+1
    xor al, al
    out dx, al      ; disable ints
    mov dx, COM1+3
    mov al, 0x80
    out dx, al    ; DLAB
    mov dx, COM1+0
    mov al, 0x03
    out dx, al    ; 38400 (115200/3)
    mov dx, COM1+1
    xor al, al
    out dx, al
    mov dx, COM1+3
    mov al, 0x03
    out dx, al    ; 8N1
    mov dx, COM1+2
    mov al, 0xC7
    out dx, al    ; FIFO on
    pop rdx
    pop rax
    ret

serial_putc: ; AL=char
    push rbx
    push rdx
    mov bl, al                             ; stash char (port read clobbers AL)
    mov dx, COM1+5
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    mov al, bl
    mov dx, COM1+0
    out dx, al
    pop rdx
    pop rbx
    ret

serial_puts: ; RSI=cstr
    push rax
.loop:
    lodsb
    test al, al
    jz .done
    call serial_putc
    jmp .loop
.done:
    pop rax
    ret

; debug aid for faults: prints fixed note (full regs dump = TODO)
serial_puts_hexdump_note:
    push rsi
    lea rsi, [rel str_faultnote]
    call serial_puts
    pop rsi
    ret
str_faultnote db "[FAULT] (regs TODO)", 10, 0

; print RAX decimal to serial (64-bit div; quotient always fits — no #DE possible)
serial_print_dec64:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    mov rbx, 10
    lea rsi, [rel dec64_buf+23]
    mov byte [rsi], 0
    test rax, rax
    jnz .divloop
    dec rsi
    mov byte [rsi], '0'
    jmp .print
.divloop:
    xor edx, edx
    div rbx                                ; RDX:RAX / 10 -> RAX=q RDX=rem
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .divloop
.print:
    call serial_puts
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret
dec64_buf times 24 db 0

; print AL as 2 hex digits to serial
serial_print_hex_byte:
    push rax
    push rcx
    mov cl, al
    shr al, 4
    call .nib
    mov al, cl
    and al, 0xF
    call .nib
    pop rcx
    pop rax
    ret
.nib:
    add al, '0'
    cmp al, '9'
    jbe .ch
    add al, 7
.ch:
    call serial_putc
    ret

; print RAX as 16 hex digits to serial
serial_print_hex64:
    push rax
    push rcx
    push rdx
    mov rcx, 60
.nib:
    mov rdx, rax
    shr rdx, cl
    and dl, 0xF
    cmp dl, 10
    jb .digit
    add dl, 'A'-10
    jmp .out
.digit:
    add dl, '0'
.out:
    mov al, dl
    call serial_putc
    sub rcx, 4
    jns .nib
    pop rdx
    pop rcx
    pop rax
    ret

; ---- PIT ----
pit_tick:                                  ; IRQ0 handler: count ticks (100Hz)
    inc qword [pit_ticks]
    ret
pit_ticks dq 0

pit_init:
    push rax
    mov al, 0x36                           ; ch0, lo/hi, square wave
    out 0x43, al
    mov al, 11932 & 0xFF                   ; 1193182/100Hz = 11931
    out 0x40, al
    mov al, 11932 >> 8
    out 0x40, al
    pop rax
    ret

; uptime seconds -> RAX
uptime_seconds:
    mov rax, [pit_ticks]
    xor edx, edx
    mov ecx, 100
    div rcx
    ret

; ---- RTC (CMOS) ----
rtc_read: ; -> RAX=HHMMSS packed BCD (DH=h DL=m CL=s style: RAX = h<<16|m<<8|s)
    push rbx
    cli
.wait_update:
    mov al, 0x0A
    out 0x70, al
    in al, 0x71
    test al, 0x80
    jnz .wait_update
    mov al, 0x00
    out 0x70, al
    in al, 0x71
    mov bl, al   ; seconds
    mov al, 0x02
    out 0x70, al
    in al, 0x71
    mov bh, al   ; minutes
    mov al, 0x04
    out 0x70, al
    in al, 0x71               ; hours in AL
    movzx eax, al
    shl eax, 16
    movzx ebx, bx
    or eax, ebx
    sti
    pop rbx
    ret

; ---- PC speaker ----
speaker_beep: ; RAX=freq Hz (0=off)
    push rax
    push rbx
    push rcx
    test rax, rax
    jz .off
    mov rbx, rax
    mov rax, 1193182
    xor edx, edx
    div rbx                                ; AX = divisor
    mov cx, ax
    mov al, 0xB6
    out 0x43, al            ; ch2, square
    mov al, cl
    out 0x42, al
    mov al, ch
    out 0x42, al
    in al, 0x61
    or al, 3
    out 0x61, al
    pop rcx
    pop rbx
    pop rax
    ret
.off:
    in al, 0x61
    and al, ~3
    out 0x61, al
    pop rcx
    pop rbx
    pop rax
    ret

; ---- power ----
; reboot via 8042, fallback triple fault
sys_reboot:
    cli
.waitkbd:
    in al, 0x64
    test al, 2
    jnz .waitkbd
    mov al, 0xFE
    out 0x64, al
    ; fallback: triple fault
    lidt [rel bad_idt]
    int 3
    hlt
    jmp sys_reboot
bad_idt: dw 0
    dq 0

; shutdown: QEMU isa-debug-exit (0x604) + Bochs (0xB004) + ACPI SLP_TC guess
sys_shutdown:
    cli
    mov dx, 0x604
    mov ax, 0x2000
    out dx, ax                             ; QEMU isa-debug-exit / default ACPI
    mov ax, 0x2000
    mov dx, 0xB004
    out dx, ax                             ; Bochs
    mov rsi, str_shutdown_halt
    call serial_puts
    hlt
    jmp sys_shutdown
str_shutdown_halt db "System halted - you can now power off", 10, 0
