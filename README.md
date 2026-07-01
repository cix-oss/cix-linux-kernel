# cix-linux-kernel

Build the upstream Linux kernel with CIX patches as Debian packages for the
CIX CD8180 / Sky1 family of SoCs (e.g. Radxa Orion O6).

This repository contains **no kernel source code**. It is a thin build
harness that fetches:

- A mainline / stable Linux tarball from `https://cdn.kernel.org/`.
- CIX patches from <https://github.com/cixtech/cix-linux-main>.

## Compatibility

The CIX patch set and build harness are **verified against Linux 7.0.13**.
They should work on other 7.0.x releases, but kernel internals change between
stable releases and patch conflicts may arise. If a patch fails to apply,
developers are expected to adjust the offending patch manually.

## Two build flows

| Directory | Flow | Output |
| --- | --- | --- |
| [`native/`](native/) | `make bindeb-pkg` from the kernel source tree | Raw `linux-image-*`, `linux-headers-*`, `linux-libc-dev-*` debs |
| [`debian-pkg/`](debian-pkg/) | Debian `linux` packaging + CIX patches | Full Debian kernel package set (image, headers, tools, libc-dev) |

Both flows target **Debian 13 (trixie)** on **arm64**.

## Native build (`make bindeb-pkg`)

Uses the CIX defconfig (`config-7.0.defconfig` from `cix-linux-main`),
which includes only the drivers and features needed for CIX hardware.
Suitable for kernel development, quick iteration, or for users who want
a small set of debs without Debian's full packaging machinery.
Build typically takes 10–20 minutes.

```bash
cd native
./build-kernel-native.sh
```

Outputs land in `native/output/`.

## Debian package build (`debian/` + quilt)

Takes the `debian/` directory from Debian's `linux` source package, modifies
it with CIX-specific patches and config, and builds full Debian kernel
packages. The `debian/` directory provides Debian's `3.0 (quilt)` layout,
configs, signing templates, and `debian/patches/` quilt series. CIX patches
are staged into `debian/patches/cix/` and appended to the series.

The kernel config is a superset: Debian's default arm64 config plus all
CIX-specific options from the native defconfig. This means the resulting
packages include all CIX drivers alongside Debian's full hardware support.

Build typically takes 1–2 hours due to the large number of drivers
included in the Debian arm64 config.

> **Note:** When building with sbuild, disable lintian (`$run_lintian = 0`
> in sbuild config) for kernel builds. The large package set (70+ debs)
> can exhaust `/tmp` space during lintian's unpacking. Run lintian
> manually after the build:
> ```bash
> TMPDIR=/var/tmp/sbuild lintian -I *.changes
> ```

### Prerequisites

```bash
sudo apt build-dep linux
```

### Build

```bash
cd debian-pkg
./prepare-source.sh
cd work/linux-<version>
dpkg-source -b .
# Standard build:
dpkg-buildpackage -us -uc -b
# Or with sbuild for a clean chroot environment:
sbuild -d trixie ../linux_*.dsc
```

To skip the large debug symbols package (`linux-image-*-dbg`, ~1 GB), use
the `nokerneldbg` build profile:

```bash
DEB_BUILD_PROFILES="pkg.linux.nokerneldbg" dpkg-buildpackage -us -uc -b
# or with sbuild:
sbuild -d trixie --profiles=pkg.linux.nokerneldbg ../linux_*.dsc
```

Or set it permanently in `~/.config/sbuild/config.pl`:

```perl
$build_profiles = 'pkg.linux.nokerneldbg';
```

`dpkg-buildpackage` is sufficient for most users after installing build
dependencies. `sbuild` is recommended when a reproducible, isolated build
environment is needed. See the [sbuild wiki](https://wiki.debian.org/sbuild)
for setup instructions.

`prepare-source.sh` also runs `debian/bin/gencontrol.py` to regenerate
`debian/control` from `debian/config/defines.toml`, where
`c_compiler = 'gcc-14'` is set for Debian 13 trixie (the upstream Debian
package targets sid with `gcc-15`). The matching `debian/control.md5sum`
is regenerated and verified automatically.

The `debian/` directory in this repository is derived from the Debian `linux`
source package (currently `linux 7.0.13-1`). It has been modified for CIX:
`gcc-14` is set instead of `gcc-15` for trixie compatibility, CIX-specific
kernel configs are added via `debian/config/arm64/config.cix`, and CIX patches
are staged under `debian/patches/cix/`. To refresh from a newer Debian `linux`
package, run `apt source linux` on a Debian 13 host and re-apply the CIX
modifications.

## Repository layout

```
cix-linux-kernel/
├── native/
│   ├── build-kernel-native.sh
│   └── patch-fixups/       # fixups for CIX patch bugs (native flow)
│       └── apply-patch-fixups.sh
└── debian-pkg/
    ├── debian/             # derived from Debian `linux` source package
    ├── prepare-source.sh   # fetch + patch + regenerate control
    └── debian/patches/
        ├── cix/            # CIX patches from cixtech/cix-linux-main
        └── cix-fixups/     # fixups for CIX patch bugs (debian-pkg flow)
```

## Environment variables

| Variable | Default | Used by |
| --- | --- | --- |
| `KERNEL_VERSION` | `7.0.13` | `native/` |
| `KERNEL_SERIES` | `7.0` | `native/` |
| `KERNEL_TARBALL_URL` | `https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-${KERNEL_VERSION}.tar.xz` | `native/` |
| `PATCH_REMOTE` | `https://github.com/cixtech/cix-linux-main.git` | both flows |
| `PATCH_BRANCH` | `main` | both flows |
| `WORK_DIR` | `$PWD/work` | both flows |
| `OUTPUT_DIR` | `$PWD/output` | `native/` |

## License

The Linux kernel is licensed under the GNU General Public License version 2
(GPL-2.0). See [`LICENSE`](LICENSE) for the full text.
