#!/usr/bin/env bash
# Prepare a source tree for Debian-style kernel package builds with CIX
# patches.
#
# The repository ships a verbatim copy of Debian's linux source-package
# `debian/` directory (3.0 quilt). This script fetches the matching upstream
# tarball, applies the `debian/` overlay, clones the CIX patch repo, copies
# its patches into `debian/patches/cix/`, and appends them to
# `debian/patches/series`. The resulting tree is ready for
# `dpkg-buildpackage -us -uc` or `sbuild -d trixie`.
#
# Required environment: Debian 13 (trixie). Run from any working directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PATCH_REMOTE="${PATCH_REMOTE:-https://github.com/cixtech/cix-linux-main.git}"
PATCH_BRANCH="${PATCH_BRANCH:-main}"

WORK_DIR="${WORK_DIR:-${PWD}/work}"

debian_dir="${SCRIPT_DIR}/debian"
[[ -d "${debian_dir}" ]] || { echo "debian/ directory not found at ${debian_dir}" >&2; exit 1; }

upstream_version="$(dpkg-parsechangelog -l "${debian_dir}/changelog" --show-field Version | sed -E 's/-[^-]+$//')"
series="${upstream_version%.*}"
package_name="$(dpkg-parsechangelog -l "${debian_dir}/changelog" --show-field Source)"

KERNEL_TARBALL_URL="${KERNEL_TARBALL_URL:-https://cdn.kernel.org/pub/linux/kernel/v${series%%.*}.x/linux-${upstream_version}.tar.xz}"

mkdir -p "${WORK_DIR}"

orig_tarball="${WORK_DIR}/${package_name}_${upstream_version}.orig.tar.xz"
src_tree="${WORK_DIR}/${package_name}-${upstream_version}"
patch_repo="${WORK_DIR}/cix-linux-main"
cix_patch_set="${patch_repo}/patches-${series}"

fetch_upstream_tarball() {
    if [[ -f "${orig_tarball}" ]]; then
        echo "Using existing tarball: ${orig_tarball}"
        return
    fi
    echo "Downloading ${KERNEL_TARBALL_URL}"
    curl -fL --retry 3 -o "${orig_tarball}.tmp" "${KERNEL_TARBALL_URL}"
    sync "${orig_tarball}.tmp"
    xz -t "${orig_tarball}.tmp"
    mv "${orig_tarball}.tmp" "${orig_tarball}"
}

extract_upstream() {
    rm -rf "${src_tree}"
    echo "Extracting upstream into ${src_tree}"
    tar -xf "${orig_tarball}" -C "${WORK_DIR}"
    [[ -d "${src_tree}" ]] || { echo "Extracted tree not found: ${src_tree}" >&2; exit 1; }
}

install_debian_dir() {
    echo "Installing debian/ overlay"
    cp -a "${debian_dir}" "${src_tree}/debian"
}

prepare_patch_repo() {
    if [[ -d "${patch_repo}/.git" ]]; then
        echo "Updating patch repo ${patch_repo}"
        git -C "${patch_repo}" fetch --depth 1 origin "${PATCH_BRANCH}"
        git -C "${patch_repo}" reset --hard "origin/${PATCH_BRANCH}"
    else
        rm -rf "${patch_repo}"
        echo "Cloning ${PATCH_BRANCH} from ${PATCH_REMOTE}"
        git clone --depth 1 --branch "${PATCH_BRANCH}" --single-branch "${PATCH_REMOTE}" "${patch_repo}"
    fi
    [[ -d "${cix_patch_set}" ]] || { echo "CIX patch set not found: ${cix_patch_set}" >&2; exit 1; }
}

stage_cix_patches() {
    local dst="${src_tree}/debian/patches/cix"
    rm -rf "${dst}"
    mkdir -p "${dst}"
    cp "${cix_patch_set}"/*.patch "${dst}/"

    local series_file="${src_tree}/debian/patches/series"
    if ! grep -q '^# CIX patches$' "${series_file}" 2>/dev/null; then
        {
            echo ""
            echo "# CIX patches"
        } >> "${series_file}"
    fi
    for p in "${dst}"/*.patch; do
        printf 'cix/%s\n' "$(basename "$p")" >> "${series_file}"
    done
    echo "Appended $(ls "${dst}" | wc -l) CIX patches to debian/patches/series"
}

fetch_upstream_tarball
extract_upstream
install_debian_dir
prepare_patch_repo
stage_cix_patches

cat <<EOF

Source tree prepared:
  ${src_tree}

Next steps on Debian 13:
  cd ${src_tree}
  dpkg-buildpackage -us -uc -b           # local build
  # or, for clean chroot builds on radxa-32g:
  sbuild -d trixie ../${package_name}_${upstream_version}-*.dsc
EOF
