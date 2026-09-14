; NovaOS kernel/mouse.asm - PS/2 mouse driver (IRQ12, 3-byte packets)
; Exports mouse_x/y/buttons + mouse_get_state. Clamps to framebuffer size.

; ---- bounded PS/2 helpers (never hang: AL=0 ok, 1 timeout) ----
; wait for input-buffer empty (bit1=0)
ps2_wait_ibf:
    push rcx
    push rdx
    mov ecx, 100000
    mov dx, 0x64
.poll:
    in al, dx
    test al, 2
    jz .ok
    dec ecx
    jnz .poll
    mov al, 1
    pop rdx
    pop rcx
    ret
.ok:
    xor eax, eax
    pop rdx
    pop rcx
    ret

; wait for output-buffer full (bit0=1)
ps2_wait_obf:
    push rcx
    push rdx
    mov ecx, 100000
    mov dx, 0x64
.poll:
    in al, dx
    test al, 1
    jnz .ok
    dec ecx
    jnz .poll
    mov al, 1
    pop rdx
    pop rcx
    ret
.ok:
    xor eax, eax
    pop rdx
    pop rcx
    ret

mouse_init:
    push rax
    push rbx
    mov dword [mouse_x], 400
    mov dword [mouse_y], 300
    mov byte [mouse_buttons], 0
    mov byte [mouse_phase], 0
    mov byte [mouse_present], 0
    ; enable aux device
    call ps2_wait_ibf
    test al, al
    jnz .done
    mov al, 0xA8
    out 0x64, al
    ; read config byte
    call ps2_wait_ibf
    test al, al
    jnz .done
    mov al, 0x20
    out 0x64, al
    call ps2_wait_obf
    test al, al
    jnz .done
    in al, 0x60
    mov bl, al
    or bl, 0x02                            ; enable IRQ12
    and bl, 0xDF                           ; enable aux clock
    call ps2_wait_ibf
    test al, al
    jnz .done
    mov al, 0x60
    out 0x64, al
    call ps2_wait_ibf
    test al, al
    jnz .done
    mov al, bl
    out 0x60, al
    ; set defaults + enable data reporting (best-effort)
    mov al, 0xF6
    call mouse_write
    call mouse_wait_ack
    mov al, 0xF4
    call mouse_write
    call mouse_wait_ack
    mov byte [mouse_present], 1
.done:
    pop rbx
    pop rax
    ret
mouse_present db 0

; wait for 0xFA ACK with timeout
mouse_wait_ack:
    push rcx
    mov ecx, 100000
.poll:
    in al, 0x64
    test al, 1
    jz .next
    in al, 0x60
    cmp al, 0xFA
    je .ok
.next:
    dec ecx
    jnz .poll
.ok:
    pop rcx
    ret

; send AL to mouse (via 0xD4 prefix), bounded. Preserves RBX.
mouse_write:
    push rbx
    mov bl, al
    call ps2_wait_ibf
    test al, al
    jnz .timeout
    mov al, 0xD4
    out 0x64, al
    call ps2_wait_ibf
    test al, al
    jnz .timeout
    mov al, bl
    out 0x60, al
    xor eax, eax
    pop rbx
    ret
.timeout:
    mov al, 1
    pop rbx
    ret

; IRQ12 handler: assemble 3-byte packet
mouse_irq_handler:
    push rax
    push rbx
    push rcx
    in al, 0x60
    mov bl, [mouse_phase]
    cmp bl, 0
    je .b0
    cmp bl, 1
    je .b1
    ; byte 2 (dy)
    movsx eax, al
    mov ecx, [mouse_pkt+0]
    test cl, 0x20                          ; Y overflow? drop
    jnz .reset
    sub [mouse_y], eax                     ; screen Y down, mouse Y up
    jmp .buttons
.b0:
    test al, 0x08                          ; bit3 must be 1 (sync)
    jz .reset
    mov [mouse_pkt+0], al
    mov byte [mouse_phase], 1
    jmp .done
.b1:
    mov [mouse_pkt+1], al
    mov byte [mouse_phase], 2
    movsx eax, al
    mov ecx, [mouse_pkt+0]
    test cl, 0x40                          ; X overflow? drop
    jnz .reset
    test cl, 0x10
    jz .posx
    sub eax, 256
.posx:
    add [mouse_x], eax
    jmp .done
.buttons:
    mov al, [mouse_pkt+0]
    and al, 0x07
    mov [mouse_buttons], al
    mov byte [mouse_phase], 0
    call mouse_clamp
    jmp .done
.reset:
    mov byte [mouse_phase], 0
.done:
    pop rcx
    pop rbx
    pop rax
    ret

mouse_clamp:
    push rax
    mov eax, [mouse_x]
    cmp eax, 0
    jge .xhi
    mov dword [mouse_x], 0
    jmp .y
.xhi:
    mov ecx, [fb_width_var]
    test ecx, ecx
    jz .y
    dec ecx
    cmp eax, ecx
    jle .y
    mov [mouse_x], ecx
.y:
    mov eax, [mouse_y]
    cmp eax, 0
    jge .yhi
    mov dword [mouse_y], 0
    jmp .out
.yhi:
    mov ecx, [fb_height_var]
    test ecx, ecx
    jz .out
    dec ecx
    cmp eax, ecx
    jle .out
    mov [mouse_y], ecx
.out:
    pop rax
    ret

; state -> RAX=x RBX=y RCX=buttons
mouse_get_state:
    mov eax, [mouse_x]
    mov ebx, [mouse_y]
    movzx ecx, byte [mouse_buttons]
    ret

mouse_x dd 400
mouse_y dd 300
mouse_buttons db 0
mouse_phase db 0
mouse_pkt times 3 db 0
; fb dims mirrored by fb_init (avoids cross-file extern issues)
fb_width_var dd 1024
fb_height_var dd 768
