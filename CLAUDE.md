# komari-agent（个人 fork）项目说明

这是 LHDyx 对 [komari-monitor/komari-agent](https://github.com/komari-monitor/komari-agent) 的个人 fork，
目的是小改后用在自己的服务器上。构建方式、跟进上游、版本号规则见 `CUSTOM-BUILD.md`。

## 当前状态（2026-11-16）

- 已完整克隆上游，HEAD = `ddbdbdc`（对应 `Snapshot-2610260110`，最近正式 tag 为 `1.5.11`）。
- 已 fork 到 LHDyx/komari-agent，main 跟踪 upstream，SSH 部署密钥可写。
- 本地新增：`.github/workflows/custom-build.yml`（15 平台在线交叉构建 + 预发布 Release）、
  `sync-upstream.sh`（跟进上游，已 gitignore）、`CUSTOM-BUILD.md`。
- 代码改动：新增 `--update-repo` / `AGENT_UPDATE_REPO`，可把自动更新源指向自己的 fork（`feat/self-update-repo`）。

## 红线

- 不加 `--disable-auto-update` 时，自动更新源默认是官方仓，会在 6 小时内覆盖自编译版本。
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
