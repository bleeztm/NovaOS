#!/usr/bin/env python3
"""NovaOS image builder - pure Python, no mtools needed.
Builds:
  floppy.img : 1.44MB FAT12 (rsvd=17: MBR + 16 raw stage2 sectors, then FATs)
  esp.img    : 33MB FAT32 ESP (BOOTX64.EFI + KERNEL.BIN)
Usage:
  mkimg.py floppy  build/mbr.bin build/stage2.bin build/KERNEL.BIN build/floppy.img
  mkimg.py esp     build/BOOTX64.EFI build/KERNEL.BIN build/esp.img
"""
import struct, sys, os

def fat12_floppy(mbr, stage2, kernel, out):
    SECT = 512
    NSECT = 2880
    img = bytearray(NSECT * SECT)
    assert len(mbr) == 512, f"mbr must be 512 bytes, got {len(mbr)}"
    assert mbr[510] == 0x55 and mbr[511] == 0xAA, "mbr missing 0xAA55"
    assert len(stage2) <= 16 * SECT, f"stage2 too big ({len(stage2)} > 8192)"
    img[0:512] = mbr
    img[512:512 + len(stage2)] = stage2
    RSVD, NFAT, FATSEC, ROOTSEC = 17, 2, 9, 14
    ROOT_LBA = RSVD + NFAT * FATSEC            # 35
    DATA_LBA = ROOT_LBA + ROOTSEC              # 49
    SPC = 1                                    # sectors per cluster
    # --- FATs: media F0, cluster chain for kernel starting at 2 ---
    ncl = (len(kernel) + SECT - 1) // SECT
    assert ncl >= 1 and 2 + ncl < 0xFF6, "kernel too big for FAT12 floppy"
    fat = bytearray(FATSEC * SECT)
    fat[0], fat[1], fat[2] = 0xF0, 0xFF, 0xFF
    def set12(cl, val):
        o = cl + cl // 2
        if cl & 1:
            fat[o] = (fat[o] & 0x0F) | ((val & 0x0F) << 4)
            fat[o + 1] = (val >> 4) & 0xFF
        else:
            fat[o] = val & 0xFF
            fat[o + 1] = (fat[o + 1] & 0xF0) | ((val >> 8) & 0x0F)
    for c in range(2, 2 + ncl - 1):
        set12(c, c + 1)
    set12(2 + ncl - 1, 0xFFF)
    for i in range(NFAT):
        o = (RSVD + i * FATSEC) * SECT
        img[o:o + len(fat)] = fat
    # --- root dir: KERNEL.BIN entry ---
    root = bytearray(ROOTSEC * SECT)
    e = struct.pack("<11sBBBHHHHHHHI", b"KERNEL  BIN", 0x20, 0, 0,
                    0, 0, 0, 0, 0, 0, 2, len(kernel))
    root[0:32] = e
    o = ROOT_LBA * SECT
    img[o:o + len(root)] = root
    # --- data ---
    o = DATA_LBA * SECT
    img[o:o + len(kernel)] = kernel
    # fix BPB total sectors just in case
    struct.pack_into("<H", img, 19, NSECT)
    with open(out, "wb") as f:
        f.write(img)
    print(f"floppy: kernel {len(kernel)}B in {ncl} clusters -> {out}")

