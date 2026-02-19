#!/usr/bin/env bash
# Run Cocoon locally. By default: worker + proxy + client + router (--local-all --test --fake-ton).
# Usage:
#   ./run-cocoon-local.sh              # full stack (proxy, worker, client, router)
#   ./run-cocoon-local.sh client-only  # client only (client + router; no proxy/worker)
# The client exposes an OpenAI-compatible API on CLIENT_HTTP_PORT (default 10000).
# Use with the bot by setting LLM_PROVIDER=cocoon and COCOON_CLIENT_URL=http://127.0.0.1:10000 in ai/backend .env.
# If the system shuts down during build, re-run this script: Ninja resumes and only rebuilds what is missing.
# To avoid OOM/overheating, limit jobs before running: export COCOON_BUILD_JOBS=4
set -euo pipefail

COCOON_MODE="${1:-full}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COCOON_DIR="${REPO_ROOT}/cocoon"

if [[ ! -d "$COCOON_DIR" ]]; then
  echo "ERROR: cocoon/ not found at $COCOON_DIR (run: git submodule update --init)"
  exit 1
fi

echo "Checking build tools (cmake, ninja, C/C++ compiler)..." >&2

# Cocoon build needs CMake, Ninja, and a C/C++ compiler. Auto-install if missing.
has_cmd() { command -v "$1" >/dev/null 2>&1; }

has_cc() {
  has_cmd clang || has_cmd gcc || has_cmd cl
}

add_to_path_if_dir() {
  local d="$1"
  if [[ -n "$d" && -d "$d" ]]; then
    export PATH="$d:$PATH"
  fi
}

is_windows_shell() {
  [[ "$(uname -s)" =~ MINGW|MSYS|CYGWIN ]] || [[ -n "${WINDIR:-}" ]]
}

# Add common Windows install paths so Git Bash sees cmake/ninja without calling cmd.exe (which can hang).
add_windows_paths() {
  if ! is_windows_shell; then
    return 0
  fi
  for p in "/c/Program Files/CMake/bin" "/c/Program Files (x86)/CMake/bin" \
           "/c/Program Files/Ninja" "/c/Program Files (x86)/Ninja" \
           "/c/Program Files/LLVM/bin" \
           "/c/msys64/mingw64/bin" "/c/msys64/ucrt64/bin" \
           "/c/Program Files/msys64/mingw64/bin" "/c/Program Files/msys64/ucrt64/bin"; do
    add_to_path_if_dir "$p"
  done
  # Prefer Unix-style path so -d and PATH work in Git Bash (LOCALAPPDATA often has backslashes).
  local local_app="${LOCALAPPDATA:-}"
  if [[ -z "$local_app" && -n "${USERNAME:-}" ]]; then
    local_app="/c/Users/$USERNAME/AppData/Local"
  elif [[ -n "$local_app" && "$local_app" == *\\* ]]; then
    local_app="/c/Users/${USERNAME:-$USER}/AppData/Local"
  fi
  if [[ -n "$local_app" ]]; then
    add_to_path_if_dir "$local_app/Programs/CMake/bin"
    add_to_path_if_dir "$local_app/Microsoft/WinGet/Links"
    # WinGet installs Ninja to versioned Packages dir; add any that contains ninja.exe
    for dir in "$local_app/Microsoft/WinGet/Packages"/Ninja*; do
      if [[ -d "$dir" && -f "$dir/ninja.exe" ]]; then
        add_to_path_if_dir "$dir"
        break
      fi
    done
  fi
}

install_build_deps() {
  if is_windows_shell; then
    # Windows: use winget if available
    if has_cmd winget; then
      echo "Installing build tools with winget (CMake, Ninja, LLVM/Clang)..." >&2
      winget install --id Kitware.CMake --exact --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity 2>/dev/null || true
      winget install --id Ninja-build.Ninja --exact --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity 2>/dev/null || true
      winget install --id LLVM.LLVM --exact --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity 2>/dev/null || true
      add_windows_paths
      return 0
    fi
    echo "WARNING: winget not found. Install CMake and Ninja manually and add them to PATH." >&2
    return 1
  fi
  # Linux / WSL
  if has_cmd apt-get; then
    echo "Installing build tools with apt (cmake, ninja-build)..."
    sudo apt-get update -qq && sudo apt-get install -y cmake ninja-build
    return 0
  fi
  if has_cmd dnf; then
    echo "Installing build tools with dnf (cmake, ninja-build)..."
    sudo dnf install -y cmake ninja-build
    return 0
  fi
  echo "WARNING: No supported package manager (apt-get/dnf). Install cmake and ninja-build manually."
  return 1
}

