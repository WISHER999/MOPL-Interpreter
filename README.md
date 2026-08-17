# MOPL# Interpreter

A tag-based scripting language with an interpreter written entirely in
ARM64 Assembly (Apple Silicon / macOS).

- **Language spec / tutorial:** see [`TUTORIAL.md`](./TUTORIAL.md)
- **Implementation notes & limitations:** see [`NOTES.md`](./NOTES.md)
- **Interpreter source:** [`mopl_backend.s`](./mopl_backend.s)

## Requirements

- macOS on Apple Silicon
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Run (command line)

```bash
chmod +x build.sh
./build.sh
./mopl run examples/hello.mopl
```

## Running natively in VS Code

This repo ships a `.vscode/tasks.json` so you can run any `.mopl` file
without touching the terminal:

1. Open this folder in VS Code (`code .`).
2. Open any `.mopl` file, e.g. `examples/hello.mopl`.
3. Press **Cmd+Shift+B** to build the interpreter, or just press
   **Cmd+Shift+P → "Run Task" → "MOPL#: Run Current File"** — it builds
   automatically if `./mopl` doesn't exist yet.
4. Output appears in the integrated terminal.

### Optional: syntax highlighting extension

The `vscode-extension/` folder is a minimal VS Code extension that adds:
- `.mopl` syntax highlighting (tags, types, operators, strings)
- A "Run" button in the editor title bar for `.mopl` files
- `Cmd+R` to run the current file

To install it locally:

```bash
cd vscode-extension
npm install -g @vscode/vsce   # one-time
vsce package
code --install-extension mopl-language-0.1.0.vsix
```

Reload VS Code afterward. Any `.mopl` file will now be highlighted and
runnable via the Run button, `Cmd+R`, or the Command Palette.

## Repo layout

```
mopl_backend.s        interpreter source (ARM64 ASM)
build.sh               assembles + links ./mopl
examples/               sample .mopl scripts
.vscode/                tasks/keybindings for running .mopl files in VS Code
vscode-extension/       syntax highlighting + Run command extension
TUTORIAL.md             language tutorial
NOTES.md                implementation scope, caveats, and next steps
```



## License

MIT — see [`LICENSE`](./LICENSE).
