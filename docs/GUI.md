# NovaOS GUI (GUI.md)

Framebuffer desktop: wallpaper gradient, draggable windows, taskbar +
start menu, arrow cursor, and four windowed apps. Files: `kernel/fb.asm`
(primitives), `kernel/wm.asm` (window manager), `kernel/gui.asm`
(compositor loop), `kernel/font.inc` (8×16 font), `apps/*.asm`.

## Framebuffer abstraction

Works with both VBE (BIOS) and GOP (UEFI) via BootInfo fields only:
32bpp fast path + 24bpp byte path, pitch-aware. Primitives: pixel,
filled rect, Bresenham line, blit, char/text with transparent background
support, scroll, clear.

## Window manager (`wm.asm`)

Up to 8 windows, 64-byte structs: x/y/w/h, flags
(visible/focused/minimized/closed), title pointer, content id.
Title-bar drag, focus-on-click, close `[X]` and minimize `[_]` buttons
(right 20px zones of the 20px title bar). `wm_draw_all` paints frames +
dispatches content painters by id (1 terminal, 2 file manager, 3 editor,
4 monitor).

## Desktop (`gui.asm`)

`gui_init` opens Terminal, File Manager, System Monitor. `gui_loop`:
pastes wallpaper → windows → taskbar → start menu → cursor at ~30fps
(PIT wait), polling keyboard/mouse. Keys: `ESC` start menu, `t` new
terminal, `e` new editor, F8/Ctrl+Alt+T → shell. Clicking the start
button toggles the menu. Settings theme colors live in `theme_*`
(`settings_toggle_theme` flips light/dark).

## Apps (`apps/`)

* `terminal.asm` — scrollback buffer + prompt, painted in-window.
* `fileman.asm` — read-only FAT12/32 root listing (`fat_ls_stub` reads
  ATA or shows demo entries); also feeds shell `ls`.
* `editor.asm` — 12-line text buffer paint; System Monitor paint
  (uptime/RAM hooks); light/dark theme toggle.

## Syscalls for apps (`int 0x80`)

eax: 0 yield, 1 alloc, 2 plot pixel, 3 getkey, 4 getmouse, 5 print.
Apps run cooperatively inside the kernel (no processes yet — v0.4 idea).

## Verified

QEMU BIOS (1280×1024×24 VBE) and UEFI/OVMF (GOP 32bpp): VRAM dumps show
wallpaper, three windows with title bars/text, and taskbar. Mouse cursor
renders; keyboard input verified via serial-echoed shell session.