require_cmd() {
  if has_cmd "$1"; then return 0; fi
  # Windows: add known install paths first (no cmd.exe - it can hang in Git Bash).
  if is_windows_shell; then
    add_windows_paths
    if has_cmd "$1"; then return 0; fi
  fi
  echo "$1 not found. Attempting to install build dependencies..." >&2
  if install_build_deps; then
    if has_cmd "$1"; then return 0; fi
  fi
  echo "ERROR: $1 is still not available. Cocoon needs CMake and Ninja to build." >&2
  echo "  Windows: install CMake (https://cmake.org) and Ninja (e.g. winget install Ninja-build.Ninja), then add them to PATH and restart the terminal." >&2
  echo "  WSL/Linux: sudo apt install cmake ninja-build" >&2
  exit 1
}

require_cmd cmake
require_cmd ninja

# On Windows we require GCC (MinGW); Clang needs Windows SDK libs (kernel32.lib etc.) which are not auto-installed.
has_gcc() { has_cmd gcc; }

install_mingw_gcc() {
  local msys64=""
  for d in "/c/msys64" "/c/Program Files/msys64"; do
    if [[ -d "$d" && -x "$d/usr/bin/bash.exe" ]]; then
      msys64="$d"
      break
    fi
  done

  # If MSYS2 is not present, install via winget. If it already exists, skip winget:
  # the installer's post-install step (bash --login -c exit) triggers keyring generation
  # and can hang at 0% CPU, so we never re-run the installer when C:\msys64 exists.
  if [[ -z "$msys64" ]]; then
    if ! has_cmd winget; then
      return 1
    fi
    echo "Installing MSYS2 (first time; installer may take a few minutes)..." >&2
    winget install --id MSYS2.MSYS2 --exact --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity 2>/dev/null || true
    for wait in 1 2 3 5 8 12; do
      for d in "/c/msys64" "/c/Program Files/msys64"; do
        if [[ -d "$d" && -x "$d/usr/bin/bash.exe" ]]; then
          msys64="$d"
          break 2
        fi
      done
      [[ $wait -lt 12 ]] && sleep $wait
    done
    if [[ -z "$msys64" ]]; then
      return 1
    fi
  else
    echo "Using existing MSYS2 at $msys64 (skipping winget to avoid installer hang)." >&2
  fi

  local bash_exe="$msys64/usr/bin/bash.exe"
  # Export PATH so both pacman -Sy and pacman -S see it (otherwise second pacman gets "command not found").
  # Relax curl low-speed limit so slow/unstable networks don't hit "Operation too slow. Less than 1 bytes/sec".
  local pacman_cmd="export PATH=\"$msys64/usr/bin:$msys64/mingw64/bin:\$PATH\" && export CURL_LOW_SPEED_LIMIT=50 && export CURL_LOW_SPEED_TIME=120 && pacman -Sy --noconfirm && pacman -S --noconfirm mingw-w64-x86_64-gcc mingw-w64-x86_64-pkg-config mingw-w64-x86_64-zlib mingw-w64-x86_64-jemalloc mingw-w64-x86_64-openssl mingw-w64-x86_64-lz4 mingw-w64-x86_64-libsodium"
  if [[ -x "$bash_exe" ]]; then
    echo "Installing mingw-w64-x86_64-gcc via pacman (max 15 min; slow connections allowed)..." >&2
    if has_cmd timeout; then
      timeout 900 "$bash_exe" -c "$pacman_cmd" || true
    else
      "$bash_exe" -c "$pacman_cmd" || true
    fi
    # Retry once on failure (often transient "Operation too slow" or mirror hiccup).
    if ! has_gcc; then
      echo "Retrying pacman install once..." >&2
      if has_cmd timeout; then
        timeout 900 "$bash_exe" -c "$pacman_cmd" || true
      else
        "$bash_exe" -c "$pacman_cmd" || true
      fi
    fi
  fi
  add_windows_paths
  return 0
}

require_cc() {
  if is_windows_shell; then
    # On Windows require GCC so we don't need Visual Studio / Windows SDK.
    add_windows_paths
    if has_gcc; then return 0; fi
    echo "GCC (MinGW) not found. Attempting to install MSYS2 + MinGW GCC..." >&2
    if install_mingw_gcc && has_gcc; then
      return 0
    fi
    echo "ERROR: GCC is required on Windows (Clang needs Visual Studio Build Tools)." >&2
    if [[ -d "/c/msys64" || -d "/c/Program Files/msys64" ]]; then
      echo "" >&2
      echo "  MSYS2 is installed but GCC was not. Run this manually in 'MSYS2 MinGW 64-bit' (Start Menu):" >&2
      echo "    pacman -Sy --noconfirm && pacman -S --noconfirm mingw-w64-x86_64-gcc" >&2
      echo "  Then run this script again." >&2
    else
      echo "  Install Git for Windows (includes MinGW), or MSYS2 then run: pacman -S mingw-w64-x86_64-gcc" >&2
    fi
    exit 1
  fi
  # Linux / WSL
  if has_cc; then return 0; fi
  if has_cmd apt-get; then
    echo "Installing C/C++ compiler (build-essential)..." >&2
    sudo apt-get update -qq && sudo apt-get install -y build-essential 2>/dev/null || true
    if has_cc; then return 0; fi
  fi
  echo "ERROR: No C/C++ compiler found. Cocoon needs gcc or clang to build." >&2
  echo "  WSL/Linux: sudo apt install build-essential" >&2
  exit 1
}
require_cc

