<div align="center">

# OnePlus KernelSU SUSFS

**Automated OnePlus Kernel Builds | SukiSU / BakaSU / FinaSU + SUSFS Integration**

[![Release](https://img.shields.io/github/v/release/LingLuo17/OnePlus_KernelSU_SUSFS?label=Release&style=flat-square&logo=github&logoColor=white&color=2ea44f)](https://github.com/LingLuo17/OnePlus_KernelSU_SUSFS/releases)
[![Coolapk](https://img.shields.io/badge/Follow-Coolapk-3DDC84?style=flat-square&logo=android&logoColor=white)](http://www.coolapk.com/u/38407386)
[<img src="https://img.shields.io/badge/Join-QQ%20Group-blue?style=flat-square&logo=github&logoColor=white">](https://qm.qq.com/q/9Wr9DiJJ9C)
[![SukiSU](https://img.shields.io/badge/SukiSU-Supported-5AA300?style=flat-square)](https://github.com/SukiSU-Ultra/SukiSU-Ultra)
[![BakaSU](https://img.shields.io/badge/BakaSU-Supported-5AA300?style=flat-square)](https://github.com/Baka-SU/BakaSU)
[![FinaSU](https://img.shields.io/badge/FinaSU-Supported-5AA300?style=flat-square)](https://github.com/LyraVoid/FinaSU)
[![SUSFS](https://img.shields.io/badge/SUSFS-Integrated-E67E22?style=flat-square)](https://gitlab.com/simonpunk/susfs4ksu)

**English** | [简体中文](#chinese)

</div>

## 📖 Introduction

This repository builds **OnePlus (Oppo/Realme) device kernels** with GitHub Actions, integrating SukiSU / BakaSU / FinaSU and the SUSFS kernel-level hiding solution, plus practical patches such as BBG and network enhancements.

- The build workflows are adapted from [WildKernels/OnePlus_KernelSU_SUSFS](https://github.com/WildKernels/OnePlus_KernelSU_SUSFS)
- Supported devices: **Android 15 / Android 16 (ColorOS)** OnePlus devices, covering GKI `5.10 / 5.15 / 6.1 / 6.6 / 6.12`
- Flashing rule: ***It can be flashed as long as the kernel version matches.***
- All the Kernels are built on <a href="https://github.com/OnePlusOSS/">OnePlus Official Source</a> and are expected to work only on Stock roms!!!.

## 📦 Supported Workflows

| Workflow | Purpose | Notes |
|:---|:---|:---|
| `build-kernel-release.yml` | Batch build & optional release | Select `A15+16` / `A15` / `A16` or a GKI filter |
| `oneplus-custom.yml` | Custom single-device build | 150 device versions, custom version name & build time |

## ✨ Features

| Feature | Description |
|:---|:---|
| 🔐 KernelSU Variants | Supports SukiSU / BakaSU / FinaSU variants, selectable at build time |
| 🔀 Build Channel | Release: latest **stable** upstream Release (tag commit + same-version manager), falls back to the newest official default-branch build when the upstream only ships pre-releases; Latest: pins the default-branch HEAD and picks the newest manager build matching that version |
| 🙈 SUSFS | Kernel-level hiding working with KSU to complete environment spoofing |
| 🔔 Re-Kernel | Optional Re-Kernel driver integration |
| 🛡️ BBG (Baseband Guard) | LSM-based protection for critical device partitions; abl/efisp whitelist for exploit devices |
| 🛠️ HMBIRD SCX | Scheduler extensions for SM8750/MT6991 devices |
| 🌐 Network Enhancement | BBRv1 / BBRv3 congestion control, CAKE & PIE qdisc, IPSet + IPv6 NAT |
| ✅ LTO | Link Time Optimisation enabled |
| 🚀 Optimisation Patches | Memory, I/O, CPU scheduler, network and other general tunings |
| 🌐 TTL Target Support | Network packet manipulation |
| ⚡ TMPFS XATTR / POSIX ACL | Extended TMPFS support for meta modules and Mountify |
| </> Unicode Bypass Fix | Prevent path traversal and other detections using non-printable Unicode codepoints |
| 🐳 Droidspaces & NTSync | Optional container support with NTSync kernel compatibility (toggle in custom build) |

## 🚀 Usage

1. **Fork this repository** (or use it directly)
2. Go to the **Actions** page and pick a workflow:
   - `Build and Release OnePlus Kernels` — batch build by Android version or GKI filter, optionally publish a Release
   - `OnePlus Custom Kernel Build` — pick one device (with kernel sub-version), choose SukiSU / BakaSU / FinaSU, custom version name & build time
3. Click **Run workflow** and fill in the parameters as needed
   - `build_channel`: build channel
     - `正式 (Release)`: manager APK taken from the latest **stable** upstream Release (`prerelease=false`) and the kernel pinned to that release tag commit; when the upstream only ships rc/pre-releases (e.g. BakaSU), the newest official default-branch build is used and pinned instead
     - `最新 (HEAD)`: kernel pinned to the default-branch HEAD, and the manager is the newest build whose version matches HEAD (any branch), so kernel and manager never drift apart
4. Once the build finishes, download the **Artifacts** from the run page:
   - `AnyKernel3.zip` — flashable zip (recommended; flash via custom Recovery or KSU manager)

> 💡 SUSFS refs are resolved automatically from [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) (latest `gki-androidXX-Y.Y` branch commit) — no manual input required. To pin a specific commit instead, see [Custom Commit Configuration](#-custom-commit-configuration).

## 🔧 Custom Commit Configuration

The [`config/config`](config/config) file lets you pin SUSFS to specific commits.

**What is a commit?**

A commit is a hash string representing the state of a repository at a certain point in time. For example, setting SUSFS to `4b8644515fe6d87a109129e590ccd9d33a855dca` means the kernel will be built with the SUSFS version from January 30.

**Why pin a commit?**

- Roll back to a stable version when upstream updates introduce bugs or compatibility issues
- Manually specify a compatible version when SUSFS and KernelSU are out of sync and the build fails

**How to use it?**

1. Set `custom=true` in [`config/config`](config/config)
2. Fill in the desired commit hash next to the matching entry (one entry per GKI branch)
3. Leave an entry empty to keep using the latest commit of that branch

**How to get a commit hash?**

- SUSFS: [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) (GitLab → Repository → Commits)

## 🙏 Acknowledgments

- [WildKernels/OnePlus_KernelSU_SUSFS](https://github.com/WildKernels/OnePlus_KernelSU_SUSFS) & [WildKernels/kernel_patches](https://github.com/WildKernels/kernel_patches)
- [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) / [BakaSU](https://github.com/Baka-SU/BakaSU) / [FinaSU](https://github.com/LyraVoid/FinaSU) / [KernelSU](https://github.com/tiann/KernelSU)
- [SUSFS](https://gitlab.com/simonpunk/susfs4ksu)
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3)
- [Baseband Guard](https://github.com/vc-teahouse/Baseband-guard)
- [Re-Kernel](https://github.com/Sakion-Team/Re-Kernel)
- [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS)
- [ZyCromerZ/Clang](https://github.com/ZyCromerZ/Clang) (build compiler)
- [OnePlusOSS](https://github.com/OnePlusOSS) (kernel sources) & [CodeLinaro](https://git.codelinaro.org/) (prebuilt toolchains)

<div align="center">

## ⚠️ Disclaimer

</div>

- Flashing this kernel will not void your warranty, but there is always a risk of bricking your device. Please make sure to:
- 💾 Back up your data
- 🧠 Understand the risks before proceeding

- Please make sure to back up the original boot image of your system in advance.

- If flashing this kernel causes your device to enter an infinite boot loop or fail to boot, enter BootLoader and flash the original boot image back.

- I take no responsibility for any issues caused by flashing this kernel.

<div align="center">

# **🚨 Proceed at your own risk!**

</div>

---

<div align="center">

<a id="chinese"></a>

# OnePlus KernelSU SUSFS

**自动化构建一加内核 | 集成 SukiSU / BakaSU / FinaSU + SUSFS**

[English](#oneplus-kernelsu-susfs) | **简体中文**

</div>

## 📖 简介

本仓库通过 GitHub Actions 自动编译 **一加（Oppo/Realme）设备内核**，集成 SukiSU / BakaSU / FinaSU 与 SUSFS 内核级隐藏方案，并附带 BBG 基带保护、网络增强等实用补丁。

- 构建工作流修改自 [WildKernels/OnePlus_KernelSU_SUSFS](https://github.com/WildKernels/OnePlus_KernelSU_SUSFS)
- 支持设备：**Android 15 / Android 16（ColorOS）** 一加设备，覆盖 GKI `5.10 / 5.15 / 6.1 / 6.6 / 6.12`
- 刷入规则：***只要内核版本匹配即可刷入***
- 所有内核均基于 <a href="https://github.com/OnePlusOSS/">OnePlus 官方源码</a> 构建，并且仅预期适用于官方原厂 ROM！！！

## 📦 可用工作流

| 工作流 | 用途 | 说明 |
|:---|:---|:---|
| `build-kernel-release.yml` | 批量构建 & 可选发布 | 选择 `A15+16` / `A15` / `A16` 或 GKI 过滤 |
| `oneplus-custom.yml` | 自定义单设备构建 | 150 个设备版本、自定义版本名与构建时间 |

## ✨ 功能特性

| 特性 | 说明 |
|:---|:---|
| 🔐 KernelSU 变体 | 支持 SukiSU / BakaSU / FinaSU 变体，构建时按需选择 |
| 🔀 构建通道 | 正式：上游最新**正式版** Release（标签提交 + 同版本管理器），上游只有预发布版时改用官方默认分支最新上传构建；最新：锁定默认分支 HEAD，管理器取与 HEAD 版本一致的最新构建 |
| 🙈 SUSFS | 内核级隐藏，配合 KSU 完成环境伪装 |
| 🔔 Re-Kernel | 可选集成 Re-Kernel 驱动 |
| 🛡️ BBG 基带保护 | 基于 LSM 保护关键设备分区；efisp 漏洞设备可加入 abl/efisp 白名单 |
| 🛠️ HMBIRD SCX | 适用于 SM8750/MT6991 设备的调度扩展 |
| 🌐 网络增强 | BBRv1 / BBRv3 拥塞控制、CAKE 与 PIE qdisc、IPSet + IPv6 NAT |
| ✅ LTO | 启用链接时优化 |
| 🚀 优化补丁 | 内存、输入输出、CPU 调度器、网络及其他通用调优 |
| 🌐 TTL 目标支持 | 网络数据包操作 |
| ⚡ TMPFS XATTR / POSIX ACL | 扩展 TMPFS 支持，用于元模块与 Mountify |
| </> Unicode 绕过修复 | 防止使用不可打印的 Unicode 码点进行路径穿越及其他检测 |
| 🐳 Droidspaces & NTSync | 可选容器支持及 NTSync 内核兼容补丁（自定义构建中可开关） |

## 🚀 使用方法

1. **Fork 本仓库**（或直接使用本仓库）
2. 进入 **Actions** 页面，选择工作流：
   - `Build and Release OnePlus Kernels` —— 按安卓版本或 GKI 过滤批量构建，可选发布 Release
   - `OnePlus Custom Kernel Build` —— 选择单台设备（含内核子版本）、SukiSU / BakaSU / FinaSU、自定义版本名与构建时间
3. 点击 **Run workflow**，按需填写参数
   - `build_channel`：构建通道
     - `正式 (Release)`：使用上游最新**正式版** Release（`prerelease=false`）的管理器 APK，内核检出该 Release 标签的同一提交；上游只有 rc/预发布版时（如 BakaSU），改用官方默认分支最新上传构建并锁定该提交
     - `最新 (HEAD)`：内核锁定默认分支 HEAD，管理器取与 HEAD 版本号一致的最新构建（不限分支），避免内核与管理器版本错位
4. 构建完成后，在本次运行页面下载 **Artifacts**：
   - `AnyKernel3.zip` —— 卡刷包（推荐，配合自定义 Recovery 或 KSU 管理器刷入）

> 💡 SUSFS 引用自动从 [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) 解析（对应 `gki-androidXX-Y.Y` 分支最新提交），无需手动填写。如需固定某个提交，见 [自定义提交配置](#-自定义提交配置)。

## 🔧 自定义提交配置

通过 [`config/config`](config/config) 文件可以指定 SUSFS 使用特定的 commit。

**什么是提交 (commit)？**

提交是一串哈希字符串，代表仓库在某个时间点的状态。例如将 SUSFS 设为 `4b8644515fe6d87a109129e590ccd9d33a855dca`，即使用 1 月 30 日的 SUSFS 版本编译内核。

**为什么要指定提交？**

- 当上游仓库更新引入 bug 或兼容性问题时，可回退到稳定版本
- 当 SUSFS 与 KernelSU 版本不同步导致编译失败时，可手动指定兼容的版本

**如何使用？**

1. 在 [`config/config`](config/config) 中将 `custom` 设为 `true`
2. 在对应配置项后填入想要的 commit hash（按 GKI 分支填写，每个分支一项）
3. 留空表示使用该分支的最新提交

**如何获取提交哈希？**

- SUSFS：[susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu)（GitLab → Repository → Commits）

## 🙏 致谢

- [WildKernels/OnePlus_KernelSU_SUSFS](https://github.com/WildKernels/OnePlus_KernelSU_SUSFS) & [WildKernels/kernel_patches](https://github.com/WildKernels/kernel_patches)
- [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) / [BakaSU](https://github.com/Baka-SU/BakaSU) / [FinaSU](https://github.com/LyraVoid/FinaSU) / [KernelSU](https://github.com/tiann/KernelSU)
- [SUSFS](https://gitlab.com/simonpunk/susfs4ksu)
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3)
- [Baseband Guard](https://github.com/vc-teahouse/Baseband-guard)
- [Re-Kernel](https://github.com/Sakion-Team/Re-Kernel)
- [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS)
- [ZyCromerZ/Clang](https://github.com/ZyCromerZ/Clang)（构建编译器）
- [OnePlusOSS](https://github.com/OnePlusOSS)（内核源码）& [CodeLinaro](https://git.codelinaro.org/)（预构建工具链）

<div align="center">

## ⚠️ 免责声明

</div>

- 刷入内核不会使保修失效，但总有设备变砖的风险，请务必：
- 💾 备份你的数据
- 🧠 在继续之前了解风险

- 请务必提前备份系统的原 Boot 镜像。

- 如果刷入内核导致设备进入无限启动循环或无法启动，请进入 BootLoader 并重新刷入原 Boot 镜像。

- 我不对刷写该内核所引发的任何问题负责。

<div align="center">

# **🚨 请自行承担风险！**

</div>
