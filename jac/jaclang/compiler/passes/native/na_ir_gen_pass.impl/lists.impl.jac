"""List type codegen and helper emission."""

"""Register __list_new_T: create an empty list with capacity 8."""
def register_new_method(
    pass_obj: NaIRGenPass,
    elem_type_name: str,
    elem_type: ir.Type,
    list_ptr_type: ir.Type
) -> ir.Function {
    i64 = ir.IntType(64);
    i32 = ir.IntType(32);
    i8_ptr = ir.IntType(8).as_pointer();
    gc_malloc = pass_obj._get_or_declare_extern("GC_malloc", i8_ptr, [i64]);

    new_fnty = ir.FunctionType(list_ptr_type, []);
    new_fn = ir.Function(
        pass_obj.llvm_module, new_fnty, name=f"__list_new_{elem_type_name}"
    );
    new_fn.linkage = "private";
    bb = new_fn.append_basic_block("entry");
    b = ir.IRBuilder(bb);

    # Allocate list struct
    null_ptr = ir.Constant(list_ptr_type, None);
    size_gep = b.gep(null_ptr, [ir.Constant(i32, 1)], name="sizeof");
    struct_size = b.ptrtoint(size_gep, i64, name="size");
    raw = b.call(gc_malloc, [struct_size], name="raw");
    list_ptr = b.bitcast(raw, list_ptr_type, name="list");

    # len = 0
    len_p = b.gep(list_ptr, [ir.Constant(i32, 0), ir.Constant(i32, 0)], name="len.ptr");
    b.store(ir.Constant(i64, 0), len_p);

    # cap = 8
    cap_p = b.gep(list_ptr, [ir.Constant(i32, 0), ir.Constant(i32, 1)], name="cap.ptr");
    b.store(ir.Constant(i64, 8), cap_p);

    # Allocate data: 8 * sizeof(elem)
    elem_null = ir.Constant(elem_type.as_pointer(), None);
    elem_gep = b.gep(elem_null, [ir.Constant(i32, 1)], name="elem.sizeof");
    elem_size = b.ptrtoint(elem_gep, i64, name="elem.size");
    data_bytes = b.mul(ir.Constant(i64, 8), elem_size, name="data.bytes");
    data_raw = b.call(gc_malloc, [data_bytes], name="data.raw");
    data = b.bitcast(data_raw, elem_type.as_pointer(), name="data");
    data_p = b.gep(
        list_ptr, [ir.Constant(i32, 0), ir.Constant(i32, 2)], name="data.ptr"
    );
    b.store(data, data_p);
    b.ret(list_ptr);

    return new_fn;
}

