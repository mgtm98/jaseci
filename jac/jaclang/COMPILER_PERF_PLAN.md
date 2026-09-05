# Jac Native Compiler: Performance Enhancement Plan

Goal: make `jac nacompile` fast enough for a tight edit-build-run loop on large
projects (reference workload: jac-bun, 158 native-pinned modules, ~500k+ lines,
including a single 29k-line module `vm.jac`).

All numbers below are **measured** (2026-09-03, x86-64 Linux, warm page cache)
with the new `JAC_PROFILE_PASSES=1` per-pass profiler on the jac-bun engine
build. Two baseline scenarios:

| Scenario | Wall time | Dominated by |
|---|---|---|
| **Cold / `--scrub`** (no native IR cache) | ~12 min | `NaIRGenPass` ≈ 1572 s aggregate (~75% of pass time), `TypeCheckPass` 338 s (315 calls = 2× per module), `EndpointEffectPass` 112 s, LLVM emit+link 32 s |
| **Warm / incremental** (all 157 deps native-IR cache HITs) | ~4.5–5 min | `TypeCheckPass` 217 s across **all 158 modules despite the IR cache HITs**, cache reads/linking ~200 s under main's `NaIRGenPass`, strict import-walker 41 s |
| Memory | 5.1 GB RSS peak | all dep ASTs + type info resident simultaneously, even on warm builds |

The two goals the user named: **parallel compilation** and **don't re-analyze
unchanged files**: map to sections P and C. Section A covers algorithmic wins
inside passes; section I covers infrastructure prerequisites.

---

## C. Caching: skip work for unchanged files

### C1. Serve module interfaces from cache for native-IR-cache HITs ⭐ biggest warm-build win

