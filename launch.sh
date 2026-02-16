#!/bin/bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS_SCRIPT="$ROOT_DIR/shell/launch.ps1"

if [ ! -f "$PS_SCRIPT" ]; then
  echo "Error: shell/launch.ps1 not found at $PS_SCRIPT"
  exit 1
fi

if command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT"
  exit $?
fi

if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -File "$PS_SCRIPT"
  exit $?
fi

echo "Error: PowerShell is required to launch parallel deploy terminals."
exit 1
