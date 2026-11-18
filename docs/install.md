# 安装与部署

> **本 fork 的安装脚本默认从 `LHDyx/komari-agent` 的 Release 下载**，并会校验发布产物附带的
> `.sha256`。面板自带的“一键部署”按钮仍指向官方脚本，要安装本 fork 请使用下面第一节的命令。

## 零、从本 fork 安装（对应面板一键部署）

把面板生成命令里的脚本地址换成我们的仓库即可；参数保持面板生成的内容不变：

```bash
# Linux（root / sudo）
wget -qO- https://raw.githubusercontent.com/LHDyx/komari-agent/refs/heads/main/install.sh \
  | sudo bash -s -- -e https://你的面板 -t TOKEN

# macOS
zsh <(curl -sL https://raw.githubusercontent.com/LHDyx/komari-agent/refs/heads/main/install.sh) \
  -e https://你的面板 -t TOKEN

# Windows（管理员 PowerShell）
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
  "iwr 'https://raw.githubusercontent.com/LHDyx/komari-agent/refs/heads/main/install.ps1' -UseBasicParsing -OutFile '.\install.ps1'; & '.\install.ps1' -e https://你的面板 -t TOKEN"
```

自动发现同理，把面板生成的 `-t TOKEN` 换成 `--auto-discovery KEY`。

脚本行为（与官方一致的部分不再赘述）：

| 行为 | 说明 |
| --- | --- |
| 版本解析 | 自动选择最新的 `<x.y.z>-custom.<i>` 正式构建，忽略预览版和 Snapshot |
| 指定版本 | `--install-version 1.5.11-custom.1`（也接受预览版 tag） |
| 校验 | 下载后校验 `.sha256`，不匹配立即中止；`--install-no-verify` 可关闭 |
| 预演 | `--install-dry-run` 只打印解析出的版本与 URL，不下载、不安装 |
| 换仓库 | `--install-repo owner/name`；指向官方仓库时自动回退到 `releases/latest` |

> 面板的 **Docker 一键部署**仍使用官方镜像；本 fork 暂未发布 `ghcr.io` 镜像。

## 一、Linux / macOS / FreeBSD：`install.sh`

### 1. 参数

```bash
curl -fsSL https://raw.githubusercontent.com/LHDyx/komari-agent/main/install.sh | bash -s -- -e <面板> -t <token>

# 安装相关参数（--install-*）
--install-dir <目录>          安装目录
--install-service-name <名>   服务名，默认 kmr-ag
--install-ghproxy <前缀>      GitHub 代理前缀
--install-version <版本>      指定版本，或 snapshot
--install-no-mirror           关闭自动镜像回退
# 其余参数原样传给 agent（-e / -t / --disable-auto-update ...）
```

### 2. 安装位置与服务类型

| 身份 / 系统 | 安装目录 | 服务 |
| --- | --- | --- |
| root + Linux | `/opt/kmr/lh` | systemd 系统服务（`kmr-ag.service`） |
| 普通用户 + Linux | `${XDG_DATA_HOME:-~/.local/share}/kmr/lh` | systemd 用户服务（`kmr-ag.service`） |
| macOS + root | `/opt/kmr/lh` | LaunchDaemon（`com.komari.kmr-ag.plist`） |
| macOS + 用户 | `~/.kmr/lh`（`/opt/kmr/lh` 不可写时） | LaunchAgent |
| FreeBSD | `/opt/kmr/lh`（非 root 用 XDG 路径） | OpenRC / rc（`/etc/init.d/kmr-ag`） |
| Windows (MSYS) | `C:\kmr\lh` | 脚本不注册服务 |
| Windows（`install.ps1`） | `C:\kmr\lh` | `kmr-ag`（nssm，本地名 `sm.exe`） |

服务运行账号默认是 `SUDO_USER`（sudo 前的用户），不是 root。

> **从旧默认迁移**：旧版本使用服务名 `komari-agent`、目录 `/opt/komari`、二进制 `agent`。
> 新脚本只按新名字清理，不会自动移除旧服务；升级前请先停用并删除旧服务/二进制，
> 否则会同时存在两套。

**磁盘上的二进制名**：Linux / macOS / FreeBSD 为 `<安装目录>/lh_kmr_ag`；Windows 为
`C:\kmr\lh\lh_kmr_ag.exe`。下载的 Release 资产名仍是 `komari-agent-<os>-<arch>`（Windows 带 `.exe`），
安装时重命名。

### 3. 执行步骤

1. **检测系统与架构**：`uname -m` → `amd64 / arm64 / 386 / arm / loong64`
2. **检查依赖**：`curl`，缺失时按 `apt / yum / apk / opkg / brew` 自动安装
3. **解析版本**：`latest` / 指定版本 / `snapshot`（查 GitHub API 找最新 `Snapshot-*`）
4. **下载**：`releases/<版本>/komari-agent-<os>-<arch>`
   - 直连失败自动依次尝试 `ghfast.top`、`gh-proxy.com`、`ghproxy.net`
   - `--install-ghproxy` 指定代理；`--install-no-mirror` 禁用回退
   - **脚本不校验 sha256**，只检查文件非空