"""Register __list_append_T: append an element, growing if needed."""
def register_append_method(
    pass_obj: NaIRGenPass,
    elem_type_name: str,
    elem_type: ir.Type,
    list_ptr_type: ir.Type
) -> ir.Function {
    i64 = ir.IntType(64);
    i32 = ir.IntType(32);
    i8_ptr = ir.IntType(8).as_pointer();
    gc_malloc = pass_obj._get_or_declare_extern("GC_malloc", i8_ptr, [i64]);
    memcpy_fn = pass_obj._get_or_declare_extern(
        "memcpy", i8_ptr, [i8_ptr, i8_ptr, i64]
    );

    append_fnty = ir.FunctionType(ir.VoidType(), [list_ptr_type, elem_type]);
    append_fn = ir.Function(
        pass_obj.llvm_module, append_fnty, name=f"__list_append_{elem_type_name}"
    );
    append_fn.linkage = "private";
    append_fn.args[0].name = "list";
    append_fn.args[1].name = "val";

    entry_bb = append_fn.append_basic_block("entry");
    grow_bb = append_fn.append_basic_block("grow");
    store_bb = append_fn.append_basic_block("store");

    b = ir.IRBuilder(entry_bb);
    l_arg = append_fn.args[0];
    v_arg = append_fn.args[1];

    len_p2 = b.gep(l_arg, [ir.Constant(i32, 0), ir.Constant(i32, 0)], name="len.ptr");
    cap_p2 = b.gep(l_arg, [ir.Constant(i32, 0), ir.Constant(i32, 1)], name="cap.ptr");
    cur_len = b.load(len_p2, name="len");
    cur_cap = b.load(cap_p2, name="cap");
    need_grow = b.icmp_unsigned(">=", cur_len, cur_cap, name="need.grow");
    b.cbranch(need_grow, grow_bb, store_bb);

    # Grow block
    b.position_at_end(grow_bb);
    new_cap = b.mul(cur_cap, ir.Constant(i64, 2), name="new.cap");
    b.store(new_cap, cap_p2);
    elem_null2 = ir.Constant(elem_type.as_pointer(), None);
    elem_gep2 = b.gep(elem_null2, [ir.Constant(i32, 1)], name="elem.sizeof");
    elem_sz = b.ptrtoint(elem_gep2, i64, name="elem.size");
    new_bytes = b.mul(new_cap, elem_sz, name="new.bytes");
    new_data_raw = b.call(gc_malloc, [new_bytes], name="new.data.raw");
    new_data = b.bitcast(new_data_raw, elem_type.as_pointer(), name="new.data");
    data_p_g = b.gep(
        l_arg, [ir.Constant(i32, 0), ir.Constant(i32, 2)], name="data.ptr.g"
    );
    old_data = b.load(data_p_g, name="old.data");
    old_bytes = b.mul(cur_len, elem_sz, name="old.bytes");
    old_i8 = b.bitcast(old_data, i8_ptr, name="old.i8");
    new_i8 = b.bitcast(new_data, i8_ptr, name="new.i8");
    b.call(memcpy_fn, [new_i8, old_i8, old_bytes]);
    b.store(new_data, data_p_g);
    b.branch(store_bb);

    # Store block
    b.position_at_end(store_bb);
    # Reload len in store block (it's valid from both entry and grow paths)
    len_p_store = b.gep(
        l_arg, [ir.Constant(i32, 0), ir.Constant(i32, 0)], name="len.ptr.store"
    );
    cur_len_store = b.load(len_p_store, name="len.store");
    data_p_s = b.gep(
        l_arg, [ir.Constant(i32, 0), ir.Constant(i32, 2)], name="data.ptr.s"
    );
    cur_data = b.load(data_p_s, name="data");
    slot = b.gep(cur_data, [cur_len_store], name="slot");
    b.store(v_arg, slot);
    new_len = b.add(cur_len_store, ir.Constant(i64, 1), name="new.len");
    b.store(new_len, len_p_store);
    b.ret_void();

    return append_fn;
}

"""Register __list_get_T: return data[index]."""
def register_get_method(
    pass_obj: NaIRGenPass,
    elem_type_name: str,
    elem_type: ir.Type,
    list_ptr_type: ir.Type
) -> ir.Function {
    i64 = ir.IntType(64);
    i32 = ir.IntType(32);

    get_fnty = ir.FunctionType(elem_type, [list_ptr_type, i64]);
    get_fn = ir.Function(
        pass_obj.llvm_module, get_fnty, name=f"__list_get_{elem_type_name}"
    );
    get_fn.linkage = "private";
    get_fn.args[0].name = "list";
    get_fn.args[1].name = "index";

    bb_g = get_fn.append_basic_block("entry");
    b = ir.IRBuilder(bb_g);
    dp = b.gep(
        get_fn.args[0], [ir.Constant(i32, 0), ir.Constant(i32, 2)], name="data.ptr"
    );
    d = b.load(dp, name="data");
    ep = b.gep(d, [get_fn.args[1]], name="elem.ptr");
    elem_val = b.load(ep, name="elem");
    b.ret(elem_val);

    return get_fn;
}

"""Register __list_set_T: data[index] = val."""
def register_set_method(
    pass_obj: NaIRGenPass,
    elem_type_name: str,
    elem_type: ir.Type,
    list_ptr_type: ir.Type
) -> ir.Function {
    i64 = ir.IntType(64);
    i32 = ir.IntType(32);

    set_fnty = ir.FunctionType(ir.VoidType(), [list_ptr_type, i64, elem_type]);
    set_fn = ir.Function(
        pass_obj.llvm_module, set_fnty, name=f"__list_set_{elem_type_name}"
    );
    set_fn.linkage = "private";
    set_fn.args[0].name = "list";
    set_fn.args[1].name = "index";
    set_fn.args[2].name = "val";

    bb_s = set_fn.append_basic_block("entry");
    b = ir.IRBuilder(bb_s);
    dp2 = b.gep(
        set_fn.args[0], [ir.Constant(i32, 0), ir.Constant(i32, 2)], name="data.ptr"
    );
    d2 = b.load(dp2, name="data");
    ep2 = b.gep(d2, [set_fn.args[1]], name="elem.ptr");
    b.store(set_fn.args[2], ep2);
    b.ret_void();

    return set_fn;
}

