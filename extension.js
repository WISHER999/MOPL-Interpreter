const vscode = require('vscode');
const path = require('path');
const { exec } = require('child_process');

function activate(context) {
  const runFile = vscode.commands.registerCommand('mopl.runFile', () => {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
      vscode.window.showErrorMessage('No active .mopl file to run.');
      return;
    }
    const filePath = editor.document.fileName;
    const workspaceFolder = vscode.workspace.getWorkspaceFolder(editor.document.uri);
    if (!workspaceFolder) {
      vscode.window.showErrorMessage('Open the mopl-interpreter folder as your workspace (needs the built ./mopl binary).');
      return;
    }
    const cwd = workspaceFolder.uri.fsPath;
    const moplBinary = path.join(cwd, 'mopl');

    const terminal = vscode.window.terminals.find(t => t.name === 'MOPL#') ||
      vscode.window.createTerminal('MOPL#');
    terminal.show(true);

    // Build first if the binary doesn't exist yet, then run.
    terminal.sendText(
      `test -f "${moplBinary}" || (cd "${cwd}" && bash build.sh); "${moplBinary}" run "${filePath}"`
    );
  });

  context.subscriptions.push(runFile);
}

function deactivate() {}

module.exports = { activate, deactivate };
