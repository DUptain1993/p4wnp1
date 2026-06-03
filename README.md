# P4wnP1 A.L.O.A. Build Scripts

This repository contains custom Kali Linux ARM build scripts specifically tailored for generating [P4wnP1 A.L.O.A.](https://github.com/RoganDawes/P4wnP1_aloa) images for the Raspberry Pi Zero W.

These scripts are based on the official [Kali Linux ARM build-scripts](https://gitlab.com/kalilinux/build-scripts/kali-arm).

## Prerequisites

- **Host OS:** Kali Linux `x64` or `x86` (Recommended: `x64`).
- **CPU Architecture:** Building on `arm64` hosts is **not supported** due to legacy nexmon firmware requirements.
- **RAM:** At least 8GB of RAM (or a swap file).
- **Disk Space:** At least 30GB of free space.

## Building

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/DUptain1993/p4wnp1.git
    cd p4wnp1
    ```

2.  **Install dependencies:**
    Run the dependency script to ensure all required tools are installed:
    ```bash
    sudo ./common.d/build_deps.sh
    ```
    *Note: You might need to reboot if prompted by the script.*

3.  **Build the P4wnP1 A.L.O.A. image:**
    ```bash
    sudo ./raspberry-pi-zero-w-p4wnp1-aloa.sh
    ```

## Output

After the build process completes:
- On **x64** systems, the image will be located in `images/` as `kali-linux-<version>-rpi-p4wnp1-aloa-armhf.img.xz`.
- On **x86** systems, the image will be `kali-linux-<version>-rpi-p4wnp1-aloa-armhf.img` (uncompressed due to RAM limitations).

## More Information

- [Official P4wnP1 A.L.O.A. Documentation](https://www.kali.org/docs/arm/raspberry-pi-zero-w-p4wnp1-aloa/)
- [Kali Linux ARM Documentation](https://www.kali.org/docs/arm/)
