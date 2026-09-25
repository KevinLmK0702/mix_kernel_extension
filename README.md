# fps_boost_ctl

面向 MT6833（evergo / everpal）的**帧感知提频**用户态控制模块，配合内核态 `fps_boost` 驱动使用。

模块根据内核正在跟踪的**渲染进程**识别当前应用，套用该应用自己的目标帧率、掉帧裕量和提频强度；检测到掉帧时提升 CPU 最低频，并可视需要把渲染进程挂入 WALT 的 RTG。附带自适应深浅色 WebUI，可在 KernelSU / Magisk 管理器中直接配置。

## 功能概览

- **按渲染进程匹配**：读取 `/proc/fps_boost/pid`，通过 `/proc/<pid>/cmdline` 得到包名，比简单的“前台应用”判断更准确；横屏、分屏和 SurfaceFlinger 中转场景下不易误判。
- **每应用参数**：不同游戏可以分别设置目标帧率、掉帧裕量、提频百分比、保持时间和 RTG id。
- **帧率档位**：`target_fps` 支持 `60,90,120` 或 `60/90/120` 形式的档位列表，内核按实测帧率匹配当前档位。
- **掉帧才提频**：未掉帧时不主动抬高频率；掉帧后至少保持 `hold_ms`，避免频率来回抖动。
- **WALT / RTG 联动**：可将渲染进程加入 WALT 关联线程组，并按 `boost_pct` 接管 `hispeed_freq` / `rtg_boost_freq`。
- **热重载**：修改 `/data/adb/` 下的配置后无需重启，守护进程按文件修改时间自动重新套用。
- **WebUI**：模块状态、每应用配置、全局选项、日志和运行环境自检。

## 环境要求

- KernelSU 或 Magisk；
- 内核启用 `CONFIG_MTK_FPS_BOOST=y`，即存在 `/proc/fps_boost`；
- 使用 RTG / WALT 相关功能时，内核还需启用 `CONFIG_CPU_FREQ_DEFAULT_GOV_WALT=y`，并包含对应的 WALT governor 移植；
- 建议使用包含 WALT util 口径修复、`auto_boost` 默认值和按 CPU 判断 RTG 负载等修复的较新内核。

安装前可以先确认节点是否存在：

```sh
ls /proc/fps_boost
```

## 目录结构

```text
fps_boost_ctl/
├── module.prop            模块信息
├── customize.sh           安装钩子：打印说明并修正权限
├── service.sh             开机入口：等待 /proc/fps_boost 后拉起守护进程
├── pack.sh                打包脚本，自带布局与内容校验
├── bin/
│   ├── fps_boost_d.sh     守护进程主循环，支持 --once 单轮调试
│   └── lib/common.sh      配置解析、模式预设、节点读写、进程识别
├── conf/                  出厂默认配置，首次运行复制到 /data/adb
│   ├── profiles.conf      每应用参数
│   ├── opts.conf          全局选项
│   └── mode               默认模式
└── webroot/               WebUI
    ├── index.html
    ├── css/app-ui.css
    └── js/{ksu.js,app.js}
```

## 安装

1. 确认内核包含 `fps_boost` 和 WALT 支持；
2. 在 KernelSU / Magisk 管理器中从本地安装 `fps_boost_ctl-vX.zip`；
3. 重启设备；
4. 打开模块 WebUI，或在终端确认节点：

```sh
cat /proc/fps_boost/status
```

只更新 WebUI 时可以不重启：

```sh
adb push webroot/ /data/adb/modules/fps_boost_ctl/
```

如果修改了 `bin/` 或 `service.sh`，需要重启模块或重新执行 `service.sh`。

## 快速配置

首次启动后，守护进程会把 `conf/` 中的默认配置复制到 `/data/adb/`：

| 文件 | 作用 |
|---|---|
| `/data/adb/fps_boost_ctl.conf` | 每应用参数 |
| `/data/adb/fps_boost_ctl.opts` | 全局选项 |
| `/data/adb/fps_boost_ctl.mode` | 当前模式，默认 `balance` |

配置优先级：

```text
模式预设  <  opts.conf  <  profiles.conf 中的每应用行
```

修改后无需重启，守护进程会自动重载。

## 每应用参数：`fps_boost_ctl.conf`

格式：

```text
<包名|*|!包名>  <target_fps>  <margin_fps>  <boost_pct>  <hold_ms>  [rtg_id]
```

