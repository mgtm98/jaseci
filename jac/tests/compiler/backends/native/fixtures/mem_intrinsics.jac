"""Fixture for the raw-memory intrinsics (__peek_uN / __poke_uN).

Each function allocates C-heap memory, writes with __poke, reads back with
__peek, and returns a value the test asserts on. Covers all four widths,
zero-byte reads (the str-reinterpret regression: a NUL used to raise
"string index out of range"), unaligned offsets, and little-endian layout.
"""

import from "/usr/lib/x86_64-linux-gnu/libc.so.6" {
    def calloc(n: int, size: int) -> int;
    def free(p: int) -> None;
}

"""Round-trip one byte."""
def:pub rt_u8(v: int) -> int {
    p: int = calloc(1, 16);
    __poke_u8(p, v);
    r: int = __peek_u8(p);
    free(p);
    return r;
}

"""Round-trip a 16-bit value."""
def:pub rt_u16(v: int) -> int {
    p: int = calloc(1, 16);
    __poke_u16(p, v);
    r: int = __peek_u16(p);
    free(p);
    return r;
}

"""Round-trip a 32-bit value."""
def:pub rt_u32(v: int) -> int {
    p: int = calloc(1, 16);
    __poke_u32(p, v);
    r: int = __peek_u32(p);
    free(p);
    return r;
}

"""Round-trip a 64-bit value (signed i64 bit pattern preserved)."""
def:pub rt_u64(v: int) -> int {
    p: int = calloc(1, 16);
    __poke_u64(p, v);
    r: int = __peek_u64(p);
    free(p);
    return r;
}

"""Read a zeroed byte: must return 0, not raise (the #8207 regression)."""
def:pub read_nul() -> int {
    p: int = calloc(1, 16);
    r: int = __peek_u8(p);
    free(p);
    return r;
}

"""Walk a buffer THROUGH interior NUL bytes and sum every byte.
Layout: [7, 0, 0, 5] -> 12. The old str-reinterpret idiom raised at index 1."""
def:pub walk_past_nul() -> int {
    p: int = calloc(1, 16);
    __poke_u8(p, 7);
    __poke_u8(p + 3, 5);
    total: int = 0;
    i: int = 0;
    while i < 4 {
        total = total + __peek_u8(p + i);
        i = i + 1;
    }
    free(p);
    return total;
}

"""Store/load a u32 at an odd (unaligned) offset."""
def:pub unaligned_u32(v: int) -> int {
    p: int = calloc(1, 16);
    __poke_u32(p + 3, v);
    r: int = __peek_u32(p + 3);
    free(p);
    return r;
}

"""Little-endian layout: poke_u32(0x01020304) -> bytes 04 03 02 01."""
def:pub endian_bytes() -> int {
    p: int = calloc(1, 16);
    __poke_u32(p, 16909060);  # 0x01020304
    b0: int = __peek_u8(p);      # 4
    b1: int = __peek_u8(p + 1);  # 3
    b2: int = __peek_u8(p + 2);  # 2
    b3: int = __peek_u8(p + 3);  # 1
    free(p);
    return b0 * 1000 + b1 * 100 + b2 * 10 + b3;  # 4321
}

"""Narrow poke truncates: __poke_u8 of 0x1FF stores 0xFF only."""
def:pub poke_truncates() -> int {
    p: int = calloc(1, 16);
    __poke_u8(p, 511);           # 0x1FF -> stores 0xFF
    r: int = __peek_u16(p);      # byte 1 is still 0 -> 255, not 511
    free(p);
    return r;
}
