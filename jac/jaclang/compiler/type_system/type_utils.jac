"""Functions that operate on Type objects.

PyrightReference: packages/pyright-internal/src/analyzer/typeUtils.ts
"""

import from dataclasses { dataclass }
import from enum { Enum }

import jaclang.compiler.unitree as uni;
import from jaclang.compiler.constant { Tokens as Tok }
import from jaclang.compiler.unitree { Symbol }

import from . { types }


"""Represents a member of a class."""
obj ClassMember {

    has symbol: Symbol;
    has class_type: types.ClassType;

    # True if it is an instance or class member; it can be both a class and
    # an instance member in cases where a class variable is overridden
    # by an instance variable
    has is_instance_member: bool = True;
    has is_class_member: bool = False;

    # Is the member in __slots__?
    has is_slots_member: bool = False;

    # True if explicitly declared as "ClassVar" and therefore is
    # a type violation if it is overwritten by an instance variable
    has is_class_var: bool = False;

    # True if the member is read-only, such as with named tuples
    # or frozen dataclasses.
    has is_read_only: bool = False;

    # True if member has declared type, false if inferred
    has is_type_declared: bool = False;

    # True if member lookup skipped an undeclared (inferred) type
    # in a subclass before finding a declared type in a base class
    has skipped_undeclared_type: bool = False;
}


"""Compute the method resolution order (MRO) for a class type.

This uses the C3 linearization algorithm to compute the MRO.
See https://www.python.org/download/releases/2.3/mro/
"""
def compute_mro_linearization(cls: types.ClassType) -> None {
    if cls.shared.mro {
        return;
    }

    # FIXME: This is an ad-hoc implementation to make the MRO works
    # and it'll cover the 90% or more of the user cases.

    # Computer MRO for base classes first
    cls.shared.mro.append(cls);
    for base in cls.shared.base_classes {
        if isinstance(base, types.ClassType) {
            compute_mro_linearization(base);
        }
    }

    # Then add base classes and their MROs
    for base in cls.shared.base_classes {
        if isinstance(base, types.ClassType) {
            for mro_cls in base.shared.mro {
                if mro_cls not in cls.shared.mro {
                    cls.shared.mro.append(mro_cls);
                }
            }
        }
    }
}

# In pyright, this class lives in the parameterUtils.ts however we're
# putting it here for now and if the scale of the code grows we can
# split it into a separate file.
"""Tracks parameter assignments for function calls.

This class helps in tracking which parameters have been matched
with arguments in a function call. It supports positional, named,
*args, and **kwargs arguments.
"""
obj ParamAssignmentTracker {

    has params: list[types.Parameter];
    has curr_param_idx: int = 0;
    has matched_params: set[types.Parameter] = set();

    # Quick access to vararg and kwarg parameters
    has varargs: types.Parameter | None = None;
    has kwargs: types.Parameter | None = None;

    """Initialize obviously."""
    def postinit {
        # "Cache" vararg and kwarg parameters for quick access
        for param in self.params {
            if param.param_kind == types.ParamKind.VARARG {
                self.varargs = param;
            } elif param.param_kind == types.ParamKind.KWARG {
                self.kwargs = param;
            }
        }
    }

    """Lookup a named parameter by name and if any match is found we mark it as such."""
    def lookup_named_parameter(param_name: str) -> types.Parameter | None {
        for param in self.params {
            # User try to pass a positional only parameter with a name, should be an error.
            if (param.param_kind == types.ParamKind.POSONLY) and (
                param_name == param.name
            ) {
                self.matched_params.add(param);
                raise Exception(
                    f"Positional only parameter '{param.name}' cannot be matched with a named argument"
                );
            }
            if param.param_kind not in (types.ParamKind.NORMAL, types.ParamKind.KWONLY) {
                continue;
            }
            if param.name == param_name {
                if param in self.matched_params {
                    raise Exception(f"Parameter '{param.name}' already matched");
                }
                self.matched_params.add(param);
                return param;
            }
        }
        # If we reached here, there is no named parameter to match with
        # however if we have **kwargs, we can match it with that, if that
        # also None, it'll return None indicating no match.
        return self.kwargs;
    }

    """Mark all named parameters as matched."""
    def _mark_all_named_params_as_matched() -> None {
        for param in self.params {
            if param.param_kind in (
                types.ParamKind.NORMAL,
                types.ParamKind.KWONLY,
                types.ParamKind.KWARG,
            ) {
                self.matched_params.add(param);
            }
        }
    }

    """Mark all positional parameters as matched."""
    def _mark_all_positional_params_as_matched() -> None {
        for param in self.params {
            if param.param_kind in (
                types.ParamKind.POSONLY,
                types.ParamKind.NORMAL,
                types.ParamKind.VARARG,
            ) {
                self.matched_params.add(param);
            }
        }
        self.curr_param_idx = -1;
    }

    """Match a named argument to a parameter."""
    def match_named_argument(arg: uni.KWPair) -> types.Parameter | None {
        if arg.key is None {
            # **{} <- This can be matched with any named parameter
            # in the current parameter list.
            self._mark_all_named_params_as_matched();
            return None;
        } else {
            if param := self.lookup_named_parameter(arg.key.sym_name) {
                return param;
            }
            raise Exception(
                f"Named argument '{arg.key.sym_name}' does not match any parameter"
            );
        }
    }

    """Match a positional argument to a parameter."""
    def match_positional_argument(arg: uni.Expr) -> types.Parameter | None {
        # NOTE: The curr_param_idx can be -1 only when a unpack (*expr) is passed
        # at that point there is no reliable way to match the remaining positional
        # arguments after the unpack, so we either match with *args or not match with
        # anything.
        if self.curr_param_idx == -1 {
            return self.varargs;
        }

        if isinstance(arg, uni.UnaryExpr) and arg.op.name == Tok.STAR_MUL {
            self._mark_all_positional_params_as_matched();
            return None;
        } else {
            if self.curr_param_idx < len(self.params) {
                param = self.params[self.curr_param_idx];
                if param.param_kind == types.ParamKind.VARARG {
                    self.matched_params.add(param);
                    return param;
                }
                if param.param_kind in (
                    types.ParamKind.NORMAL,
                    types.ParamKind.POSONLY,
                ) {
                    self.curr_param_idx += 1;
                    self.matched_params.add(param);
                    return param;
                }
            }

            # If we reached here, there is no parameter to match with
            raise Exception("Too many positional arguments");
        }
    }

    """Check if there are any unmatched required parameters."""
    def get_unmatched_required_params() -> list[types.Parameter] {
        ret: list[types.Parameter] = [];
        for param in self.params {
            if (
                param not in self.matched_params
                and param.default_value is None
                and param.param_kind
                not in (types.ParamKind.VARARG, types.ParamKind.KWARG)
            ) {
                ret.append(param);
            }
        }
        return ret;
    }
}


