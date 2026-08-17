const vscode = require('vscode');

function activate(context) {
  const runFile = vscode.commands.registerCommand('mopl.runFile', () => {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
      vscode.window.showErrorMessage('No active .mopl file to run.');
      return;
    }

    const filePath = editor.document.fileName;

    const terminal = vscode.window.terminals.find(t => t.name === 'MOPL#') ||
      vscode.window.createTerminal('MOPL#');
    terminal.show(true);

    // Runs mopl globally from anywhere on your Mac!
    terminal.sendText(`mopl run "${filePath}"`);
  });

  context.subscriptions.push(runFile);
}

function deactivate() {}

module.exports = { activate, deactivate };