**Measured waste:** 217 s/warm build (75% of warm wall time).
**Problem:** the driver fully frontend-compiles every dependency (parse →
symtab → **TypeCheck**) *before* `na_compile_pass` discovers its native IR is
already cached: the type check exists only to provide symbols/interfaces to
importers, then the compiled module is discarded in favor of the cached IR.
`vm.jac` alone: 67 s of type checking per build, unchanged.
**Fix:** consult the native IR cache (`native_dep_cache_paths` →
`.ir_cache`/`.ir_meta` existence + freshness) *before* compiling a dep; on HIT,
serve its exported interface from the always-on analysis cache (#8839,
`SEC_IFACE`) instead of frontend-compiling. Requires the iface cache to be
authoritative for cross-module symbol resolution in the native path (it already
is for the bytecode path: that's the "dependency cutoff").
**Expected:** warm builds 4.5 min → **~1.5 min**.
**Risk:** iface staleness: gate on the same source-hash the IR cache filename
already embeds.

### C2. Eliminate the double TypeCheck (2× per module even on scrub)

**Measured waste:** 315 `TypeCheckPass` calls for 158 modules; ~170 s/scrub.
Modules are checked once in the frontend program context and again in the
native compile context (`clone_for_native_import` → fresh `prog.compile`).
**Fix:** share the typed module between contexts, or make the native-context
compile reuse `nd.type` stamps when the module object is already checked
(hub-keyed memo). Investigate why `_compile_and_link_native_imports` triggers a
second full pipeline per dep instead of reusing `self.prog.scratch.na_dep_units`.
**Expected:** −170 s scrub, also reduces peak memory.

### C3. Per-pass fact caching in the module `.jir` (extend #8839)

Persist expensive per-module analysis results as jir sections and replay on
freshness, like diagnostics already are: candidates ordered by measured cost -
`EndpointEffectPass` facts (112 s/scrub), CFG summaries (13 s), RcFacts (14 s),
lint (9 s), capability check (7 s). Keyed by (source hash, dep-iface hashes).
**Expected:** −100–150 s on scrub for analysis-stable files; near-zero
re-analysis on warm builds beyond what C1 already removes.

### C4. Strict-walker verdict cache

**Measured waste:** 41 s per `--strict` build (every build): the import-graph
walker (nacompile.impl.jac, strict check #1) re-parses all 158 modules +
`.impl.jac` annexes to prove no module silently fell out of the native closure.
**Fix:** sidecar cache `(path, mtime, size) → (first_error, deps)` under
`.jac/cache/` (deliberately spared by `--scrub`'s native-only narrowing);
re-parse only changed files. Steady-state cost = one stat() sweep (<1 s).
**Expected:** −40 s on every build. Small, safe, isolated.

### C5. Native dep-hash invalidation (COMPILER_CHANGES_README #1)

Not a speed win: the **correctness prerequisite** for leaning harder on the
IR cache: a cached module must be invalidated when a *dependency's* struct
layout changes, else aggressive caching produces silently corrupt binaries.
Port the `DepClibMeta.dep_hashes` scheme before shipping C1/C3.

### C6. Finer-grained compiler self-invalidation

Today any edit under `COMPILER_DIGEST_ROOTS` changes `compiler_generation()`
(one hash over the whole tree) → the compiler recompiles ~all of itself.
`JAC_COMPILER_DIGEST_PIN` is the manual escape hatch (documented; in use).
Long-term: per-module generation via the iface-cutoff machinery so a leaf-pass
edit recompiles only its dependents. Also fold `cli/commands/` into the digest
roots story consistently (today it is outside the digest yet inside the cache,
an inconsistency that has produced confusing states).

### C7. LLVM emit caching

`NativeCompilePass` (opt+emit) is only 32 s; per-module object caching
(`SEC_NATIVE_OBJ` already exists in the unified jir) is worth it only after
P1 makes IR generation cheap; then object-level reuse removes the remaining
serial emit for unchanged modules.

---

## P. Parallelism: use all cores

The compiler is Python-hosted (self-hosted Jac lowered to CPython bytecode), so
**threads don't parallelize CPU-bound passes (GIL)**. The natural unit is the
**module**, and the existing per-module `.ir_cache`/`.ir_meta` files are the
ideal hand-off medium.

### P1. Parallel native dep compilation via worker processes ⭐ biggest scrub win

**Measured target:** `NaIRGenPass` 1572 s aggregate over 158 modules, run
strictly sequentially inside `_compile_and_link_native_imports`.
**Design (subprocess fan-out, "make -j" style):**

1. Root process runs the (cheap) placement/closure scan to get the module list
   + dependency DAG (the strict walker already computes exactly this: reuse).
2. Topologically batch modules whose deps' ifaces are ready; spawn N worker
   processes (`jac nacompile --dep-only <module>` mode), each compiling one
   module and writing its `.ir_cache`/`.ir_meta` (the exact artifacts the cache
   path already consumes). Workers share nothing; the filesystem is the mailbox.
3. Root process then runs today's sequential loop: every dep is now a cache
   HIT: and links.
**Expected:** scrub 12 min → **~3–4 min** on 8–12 cores (IR gen parallelizes;
serial residue = frontends of the DAG's critical path + link + emit).
**Prereqs:** C5 (dep-hash correctness), deterministic IR cache writes (atomic
tmp+rename: partially there), worker-safe cache dirs (already per-module
files), and C1 so workers don't each re-frontend the whole closure (workers
should consume cached ifaces: C1 and P1 compound).
**Note:** `multiprocessing` with a pickled hub is the alternative to exec'ing
workers; exec is simpler and battle-tested (this is what `make -j` is).

### P2. Parallel frontend (parse + typecheck)

Same fan-out for the frontend when C1 can't serve a cached iface (changed
files). Parsing is embarrassingly parallel; TypeCheck needs dep ifaces →
topological batches again. Lower priority once C1/C2 land (the serial frontend
of *changed* files only is small).

### P3. Parallel LLVM object emission

llvmlite's opt/emit releases the GIL in LLVM C++ land: emit per-module objects
on a thread pool instead of one big module link. Requires per-module object
emission (C7's structure). Only ~32 s today; do last.

### P4. Pipeline overlap

Overlap link/emit of ready modules with still-compiling ones (classic build
pipelining). Falls out naturally from P1's DAG scheduler; don't build
separately.

---

## A. Algorithmic / in-pass wins

### A1. `EndpointEffectPass`: 112 s/scrub, 57 s on vm.jac alone

Suspicious for what it does (endpoint/effect analysis; jac-bun has no server
endpoints). First: profile it (`JAC_PROFILE_PASSES=peak` + py-spy): likely a
quadratic walk on big modules. Second: consider gating it off entirely under
`aot_mode` when the project declares no endpoints.

### A2. `NaIRGenPass` constant-factor work

1572 s for ~500k lines ≈ 3 ms/line: high. The pass builds LLVM IR through the
vendored Python `ir` builder; suspects: string-based IR assembly, repeated
type-layout recomputation, per-node allocations. Method: py-spy/cProfile one
big module (`dispatch.jac`, 146 s), fix the top hotspots. Even −30% here is
−8 min of aggregate work (matters less once P1 spreads it, but lowers the
critical path too).

### A3. `TypeCheckPass` on huge modules

67 s for vm.jac (29k lines). Profile; likely wins: symbol-resolution memos,
avoiding re-evaluation of unchanged expression subtrees. Pairs with C3 if
facts become persistable.

### A4. Memory: release dep ASTs/type-info after iface extraction

5.1 GB peak on a *warm* build. The native side already releases dep LLVM IR
after linking (memrelease, readme #10); the frontend keeps every dep's full
AST + types resident. Freeing per-dep after iface extraction cuts peak memory
several-fold and reduces GC pressure (Python GC on a 5 GB heap is itself a
tax on every pass). `JAC_PROFILE_PASSES=1` rss_hwm deltas identify the
retaining passes.

### A5. Skip Jcir/bytecode generation for pure-AOT dep modules

`JcirGenPass` + `JcirBytecodeGenPass` ≈ 14 s + small per scrub. For AOT deps
whose bytecode is never executed, skip: but ONLY after confirming the unified
module cache tolerates bytecode-less entries (readme #11 explains why naive
skipping is now harmful). Small win; audit first.

---

## I. Infrastructure prerequisites & guardrails

1. **Fix the silent-bytecode-drop bug** (`compile_ir` returns empty with zero
   diagnostics → "No bytecode found"): incremental/parallel schemes multiply
   exposure to partial states; silent failures must become loud before we lean
   in. (`JcirBytecodeGenPass.transcribe_module`: emit a diagnostic when
   `result.modules` is empty.)
2. **Atomic cache writes everywhere** (tmp + rename): killed builds currently
   can poison module caches (observed twice this week).
3. **Keep `--strict` semantics** under parallelism: the walker (or its C4
   cached form) remains the closure-completeness gate regardless of who
   compiled what.
4. **Determinism check in CI:** same inputs → byte-identical `.ir_cache`, so
   parallel and serial builds are provably equivalent.
5. **Measurement harness:** `JAC_PROFILE_PASSES=1|peak` (landed),
   `JAC_NA_CACHE_DEBUG=1` (landed), `JAC_SYMMAP=1` for binary symbolization
   (existing). Every item above should land with before/after numbers from the
   jac-bun 158-module workload.

---

## Suggested order of attack (impact ÷ effort)

| # | Item | Scenario | Est. win | Effort |
|---|---|---|---|---|
| 1 | C4 walker cache | every build | −41 s | S |
| 2 | C2 double-TypeCheck | scrub+warm | −170 s | M |
| 3 | C1 iface-serve for IR-cache HITs | warm | −200 s (4.5→~1.5 min) | M–L |
| 4 | A1 EndpointEffect gate/fix | scrub | −60…110 s | S–M |
| 5 | C5 dep-hash port (correctness) |: | enables 6 | S–M |
| 6 | P1 parallel dep compile | scrub | 12→3–4 min | L |
| 7 | A4 memory release | all | −GB, faster GC | M |
| 8 | A2/A3 pass hotspots | all | −20–30% pass time | M–L |
| 9 | C3 pass-fact caching | warm | residual analysis → 0 | L |
| 10 | P3/C7 parallel/cached emit | scrub | −20 s | M |

End-state target: **warm incremental build ≲ 60 s, cold scrub ≲ 3 min** on the
158-module engine, single-digit seconds for a one-file engine edit.

---

## Out of scope here (separate track)

**Engine *runtime* performance**: the freshly-native binary is reported slow
at runtime. That is a codegen-quality/runtime matter, not compiler throughput:
first suspects are `opt_level` actually applied to dep modules, RC traffic
(non-atomic RC landed?), the `align=1` peek/poke sites inhibiting
vectorization (they shouldn't: they're FFI-only), missing inlining across
module boundaries (no LTO), and allocation churn. Needs its own profile
(callgrind + `JAC_SYMMAP=1`) and its own document once measured.
