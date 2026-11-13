# MIX Kernel 用户态扩展模块 和 补丁

本仓库用于存放 MIX Kernel 各内核特性配套的**用户态模块** 和 **内核补丁**。每个模块都是一个可独立刷入的 KernelSU / Magisk 包，用来补齐内核侧功能所需的用户态脚本、WebUI 或厂商驱动文件。

内核树：[`kernel_xiaomi_mt6833_mix`](https://github.com/KevinLmK0702/kernel_xiaomi_mt6833_mix)（红米 MT6833，Evergo / Everpal）。

内核与模块分别版本管理，但部分模块必须和内核同步更新；对应关系见下表。

## 分支与模块

| 分支 | 模块 | 用途 | 内核要求 |
|---|---|---|---|
| `fps_boost_ctl` | `fps_boost_ctl` | 按正在渲染的进程套用每应用参数，并根据掉帧情况提升 CPU 最低频；带自适应深浅色 WebUI | `CONFIG_MTK_FPS_BOOST=y`，存在 `/proc/fps_boost`；WALT 相关功能需要 `CONFIG_CPU_FREQ_DEFAULT_GOV_WALT=y` |
| `mali_r38p1` | `mali_r38p1` | Mali Valhall r38p1-01eac0 用户态驱动覆盖（GLES + Vulkan，32/64 位） | 内核已移植 r38p1-01eac0 DDK |
| `patches` | — | 存储内核源码以外的补丁 |
| `master` | — | 仓库说明与模块索引 | — |

每个功能分支都带有自己的完整 README，包含安装、配置、构建和排障说明。切换分支后直接阅读该分支根目录的 `README.md` 即可。

## 模块简介

### fps_boost_ctl

内核态 `fps_boost` 驱动的用户态控制端：

- 通过 `/proc/fps_boost` 获取内核正在跟踪的渲染进程，按包名匹配每应用参数；
- 掉帧时提升 CPU 最低频，并可把渲染进程挂进 WALT 的 RTG；
- `conf/` 提供出厂默认配置，首次运行复制到 `/data/adb/`；
- `webroot/` 提供 KernelSU / Magisk WebUI，支持跟随系统主题；
- 与内核的 WALT governor、RTG 频点和 `rtg_pid` 兜底逻辑联动。

打包：

```sh
git checkout fps_boost_ctl
./pack.sh
```

### mali_r38p1

Mali Valhall r38p1-01eac0 用户态驱动覆盖模块，适用于 MT6833（Mali-G57 MC2）：

- 提供 64 位与 32 位 `libGLES_mali.so`、`libgpudshim.so`；
- 包含 r38p1 的 `ro.vendor.arm.egl.configs.*` 属性，缺少这些属性时 `eglInitialize` 会崩溃；
- 分为 `gles` 与 `vulkan` 两个变体：前者让 SurfaceFlinger 保持 GLES，后者额外安装 Vulkan ICD 与 1.3 特性声明，使 SurfaceFlinger 切换到 Skia Vulkan 渲染引擎；
- 用户态与内核 DDK 的大版本必须一致，否则会出现 `Kernel version mismatch`。

构建：

```sh
git checkout mali_r38p1
./build.sh gles      # 或 ./build.sh vulkan
```

产物位于 `out/`。

## 共同说明

- 两个模块都通过 KernelSU / Magisk 安装，不直接改写系统分区。Mali 模块使用 overlay 替换 `/vendor` 下的驱动文件；`fps_boost_ctl` 则在 `/data/adb` 运行守护进程并写入 `/proc/fps_boost` 节点。
- `fps_boost_ctl` 的配置文件位于 `/data/adb/`，卸载模块后不会自动删除，可按需手动清理。
- Mali 驱动二进制来自 Arm / MediaTek 的厂商再分发文件，版权归原厂商所有，不在本仓库的开源许可范围内；仓库中镜像这些文件仅用于保证内核与用户态版本匹配。
