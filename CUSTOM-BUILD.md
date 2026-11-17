# 个人 fork 构建说明（LHDyx）

本目录是 [komari-monitor/komari-agent](https://github.com/komari-monitor/komari-agent) 的个人 fork，
用于自改 + 交叉编译后自用。上游代码 **AGPL-3.0**，本 fork 只自用、不再分发。

项目功能与流程见 `docs/`（`overview.md`、`monitoring-and-control.md`、`install.md`、
`windows-notification.md`）。

## 远程仓库

| remote | 地址 | 用途 |
| --- | --- | --- |
| `upstream` | `https://github.com/komari-monitor/komari-agent` | 官方，只读，勿 push |
| `origin` | `https://github.com/LHDyx/komari-agent` | 自己的 fork |

## 跟进上游

```bash
./sync-upstream.sh --check   # 只看落后多少
./sync-upstream.sh           # 变基到 upstream/main、构建自检、强制推送 fork
./sync-upstream.sh --no-push # 变基但不推送
```

自改（含工作区未提交改动）会被自动 stash / 变基并保留；变基前会打 `backup/pre-sync-*` tag 便于回退；
冲突时脚本会停下并给出处理步骤。

## 在线交叉构建

`.github/workflows/custom-build.yml`：

- **只在 Actions 页面手动触发**（推送 main 不会构建）；`kind` 选 `preview` 或 `release`；
- 上游继承来的 `Build on Main`、`Publish Snapshot` 也已改为仅手动触发，避免每次推送跑 40+ 个任务；
- 平台组合与官方 `build_all.sh` 完全一致（windows/linux/darwin/freebsd × amd64/arm64/386/arm，
  排除 windows/arm、darwin/386、darwin/arm，外加 linux/loong64，共 15 个）；
- 产物同时作为 Artifact 上传，并发布为 Release；发布时会清理不符合当前命名方案的旧 Release。

## 版本号规则

基础版本始终与官方最近正式 tag 同步（当前 `1.5.11`），不领先；**二进制内嵌版本与 tag 完全一致**。

| 用途 | tag / 内嵌版本 | Release 标记 | 自动更新 |
| --- | --- | --- | --- |
| 预览版 | `<基础版本>-custom-pre.<i>` | pre-release | ❌ 仅供人工手动替换 |
| 正式版 | `<基础版本>-custom.<i>` | 正式 Release | ✅ 自动通道唯一目标 |

- 两支 `i` **各自独立递增**，并从仓库现有 tag 推断（取同基础版本下的最大值 +1）；
- 官方换代后重置：`1.5.12-custom-pre.1`、`1.5.12-custom.1` 重新从 1 开始；
- 注意 `blang/semver` 里 `custom-pre.<i>` 按字符串比较 `"custom-pre" > "custom"`，
  所以**同一基础版本下预览版的版本号永远比正式版“大”**。这是设计上的：预览版只人工使用，
  自动通道用 `isCustomReleaseVersion` 限定只接受 `<base>-custom.<i>`，不会被预览版抢走；
- 发布顺序不受影响：`custom.1 < custom.2 < ...` 在正式版之间严格递增。

## 下载与替换

```bash
TAG=1.5.11-custom.1          # 预览版换成 1.5.11-custom-pre.1 这类
BIN=komari-agent-linux-amd64 # amd64 换成 arm64 等
D=/tmp/ka-dl && mkdir -p "$D" && cd "$D"
curl -fsSLO "https://github.com/LHDyx/komari-agent/releases/download/$TAG/$BIN"
curl -fsSLO "https://github.com/LHDyx/komari-agent/releases/download/$TAG/$BIN.sha256"
sha256sum -c "$BIN.sha256"
install -m755 "$BIN" /opt/komari/agent
```

## 自动更新

默认更新源就是这个 fork（`LHDyx/komari-agent`），不需要额外参数：

```bash
komari-agent --endpoint https://你的面板 --token xxx                     # 默认：跟随正式版
komari-agent --endpoint ... --update-repo komari-monitor/komari-agent    # 切回官方源
```

规则：

- **自动通道只认 `<base>-custom.<i>`**：`-custom-pre.<i>` 预览版与官方版本都不会被自动选中；
- 内嵌版本等于本次 tag 时不会重复安装（`latest.Equals(current)` 直接跳过）；
- 只跟进当前 major.minor 线内更高的版本；
- 指向自己的仓库后不再收到官方更新，官方发新版需 `./sync-upstream.sh` 手动跟并重新构建；
- 更新是原地替换二进制，失败只能手动覆盖回滚；更新成功后进程以退出码 42 退出，靠 systemd 拉起；
- 容器内（存在 `/.komari-agent-container`）一律跳过自升级。

## 本地编译

日常改动用脚本构建验证，不消耗 Actions 额度：

```bash
./build-local.sh                          # 默认 linux/amd64
./build-local.sh linux/amd64 linux/arm64  # 指定目标
VERSION=1.5.11-custom.9 ./build-local.sh  # 指定内嵌版本号
```

产物在 `build/`（已 gitignore），每个二进制带同名 `.sha256`。默认内嵌版本为
`<最近正式tag>-local.<sha>`，可直接 `./build/komari-agent-linux-amd64 --endpoint ...` 试跑。

等改动确认后再手动触发 Actions 发布预览版/正式版。

## 红线

- 默认更新源是本 fork；加 `--disable-auto-update` 会完全关闭自动更新。
- 预览版永远不进入自动通道，必须人工替换。
- 切回官方源（`--update-repo komari-monitor/komari-agent`）时，自构建版本会被官方更高版本覆盖。
- 自编译产物不要对外分发/对外提供更新源（AGPL-3.0 + 不冒充官方）。
- 本机 git 全局配置了 `http.proxy=127.0.0.1:10808`，代理没开时访问 GitHub 会直接失败。
