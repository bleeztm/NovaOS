# NovaOS Emergency Shell (SHELL.md)

Failsafe text console. Entered automatically when GUI init fails (no
framebuffer) or when the user presses **F8** / **Ctrl+Alt+T**; leave with
`gui-restart`. Implemented in `kernel/shell.asm`.

## Backends

* Framebuffer text console (8×16 font, cursor, wrap, scroll) when `fb_ok`.
* VGA text mode (`0xB8000`, 80×25, scroll) when headless.
* Every character is mirrored to COM1 serial (headless debugging).

## Commands

| Command | Effect |
|---------|--------|
| `help` | list commands |
| `clear` | clear screen |
| `info` | OS + version line |
| `mem` | free/tracked RAM bytes + heap end |
| `peek <hexaddr>` | dump 16 bytes |
| `poke <hexaddr> <hexbyte>` | write a byte |
| `ls` | list files (read-only FAT via ATA; demo entries without HDD) |
| `cat <file>` | viewer hook (see File Manager app) |
| `fbinfo` | framebuffer address + mode |
| `gui-restart` | return to the desktop |
| `reboot` / `shutdown` / `halt` | power control |

## Line editing

Echo, Backspace handling (erase), Enter executes. Input blocks on the
keyboard ring buffer (`hlt` idle).

## Notes / limits (v0.1)

* `ls` reads ATA primary-master LBA 0/19 best-effort; without an HDD
  image it shows built-in demo entries (documented in `apps/fileman.asm`).
* `peek`/`poke` access identity-mapped low memory only (first 64MB +
  framebuffer region); unmapped addresses fault to the panic stub.
* The shell shares `fb_draw_char`, which preserves RSI (string pointers)
  — a past bug here turned the prompt into garbage, see `fb.asm` note.
