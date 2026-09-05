enum IntrinsicDispatch {
    RC_RUNTIME = "rc_runtime",
    FLOAT_BITS = "float_bits",
    BITS_FLOAT = "bits_float",
    MEM_PEEK = "mem_peek",
    MEM_POKE = "mem_poke",
    MEM_LOAD = "mem_load",
    MEM_STORE = "mem_store",
    ATOMIC_XCHG = "atomic_xchg",
    CALL_DTOR = "call_dtor"
}

obj IntrinsicEntry {
    has name: str,
        param_specs: list[str],
        result_spec: str,
        dispatch: IntrinsicDispatch,
        gc_mode_gate: str | None = None;

    def arity -> int {
        return len(self.param_specs);
    }
}

obj IntrinsicRegistry {
    has _entries: dict[str, IntrinsicEntry];

    def get(name: str) -> IntrinsicEntry | None {
        return self._entries.get(name, None);
    }

    def is_intrinsic(name: str) -> bool {
        return name in self._entries;
    }

    def names -> list[str] {
        return list(self._entries.keys());
    }

    def entries -> list[IntrinsicEntry] {
        return list(self._entries.values());
    }
}

glob INTRINSIC_REGISTRY = IntrinsicRegistry(
         _entries={
             "__rc_debug_enable": IntrinsicEntry(
                 name="__rc_debug_enable",
                 param_specs=[],
                 result_spec="none",
                 dispatch=IntrinsicDispatch.RC_RUNTIME
             ),
             "__rc_debug_disable": IntrinsicEntry(
                 name="__rc_debug_disable",
                 param_specs=[],
                 result_spec="none",
                 dispatch=IntrinsicDispatch.RC_RUNTIME
             ),
             "__rc_gc_disable": IntrinsicEntry(
                 name="__rc_gc_disable",
                 param_specs=[],
                 result_spec="none",
                 dispatch=IntrinsicDispatch.RC_RUNTIME
             ),
             "__rc_gc_enable": IntrinsicEntry(
                 name="__rc_gc_enable",
                 param_specs=[],
                 result_spec="none",
                 dispatch=IntrinsicDispatch.RC_RUNTIME
             ),
             "__rc_collect_cycles": IntrinsicEntry(
                 name="__rc_collect_cycles",
                 param_specs=[],
                 result_spec="none",
                 dispatch=IntrinsicDispatch.RC_RUNTIME,
                 gc_mode_gate="cycles"
             ),
             "__float_bits": IntrinsicEntry(
                 name="__float_bits",
                 param_specs=["f64"],
                 result_spec="i64",
                 dispatch=IntrinsicDispatch.FLOAT_BITS
             ),
             "__bits_float": IntrinsicEntry(
                 name="__bits_float",
                 param_specs=["i64"],
                 result_spec="f64",
                 dispatch=IntrinsicDispatch.BITS_FLOAT
             ),
             # Raw-memory loads/stores (native-only). __peek_uN(addr) reads an
             # unsigned N-bit little-endian value at the byte address; __poke_uN
             # (addr, val) writes one. No bounds or type checks — the escape
             # hatch for FFI buffer access that str-reinterpret casts used to
             # provide before string subscripts became length-checked (#8207).
             "__peek_u8": IntrinsicEntry(
                 name="__peek_u8",
                 param_specs=["i64"],
                 result_spec="i64",
                 dispatch=IntrinsicDispatch.MEM_PEEK
             ),
             "__peek_u16": IntrinsicEntry(
                 name="__peek_u16",
                 param_specs=["i64"],
                 result_spec="i64",
                 dispatch=IntrinsicDispatch.MEM_PEEK
             ),
             "__peek_u32": IntrinsicEntry(
                 name="__peek_u32",
                 param_specs=["i64"],
                 result_spec="i64",
                 dispatch=IntrinsicDispatch.MEM_PEEK
             ),
             "__peek_u64": IntrinsicEntry(
                 name="__peek_u64",
                 param_specs=["i64"],
                 result_spec="i64",
                 dispatch=IntrinsicDispatch.MEM_PEEK
             ),
             "__poke_u8": IntrinsicEntry(
                 name="__poke_u8",
                 param_specs=["i64", "i64"],
                 result_spec="none",
                 dispatch=IntrinsicDispatch.MEM_POKE
             ),
             "__poke_u16": IntrinsicEntry(
                 name="__poke_u16",
                 param_specs=["i64", "i64"],
                 result_spec="none",
                 dispatch=IntrinsicDispatch.MEM_POKE
             ),
             "__poke_u32": IntrinsicEntry(
                 name="__poke_u32",
                 param_specs=["i64", "i64"],
                 result_spec="none",
                 dispatch=IntrinsicDispatch.MEM_POKE
             ),
             "__poke_u64": IntrinsicEntry(
                 name="__poke_u64",
                 param_specs=["i64", "i64"],
                 result_spec="none",
                 dispatch=IntrinsicDispatch.MEM_POKE
             ),
             "__mem_load_i64": IntrinsicEntry(
                 name="__mem_load_i64",
                 param_specs=["i64"],
                 result_spec="i64",
                 dispatch=IntrinsicDispatch.MEM_LOAD
             ),
             "__mem_store_i64": IntrinsicEntry(
                 name="__mem_store_i64",
                 param_specs=["i64", "i64"],
                 result_spec="none",
                 dispatch=IntrinsicDispatch.MEM_STORE
             ),
             "__atomic_xchg_i64": IntrinsicEntry(
                 name="__atomic_xchg_i64",
                 param_specs=["i64", "i64"],
                 result_spec="i64",
                 dispatch=IntrinsicDispatch.ATOMIC_XCHG
             ),
             "__mem_call_dtor": IntrinsicEntry(
                 name="__mem_call_dtor",
                 param_specs=["i64", "i64"],
                 result_spec="none",
                 dispatch=IntrinsicDispatch.CALL_DTOR
             )
         }
     );
