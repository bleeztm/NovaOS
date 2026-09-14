; NovaOS kernel/idt.asm - IDT, PIC remap, ISR/IRQ stubs, int 0x80 syscalls
; Syscalls (int 0x80, eax): 0=yield 1=alloc(RBX=size->RAX=ptr) 2=putpixel(EBX,ECX,EDX=color)
;   3=getkey(->EAX key,0=none) 4=getmouse(->EAX=x,EBX=y,ECX=buttons) 5=print(RBX=str)
; Vectors: CPU 0-31, IRQ 32-47 (PIC), syscall 0x80.

%define IDT_ENTRIES 256

idt_install:
    push rax
    push rcx
    push rdi
    ; --- remap PIC: master 0x20, slave 0x28 ---
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    mov al, 0x00
    out 0x21, al
    out 0xA1, al  ; unmask all (timer/kbd/mouse)
    ; --- fill IDT ---
    lea rdi, [rel kidt]
    mov rcx, IDT_ENTRIES
    lea rax, [rel isr_default]
.build:
    mov rdx, rax
    mov word [rdi+0], dx
    mov word [rdi+2], 0x08
    mov byte [rdi+4], 0
    mov byte [rdi+5], 0x8E                 ; P,DPL0,interrupt gate
    shr rdx, 16
    mov word [rdi+6], dx
    shr rdx, 16
    mov dword [rdi+8], edx
    mov dword [rdi+12], 0
    add rdi, 16
    dec rcx
    jnz .build
    ; per-vector stubs
    call idt_set_all
    ; syscall gate DPL3
    lea rax, [rel isr_syscall]
    lea rdi, [rel kidt+0x80*16]
    mov rdx, rax
    mov word [rdi+0], dx
    mov word [rdi+2], 0x08
    mov byte [rdi+4], 0
    mov byte [rdi+5], 0xEE                 ; P,DPL3
    shr rdx, 16
    mov word [rdi+6], dx
    shr rdx, 16
    mov dword [rdi+8], edx
    mov dword [rdi+12], 0
    lidt [rel kidt_desc]
    pop rdi
    pop rcx
    pop rax
    ret

; install handler RAX for vector in RDI-index: idt_set(vector=RDI, handler=RAX)
idt_set:
    push rdx
    push rdi
    shl rdi, 4
    lea rdi, [kidt+rdi]
    mov rdx, rax
    mov word [rdi+0], dx
    mov word [rdi+2], 0x08
    mov byte [rdi+5], 0x8E
    shr rdx, 16
    mov word [rdi+6], dx
    shr rdx, 16
    mov dword [rdi+8], edx
    pop rdi
    pop rdx
    ret

idt_set_all:
    ; CPU exceptions -> isr_fault, IRQs -> irq handlers
    lea rax, [rel isr_fault] 
    mov rdi, 0 
    call idt_set
    lea rax, [rel isr_fault] 
    mov rdi, 13
    call idt_set  ; #GP example (same stub ok)
    lea rax, [rel irq0_wrap] 
    mov rdi, 32
    call idt_set
    lea rax, [rel irq1_wrap] 
    mov rdi, 33
    call idt_set
    lea rax, [rel irq12_wrap]
    mov rdi, 44
    call idt_set
    ret

; ---- generic fault: print vector (from stack) then halt ----
isr_fault:
    cli
    mov rsi, rsp
    call serial_puts_hexdump_note          ; tiny debug aid (defined in sys.asm)
    mov rsi, str_panic
    call serial_puts
.hang:
    hlt
    jmp .hang

isr_default:
    iretq

; ---- IRQ wrappers: save regs, call C-style handler, EOI, restore ----
%macro IRQ_WRAP 2
%1:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    call %2
    mov al, 0x20
    out 0xA0, al                           ; EOI slave (harmless for master-only)
    out 0x20, al                           ; EOI master
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    iretq
%endmacro
IRQ_WRAP irq0_wrap,  pit_tick
IRQ_WRAP irq1_wrap,  kbd_irq_handler
IRQ_WRAP irq12_wrap, mouse_irq_handler

; ---- int 0x80 syscall dispatcher ----
isr_syscall:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    cmp eax, 5
    ja .done
    jmp [.sys_jmp+rax*8]
.sys_jmp:
    dq .s_yield, .s_alloc, .s_plot, .s_key, .s_mouse, .s_print
.s_yield:
    hlt                                    ; cooperative yield (STI state preserved by caller)
    jmp .done
.s_alloc:                                  ; RBX=size -> RAX=ptr
    mov rcx, rbx                           ; RBX untouched by pushes
    call kmalloc                           ; RAX=result survives pops below
    jmp .done
.s_plot:                                   ; EBX=x ECX=y EDX=color
    mov r8d, ebx
    mov r9d, ecx
    mov esi, edx
    call fb_put_pixel_xy
    jmp .done
.s_key:                                    ; -> RAX=key (0=none)
    call kbd_get_key                       ; RAX survives pops
    jmp .done
.s_mouse:                                  ; -> RAX=x RBX=y RCX=buttons
    call mouse_get_state                   ; RAX=x RBX=y RCX=btns
    mov [rsp+0], rbx                       ; patch saved RBX slot
    mov [rsp+8], rcx                       ; patch saved RCX slot
    jmp .done                              ; RAX already = x
.s_print:                                  ; RBX=cstr
    mov rsi, rbx
    call fb_print_string
.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    iretq

str_panic db "[PANIC] CPU fault - system halted", 10, 0

ALIGN 16
kidt: times IDT_ENTRIES*16 db 0
kidt_desc:
    dw IDT_ENTRIES*16-1
    dq kidt
