# Mali r38p1 用户态驱动覆盖模块

用于 MT6833（evergo / everpal，Mali-G57 MC2）的 Mali Valhall **r38p1-01eac0** 用户态驱动模块，需配合内核树中同版本的 r38p1 DDK 移植使用：

- 内核仓库：[`kernel_xiaomi_mt6833_mix`](https://github.com/KevinLmK0702/kernel_xiaomi_mt6833_mix)

内核只提供 DDK 的下半部分；`libGLES_mali.so` 和 Vulkan ICD 属于用户态，二者的大版本必须一致。版本不匹配时，EGL / GLES 初始化会失败，并在 `dmesg` 中看到：

```text
Kernel version mismatch
```

## 目录结构

```text
blobs/vendor/                 共享驱动二进制
  lib/egl/libGLES_mali.so       32 位 GLES + Vulkan
  lib/libgpudshim.so            32 位 Mali shim
  lib64/egl/libGLES_mali.so     64 位 GLES + Vulkan
  lib64/libgpudshim.so          64 位 Mali shim

variants/gles/                GLES 变体
  module.prop
  system.prop

variants/vulkan/              Vulkan 变体
  module.prop
  system.prop
  extra/vendor/lib/hw/vulkan.mali.so
  extra/vendor/lib64/hw/vulkan.mali.so
  extra/vendor/etc/permissions/android.hardware.vulkan.version.xml

common/                       Magisk 安装器与共用 customize.sh
build.sh                      组装可刷入的模块 zip
```

`blobs/` 由两个变体共享，因此 42 MB 的 64 位 `libGLES_mali.so` 只需要在仓库中保存一份。

## 构建

```sh
./build.sh gles      # -> out/mali_r38p1_vk13-v6-gles.zip
./build.sh vulkan    # -> out/mali_r38p1_vk13-v6-vulkan.zip
```

不传参数时默认构建 `gles`。构建脚本会：

1. 复制 `blobs/vendor` 到模块的 `system/vendor`；
2. 若变体带有 `extra/`，将其内容叠加到 `system/`；
3. 复制该变体的 `module.prop`、`system.prop` 和安装脚本；
4. 统一文件权限，仅保留脚本的可执行位；
5. 打包并输出 SHA-256。

## 两个变体的区别

两个变体包含相同的驱动主体，仅 `vulkan` 额外提供三个文件：

| 文件 | 作用 |
|---|---|
| `vendor/lib64/hw/vulkan.mali.so` | 64 位 Vulkan ICD |
| `vendor/lib/hw/vulkan.mali.so` | 32 位 Vulkan ICD |
| `vendor/etc/permissions/android.hardware.vulkan.version.xml` | 声明 `android.hardware.vulkan.version` 1.3.0 |

| 变体 | SurfaceFlinger 渲染引擎 |
|---|---|
| `gles` | 保持 GLES（ROM 默认） |
| `vulkan` | 切换到 Skia Vulkan |

**决定 SurfaceFlinger 行为的是 Vulkan ICD 加 1.3 特性声明，而不是系统属性。** 刷入 `vulkan` 后，`dumpsys SurfaceFlinger` 中可以看到：

```text
------------RE Vulkan------------
```

刷入 `gles` 则仍然显示 `RE GLES`。

两种变体下，普通应用都可以使用 Vulkan 1.3：应用会通过 ROM 原有的 ICD 加载被替换后的 `libGLES_mali.so`。

## 安装

1. 确认当前内核已经包含 r38p1-01eac0 DDK，并且内核与模块版本匹配；
2. 在 KernelSU / Magisk 管理器中从本地安装对应的 zip；
3. 重启设备；
4. 用以下命令确认实际生效的渲染引擎：

```sh
dumpsys SurfaceFlinger | grep -E 'RE (Vulkan|GLES)'
```

卸载模块并重启即可恢复原厂驱动。

## 验证内核与用户态版本

如果 EGL 初始化失败、应用启动黑屏或游戏无法进入，优先检查：

```sh
dmesg | grep -i 'Kernel version mismatch'
```

出现该日志说明内核 DDK 与用户态 `libGLES_mali.so` 不匹配，需要同时更新内核和模块；只更新其中一侧通常无法解决。

也可以检查模块文件是否落位：

```sh
ls -l /vendor/lib64/egl/libGLES_mali.so
ls -l /vendor/lib64/libgpudshim.so
```

## 已知问题：SurfaceFlinger 使用 Vulkan 时桌面底部黑带

在 HyperOS 2（Android 15）上使用 `vulkan` 变体时，如果关闭「高级纹理」设置，桌面底部的材质会渲染成一条黑带。`screencap` 能截到这条黑带，说明错误像素确实已经写入图层。

定位结果是 **HWUI 的 Vulkan 路径**，不是 SurfaceFlinger 或内核：

- `dumpsys gfxinfo com.miui.home` 显示 `Pipeline=Skia (Vulkan)`；
- 强制 `debug.renderengine.backend=skiagl`、`debug.hwui.renderer=skiavk` 后黑带仍然存在，可排除 SurfaceFlinger 后端；
- `libhwui.so` 中的 MIUI 材质使用 AGSL runtime shader，并依赖嵌套的 `blurChild.eval(xy)` 采样，这是 Skia 各后端之间兼容性最差的用法之一，明显是按 GL 后端编写的；
- 切换 `debug.renderengine.blur_algorithm`（`kawase2` / `gaussian`）、调整 `persist.sys.background_blur_*`、关闭 HWUI 局部更新或 scratch texture，均无法消除黑带。

内核侧唯一相关的失败是 `kbase_api_sticky_resource_unmap` 返回 `-EINVAL`，但内核将该错误视为可容忍的「资源无效，继续执行」，而且 GLES 变体同样会出现，因此可以排除内核问题。

**规避方法：使用 `gles` 变体。** 这不会损失应用侧的 Vulkan 1.3 支持，只是让合成器继续使用 ROM 默认的 GLES。

## 文件来源与许可

驱动二进制来自厂商 r38p1-01eac0 用户态包（小米 `dash-w-oss` r38p1 用户态，随 `Mali-r38p1-VK13-ksu-v*` 分发）。

这些文件是 Arm / MediaTek 的专有再分发文件，**不属于**本仓库的开源许可范围；在此镜像仅为保证内核与用户态版本同步。