"""Register __list_len_T: return len field."""
def register_len_method(
    pass_obj: NaIRGenPass,
    elem_type_name: str,
    elem_type: ir.Type,
    list_ptr_type: ir.Type
) -> ir.Function {
    i64 = ir.IntType(64);
    i32 = ir.IntType(32);

    len_fnty = ir.FunctionType(i64, [list_ptr_type]);
    len_fn = ir.Function(
        pass_obj.llvm_module, len_fnty, name=f"__list_len_{elem_type_name}"
    );
    len_fn.linkage = "private";
    len_fn.args[0].name = "list";

    bb_l = len_fn.append_basic_block("entry");
    b = ir.IRBuilder(bb_l);
    lp = b.gep(
        len_fn.args[0], [ir.Constant(i32, 0), ir.Constant(i32, 0)], name="len.ptr"
    );
    length = b.load(lp, name="len");
    b.ret(length);

    return len_fn;
}

"""Register __list_pop_T: remove and return last element."""
def register_pop_method(
    pass_obj: NaIRGenPass,
    elem_type_name: str,
    elem_type: ir.Type,
    list_ptr_type: ir.Type
) -> ir.Function {
    i64 = ir.IntType(64);
    i32 = ir.IntType(32);

    pop_fnty = ir.FunctionType(elem_type, [list_ptr_type]);
    pop_fn = ir.Function(
        pass_obj.llvm_module, pop_fnty, name=f"__list_pop_{elem_type_name}"
    );
    pop_fn.linkage = "private";
    pop_fn.args[0].name = "list";

    bb_p = pop_fn.append_basic_block("entry");
    b = ir.IRBuilder(bb_p);

    # Get len
    len_p = b.gep(
        pop_fn.args[0], [ir.Constant(i32, 0), ir.Constant(i32, 0)], name="len.ptr"
    );
    cur_len = b.load(len_p, name="len");

    # Decrement len
    new_len = b.sub(cur_len, ir.Constant(i64, 1), name="new.len");
    b.store(new_len, len_p);

    # Get element at new_len position
    data_p = b.gep(
        pop_fn.args[0], [ir.Constant(i32, 0), ir.Constant(i32, 2)], name="data.ptr"
    );
    data = b.load(data_p, name="data");
    elem_p = b.gep(data, [new_len], name="elem.ptr");
    elem = b.load(elem_p, name="elem");
    b.ret(elem);

    return pop_fn;
}

"""Register __list_clear_T: reset len to 0."""
def register_clear_method(
    pass_obj: NaIRGenPass,
    elem_type_name: str,
    elem_type: ir.Type,
    list_ptr_type: ir.Type
) -> ir.Function {
    i64 = ir.IntType(64);
    i32 = ir.IntType(32);

    clear_fnty = ir.FunctionType(ir.VoidType(), [list_ptr_type]);
    clear_fn = ir.Function(
        pass_obj.llvm_module, clear_fnty, name=f"__list_clear_{elem_type_name}"
    );
    clear_fn.linkage = "private";
    clear_fn.args[0].name = "list";

    bb_c = clear_fn.append_basic_block("entry");
    b = ir.IRBuilder(bb_c);
    len_p = b.gep(
        clear_fn.args[0], [ir.Constant(i32, 0), ir.Constant(i32, 0)], name="len.ptr"
    );
    b.store(ir.Constant(i64, 0), len_p);
    b.ret_void();

    return clear_fn;
}