# -----------------------------------------------------------------------------
# Completion item utils
# -----------------------------------------------------------------------------


"""A completion item."""
obj CompletionItem {
    has label: str;
    has kind: int;
    has detail: str | None = None;
}


"""The kind of a completion entry."""
class CompletionItemKind(int, Enum) {
    has Text: int = 1;
    has Method: int = 2;
    has Function: int = 3;
    has Constructor: int = 4;
    has Field: int = 5;
    has Variable: int = 6;
    has Class: int = 7;
    has Interface: int = 8;
    has Module: int = 9;
    has Property: int = 10;
    has Unit: int = 11;
    has Value: int = 12;
    has Enum: int = 13;
    has Keyword: int = 14;
    has Snippet: int = 15;
    has Color: int = 16;
    has File: int = 17;
    has Reference: int = 18;
    has Folder: int = 19;
    has EnumMember: int = 20;
    has Constant: int = 21;
    has Struct: int = 22;
    has Event: int = 23;
    has Operator: int = 24;
    has TypeParameter: int = 25;
}


"""Get the completion item kind from a symbol."""
def completion_kind_from_sym(sym: Symbol) -> int {
    match sym.decl.name_of {
        case uni.ModulePath():
            return CompletionItemKind.Module;
        case uni.Ability():
            return CompletionItemKind.Function;
        case uni.Archetype():
            return CompletionItemKind.Class;
        case uni.Enum():
            return CompletionItemKind.Enum;
        case uni.HasVar():
            return CompletionItemKind.Variable;
    }
    return CompletionItemKind.Text;
}

"""Return a list of completion items for the type."""
def get_completion_items(ty: types.TypeBase | uni.UniScopeNode) -> list[CompletionItem] {
    ret = [];

    if isinstance(ty, uni.UniScopeNode) {
        scope = ty;
        while scope {
            for (name, sym) in scope.names_in_scope.items() {
                kind = completion_kind_from_sym(sym);
                ret.append(CompletionItem(label=name, kind=kind));
            }
            scope = scope.parent_scope;
        }

    } elif isinstance(ty, types.ClassType) {
        for cls in ty.shared.mro {
            for (name, sym) in cls.shared.symbol_table.names_in_scope.items() {
                kind = completion_kind_from_sym(sym);
                ret.append(CompletionItem(label=name, kind=kind));
            }
        }

    } elif isinstance(ty, types.ModuleType) {
        for (name, sym) in ty.symbol_table.names_in_scope.items() {
            kind = completion_kind_from_sym(sym);
            ret.append(CompletionItem(label=name, kind=kind));
        }
    }

    return ret;
}
