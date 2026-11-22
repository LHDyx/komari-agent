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
| 版本解析 | 自动选择最新的 `<x.y.z>-custom.<i>` 正式构建，忽略预览版和 Snapshot；
  解析顺序：GitHub API（多镜像）→ `version.txt`（raw，经镜像）→ `releases.atom`；
  全部失败时可用 `--install-version <tag>` 指定 |
| 指定版本 | `--install-version 1.5.11-custom.1`（也接受预览版 tag） |
| 校验 | 下载后校验 `.sha256`，不匹配立即中止；`--install-no-verify` 可关闭 |
| 预演 | `--install-dry-run` 只打印解析出的版本与 URL，不下载、不安装 |
| 换仓库 | `--install-repo owner/name`；指向官方仓库时自动回退到 `releases/latest` |

> 面板的 **Docker 一键部署**仍使用官方镜像；本 fork 暂未发布 `ghcr.io` 镜像。

## 零之二、导入官方安装命令

如果手上只有面板生成的官方一键命令（Linux/macOS 的 `wget ... | bash -s -- ...`、
Windows 的 `powershell ... -Command "iwr ...; & '.\install.ps1' ..."`），可以用导入脚本
自动提取参数，再安装本 fork：

```bash
# Linux / macOS：先下载再运行（不要用 curl | bash，避免占用 stdin）
curl -fsSL -o /tmp/import-command.sh \
  https://raw.githubusercontent.com/LHDyx/komari-agent/refs/heads/main/import-command.sh
sudo bash /tmp/import-command.sh
# 按提示粘贴官方命令，回车
```

也可以直接传入或从管道读取：

```bash
sudo bash /tmp/import-command.sh '<官方命令>'
cat official-command.txt | sudo bash /tmp/import-command.sh
sudo bash /tmp/import-command.sh --dry-run '<官方命令>'   # 只解析不安装
```

Windows：

```powershell
iwr 'https://raw.githubusercontent.com/LHDyx/komari-agent/refs/heads/main/import-command.ps1' -UseBasicParsing -OutFile import-command.ps1
.\import-command.ps1            # 粘贴官方命令
.\import-command.ps1 -AgentCommand '<官方命令>' -DryRun
```

> 导入脚本需要 bash（Linux/macOS）或 PowerShell 5.1+（Windows）。

行为：

- 只提取白名单内的 agent / 安装参数（`-e -t -i --month-rotate --install-*` 等），
  忽略脚本 URL、`sudo`、`powershell -Command`、`iwr/-UseBasicParsing` 等噪声
- 校验必须解析出端点，以及 token 或自动发现 key，否则退出
- 输出中 token/key 会打码；默认需要确认，`--yes` 可跳过
- `--dry-run` 只打印解析结果
- 解析完成后调用本仓库的 `install.sh` / `install.ps1`，后续就是正常的安装流程

## 零之三、离线安装器（连不上 GitHub）

滚动标签 **`installer`** 的 Release 提供每个平台/架构一个可执行文件，内嵌对应 agent、
安装脚本和（Windows）nssm，不需要访问 GitHub：

```bash
# Linux（以 amd64 为例）
curl -fsSLO https://github.com/LHDyx/komari-agent/releases/download/installer/komari-agent-installer-linux-amd64
chmod +x komari-agent-installer-linux-amd64
sudo ./komari-agent-installer-linux-amd64 -e https://status.lhdyx.top -t '<TOKEN>' -i 10 --month-rotate 1
```

```powershell
# Windows（管理员 PowerShell）
iwr 'https://github.com/LHDyx/komari-agent/releases/download/installer/komari-agent-installer-windows-amd64.exe' -UseBasicParsing -OutFile kmr-installer.exe
.\kmr-installer.exe -e https://status.lhdyx.top -t '<TOKEN>' -i 10 --month-rotate 1
```

其他资源名：`komari-agent-installer-linux-arm64`、`linux-arm`、`linux-386`、`linux-loong64`、
`windows-arm64.exe`、`darwin-amd64|arm64`、`freebsd-*`，均带同名 `.sha256`。

安装器选项：

| 选项 | 作用 |
| --- | --- |
| `--extract <目录>` | 只释放文件（agent、安装脚本、sha256、README），拷到离线机器再安装 |
| `--dry-run` | 显示目标平台、内嵌 agent 版本和参数 |
| `--version` | 显示内嵌 agent 版本 |
| `--keep-temp` | 安装后保留临时目录 |

- agent 参数（`-e/-t/-i/--month-rotate/--disable-web-ssh/...`）原样透传
- 安装器不需要联网；**agent 连面板仍然需要网络**
- 离线环境建议加 `--disable-auto-update`（自动更新需要访问 GitHub）

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

### 自动清理旧版本安装

脚本会在安装前检查旧默认安装（服务名 `komari-agent`、目录 `/opt/komari`、二进制 `agent`；
Windows 为 `komari-agent` 服务与 `C:\Program Files\Komari\komari-agent.exe`）。

**只有在“端点 + 身份”一致时才会删除**，避免误删同机上反馈给其他主控的 agent：

| 情况 | 行为 |
| --- | --- |
| 端点一致，token（或自动发现 key）也一致 | 停止并删除旧服务与旧二进制 |
| 端点一致，但 token/key 不同 | 保留，并警告“reports to …; leaving it untouched” |
| 端点不同 | 保留 |
| 无法从旧服务定义中解析出端点或身份（如用 `--config`） | 保留，并提示手动处理 |

- `--install-keep-legacy` 可完全关闭自动清理
- Linux 会检查 systemd（系统/用户）、OpenRC、procd、Upstart、launchd
- Windows 从 nssm 的服务注册表参数（`AppParameters`/`Application`/`AppEnvironmentExtra`）读取旧身份

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

6. 安装完成后会把 `C:\kmr\lh` 标记为隐藏系统文件夹（`attrib +s +h`），
   `--install-no-hide` 可关闭
7. 服务管理器优先使用 `sm.exe`（nssm）；下载文件会自动 `Unblock-File` 并清除属性，
   仍无法执行时**默认报错退出**；显式加 `--install-use-sc` 才回退到 `sc.exe`
   （`New-Service` + `sc failure` 重启策略）
8. 服务启动后，agent 会向每个交互式登录会话弹出安全通知（见
   [windows-notification.md](windows-notification.md)）

> **关于服务与日志**：服务注册项属于任何开机自启的服务（nssm 方式同样有），卸载时删除。
> SCM 的系统事件日志（7036/7031 等）对所有服务统一记录，没有受支持的按服务关闭方式。
> 默认不会用 `sc.exe` 注册服务；`sm.exe` 无法执行时直接报错并提示手动解封或安装 nssm。
> 确需 sc 兜底时加 `--install-use-sc`。

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
