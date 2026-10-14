# jetson-orin-datax-seeed — DataX ADIS16470 IMU on the **Seeed H01** AGX Orin

Builds the **custom JetPack 7.2.1 / L4T r39.2.1 image** (ADIS16470 IMU baked in over SPI/IIO) for the
**Seeed Studio AGX Orin 32GB H01** carrier. This is the **sibling** of [`jetson-orin-datax`](../jetson-orin-datax)
(the NVIDIA-reference devkit) — pick the target that matches your carrier:

| Your carrier | Target |
|---|---|
| NVIDIA-reference AGX Orin devkit | `jetson-orin-datax` |
| **Seeed Studio H01 (32GB)** | **`jetson-orin-datax-seeed`** ← this one |

## How it differs from the NVIDIA target
The image is **carrier-agnostic above the board layer** — identical kernel, rootfs, `CONFIG_ADIS16475=y`
driver, CAN, and ROS/Docker stack. The **only** difference is a **post-build carrier overlay**: after the
normal build, `datax-image-builder/apply-seeed-carrier.sh` (CARRIER=seeed-h01) copies Seeed's **MB1 pinmux/gpio
BCT + MB2 BCT + the board `-nv.dtb`** (committed in the effort repo at `boards/seeed-h01/`) over the built tree,
replacing the NVIDIA-ref carrier files. Those Seeed DTBs carry Seeed's on-carrier **EQOS/RJ45** plus the injected
`imu@0` + evicted spidev. This reproduces the **proven, flashed-and-booted** Seeed graft (on-device verified
2026-10-12). Rationale for why it's a file overlay (not `git apply` patches): datax-orin `docs/CIM-INTEGRATION.md` §5.

## Before you start (WSL2 host)
Flashing later uses `usbipd`. **Default (NAT) WSL networking is fine — do nothing.** Only if you deliberately
set `networking=mirrored` in `.wslconfig` should you revert it: mirrored mode blocks `usbipd` device-attach and
link-local board reach (the proven cause of the "can't reach the Seeed" symptom). Worth checking **now**, before
the long download/build — not at flash time.

## Usage
```bash
cim init --source https://github.com/cjones-adi/cim-manifests.git -t jetson-orin-datax-seeed
cd ~/dsdk-jetson-orin-datax-seeed
cim install os-deps                     # host build deps (apt)
cim makefile
make install-stage-toolchain            # untar x-tools (bzip2) → TOOLCHAIN
make install-stage-bsp                  # extract BSP + rootfs + sources, apply_binaries (sudo)
make install-integrate-adis16470        # apply the device patches
make sdk-build                          # build + Seeed carrier overlay (sudo + network)
make sdk-test                           # verify-gates.sh (CARRIER=seeed-h01)
make sdk-flash                          # prints the flash recipe
```

## Flash notes (Seeed-specific)
- Same command: `sudo ./flash.sh jetson-agx-orin-devkit internal` (Seeed's conf symlinks to the same config).
- **Recovery** = the Seeed board's physical **FC-REC** button (not the devkit's).
- **WSL2**: `sudo systemctl restart systemd-binfmt.service` first (else `nv-update-initrd` fails). (WSL networking:
  see *Before you start* above — only relevant if you changed it to mirrored.)
- Verify on-device: `ls /sys/bus/iio/devices` (iio:device0 / PROD_ID 16470), `ip link show end0` (EQOS/RJ45).

## Notes
- The 5 Seeed carrier files live in the effort repo at `datax-image-builder/boards/seeed-h01/` (committed, so a
  cloner gets them). `sha256:` pins on the 4 `copy_files` archives remain the open reproducibility TODO (shared
  with the NVIDIA target).
- **Follow-up (DRY):** once both targets are stable, factor the shared sdk.yml into a base + cim `extends:`.