"""Register __list_insert_T: insert element at index, shifting others right."""
def register_insert_method(
    pass_obj: NaIRGenPass,
    elem_type_name: str,
    elem_type: ir.Type,
    list_ptr_type: ir.Type
) -> ir.Function {
    i64 = ir.IntType(64);
    i32 = ir.IntType(32);
    i8_ptr = ir.IntType(8).as_pointer();
    gc_malloc = pass_obj._get_or_declare_extern("GC_malloc", i8_ptr, [i64]);
    memmove_fn = pass_obj._get_or_declare_extern(
        "memmove", i8_ptr, [i8_ptr, i8_ptr, i64]
    );

    insert_fnty = ir.FunctionType(ir.VoidType(), [list_ptr_type, i64, elem_type]);
    insert_fn = ir.Function(
        pass_obj.llvm_module, insert_fnty, name=f"__list_insert_{elem_type_name}"
    );
    insert_fn.linkage = "private";
    insert_fn.args[0].name = "list";
    insert_fn.args[1].name = "index";
    insert_fn.args[2].name = "val";

    entry_bb = insert_fn.append_basic_block("entry");
    grow_bb = insert_fn.append_basic_block("grow");
    shift_bb = insert_fn.append_basic_block("shift");

    b = ir.IRBuilder(entry_bb);
    l_arg = insert_fn.args[0];
    idx_arg = insert_fn.args[1];
    val_arg = insert_fn.args[2];

    # Load len and cap
    len_p = b.gep(l_arg, [ir.Constant(i32, 0), ir.Constant(i32, 0)], name="len.ptr");
    cap_p = b.gep(l_arg, [ir.Constant(i32, 0), ir.Constant(i32, 1)], name="cap.ptr");
    cur_len = b.load(len_p, name="len");
    cur_cap = b.load(cap_p, name="cap");

    # Check if grow needed
    need_grow = b.icmp_unsigned(">=", cur_len, cur_cap, name="need.grow");
    b.cbranch(need_grow, grow_bb, shift_bb);

    # Grow block (similar to append)
    b.position_at_end(grow_bb);
    new_cap = b.mul(cur_cap, ir.Constant(i64, 2), name="new.cap");
    b.store(new_cap, cap_p);
    elem_null = ir.Constant(elem_type.as_pointer(), None);
    elem_gep = b.gep(elem_null, [ir.Constant(i32, 1)], name="elem.sizeof");
    elem_sz = b.ptrtoint(elem_gep, i64, name="elem.size");
    new_bytes = b.mul(new_cap, elem_sz, name="new.bytes");
    new_data_raw = b.call(gc_malloc, [new_bytes], name="new.data.raw");
    new_data = b.bitcast(new_data_raw, elem_type.as_pointer(), name="new.data");
    data_p_g = b.gep(
        l_arg, [ir.Constant(i32, 0), ir.Constant(i32, 2)], name="data.ptr.g"
    );
    old_data = b.load(data_p_g, name="old.data");
    old_bytes = b.mul(cur_len, elem_sz, name="old.bytes");
    old_i8 = b.bitcast(old_data, i8_ptr, name="old.i8");
    new_i8 = b.bitcast(new_data, i8_ptr, name="new.i8");
    b.call(memmove_fn, [new_i8, old_i8, old_bytes]);
    b.store(new_data, data_p_g);
    b.branch(shift_bb);

    # Shift block: move elements [index..len) to [index+1..len+1)
    b.position_at_end(shift_bb);
    len_p_s = b.gep(
        l_arg, [ir.Constant(i32, 0), ir.Constant(i32, 0)], name="len.ptr.s"
    );
    cur_len_s = b.load(len_p_s, name="len.s");
    data_p_s = b.gep(
        l_arg, [ir.Constant(i32, 0), ir.Constant(i32, 2)], name="data.ptr.s"
    );
    data_s = b.load(data_p_s, name="data.s");

    # Calculate elements to move: len - index
    elem_null_s = ir.Constant(elem_type.as_pointer(), None);
    elem_gep_s = b.gep(elem_null_s, [ir.Constant(i32, 1)], name="elem.sizeof.s");
    elem_sz_s = b.ptrtoint(elem_gep_s, i64, name="elem.sz.s");
    elems_to_move = b.sub(cur_len_s, idx_arg, name="elems.to.move");
    bytes_to_move = b.mul(elems_to_move, elem_sz_s, name="bytes.to.move");

    # Source: data[index]
    src_p = b.gep(data_s, [idx_arg], name="src.ptr");
    # Dest: data[index+1]
    idx_plus_1 = b.add(idx_arg, ir.Constant(i64, 1), name="idx.plus.1");
    dst_p = b.gep(data_s, [idx_plus_1], name="dst.ptr");

    # memmove(dst, src, bytes_to_move)
    src_i8 = b.bitcast(src_p, i8_ptr, name="src.i8");
    dst_i8 = b.bitcast(dst_p, i8_ptr, name="dst.i8");
    b.call(memmove_fn, [dst_i8, src_i8, bytes_to_move]);

    # Store value at index
    insert_p = b.gep(data_s, [idx_arg], name="insert.ptr");
    b.store(val_arg, insert_p);

    # Increment len
    new_len_s = b.add(cur_len_s, ir.Constant(i64, 1), name="new.len.s");
    b.store(new_len_s, len_p_s);
    b.ret_void();

    return insert_fn;
}

