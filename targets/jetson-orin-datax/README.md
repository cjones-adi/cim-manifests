# jetson-orin-datax — DataX ADIS16470 IMU on AGX Orin

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
cim install toolchains                  # fetch + extract x-tools
cim makefile
make install-stage-bsp                  # extract BSP + rootfs + sources, apply_binaries (sudo)
make install-integrate-adis16470        # apply the device patches
make sdk-build                          # kernel + OOT modules + -nv.dtb + rootfs userspace
make sdk-test                           # verify-gates.sh (all gates pass)
make sdk-flash                          # prints the flash recipe (Force Recovery + flash.sh)
```

## Before first real build — fill these in (`sdk.yml`)
- **`sha256:`** on the 3 `copy_files` archives and the `x-tools` toolchain (pin for reproducibility).
- **`gits.commit`** — pin `datax-orin` to a SHA instead of `master`.
- Verify the `x-tools` `strip_components` against `tar tf x-tools.tbz2` (assumes root is `x-tools/`).

## Adding another device (the `integrate <device>` pattern)
Each device is a new `install:` preset that applies its patch set — e.g. add
`integrate-<device>` alongside `integrate-adis16470`. A base Orin image + per-device variants can also be
expressed with CiM `extends:`/`overlay:` (a base `jetson-orin` target + per-device overlays).

## Notes
- **This is a first-cut draft** — validate with `cim makefile` and inspect the generated Makefile before
  building (Make runs each recipe line in its own shell; dependent commands are `&&`-chained here).
- `stage-bsp`, `sdk-build`, and flashing need **`sudo`** (like kuiper's `sudo ./build-docker.sh`).
- WSL2 flash: `sudo systemctl restart systemd-binfmt.service` first, and `usbipd attach --wsl --auto-attach`.