| 字段 | 说明 |
|---|---|
| 包名 | 精确匹配，优先级高于 `*`，与行序无关 |
| `*` | 全局默认行，为未显式列出的应用提供参数 |
| `!包名` | 黑名单。命中的应用完全不被接管，适合跑分和敏感应用 |
| `target_fps` | 目标帧率 1–300；也可写档位列表，如 `60,90,120` 或 `60/90/120` |
| `margin_fps` | 允许的掉帧裕量 0–120，低于 `target - margin` 才提频 |
| `boost_pct` | 提频强度 5–100，表示把最低频抬到该 cluster 最高频的百分比；写 `-` 表示沿用模式或全局值 |
| `hold_ms` | 掉帧后至少保持提频的时长，10–10000 ms；写 `-` 表示沿用模式或全局值 |
| `rtg_id` | WALT 关联线程组 id，0 表示关闭，1–19 可用；写 `-` 或缺省表示沿用全局值 |

示例：

```text
# 默认：60fps，允许掉 1 帧，提频强度和保持时间用模式预设，RTG 1
* 60 1 - - 1

# 原神：按实测帧率在 60 / 90 / 120 三档中匹配
com.miHoYo.Yuanshen 60,90,120 1 - - 1

# 王者荣耀：不允许掉帧，直接 100% 提频，保持 500ms，不挂 RTG
com.tencent.tmgp.sgame 60 0 100 500 0

# 跑分应用：完全不接管
!com.antutu.ABenchMark - - - - -
!com.primatelabs.geekbench6 - - - - -
```

以 `#` 开头的行是注释。修改后守护进程会在约 1 秒内重新读取并应用。

## 全局选项：`fps_boost_ctl.opts`

格式为每行一个 `<键> <值>`，只接受白名单键。未识别的键会被忽略。

| 键 | 默认值 | 说明 |
|---|---|---|
| `only_listed` | `0` | `1` = 只对 `fps_boost_ctl.conf` 中显式列出的包名生效，`*` 仅提供参数默认值；`0` = 任意前台应用都套用 `*` |
| `governor` | `walt` | 固定各 policy 的 cpufreq governor；`keep` = 不干预，保持系统或内核当前的 governor |
| `rtg_id` | `1` | WALT 关联线程组 id，0 表示关闭，1–19 可用 |
| `rtg_mode` | `2` | `0` = 关闭；`1` = 仅提频时挂组；`2` = 跟踪到渲染进程就挂组 |
| `rtg_pid_auto` | `1` | 内核没有跟踪到渲染 pid 时，用前台包名反查主进程 pid 并写入 `rtg_pid` |
| `rtg_pid` | `0` | 手动指定渲染进程 pid；非 0 时优先于 `rtg_pid_auto` |
| `floor_en` | `1` | 是否抬高 cpufreq 最低频；设为 `0` 时只依赖 WALT governor |
| `graded` | `1` | 分级提频：按低于目标的程度把 `boost_pct` 线性放大到 100% |
| `ged_target` | `1` | 采用 GED 上报的目标帧率进行换算 |
| `sample_ms` | `200` | 内核控制环周期（ms） |
| `rtg_boost_freq` | 未设置 | WALT 的 RTG 目标频点；`kHz` 或 `max`。未设置时使用内核按 cluster 计算的默认值（最高频的 70%）；写 `0` 才表示真正关闭 RTG 抬频 |
| `walt_auto_boost` | `1` | `hispeed_freq` / `rtg_boost_freq` 为 0 时，使用内核按 cluster 计算的默认值（hispeed 80%、RTG 70%）；`0` = 关闭自动取值 |
| `walt_pl` | `1` | 启用 WALT 预测负载抬频；耗电敏感时可设为 `0` |
| `walt_hispeed_freq` | 未设置 | 高负载时顶到的频率；`max` 表示该 cluster 的最高频 |
| `walt_hispeed_load` | `90` | 触发 hispeed 的负载阈值 |
| `walt_boost` | `0` | util 的额外百分比缩放，可为负 |
| `walt_adaptive_low_freq` / `walt_adaptive_high_freq` | 未设置 | 自适应频带，把频率限制在该区间内 |
| `walt_<其它>` | — | 任意 `walt_<tunable>` 都会写入各 policy 的 `/sys/.../policyN/walt/<tunable>`；值写 `max` 表示该 cluster 的最高频 |

`governor`、`rtg_boost_freq` 和所有 `walt_*` 键会被守护进程每 5 秒校验并重新写入，因为 governor 被重新选择时会重建 tunable 目录并把值复位。

## 模式：`fps_boost_ctl.mode`

文件内容只有一行：`powersave`、`balance`、`performance` 或 `fast`。

