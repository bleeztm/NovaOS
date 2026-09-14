; NovaOS kernel/entry.asm - 64-bit kernel entry (flat binary at 0x100000)
; Build: nasm -f bin kernel/entry.asm -o build/KERNEL.BIN
; Entry: kernel_entry(BootInfo* in RDI) — called by stage2 (BIOS) and BOOTX64 (UEFI).
[BITS 64]
[ORG 0x100000]
[DEFAULT ABS]
%include "include/bootinfo.inc"

kernel_entry:
    cli
    cld
    mov rsp, kernel_stack_top
    mov rbp, rsp
    push rdi                                ; save BootInfo*
    ; Copy BootInfo (80B) out of low RAM into kernel .bss ASAP via byte
    ; moves. Rationale: firmware/BIOS data areas overlap low RAM and
    ; 64-bit loads from 0x9000 observed returning stale low bytes on QEMU.
    pop rax
    mov [bootinfo_ptr], rax
    mov rsi, rax                            ; src = original BootInfo
    lea rdi, [rel bootinfo_copy]            ; dst = kernel copy
    mov ecx, BI_SIZE
    rep movsb
    lea rax, [rel bootinfo_copy]
    mov [bootinfo_ptr], rax
    mov rdi, rax

    call serial_init
    lea rsi, [rel kmsg_boot]
    call serial_puts

    call gdt_install
    lea rsi, [rel kmsg_gdt]
    call serial_puts

    call idt_install
    lea rsi, [rel kmsg_idt]
    call serial_puts

    mov rdi, [bootinfo_ptr]
    call pmm_init
    lea rsi, [rel kmsg_mm]
    call serial_puts

    mov rdi, [bootinfo_ptr]
    call fb_init                            ; AL=1 graphics, 0=headless
    mov [gfx_ok], al
    push rax
    push rsi
    ; compact framebuffer mode line: "FB <w>x<h>x<bpp> @<addr>"
    lea rsi, [rel kmsg_fb]
    call serial_puts
    mov rdi, [bootinfo_ptr]
    mov eax, [rdi+16]
    call serial_print_dec64
    mov al, 'x'
    call serial_putc
    mov rdi, [bootinfo_ptr]
    mov eax, [rdi+20]
    call serial_print_dec64
    mov al, 'x'
    call serial_putc
    mov rdi, [bootinfo_ptr]
    mov eax, [rdi+28]
    call serial_print_dec64
    lea rsi, [rel kmsg_fbat]
    call serial_puts
    mov rax, [fb_addr]                          ; byte-assembled by fb_init
    call serial_print_hex64
    mov al, 10
    call serial_putc
    pop rsi
    pop rax

    lea rsi, [rel kmsg_1]
    call serial_puts
    call pit_init
    lea rsi, [rel kmsg_2]
    call serial_puts
    call kbd_init
    lea rsi, [rel kmsg_3]
    call serial_puts
    call mouse_init
    lea rsi, [rel kmsg_4]
    call serial_puts
    call ata_init
    lea rsi, [rel kmsg_drv]
    call serial_puts

    sti
    mov al, 0
    call speaker_beep                       ; ensure speaker off (documented POST beep below)
    mov rax, 880
    ; (short POST beep commented out for QEMU-audio-less CI; enable on HW)
    ; call speaker_beep

    ; F8 pressed during boot? -> straight to shell
    cmp byte [kbd_f8_flag], 0
    jne .shell
    cmp byte [gfx_ok], 0
    je .shell                                ; no framebuffer -> VGA shell
    call gui_init
    test al, al
    jz .shell
    lea rsi, [rel kmsg_gui]
    call serial_puts
    call gui_loop                            ; returns only via shell->gui-restart loop inside
    jmp .halt
.shell:
    lea rsi, [rel kmsg_shell]
    call serial_puts
    call shell_main                          ; 'gui-restart' returns here
    cmp byte [gfx_ok], 0
    je .shell
    call gui_init
    call gui_loop
.halt:
    cli
    hlt
    jmp .halt

kmsg_boot  db "NovaOS kernel v0.1 booting",10,0
kmsg_fb    db "FB ",0
kmsg_fbat  db " @",0
kmsg_gdt   db "[OK] GDT",10,0
kmsg_idt   db "[OK] IDT+PIC",10,0
kmsg_mm    db "[OK] PMM",10,0
kmsg_1     db "[..] fb ok, init PIT",10,0
kmsg_2     db "[..] PIT ok, init KBD",10,0
kmsg_3     db "[..] KBD ok, init MOUSE",10,0
kmsg_4     db "[..] MOUSE ok, init ATA",10,0
kmsg_drv   db "[OK] PIT/KBD/MOUSE/ATA/RTC",10,0
kmsg_gui   db "[OK] GUI starting",10,0
kmsg_shell db "[!] Emergency shell",10,0
bootinfo_ptr dq 0
gfx_ok db 0
ALIGN 8
bootinfo_copy times BI_SIZE db 0

; ---- modules (single-binary link via includes) ----
%include "kernel/gdt.asm"
%include "kernel/idt.asm"
%include "kernel/mm.asm"
%include "kernel/sys.asm"
%include "kernel/fb.asm"
%include "kernel/kbd.asm"
%include "kernel/mouse.asm"
%include "kernel/ata.asm"
%include "kernel/wm.asm"
%include "kernel/gui.asm"
%include "kernel/shell.asm"
%include "apps/terminal.asm"
%include "apps/fileman.asm"
%include "apps/editor.asm"

; ---- 16KB boot stack ----
ALIGN 16
kernel_stack_bottom:
times 16384 db 0
kernel_stack_top:
