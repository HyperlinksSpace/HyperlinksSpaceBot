#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   source shell/activate-tools.sh
#
# This script wires common dev tools needed for this repo:
# - Exposes GitHub CLI from Windows install into PATH (WSL)
# - Creates/activates services/unified virtualenv
# - Installs services/unified Python requirements (including pytest)
#
# Optional:
#   TOOLS_NO_INSTALL=1 source shell/activate-tools.sh
#   (skip pip install and only activate PATH/venv)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Run with: source shell/activate-tools.sh"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GH_WIN_PATH="/mnt/c/Program Files/GitHub CLI/gh.exe"

if [[ -x "${GH_WIN_PATH}" ]]; then
  TOOLS_BIN="${REPO_ROOT}/.tools/bin"
  mkdir -p "${TOOLS_BIN}"
  cat > "${TOOLS_BIN}/gh" <<EOF
#!/usr/bin/env bash
"${GH_WIN_PATH}" "\$@"
EOF
  chmod +x "${TOOLS_BIN}/gh"
  export PATH="${TOOLS_BIN}:${PATH}"
  echo "gh: enabled via ${TOOLS_BIN}/gh"
else
  echo "gh: not found at ${GH_WIN_PATH}"
fi

UNIFIED_DIR="${REPO_ROOT}/services/unified"
VENV_DIR="${UNIFIED_DIR}/.venv"

if [[ -d "${UNIFIED_DIR}" ]]; then
  if [[ ! -d "${VENV_DIR}" ]]; then
    python3 -m venv "${VENV_DIR}"
    echo "python venv: created at ${VENV_DIR}"
  fi

  # shellcheck disable=SC1091
  source "${VENV_DIR}/bin/activate"

  if [[ "${TOOLS_NO_INSTALL:-0}" != "1" ]]; then
    if python -m pip install -r "${UNIFIED_DIR}/requirements.txt" >/dev/null; then
      echo "python deps: installed from services/unified/requirements.txt"
    else
      echo "python deps: install skipped/failed (offline or index unavailable)"
    fi
  else
    echo "python deps: skipped (TOOLS_NO_INSTALL=1)"
  fi

  echo "python: $(python --version)"
  if command -v pytest >/dev/null 2>&1; then
    echo "pytest: $(pytest --version)"
  else
    echo "pytest: not found in current env (run pip install -r services/unified/requirements.txt)"
  fi
  echo "venv: activated (${VIRTUAL_ENV})"
else
  echo "services/unified not found, skipped python setup"
fi
