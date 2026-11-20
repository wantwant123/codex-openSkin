# Codex OpenSkin · 翡翠觉醒

在 Codex 桌面窗口上播放《翡翠觉醒》。11 秒有声开屏从金色星光和线稿过渡到银发女孩与掌心水晶。打开循环背景后，开屏会衔接一段 6 秒的无声动画。菜单中另有 23 秒的完整成片预览。

## 下载与使用

从 [GitHub Releases](https://github.com/wantwant123/codex-openSkin/releases/latest) 下载对应的 ZIP 并解压。

| 系统 | 下载包 | 如何启动 |
| --- | --- | --- |
| macOS 13+，Apple Silicon 或 Intel | `CodexOpenSkin-macOS-universal.zip` | 把 `CodexBootAnimation.app` 拖入「应用程序」后打开，点菜单栏的 ✨。 |
| Windows 10/11 x64，.NET Framework 4.8 | `CodexOpenSkin-Windows-x64.zip` | 完整解压，在文件夹内双击 `CodexOpenSkin.exe`，右击系统托盘图标。Windows N 版播放 MP4 需要系统媒体功能包。 |

先启动 OpenSkin，再打开 Codex 桌面窗口。默认每个新窗口播放一次，右上角可跳过，动画其余区域支持点击穿透。拖动或缩放 Codex 时画面随窗口移动，切换到其他窗口或最小化时隐藏并暂停。

- **播放一次开屏**可以在已有窗口重播。Windows 上双击托盘图标，或选择「在 Codex 上播放开屏」，即可将已有 Codex 窗口调到前台播放。系统限制窗口激活时，在 15 秒内切回 Codex 即可。
- **完整预览**可按原速播放 23 秒原片。Windows 托盘中的「在 Codex 上播放完整影片」同样覆盖 Codex 窗口。Mac 的独立预览入口在「设置…」。
- **动态背景**默认关闭。Mac 可在设置中调整透明度和开屏时长，Windows 可在托盘菜单开启低透明度背景。
- 菜单中的**退出**会关闭助手。应用独立运行，不修改 Codex 安装文件。

macOS 使用临时签名，未经 Apple 公证。Windows 可执行文件无代码签名。每个发布版本附有两个 ZIP 的 SHA-256 校验值。

## 构建与发布

GitHub Actions 在 macOS 和 Windows 原生 runner 上测试、打包。推送到 main 可在该次运行的 Artifacts 中下载测试包；推送版本标签（例如 `v0.5.0`）时，两端通过后会自动建立 GitHub Release 并上传 ZIP 和校验文件。

本地构建 macOS 需要 Xcode Command Line Tools。

```sh
bash scripts/build.sh
bash scripts/test.sh
```

本地构建 Windows 需要 .NET SDK 和 .NET Framework 4.8 Developer Pack。

```powershell
dotnet build Windows/OpenSkin.csproj -c Release -o dist/CodexOpenSkin
```

## 跟随验收

```bash
bash scripts/build.sh
bash scripts/test.sh --fixture
```

打开 `build/FollowFixture.app` 和 `build/FollowOverlay.app`，在浮层设置中点“播放一次”，再在测试窗口点“运行跟随验收”。测试窗口只操作它自己的窗口；测试浮层的目标仅为 `local.codexboot.fixture`。持续跟随模式把开屏暂时延长到 3600 秒，不影响正式应用的 11 秒默认值。

验收会依次移动、缩放、最小化、恢复、新建第二窗口、切回第一窗口。日志在 `output/follow-test/events.jsonl`，包含目标与浮层边界，可检查是否完全一致。

在同一测试会话中完成持续跟随后，把时长改为 2 秒、关闭循环背景，再播放并运行一次验收，验证自动淡出。随后可运行 `python3 scripts/check-follow-log.py` 检查边界一致性、隐藏恢复、固定窗口和自动清理。此检查需要上述两种场景的日志，单纯运行持续跟随不会产生自动淡出记录。

正式配置和限长日志位于 `~/Library/Application Support/CodexBootAnimation/`。程序只读取窗口 PID、编号、层级和边界，不读取窗口标题、代码或对话，不申请辅助功能或屏幕录制权限，没有网络请求。

Windows 自动化检查在原生测试窗口上验证前台进程筛选、窗口坐标跟随、点击穿透样式、最小化与关闭，并逐文件验证安装包里的影片。真实 Codex 的多屏、全屏、媒体播放体验还需要桌面实机验收。

## 来源

《翡翠觉醒》的视频由用户提供，视频授权与本项目代码分开。窗口跟随方案参考 [wynneceles/ai-boot-animations](https://github.com/wynneceles/ai-boot-animations)。本项目代码许可见 `LICENSE`。
