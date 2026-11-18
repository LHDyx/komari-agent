# komari-agent（个人 fork）项目说明

这是 LHDyx 对 [komari-monitor/komari-agent](https://github.com/komari-monitor/komari-agent) 的个人 fork，
目的是小改后用在自己的服务器上。构建方式、跟进上游、版本号规则见 `CUSTOM-BUILD.md`。

完整文档见 `docs/`：

- `docs/overview.md` 项目结构、启动流程、配置、连接与自更新
- `docs/monitoring-and-control.md` 指标、协议、命令/终端/文件
- `docs/install.md` 安装脚本逐段行为、各平台服务、Docker
- `docs/windows-notification.md` Windows 安装后 Toast 通知的完整行为

## 当前状态（2026-11-17）

- 基于上游 `ddbdbdc`，本地已叠加自改提交；最近正式 tag 为 `1.5.11`。
- 已发布 `1.5.11-custom.1`（正式）与 `1.5.11-custom-pre.1~4`（预览）。
- 已 fork 到 LHDyx/komari-agent，main 跟踪 upstream，SSH 部署密钥可写。
- 本地新增：`.github/workflows/custom-build.yml`（15 平台在线交叉构建 + 预发布 Release）、
  `sync-upstream.sh`（跟进上游，已 gitignore）、`build-local.sh`（本地交叉编译）、`CUSTOM-BUILD.md`。
- 所有 GitHub Actions 均已改为**仅手动触发**，推送 main 不构建；日常改动用 `./build-local.sh`。
- 安装默认值：服务名 `kmr-ag`；目录 `/opt/kmr/lh`（Linux/macOS root）、`C:\kmr\lh`（Windows）；
  二进制 `lh_kmr_ag`（Windows `lh_kmr_ag.exe`）；Windows 服务管理器 nssm 统一保存为 `sm.exe`。
- 代码改动：`--update-repo` / `AGENT_UPDATE_REPO`，**默认更新源已是 LHDyx/komari-agent**；
  `--enable-security-warning`（默认 false，关闭 Linux MOTD 与 Windows Toast）；
  非官方源时打开 allowPrerelease，只接受 tag 含 `-custom.` 的自构建。
- 版本号：预览 `<base>-custom-pre.<i>`，正式 `<base>-custom.<i>`，两支 i 独立计数；内嵌版本与 tag 相同。
  自动通道（`isCustomReleaseVersion`）只接受 `<base>-custom.<i>`，预览版只供人工替换。

## 红线

- 默认更新源是本 fork；把 `--update-repo` 改回官方时，官方更高版本会覆盖自构建。
- 产物只自用，不对外分发或提供更新源（AGPL-3.0 + 不冒充官方）。
- 交叉编译一律 `CGO_ENABLED=0`。
- `blang/semver` 把 `x.y.z-alpha.123` 判为小于 `x.y.z`（预发布含 alpha+数字），
  生成 tag/版本号时必须实测比较结果，不要按 semver 规范想当然。
- 不要 push 到 `upstream` remote。

## 常用命令

```bash
export PATH=/home/dyx/toolchains/go1.25.11/bin:$PATH
go build -o /dev/null .          # 编译自检
go test ./...                    # 单测
./sync-upstream.sh --check       # 检查上游更新
```