def fat32_esp(efi, kernel, out):
    SECT = 512
    # 64MB disk: 131072 sectors. Layout: MBR + partition 1 (type 0xEF ESP)
    # starting at LBA 2048; FAT32 lives inside the partition.
    # NOTE: >=65525 clusters required, else EDK2 treats the volume as FAT16
    # and rejects the FAT32 BPB. (126944 clusters with the geometry below.)
    NSECT = 131072
    PART_OFF = 2048
    RSVD, NFAT, FATSEC, SPC = 32, 2, 1024, 1
    img = bytearray(NSECT * SECT)
    # --- MBR partition table: one bootable ESP partition ---
    pentry = struct.pack("<B3sB3sII", 0x80, b"\x20\x21\x00", 0xEF,
                         b"\xFF\xFF\xFF", PART_OFF, NSECT - PART_OFF)
    img[446:462] = pentry
    img[510], img[511] = 0x55, 0xAA
    base = PART_OFF * SECT                       # FAT32 base byte offset
    def w(off, data):
        img[base + off:base + off + len(data)] = data
    # --- boot sector (FAT32 BPB layout) ---
    bs = bytearray(SECT)
    bs[0:3] = b"\xEB\x58\x90"
    bs[3:11] = b"NOVAOS  "
    struct.pack_into("<H", bs, 11, SECT)   # BytesPerSec
    bs[13] = SPC                           # SecPerClus
    struct.pack_into("<H", bs, 14, RSVD)   # RsvdSecCnt
    bs[16] = NFAT                          # NumFATs
    struct.pack_into("<H", bs, 17, 0)      # RootEntCnt (0 for FAT32)
    struct.pack_into("<H", bs, 19, 0)      # TotSec16 (0 -> use TotSec32)
    bs[21] = 0xF8                          # Media
    struct.pack_into("<H", bs, 22, 0)      # FATSz16 (0 for FAT32)
    struct.pack_into("<H", bs, 24, 32)     # SecPerTrk
    struct.pack_into("<H", bs, 26, 64)     # NumHeads
    struct.pack_into("<I", bs, 28, PART_OFF)  # HiddSec
    struct.pack_into("<I", bs, 32, NSECT - PART_OFF)  # TotSec32 (partition size)
    struct.pack_into("<I", bs, 36, FATSEC) # FATSz32
    struct.pack_into("<H", bs, 40, 0)      # ExtFlags
    struct.pack_into("<H", bs, 42, 0)      # FSVer
    struct.pack_into("<I", bs, 44, 2)      # RootClus
    struct.pack_into("<H", bs, 48, 1)      # FSInfo
    struct.pack_into("<H", bs, 50, 6)      # BkBootSec
    bs[64] = 0x80
    bs[66] = 0x29
    struct.pack_into("<I", bs, 67, 0x4E4F5641)
    bs[71:82] = b"NOVAOS ESP "
    bs[82:90] = b"FAT32   "
    bs[510], bs[511] = 0x55, 0xAA
    w(0, bs)
    w(6 * SECT, bs)                           # backup boot sector
    # --- FSInfo ---
    fs = bytearray(SECT)
    struct.pack_into("<I", fs, 0, 0x41615252)
    struct.pack_into("<I", fs, 484, 0x61417272)
    struct.pack_into("<I", fs, 488, 0xFFFFFFFF)
    struct.pack_into("<I", fs, 492, 0x00000003)
    struct.pack_into("<H", fs, 510, 0xAA55)
    w(1 * SECT, fs)
    # --- FATs (offsets relative to partition start) ---
    def fat_off(n):
        return base + (RSVD + n * FATSEC) * SECT
    for n in range(NFAT):
        o = fat_off(n)
        struct.pack_into("<III", img, o, 0x0FFFFFF8, 0x0FFFFFFF, 0x0FFFFFFF)
    # data area starts at cluster 2 (partition-relative LBA)
    data_lba = RSVD + NFAT * FATSEC
    part_data = PART_OFF + data_lba            # absolute LBA of cluster 2
    # UEFI shell auto-run script (diagnostics + chainload)
    nsh = (b"echo NovaOS ESP contents:\r\nls fs0:\\EFI\\BOOT\\\r\n"
           b"echo Booting NovaOS...\r\nfs0:\\EFI\\BOOT\\BOOTX64.EFI\r\n")
    files = [(b"EFI", True, 0), (b"BOOT", True, 0),
             (b"BOOTX64 EFI", False, efi), (b"KERNEL  BIN", False, kernel),
             (b"STARTUP NSH", False, nsh)]
    # allocate: cluster 2 = root, 3 = EFI, 4 = BOOT, then file chains
    nxt = 3
    alloc = {}
    for name, isdir, data in files:
        if isdir:
            alloc[name] = (nxt, [])
            nxt += 1
        else:
            n = max(1, (len(data) + SECT - 1) // SECT)
            alloc[name] = (nxt, data)
            nxt += n
    def set32(cl, v):
        for n in range(NFAT):
            struct.pack_into("<I", img, fat_off(n) + cl * 4, v)
    # root dir cluster 2: entries EFI + volume label-ish
    def dirent(name11, attr, cl, size):
        return struct.pack("<11sBBBHHHHHHHI", name11, attr, 0, 0,
                           0, 0, 0, 0, 0, 0, cl, size)
    root = bytearray()
    root += dirent(b"EFI        ", 0x10, alloc[b"EFI"][0], 0)
    efi_cl = alloc[b"EFI"][0]
    boot_cl = alloc[b"BOOT"][0]
    efi_dir = dirent(b".          ", 0x10, efi_cl, 0)
    efi_dir += dirent(b"..         ", 0x10, 2, 0)
    efi_dir += dirent(b"BOOT       ", 0x10, boot_cl, 0)
    boot_dir = dirent(b".          ", 0x10, boot_cl, 0)
    boot_dir += dirent(b"..         ", 0x10, efi_cl, 0)
    for name, isdir, data in files:
        if isdir or name in (b"EFI", b"BOOT"):
            continue
        cl, blob = alloc[name]
        n = max(1, (len(blob) + SECT - 1) // SECT)
        for i in range(n - 1):
            set32(cl + i, cl + i + 1)
        set32(cl + n - 1, 0x0FFFFFFF)
        # write data (absolute image offset)
        o = (part_data + (cl - 2) * SPC) * SECT
        img[o:o + len(blob)] = blob
        if name == b"BOOTX64 EFI":
            boot_dir += dirent(name, 0x20, cl, len(blob))
        else:
            # KERNEL.BIN in ESP root
            root += dirent(name, 0x20, cl, len(blob))
    set32(2, 0x0FFFFFFF)
    set32(efi_cl, 0x0FFFFFFF)
    set32(boot_cl, 0x0FFFFFFF)
    o = (part_data + (2 - 2)) * SECT
    img[o:o + len(root)] = root
    o = (part_data + (efi_cl - 2)) * SECT
    img[o:o + len(efi_dir)] = efi_dir
    o = (part_data + (boot_cl - 2)) * SECT
    img[o:o + len(boot_dir)] = boot_dir
    with open(out, "wb") as f:
        f.write(img)
    print(f"esp: efi {len(efi)}B + kernel {len(kernel)}B -> {out}")

if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "floppy":
        _, _, mbr, s2, kern, out = sys.argv
        fat12_floppy(open(mbr, "rb").read(), open(s2, "rb").read(),
                     open(kern, "rb").read(), out)
    elif mode == "esp":
        _, _, efi, kern, out = sys.argv
        fat32_esp(open(efi, "rb").read(), open(kern, "rb").read(), out)
    else:
        sys.exit("usage: mkimg.py [floppy|esp] ...")
