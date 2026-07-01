# Patch fixups (native flow only)

This directory holds local hotfixes applied to upstream CIX patches *before*
they are applied to the kernel source tree. It exists only for the
`native/` build flow, which uses `git am` and therefore needs the patch
files themselves to be correct.

The `debian-pkg/` flow uses Debian's `3.0 (quilt)` source format and instead
ships follow-up fixes as ordinary patches in
`debian-pkg/debian/patches/cix-fixups/`, appended to `debian/patches/series`
after the CIX patches.

Each fixup here is a short shell snippet (sed/grep) that rewrites a specific
patch file in the cloned `cix-linux-main` checkout. `native/build-kernel-native.sh`
invokes `apply-patch-fixups.sh` after cloning the CIX patch repo and before
applying patches to the kernel tree. Fixups are intentionally local: they
unblock builds on Debian 13 (trixie) toolchains while the real fix is pending
upstream.

Each fixup MUST be idempotent — re-running the script must not corrupt
already-fixed patches.

## Active fixups

### `0033-regulator-add-acpi-support.patch`

`drivers/regulator/fwnode_regulator.c` calls `IS_ERR()` on an `int` return
value of `fwnode_count_reference_with_args()`. Debian 13's GCC defaults to
`-Werror=int-conversion`, which turns this into a hard build error. The
follow-up `max(n_phandles, 0)` shows the intent was to clamp negative error
returns to zero, so the fixup replaces the bogus `IS_ERR()` check with a
proper `< 0` test.

The equivalent follow-up patch for the `debian-pkg/` flow lives at
`debian-pkg/debian/patches/cix-fixups/0001-regulator-fix-IS_ERR-on-int.patch`.

Upstream issue: not yet reported to `cixtech/cix-linux-main`.

