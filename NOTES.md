# MOPL# Interpreter — Implementation Notes

## What's actually implemented (in `mopl_backend.s`)

- **File I/O**: `open`/`read`/`close` on the `.mopl` file passed as `argv[1]`
  (macOS BSD syscalls, class `0x2000000`).
- **Line scanner**: splits the script on `\n`, trims leading whitespace,
  dispatches each line by its leading keyword.
- **Tag table**: a linked list in a 256 KB bump-allocated heap. Each node is
  a fixed 48-byte record: `next | name ptr | type | int value | str value | assignment level`.
- **`Tag.name = type.value`**: creates or updates a tag. On update, the
  assignment level counter is incremented (this is the runtime-side "law" —
  see the caveat below).
- **`Terminal 'name'`**: prints a tag's value + newline for `num`, `state`,
  and `blea` types.
- **`Op of A <op> B ==`**: supports `add`, `subtract`, `times`, `divide` on
  numeric operands (tag names or literals). Result is stashed in a synthetic
  tag named `_` so a following `Terminal '_'` prints it.
- **`Dif in a, b, c`**: prints `name = type, level N` per tag.

## Known simplifications / caveats

1. **The "+" reassignment law is not strictly *validated*.** The interpreter
   tracks and increments an assignment-level counter automatically on every
   write, but it does not currently parse and cross-check the number of `+`
   characters in the source against that counter (i.e. it won't reject a
   line that uses `+=` when `++=` was expected). Enforcing that is a small
   addition to `_handle_tag_line`: count consecutive `+` bytes between the
   tag name and `=`, then compare against `[record+40]` before writing.

2. **`Op of` only handles `num` operands and `add/subtract/times/divide`.**
   `cos`/`tan` fall through to a stub that returns the first operand
   unchanged (`.Lao_default` in `_apply_operator`). Mixed `num`/`state`
   string concatenation (Feature 7's `blea` example) is not implemented —
   the extension point is `_apply_operator`, which would need a branch that
   detects mixed operand types, calls an `itoa`-then-append routine, and
   stores a `TAG_BLEA` result instead of a `TAG_NUM` one.

3. **Not implemented in this pass**: `logic`/`EndLogic` execution,
   `Check`/`EndCheck`, `Cycle`/`EndCycle`, and the whole GUI stack
   (`Window`, `In`, `At ... add a ...`, `objc_msgSend` bridging to
   Cocoa/AppKit). These are architecturally the biggest pieces — the GUI
   layer alone requires bridging into the Objective-C runtime
   (`_objc_getClass`, `_sel_registerName`, `objc_msgSend`) and driving the
   AppKit run loop, which is a separate module worth its own file rather
   than bolting onto this one. The line dispatcher (`_dispatch_line`)
   already has a fallthrough that silently skips any line it doesn't
   recognize, so adding a new keyword just means adding another
   `_starts_with` check + handler routine there.

4. **Single-pass execution.** There's no lookahead, so `logic` blocks
   (when added) would need the dispatcher to switch into a "collecting
   mode" that buffers lines between `= logic.` and `EndLogic` into a
   stored block, rather than executing immediately.

## Build & run (macOS, Apple Silicon only — this cannot be assembled on
the Linux sandbox this was written in)

```bash
chmod +x build.sh
./build.sh
./mopl run examples/hello.mopl
```

Expected output:
```
10
1true
x = num, level 2
HI = state, level 1
Hi = num, level 1
```

(Note: mixed-type concatenation for `Op of Hi add HI ==` is one of the
simplifications above — until that's added, the numeric add path runs
and treats `HI`'s state value as its underlying int, i.e. `1 + 1 = 2`,
not the spec's `"1true"` string. This is called out so it isn't a
silent surprise — see caveat #2 for the fix.)

## Suggested next steps, in order of leverage
1. Enforce the `+` reassignment law strictly (small, in `_handle_tag_line`).
2. Add mixed-type `blea` concatenation to `_apply_operator`.
3. Add `logic`/`EndLogic` as a "collect lines into a stored block" mode.
4. Add `Check`/`EndCheck` using the same operand-resolution helpers already
   built (`_resolve_operand`) plus a comparison-operator dispatch modeled
   on `_apply_operator`.
5. Add `Cycle`/`EndCycle` as a simple counted loop calling the stored logic
   block N times.
6. GUI last — it's the only piece that needs the Objective-C bridge.