"""Register __list_remove_T: remove element at index, shifting others left."""
def register_remove_method(
    pass_obj: NaIRGenPass,
    elem_type_name: str,
    elem_type: ir.Type,
    list_ptr_type: ir.Type
) -> ir.Function {
    i64 = ir.IntType(64);
    i32 = ir.IntType(32);
    i8_ptr = ir.IntType(8).as_pointer();
    memmove_fn = pass_obj._get_or_declare_extern(
        "memmove", i8_ptr, [i8_ptr, i8_ptr, i64]
    );

    # Signature: void remove(list, value)
    remove_fnty = ir.FunctionType(ir.VoidType(), [list_ptr_type, elem_type]);
    remove_fn = ir.Function(
        pass_obj.llvm_module, remove_fnty, name=f"__list_remove_{elem_type_name}"
    );
    remove_fn.linkage = "private";
    remove_fn.args[0].name = "list";
    remove_fn.args[1].name = "value";

    entry_bb = remove_fn.append_basic_block("entry");
    loop_bb = remove_fn.append_basic_block("loop");
    check_bb = remove_fn.append_basic_block("check");
    next_bb = remove_fn.append_basic_block("next");
    found_bb = remove_fn.append_basic_block("found");
    not_found_bb = remove_fn.append_basic_block("not_found");

    b = ir.IRBuilder(entry_bb);
    l_arg = remove_fn.args[0];
    val_arg = remove_fn.args[1];

    # Load len
    len_p = b.gep(l_arg, [ir.Constant(i32, 0), ir.Constant(i32, 0)], name="len.ptr");
    cur_len = b.load(len_p, name="len");

    # Get data pointer
    data_p = b.gep(l_arg, [ir.Constant(i32, 0), ir.Constant(i32, 2)], name="data.ptr");
    data = b.load(data_p, name="data");

    # Start loop: search for value
    b.branch(loop_bb);

    # Loop: iterate through list
    b.position_at_end(loop_bb);
    idx_phi = b.phi(i64, name="idx");
    idx_phi.add_incoming(ir.Constant(i64, 0), entry_bb);

    # Check if idx < len
    in_bounds = b.icmp_signed("<", idx_phi, cur_len, name="in.bounds");
    b.cbranch(in_bounds, check_bb, not_found_bb);

    # Check if data[idx] == value
    b.position_at_end(check_bb);
    elem_p = b.gep(data, [idx_phi], name="elem.ptr");
    elem_val = b.load(elem_p, name="elem");

    # Compare values (works for i64, f64, ptr)
    if isinstance(elem_type, ir.IntType) {
        is_equal = b.icmp_signed("==", elem_val, val_arg, name="is.equal");
    } elif isinstance(elem_type, ir.DoubleType) {
        is_equal = b.fcmp_ordered("==", elem_val, val_arg, name="is.equal");
    } else {
        # Pointer comparison
        is_equal = b.icmp_signed("==", elem_val, val_arg, name="is.equal");
    }

    b.cbranch(is_equal, found_bb, next_bb);

    # Not equal, continue loop
    b.position_at_end(next_bb);
    next_idx = b.add(idx_phi, ir.Constant(i64, 1), name="next.idx");
    idx_phi.add_incoming(next_idx, next_bb);
    b.branch(loop_bb);

    # Not found: print error and exit
    b.position_at_end(not_found_bb);
    printf_fn = pass_obj._get_printf();
    exit_fn = pass_obj._get_or_declare_extern("exit", ir.VoidType(), [i32]);
    # Create error message string constant (unique name per element type)
    err_str = "ValueError: list.remove(x): x not in list\n\0";
    err_bytes = bytearray(err_str.encode("utf8"));
    err_const = ir.Constant(ir.ArrayType(ir.IntType(8), len(err_bytes)), err_bytes);
    err_global = ir.GlobalVariable(
        pass_obj.llvm_module, err_const.type, name=f".remove_err_msg_{elem_type_name}"
    );
    err_global.linkage = "private";
    err_global.global_constant = True;
    err_global.initializer = err_const;
    err_msg_ptr = b.gep(
        err_global, [ir.Constant(i32, 0), ir.Constant(i32, 0)], name="err.msg.ptr"
    );
    b.call(printf_fn, [err_msg_ptr]);
    b.call(exit_fn, [ir.Constant(i32, 1)]);
    b.unreachable();

    # Found: shift elements
    b.position_at_end(found_bb);
    found_idx = idx_phi;

    # Calculate elements to move: len - found_idx - 1
    elem_null = ir.Constant(elem_type.as_pointer(), None);
    elem_gep = b.gep(elem_null, [ir.Constant(i32, 1)], name="elem.sizeof");
    elem_sz = b.ptrtoint(elem_gep, i64, name="elem.size");
    idx_plus_1 = b.add(found_idx, ir.Constant(i64, 1), name="idx.plus.1");
    elems_to_move = b.sub(cur_len, idx_plus_1, name="elems.to.move");
    bytes_to_move = b.mul(elems_to_move, elem_sz, name="bytes.to.move");

    # Dest: data[found_idx]
    dst_p = b.gep(data, [found_idx], name="dst.ptr");
    # Source: data[found_idx+1]
    src_p = b.gep(data, [idx_plus_1], name="src.ptr");

    # memmove(dst, src, bytes_to_move)
    dst_i8 = b.bitcast(dst_p, i8_ptr, name="dst.i8");
    src_i8 = b.bitcast(src_p, i8_ptr, name="src.i8");
    b.call(memmove_fn, [dst_i8, src_i8, bytes_to_move]);

    # Decrement len
    new_len = b.sub(cur_len, ir.Constant(i64, 1), name="new.len");
    b.store(new_len, len_p);
    b.ret_void();

    return remove_fn;
}

