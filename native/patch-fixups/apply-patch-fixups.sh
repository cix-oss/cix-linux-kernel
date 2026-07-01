#!/usr/bin/env bash
# Apply local fixups to upstream CIX patches before they get applied to the
# kernel source tree. Idempotent — re-running must not corrupt already-fixed
# patches.
#
# Usage: apply-patch-fixups.sh <patch-repo-root> <kernel-series>
#   patch-repo-root: path to the cloned cixtech/cix-linux-main checkout
#   kernel-series:   e.g. "7.0" (selects patches-<series>/)
set -euo pipefail

patch_repo="${1:?missing patch-repo path}"
series="${2:?missing kernel-series}"
patchset_dir="${patch_repo}/patches-${series}"

[[ -d "${patchset_dir}" ]] || { echo "patch set not found: ${patchset_dir}" >&2; exit 1; }

fixup_0033_is_err() {
    # 0033-regulator-add-acpi-support.patch: IS_ERR() called on int.
    # Replace with a `< 0` check (the surrounding code already does
    # `max(n_phandles, 0)` so this is the intended semantic).
    local p="${patchset_dir}/0033-regulator-add-acpi-support.patch"
    [[ -f "$p" ]] || { echo "  skip 0033: file not present"; return; }
    if grep -q '+\s*if (IS_ERR(n_phandles))' "$p"; then
        sed -i 's|+\(\s*\)if (IS_ERR(n_phandles))|+\1if (n_phandles < 0)|' "$p"
        echo "  fixed 0033-regulator-add-acpi-support.patch (IS_ERR on int)"
    else
        echo "  skip 0033: already fixed or upstream changed"
    fi
}

echo "Applying patch fixups in ${patchset_dir}"
fixup_0033_is_err
echo "Patch fixups done."
