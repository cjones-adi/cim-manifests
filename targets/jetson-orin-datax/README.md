# jetson-orin-datax — DataX ADIS16470 IMU on the NVIDIA-reference AGX Orin

> **Which carrier?** This target builds for the **NVIDIA-reference AGX Orin devkit**. For the **Seeed Studio
> H01** carrier, use the sibling target [`jetson-orin-datax-seeed`](../jetson-orin-datax-seeed) instead (same
> image + a Seeed carrier overlay).

Builds a **custom JetPack 7.2.1 / L4T r39.2.1 image** with the **ADIS16470 IMU baked in over SPI/IIO**
(`CONFIG_ADIS16475=y` + baked DT node + MB1 pinmux), via the NVIDIA L4T BSP flow. Like the `kuiper`
target, this is an **OS-image build**: CiM handles fetch + workspace + `make` targets, and the real build
is driven by the effort repo **[datax-orin](https://github.com/Carlosjr-Jones_adi/datax-orin)** (its
`datax-image-builder/` scripts). Full docs, wiring, and field notes live in that repo.

## Prerequisites
- **Linux or WSL2, x86_64**, ~40 GB free disk, `sudo`. (Cross-build: x-tools x86_64 → aarch64.)
- Docker is **not** needed (unlike kuiper) — the build is native L4T, not debootstrap.

## Usage
```bash
cim init --source https://github.com/cjones-adi/cim-manifests.git -t jetson-orin-datax
cd ~/dsdk-jetson-orin-datax
cim install os-deps                     # host build deps (apt)
cim makefile
make install-stage-toolchain            # untar x-tools (bzip2) → TOOLCHAIN
make install-stage-bsp                  # extract BSP + rootfs + sources, apply_binaries (sudo)
make install-integrate-adis16470        # apply the device patches
make sdk-build                          # kernel + OOT modules + -nv.dtb + rootfs userspace
make sdk-test                           # verify-gates.sh (all gates pass)
make sdk-flash                          # prints the flash recipe (Force Recovery + flash.sh)
```

## Before first real build — fill these in (`sdk.yml`)
- **`sha256:`** on the 4 `copy_files` archives (3 BSP + `x-tools.tbz2`) — pin for reproducibility.
- ~~**`gits.commit`** — pin `datax-orin` to a SHA instead of `master`.~~ Done — pinned to
  `2f758f1` (2026-10-14). Bump this SHA when datax-orin advances.

> **Why the toolchain is a `copy_files` download, not a `toolchains:` entry:** `x-tools.tbz2` is bzip2,
> and CiM's toolchain extractor only handles `.tar.xz/.gz/.tar/.zip` (no bzip2) → "Unsupported archive
> format". So it's fetched as a plain download and untarred in `make install-stage-toolchain` with
> `tar xf` (auto-detects bzip2); the archive root is `./x-tools/`, hence `--strip-components=2`.

## First boot
The image is pre-seeded with a default login user **`analog` / `analog`** (hostname `orin`, autologin) by
`preseed-user.sh` — like ADI Kuiper ships a default user — so it boots **straight past** NVIDIA's
`nv-oem-config` setup. Override at build time with `OEM_USER` / `OEM_PASS` / `OEM_HOST`.

## Post-flash provisioning (on the Orin, after `sdk-flash`)
- **docker/dialout groups** — the baked `analog` user is **not yet** in the `docker`/`dialout` groups, so
  `docker` and serial devices (`/dev/ttyCAN`, `/dev/ttyCRSF`) need `sudo` until:
  `sudo usermod -aG docker,dialout analog` → log out/in (or `newgrp docker`). *(Now that the user is baked, this
  could be baked too — see follow-ups.)*
- **RTC clock** — this Orin's RTC is not battery-backed and loses the clock on every cold boot; a past
  clock breaks `ros2_canopen` bring-up (surfaces as "error on initialization"). Check `date` first; fix with
  `sudo timedatectl set-ntp true` (networked) / `fake-hwclock` (offline) / fit the RTC coin cell (permanent).

## Adding another device (the `integrate <device>` pattern)
Each device is a new `install:` preset that applies its patch set — e.g. add
`integrate-<device>` alongside `integrate-adis16470`. A base Orin image + per-device variants can also be
expressed with CiM `extends:`/`overlay:` (a base `jetson-orin` target + per-device overlays).

## Notes
- **This is a first-cut draft** — validate with `cim makefile` and inspect the generated Makefile before
  building (Make runs each recipe line in its own shell; dependent commands are `&&`-chained here).
- `stage-bsp`, `sdk-build`, and flashing need **`sudo`** (like kuiper's `sudo ./build-docker.sh`).
- WSL2 flash: `sudo systemctl restart systemd-binfmt.service` first, and `usbipd attach --wsl --auto-attach`.
