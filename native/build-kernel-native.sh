#!/usr/bin/env bash
# Build a CIX-patched Linux kernel as Debian packages using the kernel's own
# `make bindeb-pkg` flow.
#
# Required environment: Debian 13 (trixie) on arm64, native build (no
# cross-compile). Run from any working directory; outputs go to ./output by
# default.
#
# Usage:
#   ./build-kernel-native.sh                 # build the default CIX-tracked release
#   KERNEL_VERSION=7.0.13 ./build-kernel-native.sh
set -euo pipefail

KERNEL_VERSION="${KERNEL_VERSION:-7.0.13}"
KERNEL_SERIES="${KERNEL_SERIES:-7.0}"

WORK_DIR="${WORK_DIR:-${PWD}/work}"
OUTPUT_DIR="${OUTPUT_DIR:-${PWD}/output}"

PATCH_REMOTE="${PATCH_REMOTE:-https://github.com/cixtech/cix-linux-main.git}"
PATCH_BRANCH="${PATCH_BRANCH:-main}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXUPS_SCRIPT="${SCRIPT_DIR}/patch-fixups/apply-patch-fixups.sh"

KERNEL_TARBALL_URL="${KERNEL_TARBALL_URL:-https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_SERIES%%.*}.x/linux-${KERNEL_VERSION}.tar.xz}"

KERNEL_TARBALL="${WORK_DIR}/linux-${KERNEL_VERSION}.tar.xz"
KERNEL_DIR="${WORK_DIR}/linux-${KERNEL_VERSION}"
PATCH_DIR="${WORK_DIR}/cix-linux-main"
PATCHSET_DIR="${PATCH_DIR}/patches-${KERNEL_SERIES}"
DEFCONFIG="${PATCH_DIR}/config/config-${KERNEL_SERIES}.defconfig"

for cmd in make gcc git tar curl; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 1; }
done

mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"

fetch_kernel_tarball() {
    if [[ -f "${KERNEL_TARBALL}" ]]; then
        echo "Using existing kernel tarball: ${KERNEL_TARBALL}"
        return
    fi
    echo "Downloading kernel tarball: ${KERNEL_TARBALL_URL}"
    curl -fL --retry 3 -o "${KERNEL_TARBALL}.tmp" "${KERNEL_TARBALL_URL}"
    sync "${KERNEL_TARBALL}.tmp"
    xz -t "${KERNEL_TARBALL}.tmp"
    mv "${KERNEL_TARBALL}.tmp" "${KERNEL_TARBALL}"
}

extract_kernel_source() {
    rm -rf "${KERNEL_DIR}"
    echo "Extracting ${KERNEL_TARBALL}"
    tar -xf "${KERNEL_TARBALL}" -C "${WORK_DIR}"
    [[ -d "${KERNEL_DIR}" ]] || { echo "Extracted directory not found: ${KERNEL_DIR}" >&2; exit 1; }
}

prepare_patch_repo() {
    if [[ -d "${PATCH_DIR}/.git" ]]; then
        echo "Updating existing patch repo: ${PATCH_DIR}"
        git -C "${PATCH_DIR}" fetch --depth 1 origin "${PATCH_BRANCH}"
        git -C "${PATCH_DIR}" reset --hard "origin/${PATCH_BRANCH}"
    else
        rm -rf "${PATCH_DIR}"
        echo "Cloning ${PATCH_BRANCH} from ${PATCH_REMOTE}"
        git clone --depth 1 --branch "${PATCH_BRANCH}" --single-branch "${PATCH_REMOTE}" "${PATCH_DIR}"
    fi

    [[ -d "${PATCHSET_DIR}" ]] || { echo "Patch set not found for series ${KERNEL_SERIES}: ${PATCHSET_DIR}" >&2; exit 1; }
    [[ -f "${DEFCONFIG}" ]] || { echo "defconfig not found: ${DEFCONFIG}" >&2; exit 1; }

    if [[ -x "${FIXUPS_SCRIPT}" ]]; then
        "${FIXUPS_SCRIPT}" "${PATCH_DIR}" "${KERNEL_SERIES}"
    fi
}

apply_patches() {
    cd "${KERNEL_DIR}"
    git init -q
    git -c user.name=build -c user.email=build@localhost -c commit.gpgsign=false \
        add -A
    git -c user.name=build -c user.email=build@localhost -c commit.gpgsign=false \
        commit -qm "import linux-${KERNEL_VERSION}"
    git -c user.name=build -c user.email=build@localhost -c commit.gpgsign=false \
        am --whitespace=nowarn "${PATCHSET_DIR}"/*.patch
}

configure_kernel() {
    cp "${DEFCONFIG}" "${KERNEL_DIR}/.config"
    make -C "${KERNEL_DIR}" ARCH=arm64 olddefconfig
}

build_packages() {
    make -C "${KERNEL_DIR}" -j"$(nproc)" LOCALVERSION=-cix bindeb-pkg
}

collect_artifacts() {
    shopt -s nullglob
    local moved=0
    for deb in "${WORK_DIR}"/linux-*.deb "${WORK_DIR}"/linux-*.buildinfo "${WORK_DIR}"/linux-*.changes; do
        mv -f "$deb" "${OUTPUT_DIR}/"
        moved=1
    done
    shopt -u nullglob
    if [[ ${moved} -eq 0 ]]; then
        echo "No deb artifacts found in ${WORK_DIR}" >&2
        exit 1
    fi
}

fetch_kernel_tarball
extract_kernel_source
prepare_patch_repo
apply_patches
configure_kernel
build_packages
collect_artifacts

echo "Done. Artifacts in: ${OUTPUT_DIR}"
ls -lh "${OUTPUT_DIR}"