"""Emit LLVM IR helper functions for a list with given element type."""
impl NaIRGenPass._emit_list_helpers(elem_type_name: str, elem_type: ir.Type) -> None {
    if elem_type_name in self.list_helpers {
        return;
    }
    # For "ptr" variant, always use i8* so all pointer types are interchangeable
    if elem_type_name == "ptr" {
        elem_type = ir.IntType(8).as_pointer();
    }
    # Create list struct type: { i64 len, i64 cap, elem_type* data }
    list_struct = self.llvm_module.context.get_identified_type(
        f"List.{elem_type_name}"
    );
    list_struct.set_body(ir.IntType(64), ir.IntType(64), elem_type.as_pointer());
    self.list_types[elem_type_name] = list_struct;
    list_ptr_type = list_struct.as_pointer();
    # Register all list methods
    new_fn = register_new_method(self, elem_type_name, elem_type, list_ptr_type);
    append_fn = register_append_method(self, elem_type_name, elem_type, list_ptr_type);
    get_fn = register_get_method(self, elem_type_name, elem_type, list_ptr_type);
    set_fn = register_set_method(self, elem_type_name, elem_type, list_ptr_type);
    len_fn = register_len_method(self, elem_type_name, elem_type, list_ptr_type);
    pop_fn = register_pop_method(self, elem_type_name, elem_type, list_ptr_type);
    clear_fn = register_clear_method(self, elem_type_name, elem_type, list_ptr_type);
    insert_fn = register_insert_method(self, elem_type_name, elem_type, list_ptr_type);
    remove_fn = register_remove_method(self, elem_type_name, elem_type, list_ptr_type);
    # Store helpers
    self.list_helpers[elem_type_name] = {
        "new": new_fn,
        "append": append_fn,
        "get": get_fn,
        "set": set_fn,
        "len": len_fn,
        "pop": pop_fn,
        "clear": clear_fn,
        "insert": insert_fn,
        "remove": remove_fn,
        "elem_type": elem_type
    };
}