| 模式 | `boost_pct` | `hold_ms` | `graded` | `rtg_mode` |
|---|---:|---:|---:|---:|
| `powersave` | 45 | 150 | 0 | 1 |
| `balance` | 60 | 250 | 1 | 2 |
| `performance` | 80 | 400 | 1 | 2 |
| `fast` | 100 | 600 | 1 | 2 |

模式为 `profile` 中写 `-` 的字段提供默认值，也会用于没有被任何 profile 行命中的场景。也可以直接在 WebUI 中切换模式。

## 守护进程工作方式

```text
每秒：
  1. 读取 /proc/fps_boost/pid，得到内核正在跟踪的渲染进程
  2. 通过 /proc/<pid>/cmdline 得到包名（去掉 :remote 后缀）
     取不到包名且模块处于开启状态时，才回退到 dumpsys 前台应用，
     并限制为每 30 秒最多一次
  3. 包名或命中的 profile 发生变化 → 写入 /proc/fps_boost
     opts / mode 文件 mtime 变化 → 重新套用模式和全局选项
每 5 秒：
  校验 governor、rtg_boost_freq 和 walt_* tunables 没有被其他组件改走
每轮：
  在 GED 没有上报渲染 pid 时，按包名反查主进程 pid，补写 rtg_pid
```

调试时可以只跑一轮并打印识别结果、命中的 profile、套用后的节点值和内核状态：

```sh
su -c "sh /data/adb/modules/fps_boost_ctl/bin/fps_boost_d.sh --once"
```

## 与内核的接口

| 节点 | 作用 |
|---|---|
| `enable` / `target_fps` / `target_fps_list` / `margin_fps` / `boost_pct` / `hold_ms` | 基本提频参数 |
| `rtg_id` / `rtg_mode` / `floor_en` / `graded` / `ged_target` / `sample_ms` | 行为开关 |
| `rtg_pid` | 显式指定参与 RTG 的渲染进程 pid；`0` 表示使用 GED 上报值。用于 GED 静默、只有 DRM present 帧源的场景 |
| `status` | 实时状态：`eff_target`、`cur_pct`、`capped_event`、`foreign_evt`、`rtg_pid`、每 cluster 的 `min/max/user_min/floor/base`，以及 WALT 耦合信息 |

`status` 中的 `min` 是各 cluster 实际生效的最低频；如果 `min != user_min`，说明写入被热控或平台策略拒绝，模块会通过 `capped_event` / `foreign_evt` 记录。

## WALT 与 RTG 联动

提频强度可以接管 WALT governor 的 `hispeed_freq` 和 `rtg_boost_freq`，优先级如下：

| 优先级 | 来源 | 说明 |
|---|---|---|
| 1（最高） | sysfs 手填的 tunable | `rtg_boost_freq` / `walt_hispeed_freq` 非 0 时，后两级失效 |
| 2 | `fps_boost` 的 `boost_pct` | 仅在 `boosting` 期间生效，按每个 cluster 自己的最高频换算并对齐到真实频点 |
| 3 | 内核每 cluster 默认值 | `auto_boost=1` 时的 80% / 70% |

几点说明：

- 提频目标向下取整，`floor` 向上取整，分别保证“不超过百分比”和“不低于百分比”；地板从 1200 变成 1280 只是数值更接近实际频点，硬件行为不变。
- 早判（`sched_walt_early_det`）由内核在 `enable=1` 期间停用，避免与提频重复抬频；关闭模块或卸载时由内核还原。
- 相关状态可以在 `/proc/fps_boost/status` 的 `walt_boost`、`waltpolicyN`、`early_det`、`early_hits` 中查看，也可在 WebUI 的「主界面 → WALT 调度器」中展开。
- 想让内核完全接管频率：把 RTG 目标 / WALT hispeed 留空，或设置 `walt_auto_boost 0` 关闭自动顶频。

两种典型用法：

- **只信 WALT**：`floor_en 0` + `rtg_mode 2` + 设置合适的 `rtg_boost_freq`；
- **只信硬地板**：`rtg_mode 0` + `floor_en 1`。

## WebUI

入口：KernelSU / Magisk 管理器 → 模块 → WebUI。

- **主界面**：模块状态、当前模式、帧率 / 提频 / 热控指标、内核原始状态、WALT 调度器。
- **配置**：每应用参数列表、添加包名、黑名单、从已安装应用中选择，以及快速参数和全局选项。
- **关于**：模块信息、内核状态原文、守护进程日志、配置文件和运行环境自检。

