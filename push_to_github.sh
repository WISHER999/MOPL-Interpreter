#!/bin/bash
# Run this from inside the mopl-interpreter folder, on your own machine,
# after creating an empty repo on GitHub (no README/license — this repo
# already has them).
#
# Usage: ./push_to_github.sh <your-github-username> [repo-name]
set -e

USERNAME="$1"
REPO="${2:-MOPL-Interpreter}"

if [ -z "$USERNAME" ]; then
  echo "Usage: ./push_to_github.sh <your-github-username> [repo-name]"
  exit 1
fi

git init
git add .
git commit -m "Initial commit: MOPL# interpreter (ARM64 ASM) + VS Code support"
git branch -M main
git remote add origin "https://github.com/${USERNAME}/${REPO}.git"
git push -u origin main

echo "Pushed to https://github.com/${USERNAME}/${REPO}"
