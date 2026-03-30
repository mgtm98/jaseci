"""Debug helpers: post_transform dumps/validates the generated LLVM IR.

Environment variables
---------------------
JAC_DEBUG_IR=1        — save IR to .jac_ir/<stem>.ll next to the source file
JAC_VERIFY_IR=1       — run llvmlite parse_assembly to verify the IR
"""
import from llvmlite { binding as llvm }
import os;
import sys;

"""Dump and/or validate the generated LLVM IR.  Called after transform()."""
impl NaIRGenPass.post_transform -> None {
    if not self.has_native_code {
        return;
    }

    # ── Emit DWARF compile-unit and required module flags (JAC_NATIVE_DEBUG) ──
    if self.di_cu is not None {
        try {
            self.llvm_module.add_named_metadata("llvm.dbg.cu").add(self.di_cu);
            _nm_flags = self.llvm_module.add_named_metadata("llvm.module.flags");
            _nm_flags.add(
                self.llvm_module.add_metadata(
                    [
                        ir.Constant(ir.IntType(32), 7),
                        "Dwarf Version",
                        ir.Constant(ir.IntType(32), 5)
                    ]
                )
            );
            _nm_flags.add(
                self.llvm_module.add_metadata(
                    [
                        ir.Constant(ir.IntType(32), 2),
                        "Debug Info Version",
                        ir.Constant(ir.IntType(32), 3)
                    ]
                )
            );
        } except Exception {
            pass;  # debug flags are best-effort
        }
    }
}
