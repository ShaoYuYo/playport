#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# GitHub Linux runner setup for PlayPort's KosmicKrisp / Mesa host tools.
# Mesa requires Meson >=1.9.1 and LLVM-matched SPIRV-LLVM-Translator.
# Called only by the separate cloud-build workspace, not by pp itself.
set -euo pipefail

# This script expects the apt.llvm.org Noble LLVM 22 repository to be enabled.
# Do not silently fall back to the host distro's (much older) LLVM.
test -x /usr/lib/llvm-22/bin/llvm-config
test -x /usr/lib/llvm-22/bin/clang
sudo apt-get install -y --no-install-recommends \
    python3-venv python3-pip libclang-22-dev libclc-22-dev \
    spirv-tools libelf-dev libexpat1-dev libzstd-dev

# Mesa's own KosmicKrisp documentation specifies 1.9.1+, whereas
# Ubuntu 24.04's apt package provides only 1.3.x.
ENV_ROOT="${PLAYPORT_MESA_VENV:-$PWD/.work/inputs/mesa-venv}"
python3 -m venv "$ENV_ROOT"
"$ENV_ROOT/bin/pip" install --disable-pip-version-check --no-cache-dir \
    "meson==1.9.1" "mako" "PyYAML" "packaging"
export PATH="$ENV_ROOT/bin:$PATH"
echo "$ENV_ROOT/bin" >> "${GITHUB_PATH:-/dev/null}"
meson --version
test "$(meson --version)" = 1.9.1

# Ubuntu 24.04's spirv-tools *itself* contains headers, static archives,\n# and SPIRV-Tools.pc; no spirv-tools-dev package exists for Noble.\n# The packaged SPIR-V Tools must actually provide a recent enough
# pkg-config description; command-line spirv-val alone isn't sufficient.
pkg-config --atleast-version=2024.1 SPIRV-Tools || {
    echo 'Mesa needs SPIRV-Tools >= 2024.1 with development libraries' >&2
    exit 1
}
pkg-config --modversion SPIRV-Tools
if ! pkg-config --exists LLVMSPIRVLib ||
    ! pkg-config --atleast-version=22.1 LLVMSPIRVLib; then
    # Ubuntu Noble doesn't provide the LLVM 22 translator development
    # package, so use upstream's LLVM-22 release branch and public headers.
    SRC="$PWD/.work/inputs/spirv-llvm-translator"
    git clone -q --depth 1 --branch llvm_release_220 \
        https://github.com/KhronosGroup/SPIRV-LLVM-Translator.git "$SRC"
    cmake -S "$SRC" -B "$SRC/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_DIR=/usr/lib/llvm-22/lib/cmake/llvm \
        -DLLVM_SPIRV_BUILD_EXTERNAL=YES \
        -DCMAKE_INSTALL_PREFIX=/usr/local
    ninja -C "$SRC/build" -j "${JOBS:-3}"
    sudo ninja -C "$SRC/build" install
    sudo ldconfig
fi
pkg-config --modversion LLVMSPIRVLib
LLVM_VERSION="$(/usr/lib/llvm-22/bin/llvm-config --version)"
SPIRV_VERSION="$(pkg-config --modversion LLVMSPIRVLib)"
LLVM_MM="$(echo "$LLVM_VERSION" | cut -d. -f1-2)"
SPIRV_MM="$(echo "$SPIRV_VERSION" | cut -d. -f1-2)"
if [ "$LLVM_MM" != "$SPIRV_MM" ]; then
    echo "LLVM $LLVM_VERSION and LLVMSPIRVLib $SPIRV_VERSION are incompatible" >&2
    exit 1
fi
echo "PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}" >> "${GITHUB_ENV:-/dev/null}"
echo "Mesa dependencies ready: Meson $(meson --version), LLVM $LLVM_VERSION, translator $SPIRV_VERSION"
