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
- 产物同时作为 Artifact 上传，并发布为**预发布 Release**，tag 形如 `1.5.11-custom.2611161100`；
- 只保留最近 10 个自构建 Release，更早的自动删除（按时间戳倒序）。

下载某一个具体构建（tag 换成你要的那次）：

```bash
curl -fL -o /tmp/komari-agent \
  https://github.com/LHDyx/komari-agent/releases/download/1.5.11-custom.2611161100/komari-agent-linux-amd64
sha256sum -c <(curl -fsSL .../komari-agent-linux-amd64.sha256 | sed "s#komari-agent-#/tmp/komari-agent#")
install -m755 /tmp/komari-agent /opt/komari/agent
```

每个二进制旁边都有同名 `.sha256` 文件。

## 版本号规则

基础版本始终与官方最近正式 tag 同步（当前 `1.5.11`），不领先：

| 用途 | 格式 | 示例 |
| --- | --- | --- |
| 二进制内嵌版本 | `<正式 tag>-0.custom.<yymmddhhMM>` | `1.5.11-0.custom.2611161100` |
| Release tag | `<正式 tag>-custom.<yymmddhhMM>` | `1.5.11-custom.2611161100` |

- 内嵌版本多一级预发布 `-0`，让它**严格低于**同号正式版和任何 `1.5.11-custom.*`，
  这样后续自构建才被更新器识别为“更新”；
- Release tag 用时间戳递增，是当前自构建的“新版本号”；
- `+`/`-` 的判定完全以 `blang/semver` 实测为准（`x.y.z-alpha.123` 小于 `x.y.z`）。
  需要固定内嵌版本号时可手动触发并填写 `version`。

## 自动更新

默认更新源就是这个 fork（`LHDyx/komari-agent`），不需要额外参数；`--update-repo` / `AGENT_UPDATE_REPO`
可改回官方（`komari-monitor/komari-agent`）或指向别处。

```bash
komari-agent --endpoint https://你的面板 --token xxx          # 默认：只跟随本仓库的自构建
komari-agent --endpoint ... --update-repo komari-monitor/komari-agent   # 切回官方源
```

规则：

- 更新源不是官方仓库时自动打开“允许预发布”，但**只接受 tag 含 `-custom.` 的自构建**，
  不会被官方同名正式版（如 `1.5.11`）顶掉；指回官方仓库时恢复原始稳定通道规则；
- 只跟进当前 major.minor 线内更高的版本，每次成功构建的 `1.5.11-custom.<较新时间戳>` 都是候选；
- 指向自己的仓库后**不再收到官方更新**，官方发新版需要 `./sync-upstream.sh` 手动跟并重新构建；
- 更新是原地替换二进制，失败只能手动覆盖回滚；更新成功后进程以退出码 42 退出，靠 systemd 拉起；
- 容器内（存在 `/.komari-agent-container`）一律跳过自升级。

## 本地编译

```bash
export PATH=/home/dyx/toolchains/go1.25.11/bin:$PATH
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath \
  -ldflags="-s -w -X github.com/komari-monitor/komari-agent/update.CurrentVersion=$(git describe --tags --abbrev=0)-local" \
  -o build/komari-agent-linux-arm64 .
```

`CGO_ENABLED=0` 必需（项目本身也不依赖 CGO），产物是静态链接。

## 红线

- 默认更新源是本 fork；加 `--disable-auto-update` 会完全关闭自动更新。
- 切回官方源（`--update-repo komari-monitor/komari-agent`）时，自构建版本会被官方更高版本覆盖。
- 自编译产物不要对外分发/对外提供更新源（AGPL-3.0 + 不冒充官方）。
- 本机 git 全局配置了 `http.proxy=127.0.0.1:10808`，代理没开时访问 GitHub 会直接失败。
