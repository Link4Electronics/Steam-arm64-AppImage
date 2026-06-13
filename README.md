<div align="center">

# **THIS IS DEAD, this is crap too since it still relies on 32bit libs**

# Steam-arm64-AppImage 🐧

[![GitHub Downloads](https://img.shields.io/github/downloads/Link4Electronics/Steam-arm64-AppImage/total?logo=github&label=GitHub%20Downloads)](https://github.com/Link4Electronics/Steam-arm64-AppImage/releases/latest)
[![CI Build Status](https://github.com//Link4Electronics/Steam-arm64-AppImage/actions/workflows/appimage.yml/badge.svg)](https://github.com/Link4Electronics/Steam-arm64-AppImage/releases/latest)
[![Latest Stable Release](https://img.shields.io/github/v/release/Link4Electronics/Steam-arm64-AppImage)](https://github.com/Link4Electronics/Steam-arm64-AppImage/releases/latest)

<p align="center">
  <img src="https://github.com/user-attachments/assets/0de7bd75-fd58-44f0-ba5f-74bad7261a3b" width="128" />
</p>

Portable AppImage of the **Steam arm64 beta client** for aarch64 Linux,
built on top of [RunImage](https://github.com/VHSgunzo/runimage) — a portable
single-file Linux container using unprivileged user namespaces.


| Latest Stable Release | Upstream URL |
| :---: | :---: |
| [Click here](https://github.com/Link4Electronics/Steam-arm64-AppImage/releases/latest) | [Click here](https://store.steampowered.com/) |

</div>

## How it works

This AppImage does **NOT** bundle Steam binaries. It contains:

1. A **RunImage container** (Ubuntu Linux arm rootfs) with all libraries Steam
   needs (mesa, gtk3, pipewire, vulkan, etc.)
2. A **launcher** that downloads the official Steam ARM64 beta from Valve's
   CDN on **first run** to `~/.local/share/Steam-ARM-AppImage/`

This avoids redistributing proprietary software, respecting Valve's Steam
Subscriber Agreement. No FUSE required (uses uruntime).

## Usage

**Note: Only works on glibc distros, on musl like postmarketOS need to run inside a container**

---
1. Download the AppImage from [Releases](https://github.com/Link4Electronics/Steam-arm64-AppImage/releases/latest)
2. `chmod +x Steam-*.AppImage`
3. Run it: `./Steam-*.AppImage`
4. On first launch, Steam will be downloaded automatically (may take a few minutes)


---

<details>
  <summary><b><i>raison d'être</i></b></summary>
    <img src="https://github.com/user-attachments/assets/d40067a6-37d2-4784-927c-2c7f7cc6104b" alt="Inspiration Image">
  </a>
</details>

---

More at: [AnyLinux-AppImages](https://pkgforge-dev.github.io/Anylinux-AppImages/)