"""Generate code for a list literal [a, b, c, ...]."""
impl NaIRGenPass._codegen_list_val(node: uni.ListVal) -> (ir.Value | None) {
    if not node.values {
        # Empty list: infer type from context
        elem_type_name = "i64";
        # 1. Check the type hint set by assignment/field context
        if self._list_type_hint is not None {
            elem_type_name = self._list_type_hint;
        } elif self.builder and self.builder.function {
            # 2. Fallback: infer from function return type
            ret_type = self.builder.function.return_value.type;
            if isinstance(ret_type, ir.PointerType) {
                # Check if it's a list pointer type
                for (tn, lt) in self.list_types.items() {
                    if lt.as_pointer() == ret_type {
                        elem_type_name = tn;
                        break;
                    }
                }
            }
        }
        # Ensure helpers exist for this elem type
        if elem_type_name == "ptr" {
            self._emit_list_helpers("ptr", ir.IntType(8).as_pointer());
        } elif elem_type_name == "f64" {
            self._emit_list_helpers("f64", ir.DoubleType());
        } else {
            self._emit_list_helpers("i64", ir.IntType(64));
        }
        helpers = self.list_helpers.get(elem_type_name);
        if helpers is not None {
            return self.builder.call(helpers["new"], [], name="list.empty");
        }
        return None;
    }
    # Codegen first element to determine type
    first_val = self._codegen_expr(node.values[0]);
    if first_val is None {
        return None;
    }
    elem_type = first_val.type;
    elem_type_name = "i64";
    if isinstance(elem_type, ir.DoubleType) {
        elem_type_name = "f64";
    } elif isinstance(elem_type, ir.PointerType) {
        elem_type_name = "ptr";
    }
    # Ensure helpers exist
    self._emit_list_helpers(elem_type_name, elem_type);
    helpers = self.list_helpers[elem_type_name];
    i8p = ir.IntType(8).as_pointer();
    # Create new list
    list_val = self.builder.call(helpers["new"], [], name="list.new");
    # Append first element (bitcast pointers to i8* for ptr lists)
    append_val = first_val;
    if elem_type_name == "ptr" and isinstance(first_val.type, ir.PointerType) {
        append_val = self.builder.bitcast(first_val, i8p, name="elem.cast");
    }
    self.builder.call(helpers["append"], [list_val, append_val]);
    # Append remaining elements
    for i in range(1, len(node.values)) {
        val = self._codegen_expr(node.values[i]);
        if val is not None {
            if elem_type_name == "ptr" and isinstance(val.type, ir.PointerType) {
                val = self.builder.bitcast(val, i8p, name="elem.cast");
            } else {
                val = self._coerce_type(val, elem_type);
            }
            self.builder.call(helpers["append"], [list_val, val]);
        }
    }
    return list_val;
}

"""Get element at index from a list (with IndexError bounds check)."""
impl NaIRGenPass._codegen_index(
    target_val: ir.Value, index_val: ir.Value, elem_type_name: str
) -> (ir.Value | None) {
    helpers = self.list_helpers.get(elem_type_name);
    if helpers is None {
        return None;
    }
    i64 = ir.IntType(64);
    index_val = self._coerce_type(index_val, i64);
    # Get list length
    len_val = self.builder.call(helpers["len"], [target_val], name="list.len.chk");
    # Support negative indexing: if index < 0, convert to len + index
    is_neg = self.builder.icmp_signed(
        "<", index_val, ir.Constant(i64, 0), name="idx.is.neg"
    );
    # adjusted_index = is_neg ? (len + index) : index
    adjusted_for_neg = self.builder.add(len_val, index_val, name="idx.adjusted.neg");
    adjusted_index = self.builder.select(
        is_neg, adjusted_for_neg, index_val, name="idx.adjusted"
    );
    # IndexError: check adjusted_index < 0 (still negative after adjustment)
    still_neg = self.builder.icmp_signed(
        "<", adjusted_index, ir.Constant(i64, 0), name="idx.still.neg"
    );
    self._emit_runtime_raise(still_neg, "IndexError", "list index out of range");
    # IndexError: check adjusted_index >= len
    is_oob = self.builder.icmp_signed(
        ">=", adjusted_index, len_val, name="idx.oob.chk"
    );
    self._emit_runtime_raise(is_oob, "IndexError", "list index out of range");
    return self.builder.call(
        helpers["get"], [target_val, adjusted_index], name="list.get"
    );
}

