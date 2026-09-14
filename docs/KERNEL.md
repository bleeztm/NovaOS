# NovaOS Kernel (KERNEL.md)

Pure NASM x86-64, single flat binary (`KERNEL.BIN` at `0x100000`).
All modules are `%include`d by `kernel/entry.asm` (no linker needed).

## Entry — `kernel/entry.asm`

`kernel_entry(BootInfo* in RDI)`: sets up a 16KB stack, copies the 80-byte
BootInfo into kernel `.bss` (`bootinfo_copy`, byte moves), then:

`serial_init` → `gdt_install` → `idt_install` → `pmm_init` →
`fb_init` → `pit_init`/`kbd_init`/`mouse_init`/`ata_init` → `sti` →
GUI (`gui_init`/`gui_loop`) or Emergency Shell (`shell_main`) when there
is no framebuffer or F8 was pressed. Serial log shows each stage.

## Core

* `gdt.asm` — flat 64-bit GDT (KCODE 0x08 / KDATA 0x10 + user slots),
  reloaded with a far return.
* `idt.asm` — 256-entry IDT, PIC remap (master `0x20`, slave `0x28`),
  CPU-fault stub (serial note + halt), IRQ wrappers (IRQ0 PIT, IRQ1
  keyboard, IRQ12 mouse) with PIC EOI, and `int 0x80` syscalls for GUI
  apps: 0 yield, 1 alloc(RBX=size→RAX), 2 plot(EBX,ECX,EDX),
  3 getkey(→RAX), 4 getmouse(→RAX/ RBX/RCX), 5 print(RBX=cstr).
* `mm.asm` — physical bitmap allocator (16KB bitmap at `0x150000`
  tracking 512MB in 4KB pages; first-fit `pmm_alloc_page`) fed by the
  BootInfo map, plus a 16-aligned bump `kmalloc` (no free in v0.1) and
  `pmm_stats` for System Monitor.
* `sys.asm` — COM1 serial (38400 8N1, debug lifeline), PIT 100Hz ticks +
  `uptime_seconds`, CMOS RTC read, PC-speaker beep, `sys_reboot` (8042,
  triple-fault fallback) and `sys_shutdown` (QEMU `0x604` / Bochs
  `0xB004` + halt message).

## Drivers

* `kbd.asm` — PS/2 Set-1, 256-byte ring buffer, Shift/Ctrl/Alt tracking,
  normal+shift ASCII maps, F8 flag and Ctrl+Alt+T hotkey flag.
* `mouse.asm` — PS/2 aux init with **bounded** waits (never hangs boot;
  `mouse_present` flag), 3-byte packets on IRQ12, screen clamping.
* `ata.asm` — ATA PIO LBA28 polling reads (primary master) for the
  read-only File Manager and shell `ls`.
* `fb.asm` — framebuffer driver over BootInfo (32bpp fast path + 24bpp),
  `put_pixel`/`fill_rect`/`draw_line` (Bresenham)/`blit`, 8×16 font text
  (`draw_char`, `print_string` with wrap+scroll), `fb_clear`, `fb_scroll`.

## Memory layout (physical)

| Region | Use |
|--------|-----|
| `0x5000`–`0x8FFF` | boot scratch (VBE/E820, BIOS path) |
| `0x9000` | BootInfo (copied to kernel `.bss` at entry) |
| `0x70000`–`0x73FFF` | page tables (PML4/PDPT/PD + fb PD) |
| `0x100000`+ | kernel image, 16KB stack, heap from `0x200000` |
| `0x150000` | PMM bitmap |
| `0xFD000000`+ etc. | framebuffer (mapped 1:1 via extra PD) |

## Paging

Stage2 maps identity 0..64MB (2MB pages) plus the 1GB region containing
the framebuffer. The kernel reuses these tables (higher-half alias
PML4[256] present for future use). Page faults land in `isr_fault`
(serial note + halt) — check serial output first when debugging.
