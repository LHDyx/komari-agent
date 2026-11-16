# 个人 fork 构建说明（LHDyx）

本目录是 [komari-monitor/komari-agent](https://github.com/komari-monitor/komari-agent) 的个人 fork，
用于自改 + 交叉编译后自用。上游代码 **AGPL-3.0**，本 fork 只自用、不再分发。

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

- 推送到 `main` 或在 Actions 页面手动 `Run workflow` 触发；
- 平台组合与官方 `build_all.sh` 完全一致（windows/linux/darwin/freebsd × amd64/arm64/386/arm，
  排除 windows/arm、darwin/386、darwin/arm，外加 linux/loong64，共 15 个）；
- 产物同时作为 Artifact 上传，并滚动发布到 **tag 为 `custom`** 的 Release（每次删除重建）。

服务器上直接下载（无需登录）：

```bash
curl -fL -o /opt/komari/agent \
  https://github.com/LHDyx/komari-agent/releases/download/custom/komari-agent-linux-amd64
chmod +x /opt/komari/agent
```

每个二进制旁边还有同名 `.sha256` 文件。

## 版本号规则

默认 `最近正式 tag + 1 个 patch + build 元数据`，例如 `1.5.11` → `1.5.12+custom.2611160921.ddbdbdc`：

- build 元数据不参与 semver 比较，所以比官方 `1.5.11` 新、与 `1.5.12` 相等、比 `1.5.13` 旧；
- 不是预发布，面板会正常显示；
- 需要固定版本号时可手动触发并填写 `version` 输入。

## 本地编译

```bash
export PATH=/home/dyx/toolchains/go1.25.11/bin:$PATH
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath \
  -ldflags="-s -w -X github.com/komari-monitor/komari-agent/update.CurrentVersion=$(git describe --tags --abbrev=0)-local" \
  -o build/komari-agent-linux-arm64 .
```

`CGO_ENABLED=0` 必需（项目本身也不依赖 CGO），产物是静态链接。

## 红线

- **服务端必须加 `--disable-auto-update`**：否则官方自动更新会每 6 小时用官方 Release 覆盖自编译版本。
- 自编译产物不要对外分发/对外提供更新源（AGPL-3.0 + 不冒充官方）。
- 本机 git 全局配置了 `http.proxy=127.0.0.1:10808`，代理没开时访问 GitHub 会直接失败。