"""Set element at index in a list (with IndexError bounds check)."""
impl NaIRGenPass._codegen_index_set(
    target_val: ir.Value, index_val: ir.Value, value: ir.Value, elem_type_name: str
) -> None {
    helpers = self.list_helpers.get(elem_type_name);
    if helpers is None {
        return;
    }
    i64 = ir.IntType(64);
    index_val = self._coerce_type(index_val, i64);
    # Get list length
    len_val = self.builder.call(helpers["len"], [target_val], name="list.setlen.chk");
    # Support negative indexing: if index < 0, convert to len + index
    is_neg = self.builder.icmp_signed(
        "<", index_val, ir.Constant(i64, 0), name="setidx.is.neg"
    );
    adjusted_for_neg = self.builder.add(len_val, index_val, name="setidx.adjusted.neg");
    adjusted_index = self.builder.select(
        is_neg, adjusted_for_neg, index_val, name="setidx.adjusted"
    );
    # IndexError: check adjusted_index < 0
    still_neg = self.builder.icmp_signed(
        "<", adjusted_index, ir.Constant(i64, 0), name="setidx.still.neg"
    );
    self._emit_runtime_raise(
        still_neg, "IndexError", "list assignment index out of range"
    );
    # IndexError: check adjusted_index >= len
    is_oob = self.builder.icmp_signed(
        ">=", adjusted_index, len_val, name="setidx.oob.chk"
    );
    self._emit_runtime_raise(
        is_oob, "IndexError", "list assignment index out of range"
    );
    elem_type = helpers["elem_type"];
    value = self._coerce_type(value, elem_type);
    self.builder.call(helpers["set"], [target_val, adjusted_index, value]);
}

"""Call list.pop() method - remove and return last element."""
impl NaIRGenPass._codegen_list_pop(
    target_val: ir.Value, elem_type_name: str
) -> (ir.Value | None) {
    helpers = self.list_helpers.get(elem_type_name);
    if helpers is None {
        return None;
    }
    i64 = ir.IntType(64);
    # Check that list is not empty
    len_val = self.builder.call(helpers["len"], [target_val], name="list.len.pop");
    is_empty = self.builder.icmp_signed(
        "==", len_val, ir.Constant(i64, 0), name="is.empty"
    );
    self._emit_runtime_raise(is_empty, "IndexError", "pop from empty list");
    return self.builder.call(helpers["pop"], [target_val], name="list.pop");
}

"""Call list.clear() method - reset length to 0."""
impl NaIRGenPass._codegen_list_clear(target_val: ir.Value, elem_type_name: str) -> None {
    helpers = self.list_helpers.get(elem_type_name);
    if helpers is None {
        return;
    }
    self.builder.call(helpers["clear"], [target_val]);
}

"""Call list.insert(index, value) method - insert element at index."""
impl NaIRGenPass._codegen_list_insert(
    target_val: ir.Value, index_val: ir.Value, value: ir.Value, elem_type_name: str
) -> None {
    helpers = self.list_helpers.get(elem_type_name);
    if helpers is None {
        return;
    }
    i64 = ir.IntType(64);
    index_val = self._coerce_type(index_val, i64);
    # Get list length
    len_val = self.builder.call(helpers["len"], [target_val], name="list.len.insert");
    # Adjust negative indices and clamp to [0, len]
    is_neg = self.builder.icmp_signed(
        "<", index_val, ir.Constant(i64, 0), name="insert.is.neg"
    );
    adjusted_for_neg = self.builder.add(len_val, index_val, name="insert.adjusted.neg");
    adjusted_index = self.builder.select(
        is_neg, adjusted_for_neg, index_val, name="insert.adjusted"
    );
    zero = ir.Constant(i64, 0);
    is_below = self.builder.icmp_signed("<", adjusted_index, zero, name="insert.below");
    clamped_low = self.builder.select(
        is_below, zero, adjusted_index, name="insert.clamped.low"
    );
    is_above = self.builder.icmp_signed(">", clamped_low, len_val, name="insert.above");
    final_index = self.builder.select(
        is_above, len_val, clamped_low, name="insert.final"
    );
    elem_type = helpers["elem_type"];
    value = self._coerce_type(value, elem_type);
    self.builder.call(helpers["insert"], [target_val, final_index, value]);
}

"""Call list.remove(value) method - remove first occurrence of value."""
impl NaIRGenPass._codegen_list_remove(
    target_val: ir.Value, value: ir.Value, elem_type_name: str
) -> None {
    helpers = self.list_helpers.get(elem_type_name);
    if helpers is None {
        return;
    }
    # Coerce value to the correct element type
    elem_type = helpers["elem_type"];
    value = self._coerce_type(value, elem_type);
    # Call the helper function directly (it searches for the value)
    self.builder.call(helpers["remove"], [target_val, value]);
}
