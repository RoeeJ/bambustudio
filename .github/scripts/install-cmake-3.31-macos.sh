#!/bin/bash
# Install CMake 3.31.0 on a GitHub macOS runner.
#
# Homebrew's curl is linked against /opt/homebrew/opt/zstd/lib/libzstd.1.dylib.
# If that library is missing, every brew download fails, including the
# cmake@3.31.0 formula (whose legacy mirror is plain HTTP on fresh-center.net).
# Repair zstd and curl first. If the formula install still fails, use the
# official Kitware 3.31.0 macOS binary via the system curl, which does not
# depend on Homebrew's zstd.
#
# Source this script so a fallback cmake stays on PATH in the caller.

# `brew install` exits 0 when the keg is already present, even if the dylib
# curl needs was deleted. Reinstall in that case.
zstd_prefix="$(brew --prefix zstd 2>/dev/null || true)"
if [ -z "$zstd_prefix" ] || [ ! -e "$zstd_prefix/lib/libzstd.1.dylib" ]; then
    brew install zstd || brew reinstall zstd
fi
brew reinstall curl

brew unlink cmake || true

installed=0
if brew tap-new "$USER/old-cmake" && brew extract --version=3.31.0 cmake "$USER/old-cmake"; then
    formula="$(find "$(brew --repository)/Library/Taps" -path '*old-cmake*' -name 'cmake@3.31.0.rb' -print -quit || true)"
    if [ -n "$formula" ]; then
        # Same tarball as the formula's sha256. Drop the unreliable HTTP mirror.
        perl -i -pe 's#http://fresh-center\.net/[^"[:space:]]+#https://github.com/Kitware/CMake/releases/download/v3.31.0/cmake-3.31.0.tar.gz#g' "$formula"
    fi
    if brew install "$USER/old-cmake/cmake@3.31.0"; then
        brew link --overwrite cmake@3.31.0
        brew pin cmake@3.31.0
        installed=1
    fi
fi

if [ "$installed" -ne 1 ]; then
    echo "brew cmake@3.31.0 failed; installing the Kitware 3.31.0 macOS binary"
    tmp="$(mktemp -d)"
    /usr/bin/curl --fail --location --retry 5 --retry-delay 2 \
        --output "$tmp/cmake.tar.gz" \
        "https://github.com/Kitware/CMake/releases/download/v3.31.0/cmake-3.31.0-macos-universal.tar.gz"
    tar -xzf "$tmp/cmake.tar.gz" -C "$tmp"
    cmake_bin="$(find "$tmp" -type f -path '*/bin/cmake' -print -quit)"
    if [ -z "$cmake_bin" ]; then
        echo "Kitware archive did not contain a cmake binary" >&2
        exit 1
    fi
    bindir="$(cd "$(dirname "$cmake_bin")" && pwd)"
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$bindir/cmake" "$HOME/.local/bin/cmake"
    ln -sfn "$bindir/cpack" "$HOME/.local/bin/cpack"
    ln -sfn "$bindir/ctest" "$HOME/.local/bin/ctest"
    export PATH="$HOME/.local/bin:$PATH"
    if [ -n "${GITHUB_PATH:-}" ]; then
        echo "$HOME/.local/bin" >> "$GITHUB_PATH"
    fi
fi

cmake --version
cmake --version | grep -q 'version 3\.31\.0'
