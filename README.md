# cix-linux-kernel

Build the upstream Linux kernel with CIX patches as Debian packages for the
CIX CD8180 / Sky1 family of SoCs (e.g. Radxa Orion O6).

This repository contains **no kernel source code**. It is a thin build
harness that fetches:

- A mainline / stable Linux tarball from `https://cdn.kernel.org/`.
- CIX patches from <https://github.com/cixtech/cix-linux-main>.

Two independent build flows are provided:

| Directory | Flow | Output |
| --- | --- | --- |
| [`native/`](native/) | `make bindeb-pkg` from the kernel source tree | Raw `linux-image-*`, `linux-headers-*`, `linux-libc-dev-*` debs |
| [`debian-pkg/`](debian-pkg/) | Debian's own `linux` source package + CIX patches | Full Debian linux package set (signed templates, installer udebs, etc.) |

Both flows are intended to run on **Debian 13 (trixie)** on **arm64**. The
canonical place to run them is the CIX-chip build machine `radxa-32g`.

## Hardware / firmware requirements

The CIX patch set assumes a working firmware on the target board. See the
[`cixtech/cix-linux-main` README](https://github.com/cixtech/cix-linux-main)
for the up-to-date hardware support matrix and required firmware.

## Flow 1 — Kernel-native `bindeb-pkg`

The simplest path. Suitable for kernel development, quick iteration, or for
users who want a small set of debs without Debian's full packaging machinery.

```bash
cd native
./build-kernel-native.sh
# Override version if desired:
KERNEL_VERSION=7.0.2 KERNEL_SERIES=7.0 ./build-kernel-native.sh
```

Outputs land in `native/output/`.

## Flow 2 — Debian source package

Reuses Debian's official `linux` source-package layout (`3.0 (quilt)`),
including its configs, signing templates, installer integration, and
`debian/patches/` quilt series. CIX patches are staged into
`debian/patches/cix/` and appended to the series.

```bash
cd debian-pkg
./prepare-source.sh
cd work/linux-<version>
# Local build (Debian 13 host):
dpkg-buildpackage -us -uc -b
# Clean chroot build (recommended, on radxa-32g):
sbuild -d trixie
```

The `debian/` directory tracked in this repository was imported verbatim from
the Debian `linux` source package (currently `linux 7.0.13-1`). Refresh it by
re-running `apt source linux` on a Debian 13 host and copying the result over
`debian-pkg/debian/`.

## Repository layout

```
cix-linux-kernel/
├── native/
│   └── build-kernel-native.sh
└── debian-pkg/
    ├── debian/              # imported from Debian sid `linux` source pkg
    └── prepare-source.sh
```

## Environment variables

| Variable | Default | Used by |
| --- | --- | --- |
| `KERNEL_VERSION` | `7.0.13` | `native/` |
| `KERNEL_SERIES` | `7.0` | `native/` |
| `KERNEL_TARBALL_URL` | `https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-${KERNEL_VERSION}.tar.xz` | both flows |
| `PATCH_REMOTE` | `https://github.com/cixtech/cix-linux-main.git` | both flows |
| `PATCH_BRANCH` | `main` | both flows |
| `WORK_DIR` | `$PWD/work` | both flows |
| `OUTPUT_DIR` | `$PWD/output` | `native/` |