主题按钮按 **跟随系统 → 深色 → 浅色** 循环，选择保存在 `localStorage`。表单中的开关和枚举项使用下拉选择，只有真正需要数值的字段才使用输入框。删除或移除应用会立即写盘，不需要额外点击保存。

## 排障

```sh
cat /data/adb/fps_boost_ctl.state   # 最近一次套用
cat /data/adb/fps_boost_ctl.log     # 守护进程日志
cat /proc/fps_boost/status          # 内核侧真实状态
```

- **状态一直显示空闲，但游戏在掉帧**：确认 `enable=1`、`target_fps` / `target_fps_list` 是期望值，并观察 `samples` 是否增长。
- **WebUI 打不开或报错**：查看「关于 → 运行环境自检」，红条会显示 JS 错误原因。
- **状态栏提示模块未生效**：按提示检查模块是否被禁用、内核是否缺少 `/proc/fps_boost`、守护进程是否运行。
- **提频事件没有日志**：守护进程每秒读取一次 `status`，只在 `boosting` 从 0 变 1 或从 1 变 0 时记录；持续时间短于 1 秒的事件会以「提频(瞬时)」形式补记。

### 开启模块后跑分变低

「保帧提频」类模块会抬高最低频，跑分下降通常是正常代价。可以按以下顺序排查：

1. **模块是否在管理跑分应用**：设置 `only_listed 1`，或把跑分应用加入 `!包名` 黑名单；默认 `*` 行会让任意前台应用在掉帧时被抬频。
2. **WALT governor 是否合适**：先尝试 `walt_pl 0`、`walt_auto_boost 0` 对比；想完全回到系统原生行为就设置 `governor keep`。
3. **是否触发温度墙**：最低频长期抬高会增加功耗和温度，MTK PPM 热控会先把频率上限压下来，导致持续分数更低。可尝试 `mode powersave` 或降低 `boost_pct` / `hold_ms`。
4. **纯 CPU 跑分不渲染**：模块没有帧可依据，不会提频，但可能每 30 秒执行一次 `dumpsys` 作为前台回退；设置 `only_listed 1` 或加入黑名单可以彻底安静。
5. **想要分数优先**：设置 `enable 0` + `governor keep`，并确认 `/proc/fps_boost/floor_en = 0`。

### 旧内核上的 WALT 问题

早期 WALT governor 直接读取原始 util，缺少 `boosted_cpu_util()` 中 schedtune 对前台 cgroup 的加成，导致频率系统性低于 schedutil；这是“开启 walt 后跑分反而低”的主要原因。后续内核已经修复 util 口径，并补齐了 `CPU_FREQ_DEFAULT_GOV_WALT`、`auto_boost` 默认值、按 CPU 判断 RTG 负载和 `avg_cap` 老化等问题。

如果内核仍停留在旧版本，建议先使用 `governor keep`；更新内核后再对比 `governor walt`。

## 与 FAS / fas-rs 的区别

FAS 系方案通常以 eBPF 或用户态守护限制帧时长，用 P 控制器把频率压到“刚好达标”，目标是**限频省电**；本模块是纯内核态的**保帧提频**：掉帧时抬高最低频，并把渲染进程挂入 WALT 的 RTG。

两者可以共存：一个压上限，一个抬下限。热控压低频率上限时，本模块会主动让位，并通过 `capped_event` 记录。

## 打包

```sh
./pack.sh              # 输出到仓库上一级目录
./pack.sh -o /tmp      # 指定输出目录
```

产物命名：

```text
fps_boost_ctl-v<版本>-<YYMMDD>.zip
```

版本号取自 `module.prop`。`pack.sh` 会排除 `.git/`、`pack.sh` 自身、已有 zip 和 macOS 垃圾文件，并在打包后检查 `module.prop`、`customize.sh`、`service.sh`、`bin/`、`conf/` 和 `webroot/index.html` 是否齐全；任何一项缺失都会删除产物并以非 0 退出。

不建议直接执行 `zip -r out.zip .`：当前目录本身是 git 仓库，这样会把整个 `.git/` 历史打进模块，既增大体积，也会在刷入后的模块目录里留下 `.git`。

## 卸载

在 KernelSU / Magisk 管理器中删除模块并重启即可。

以下文件不会随模块自动删除，可按需手动清理：

```text
/data/adb/fps_boost_ctl.conf
/data/adb/fps_boost_ctl.opts
/data/adb/fps_boost_ctl.mode
/data/adb/fps_boost_ctl.state
/data/adb/fps_boost_ctl.log
/data/adb/fps_boost_ctl.pid
```
