# MOPL# Tutorial

## 1. Setup

```bash
chmod +x build.sh
./build.sh
```

Assembles and links `mopl` from `mopl_backend.s`. Must be run on an Apple
Silicon Mac with Xcode Command Line Tools installed.

## 2. Your First Script

`first.mopl`:
```
Tag.x = num.5
Terminal 'x'
```

```bash
./mopl run first.mopl
```
```
5
```

`Tag.x = num.5` declares a tag named `x`, of type `num`, value `5`.
`Terminal 'x'` prints its current value.

## 3. Reassigning a Tag (the "+" Law)

Each time you write to an existing tag, add one more `+` before `=`:

```
Tag.x = num.5     // 1st write
Tag.x += num.10    // 2nd write
Terminal 'x'
```
```
10
```

A third write would be `Tag.x ++= num.20`, and so on.

## 4. The Four Data Types

```
Tag.a = num.42            // numeric
Tag.b = state.true        // boolean
Tag.c = blea.Hello World  // text
Tag.d = logic.            // code block (not yet executable)
```

## 5. Doing Math — `Op of`

```
Tag.a = num.4
Tag.b = num.3
Op of a add b ==
Terminal '_'
```
```
7
```

The result of any `Op of ... ==` lands in a special tag called `_`. Print
it right after with `Terminal '_'`.

Supported operators: `add`, `subtract`, `times`, `divide` (numeric only —
see `NOTES.md` for the mixed-type `blea` extension point).

## 6. Inspecting Tags — `Dif`

```
Tag.x = num.1
Tag.x += num.2
Dif in x
```
```
x = num, level 2
```

List multiple tags: `Dif in x, y, z`.

## 7. Full Example

```
Tag.x = num.5
Tag.x += num.10
Terminal 'x'

Tag.HI = state.true
Tag.Hi = num.1
Op of Hi add HI ==
Terminal '_'

Dif in x, HI, Hi
```

```bash
./mopl run examples/hello.mopl
```

## 8. What Doesn't Work Yet

Not implemented in the current interpreter:
- `logic` blocks (`EndLogic`) — functions aren't executable yet
- `Check`/`EndCheck` — conditionals
- `Cycle`/`EndCycle` — loops
- `Window`/`In`/`At` — the GUI system

Lines using these keywords are silently skipped rather than erroring.
See `NOTES.md` for what each would take to add.

## 9. Current Limitations

- `Op of` only does numeric math — mixing `num` and `state` operands
  currently does math on the underlying `1`/`0` rather than the spec's
  string-concatenation behavior.
- The `+` count in source isn't cross-checked against the actual write
  count yet — the interpreter tracks the level internally regardless of
  how many `+` you type.

## 10. Running in VS Code

See the "Running natively in VS Code" section of `README.md` for the
task runner and optional syntax-highlighting extension.