# Use GCC and force re-configure so CMake does not use a previously cached Clang.
if is_windows_shell && has_gcc; then
  gcc_dir="$(dirname "$(command -v gcc)")"
  export PATH="$gcc_dir:$PATH"
  export CC=gcc
  export CXX=g++
  # So CMake finds ZLIB, RocksDB, etc. in MSYS2 MinGW (FindZLIB does not search mingw64 by default on Windows).
  if [[ "$gcc_dir" == *msys64* ]]; then
    msys_root="${gcc_dir%/mingw64/bin}"
    export CMAKE_PREFIX_PATH="${msys_root}/mingw64${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
    # So ninja can run blst's build.sh via bash
    export PATH="${msys_root}/usr/bin:$PATH"
  fi
  if [[ "$gcc_dir" == *msys64* ]]; then
    need_deps=""
    has_cmd pkg-config || need_deps="mingw-w64-x86_64-pkg-config"
    # Check for zlib and jemalloc (Cocoon build needs them)
    for d in "/c/msys64" "/c/Program Files/msys64"; do
      if [[ -d "$d/mingw64/include" ]]; then
        [[ -f "$d/mingw64/include/zlib.h" ]] || need_deps="$need_deps mingw-w64-x86_64-zlib"
        [[ -f "$d/mingw64/include/jemalloc/jemalloc.h" ]] || need_deps="$need_deps mingw-w64-x86_64-jemalloc"
        [[ -d "$d/mingw64/include/openssl" ]] || need_deps="$need_deps mingw-w64-x86_64-openssl"
        [[ -f "$d/mingw64/include/lz4.h" ]] || need_deps="$need_deps mingw-w64-x86_64-lz4"
        [[ -f "$d/mingw64/include/sodium.h" ]] || need_deps="$need_deps mingw-w64-x86_64-libsodium"
        break
      fi
    done
    if [[ -n "$need_deps" ]]; then
      for d in "/c/msys64" "/c/Program Files/msys64"; do
        if [[ -x "$d/usr/bin/bash.exe" ]]; then
          echo "Installing Cocoon build deps (pkg-config, zlib, jemalloc, openssl, etc.)..." >&2
          export CURL_LOW_SPEED_LIMIT=50 CURL_LOW_SPEED_TIME=120
          PATH="$d/usr/bin:$d/mingw64/bin:$PATH" "$d/usr/bin/bash.exe" -c "pacman -Sy --noconfirm && pacman -S --noconfirm mingw-w64-x86_64-pkg-config mingw-w64-x86_64-zlib mingw-w64-x86_64-jemalloc mingw-w64-x86_64-openssl mingw-w64-x86_64-lz4 mingw-w64-x86_64-libsodium" 2>/dev/null || true
          add_windows_paths
          break
        fi
      done
    fi
  fi
  # Avoid deleting CMakeCache.txt/build.ninja here: it triggers ninja -t restat during
  # regenerate, which can hit "Permission denied" if the build dir is locked.
  # For a clean GCC reconfig, remove cocoon/cmake-build-default-tdx manually and re-run.
fi

cd "$COCOON_DIR"
if [[ "$COCOON_MODE" == "client-only" ]]; then
  echo "Starting Cocoon (client only) in $COCOON_DIR ..." >&2
else
  echo "Starting Cocoon (worker + proxy + client) in $COCOON_DIR ..." >&2
fi
echo "Client HTTP API will be on http://127.0.0.1:10000 (CLIENT_HTTP_PORT) unless overridden." >&2
# Use a separate build dir on Windows to avoid "ninja: failed recompaction: Permission denied"
# when the default build dir is locked. Use cmake-build-tdx2 so we don't touch a possibly locked dir.
if is_windows_shell && [[ -z "${BUILD_DIR:-}" ]]; then
  export BUILD_DIR="${COCOON_DIR}/cmake-build-tdx2"
fi
# Default to 1 job on low-memory machines to avoid compiler OOM (cc1plus: out of memory).
# Override with COCOON_BUILD_JOBS=4 (or higher) if you have enough RAM.
export COCOON_BUILD_JOBS="${COCOON_BUILD_JOBS:-1}"
echo "Build jobs: -j ${COCOON_BUILD_JOBS} (set COCOON_BUILD_JOBS=4+ if you have enough RAM)." >&2
export PATH
if [[ "$COCOON_MODE" == "client-only" ]]; then
  exec python3 scripts/cocoon-launch --type client --test --fake-ton
else
  exec python3 scripts/cocoon-launch --local-all --test --fake-ton
fi
