# komari-agent（个人 fork）项目说明

这是 LHDyx 对 [komari-monitor/komari-agent](https://github.com/komari-monitor/komari-agent) 的个人 fork，
目的是小改后用在自己的服务器上。构建方式、跟进上游、版本号规则见 `CUSTOM-BUILD.md`。

## 当前状态（2026-11-16）

- 已完整克隆上游，HEAD = `ddbdbdc`（对应 `Snapshot-2610260110`，最近正式 tag 为 `1.5.11`）。
- 本地新增：`.github/workflows/custom-build.yml`（15 平台在线交叉构建 + 滚动 `custom` Release）、
  `sync-upstream.sh`（跟进上游，已 gitignore）、`CUSTOM-BUILD.md`。
- 尚未在自己账号上创建 fork、尚未推送。

## 红线

- 服务端启动参数必须带 `--disable-auto-update`，否则官方自动更新会覆盖自编译版本。
- 产物只自用，不对外分发或提供更新源（AGPL-3.0 + 不冒充官方）。
- 交叉编译一律 `CGO_ENABLED=0`。
- 不要 push 到 `upstream` remote。

## 常用命令

```bash
export PATH=/home/dyx/toolchains/go1.25.11/bin:$PATH
go build -o /dev/null .          # 编译自检
go test ./...                    # 单测
./sync-upstream.sh --check       # 检查上游更新
```
