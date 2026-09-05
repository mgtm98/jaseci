"""Tests for the raw-memory intrinsics (__peek_u8/u16/u32/u64, __poke_uN).

These are the sanctioned escape hatch for FFI buffer access: unchecked,
unaligned, little-endian loads/stores lowered to inttoptr + load/store
align 1. They replace the `s: str = ptr; ord(s[i])` reinterpret idiom,
which broke when string subscripts became length-checked (#8207): any
buffer byte at/past a NUL raised "string index out of range" — segfaulting
the first fully-native jac-bun engine binary in process_populate_env.
"""

import ctypes;
import from tests.support { compile_native, get_func }

test "peek/poke u8 round-trip" {
    (eng, _) = compile_native("mem_intrinsics.jac");
    f = get_func(eng, "rt_u8", ctypes.c_int64, ctypes.c_int64);
    assert f(0) == 0;
    assert f(171) == 171;
    assert f(255) == 255;
}

test "peek/poke u16 round-trip" {
    (eng, _) = compile_native("mem_intrinsics.jac");
    f = get_func(eng, "rt_u16", ctypes.c_int64, ctypes.c_int64);
    assert f(48879) == 48879;
    assert f(65535) == 65535;
}

test "peek/poke u32 round-trip" {
    (eng, _) = compile_native("mem_intrinsics.jac");
    f = get_func(eng, "rt_u32", ctypes.c_int64, ctypes.c_int64);
    assert f(3735928559) == 3735928559;
    assert f(4294967295) == 4294967295;
}

test "peek/poke u64 round-trip preserves i64 bit pattern" {
    (eng, _) = compile_native("mem_intrinsics.jac");
    f = get_func(eng, "rt_u64", ctypes.c_int64, ctypes.c_int64);
    assert f(81985529216486895) == 81985529216486895;
    assert f(-1) == -1;
    assert f(-9223372036854775808) == -9223372036854775808;
}

test "reading a zero byte returns 0 (no bounds raise)" {
    (eng, _) = compile_native("mem_intrinsics.jac");
    f = get_func(eng, "read_nul", ctypes.c_int64);
    assert f() == 0;
}

test "walking through interior NUL bytes works" {
    (eng, _) = compile_native("mem_intrinsics.jac");
    f = get_func(eng, "walk_past_nul", ctypes.c_int64);
    assert f() == 12;
}

test "unaligned u32 store/load" {
    (eng, _) = compile_native("mem_intrinsics.jac");
    f = get_func(eng, "unaligned_u32", ctypes.c_int64, ctypes.c_int64);
    assert f(3735928559) == 3735928559;
}

test "layout is little-endian" {
    (eng, _) = compile_native("mem_intrinsics.jac");
    f = get_func(eng, "endian_bytes", ctypes.c_int64);
    assert f() == 4321;
}

test "narrow poke truncates the value" {
    (eng, _) = compile_native("mem_intrinsics.jac");
    f = get_func(eng, "poke_truncates", ctypes.c_int64);
    assert f() == 255;
}
