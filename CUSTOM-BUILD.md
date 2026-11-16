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
- 产物同时作为 Artifact 上传，并发布为**预发布 Release**，tag 形如 `1.5.13-custom.2611161036`；
- 只保留最近 10 个自构建 Release，更早的自动删除。

下载某一个具体构建（tag 换成你要的那次）：

```bash
curl -fL -o /tmp/komari-agent \
  https://github.com/LHDyx/komari-agent/releases/download/1.5.13-custom.2611161036/komari-agent-linux-amd64
sha256sum -c <(curl -fsSL .../komari-agent-linux-amd64.sha256 | sed "s#komari-agent-#/tmp/komari-agent#")
install -m755 /tmp/komari-agent /opt/komari/agent
```

每个二进制旁边都有同名 `.sha256` 文件。

## 版本号规则

| 用途 | 格式 | 示例 |
| --- | --- | --- |
| 二进制内嵌版本 | `<最近正式 tag +1 patch>+custom.<yymmddhhMM>.<sha>` | `1.5.12+custom.2611161036.d4f4eda` |
| Release tag | `<最近正式 tag +2 patch>-custom.<yymmddhhMM>` | `1.5.13-custom.2611161036` |

- 内嵌版本的 `+custom…` 是 build 元数据，不参与 semver 比较：它**等于** `1.5.12`，比官方 `1.5.11` 新；
- Release tag 必须是**预发布**，且**比内嵌版本高一个 patch**。原因是 `blang/semver` 的一处怪癖：
  `1.5.12-custom.123`（alpha + 数字）会被判为**小于** `1.5.12`，用它当 tag 会永远选不中；
  抬到 `1.5.13-custom.*` 后严格更大，并按时间戳递增，可作为自构建之间的更新源；
- 需要固定内嵌版本号时可手动触发并填写 `version` 输入（Release tag 仍按上面的规则生成）。

## 自动更新

默认更新源仍是上游 `komari-monitor/komari-agent`。改成自己的仓库：

```bash
komari-agent --endpoint ... --token ... --update-repo LHDyx/komari-agent   # 且不要加 --disable-auto-update
# 或 AGENT_UPDATE_REPO=LHDyx/komari-agent
# 实测日志：No stable release asset was found for komari-agent-linux-amd64 in 1.5.*.
```

- **重要：自动更新会跳过你的自构建。** `selectLatestStableRelease` 会跳过 GitHub 上标记为
  prerelease 的 Release，以及任何带 `-` 预发布标识的 tag。因此预发布的自构建不会被自动拉取；
  发布成正式 Release 也不行（tag 带 `-custom.` 仍被跳过）。
- 实际可选择的两条路：
  1. **手动更新**（推荐）：加 `--disable-auto-update`，每次构建后用 `curl` + `.sha256` 覆盖二进制；
  2. **给每次构建打正式 semver tag**（如 `1.5.13`、`1.5.14`…，不带任何 `-` 预发布段）并发布为正式
     Release，此时 `--update-repo LHDyx/komari-agent` 会被自动升级到最新 tag。代价：这些 tag 会占用
     官方版本号，将来官方发同名版本时会撞车。
- 默认更新源仍是上游仓；`--update-repo` / `AGENT_UPDATE_REPO` 只是切换查询的仓库。
- 指向自己的仓库后**不再收到官方更新**，官方发布新版本需要你用 `./sync-upstream.sh` 手动跟；
- 更新是原地替换二进制，失败只能手动覆盖回滚；更新成功时进程以退出码 42 退出，靠 systemd 拉起。

## 本地编译

```bash
export PATH=/home/dyx/toolchains/go1.25.11/bin:$PATH
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath \
  -ldflags="-s -w -X github.com/komari-monitor/komari-agent/update.CurrentVersion=$(git describe --tags --abbrev=0)-local" \
  -o build/komari-agent-linux-arm64 .
```

`CGO_ENABLED=0` 必需（项目本身也不依赖 CGO），产物是静态链接。

## 红线

- 默认更新源是官方仓；不加 `--disable-auto-update` 就会在 6 小时内被官方版覆盖。
  指向自己的仓库（`--update-repo LHDyx/komari-agent`）后同理：不要同时加 `--disable-auto-update`。
- 自编译产物不要对外分发/对外提供更新源（AGPL-3.0 + 不冒充官方）。
- 本机 git 全局配置了 `http.proxy=127.0.0.1:10808`，代理没开时访问 GitHub 会直接失败。
