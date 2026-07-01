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
full_version="$(dpkg-parsechangelog -l "${debian_dir}/changelog" --show-field Version)"
distribution="$(dpkg-parsechangelog -l "${debian_dir}/changelog" --show-field Distribution)"
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

    # Local follow-up patches that fix bugs in the upstream CIX patch set.
    # Tracked in debian/patches/cix-fixups/ and applied after cix/*.
    local fixups_dir="${src_tree}/debian/patches/cix-fixups"
    if [[ -d "${fixups_dir}" ]] && compgen -G "${fixups_dir}/*.patch" >/dev/null; then
        if ! grep -q '^# CIX fixups$' "${series_file}"; then
            {
                echo ""
                echo "# CIX fixups"
            } >> "${series_file}"
        fi
        for p in "${fixups_dir}"/*.patch; do
            printf 'cix-fixups/%s\n' "$(basename "$p")" >> "${series_file}"
        done
        echo "Appended $(ls "${fixups_dir}" | wc -l) CIX fixup patches to debian/patches/series"
    fi
}

regenerate_control() {
    echo "Regenerating debian/control via gencontrol.py"

    # gencontrol.py reads debian/build/version-info for the package version.
    # The md5sum of this file is tracked in debian/control.md5sum, so the
    # content must match exactly.
    mkdir -p "${src_tree}/debian/build"
    cat > "${src_tree}/debian/build/version-info" <<EOF
Source: ${package_name}
Version: ${full_version}
Distribution: ${distribution}
EOF

    # Regenerate debian/control from debian/config/defines.toml (which
    # carries the c_compiler = 'gcc-14' override for trixie).
    ( cd "${src_tree}" && PYTHONHASHSEED=0 debian/bin/gencontrol.py )

    # debian/control-real-fail regenerates debian/control.md5sum and then
    # exits 1 by design. The md5sum file is now correct for the current
    # source tree (including the gcc-14 defines.toml and staged CIX patches).
    ( cd "${src_tree}" && make -f debian/rules debian/control-real-fail ) || true

    # Verify the md5sum now passes.
    ( cd "${src_tree}" && md5sum --check debian/control.md5sum --status ) \
        || { echo "debian/control.md5sum verification failed" >&2; exit 1; }

    # gencontrol.py leaves __pycache__ directories that dpkg-source rejects.
    find "${src_tree}/debian" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    echo "debian/control regenerated and verified"
}

fetch_upstream_tarball
extract_upstream
install_debian_dir
prepare_patch_repo
stage_cix_patches
regenerate_control

cat <<EOF

Source tree prepared:
  ${src_tree}

Next steps on Debian 13 (trixie):
  cd ${src_tree}
  dpkg-source -b .
  # then build in a clean chroot:
  sbuild -d trixie --arch=arm64 --no-arch-all --no-source ../${package_name}_${full_version}.dsc
EOF
