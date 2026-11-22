# Bao Hypervisor Workspace for Verdin iMX8M Plus

Development workspace for running the [Bao](https://github.com/bao-project/bao-hypervisor)
static partitioning hypervisor on the **Toradex Verdin iMX8M Plus**
(4× Cortex-A53, GICv3).

It collects everything needed to build the hypervisor and its guests in one
place: Bao with a Verdin platform port, a FreeRTOS guest, Linux 6.1 and
Buildroot for Linux guests, and a Toradex Yocto (OpenEmbedded) tree for
building board kernels and root filesystems.

The VM configuration and device trees live in the companion repository
[bao-demos](https://github.com/Rivanfirdausa123/bao-demos)
(`demos/linux+freertos/`, platform `imx8mp-verdin`).

## Architecture

Bao statically splits the four cores, memory and devices between VMs. There
is no scheduler in the hypervisor: each VM owns its cores and only sees the
devices assigned to it.

```
 ┌───────────────────────────────┐ ┌───────────────────────────────┐
 │ VM 1 · Linux (non-critical)   │ │ VM 2 · Linux RT / FreeRTOS    │
 │ CPU 0-1 · 1 GiB               │ │ CPU 2-3 · 1 GiB               │
 │ most SoC peripherals          │ │ EQOS Ethernet                 │
 └───────────────┬───────────────┘ └───────────────┬───────────────┘
                 │      shared memory IPC 64 KiB   │
                 │   (phys 0xFD000000, IRQ 53)     │
 ┌───────────────┴─────────────────────────────────┴───────────────┐
 │ Bao hypervisor (EL2)  · console on UART3 (0x30880000)           │
 ├─────────────────────────────────────────────────────────────────┤
 │ Verdin iMX8M Plus · 4× Cortex-A53 · GICv3 · DRAM at 0x40000000  │
 └─────────────────────────────────────────────────────────────────┘
```

Boot flow: U-Boot loads `bao.bin` from the SD card and jumps to it. Bao then
starts each guest from the images that are linked into the binary.

## Repository layout

| Path | Contents |
| --- | --- |
| `bao/` | Bao hypervisor source, with the `imx8mp-verdin` platform in `src/platform/imx8mp-verdin/` |
| `freertos/` | FreeRTOS guest: FreeRTOS kernel, [bao-baremetal-guest](https://github.com/bao-project/bao-baremetal-guest) runtime and the `imx8mp-verdin` port in `src/baremetal-runtime/src/platform/imx8mp-verdin/` |
| `linux-v6.1/` | Linux 6.1 kernel source |
| `buildroot-aarch64-v6.1/` | Buildroot, used to build small root filesystems for Linux guests |
| `oe-core/` | Toradex OpenEmbedded setup (Scarthgap): `layers/` with `meta-toradex-nxp`, `meta-freescale`, `meta-arm` and friends, plus the `export` helper script |

The third-party trees are vendored as plain directories (not submodules), so a
normal `git clone` is enough. Each keeps its original license.

### Verdin-specific files

| File | What it defines |
| --- | --- |
| `bao/src/platform/imx8mp-verdin/desc.c` | CPUs, DRAM region, UART3 console, GIC distributor/redistributor addresses |
| `bao/src/platform/imx8mp-verdin/platform.mk` | Architecture and GIC version for the build |
| `freertos/src/baremetal-runtime/src/platform/imx8mp-verdin/inc/plat.h` | Guest memory (`0x80200000`, 128 MiB), GIC and UART used by FreeRTOS |
| `oe-core/layers/meta-toradex-nxp/conf/machine/verdin-imx8mp.conf` | Yocto machine definition |

## Prerequisites

Tested on Ubuntu 22.04.

```bash
# Bare-metal toolchain for Bao and FreeRTOS
# Download "aarch64-none-elf" from https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads
export CROSS_COMPILE=aarch64-none-elf-

# Yocto host packages
sudo apt install gawk wget git diffstat unzip texinfo gcc build-essential chrpath \
    socat cpio python3 python3-pip python3-pexpect xz-utils debianutils iputils-ping \
    python3-git python3-jinja2 python3-subunit zstd liblz4-tool file locales libacl1
sudo locale-gen en_US.UTF-8
```

A Yocto build needs roughly 100 GB of free disk space.

## Building

### 1. Linux kernel and rootfs with Yocto

```bash
cd oe-core
. export
```

The first run creates `oe-core/build/` and leaves you inside it. Edit
`conf/local.conf`:

```
MACHINE ?= "verdin-imx8mp"
ACCEPT_FSL_EULA = "1"
```

Then build:

```bash
bitbake tdx-reference-minimal-image
```

The kernel ends up in `deploy/images/verdin-imx8mp/Image`. This is the image
the Linux VMs in `bao-demos` are built from.

> `export` also looks for a `repo` manifest in `oe-core/.repo/`, which is not part
> of this workspace. The resulting `grep` warnings on the first run are harmless.

### 2. FreeRTOS guest

```bash
cd freertos
make PLATFORM=imx8mp-verdin
```

Output: `freertos/build/imx8mp-verdin/freertos.bin`

### 3. Bao hypervisor

The VM layout (`imx8mp-verdin.c`) comes from `bao-demos`. It embeds the guest
images, so build the guests first and point Bao at the config directory:

```bash
cd bao
make PLATFORM=imx8mp-verdin \
     CONFIG_REPO=/path/to/bao-demos/demos/linux+freertos/configs \
     CONFIG=imx8mp-verdin
```

Output: `bao/bin/imx8mp-verdin/imx8mp-verdin/bao.bin`

The config refers to guest images through `BAO_DEMOS_WRKDIR_IMGS`, so the
easiest way to get a complete image is to run the full flow from `bao-demos`,
which builds the guests, wraps them and then builds Bao:

```bash
cd /path/to/bao-demos
make PLATFORM=imx8mp-verdin DEMO=linux+freertos
```

## Running on the board

1. Copy `bao.bin` to the FAT boot partition of an SD card and insert it into the Verdin carrier board.
2. Open the debug UART at 115200 baud, for example `screen /dev/ttyUSB3 115200`.
3. Reset the board, stop autoboot, and at the U-Boot prompt run:

```
fatload mmc 1 0x60200000 bao.bin && go 0x60200000
```

Bao prints its banner on UART3, followed by the guests' output.

## Upstream projects

- Bao hypervisor: <https://github.com/bao-project/bao-hypervisor>
- Bao demos: <https://github.com/bao-project/bao-demos>
- Bao bare-metal guest: <https://github.com/bao-project/bao-baremetal-guest>
- FreeRTOS kernel: <https://github.com/FreeRTOS/FreeRTOS-Kernel>
- Linux kernel: <https://kernel.org>
- Buildroot: <https://buildroot.org>
- Toradex BSP layers: <https://git.toradex.com>
