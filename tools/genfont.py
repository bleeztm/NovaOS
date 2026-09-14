#!/usr/bin/env python3
"""NovaOS font tool - convert a PSF1/PSF2 (8x16) font into kernel/font.inc format.
Usage: genfont.py font.psf > font_rows.txt   (then paste into kernel/font.inc)

v0.1 ships a hand-tuned 8x16 font (kernel/font.inc). Use this script to
replace it with e.g. Lat2-Terminus16.psf for real hardware polish.
PSF1 layout: magic 0x0436, mode, charsize; glyphs follow (charsize bytes each).
"""
import struct, sys

def read_psf1(path):
    d = open(path, "rb").read()
    assert d[0] == 0x36 and d[1] == 0x04, "not PSF1"
    mode, charsize = d[2], d[3]
    n = 512 if mode & 1 else 256
    off = 4
    glyphs = [d[off + i * charsize:off + (i + 1) * charsize] for i in range(n)]
    return glyphs, charsize

if __name__ == "__main__":
    glyphs, cs = read_psf1(sys.argv[1])
    assert cs == 16, f"need 8x16 font, got charsize {cs}"
    for i in range(256):
        g = glyphs[i]
        print("db " + ",".join(f"0x{b:02X}" for b in g[:16]))