5. **清理旧安装**：停止并删除旧服务单元、旧二进制
   - 不会删除 `net_static.json`、`config.json`、`auto-discovery.json`
6. **写入服务单元并启动**

### 4. 各 init 系统的服务定义

| init | 关键配置 |
| --- | --- |
| systemd | `Type=simple`、`Restart=always`、`WorkingDirectory=<安装目录>`、`User=<服务用户>` |
| systemd --user | 同上，`WantedBy=default.target` |
| OpenRC | `supervise-daemon`、`retry=SIGTERM/30` |
| procd（OpenWrt） | 参数逐个 `procd_append_param`、`respawn`、`user` |
| launchd | plist、`RunAtLoad`、`KeepAlive`，日志到 `~/Library/Logs` 或 `/var/log` |
| Upstart | `respawn limit 10 5` |
| NixOS | 不写服务，打印声明式配置片段 |

`Restart=always` / `respawn` 是把**退出码 42**（自更新完成）变成平滑升级的关键：
agent 更新后主动退出，服务管理器立即拉起新版本。

示例（systemd）：

```ini
[Unit]
Description=Komari Agent Service
After=network.target

[Service]
Type=simple
ExecStart=/opt/kmr/lh/lh_kmr_ag -e https://panel.example.com -t xxx
WorkingDirectory=/opt/kmr/lh
Restart=always
User=www-data

[Install]
WantedBy=multi-user.target
```

## 二、Windows：`install.ps1`

1. 默认安装目录 `C:\Program Files\Komari`（可用 `--install-dir` 覆盖）
2. 准备服务管理器：优先复用 PATH 中的 nssm，否则下载 nssm，统一保存为
   `C:\kmr\lh\sm.exe`，之后所有操作都用它执行
3. 停止并移除旧服务（`sm remove kmr-ag confirm`，失败回退 `sc.exe delete`），删除旧二进制
   `C:\kmr\lh\lh_kmr_ag.exe`
4. 解析版本（`latest` / 指定 / `snapshot`）并下载 `komari-agent-windows-<arch>.exe`
5. 用 `sm.exe` 注册并启动服务：

```powershell
& C:\kmr\lh\sm.exe install kmr-ag C:\kmr\lh\lh_kmr_ag.exe "-e ... -t ..."
& C:\kmr\lh\sm.exe set kmr-ag DisplayName "Komari Agent Service"
& C:\kmr\lh\sm.exe set kmr-ag Start SERVICE_AUTO_START
& C:\kmr\lh\sm.exe set kmr-ag AppExit Default Restart
& C:\kmr\lh\sm.exe set kmr-ag AppRestartDelay 5000
& C:\kmr\lh\sm.exe start kmr-ag
```

6. 服务启动后，agent 会向每个交互式登录会话弹出安全通知（见
   [windows-notification.md](windows-notification.md)）

注意事项：

- 服务默认以 **LocalSystem** 运行（nssm 默认），因此能向用户会话注入通知进程
- 命令执行依赖 PowerShell；Web SSH 依赖 ConPTY（Windows 10 1809+）
- 自更新替换正在运行的服务二进制由 `go-update` 处理，重启由 nssm 负责

## 三、Docker

官方 `Dockerfile`：

```dockerfile
FROM alpine:3.21
WORKDIR /app
COPY --chmod=755 komari-agent-${TARGETOS}-${TARGETARCH} /app/komari-agent
RUN touch /.komari-agent-container
ENTRYPOINT ["/app/komari-agent"]
```

要点：

- **容器内检测到 `/.komari-agent-container` 就跳过自更新**，升级靠换镜像
- 镜像需要预先放入对应架构的二进制（构建上下文）
- 监控宿主进程时可设 `HOST_PROC=/host/proc` 并挂载 `/proc`
- 运行示例：

```bash
docker run -d --name komari-agent --network host --pid host \
  -v /proc:/host/proc:ro -e HOST_PROC=/host/proc \
  ghcr.io/komari-monitor/komari-agent:latest -e https://panel.example.com -t xxx
```

## 四、安装后建议

1. **校验哈希**：我们的 Release 每个二进制都附带 `.sha256`，官方脚本不校验，建议手动核对
2. **`--disable-web-ssh`**：如果面板暴露在公网且不需要远程控制
3. **固定 `--update-repo`**：明确更新源（本 fork 默认即自己的仓库）
4. **检查工作目录**：流量统计文件写在服务工作目录，迁移前先备份 `net_static.json`
5. **安全提示默认关闭**（本 fork）：需要时加 `--enable-security-warning`；
   Linux 会写 `/etc/motd`，Windows 会弹 Toast（见 [windows-notification.md](windows-notification.md)）
