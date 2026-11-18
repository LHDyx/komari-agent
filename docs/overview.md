# 项目总览

## 一、它是什么

一个单文件、静态链接的监控采集代理，部署在被监控机器上：

- **只出站**：主动连接面板 `ws(s)://<面板>/api/clients/v2/rpc?token=...`，不监听任何端口
- **监控上报**：CPU / 内存 / 交换 / 负载 / 磁盘 / 网络 / 连接数 / GPU / 运行时长 / 进程数
- **远程控制**：执行命令、ICMP/TCP/HTTP Ping、Web SSH、文件管理、切换自身版本
- **自更新**：从 GitHub Releases 检查并原地替换自身二进制

- 语言：Go 1.24；`CGO_ENABLED=0`，交叉编译到 Linux / Windows / macOS / FreeBSD
- 许可：AGPL-3.0

## 二、代码结构

```
main.go                 入口，调用 cmd.Execute()
cmd/
  root.go               主流程：解析配置、启动各协程、连接循环
  flags/flag.go         全部配置字段（json / env / flag 一一对应）
  autodiscovery.go      --auto-discovery 注册流程
  checkMem.go           check-mem 子命令（三种内存口径对比）
  shutdown.go           退出协调（信号 / 更新重启）
  warn*.go              安全提示：Linux 写 MOTD，Windows 弹 Toast，其他平台空实现
server/
  websocket.go          WebSocket 连接、上报、事件分发、POST 回退与拉取循环
  basicInfo.go          基础信息上报（5 分钟 + 每次连接前）
  task.go               exec 与 ping 任务
  files.go              文件操作（元数据）
  file_stream.go        文件内容传输（HTTP 专用端点）
  startup_config.go     回传启动配置
  switch_version.go     面板触发版本切换
monitoring/
  monitoring.go         汇总生成 report JSON
  unit/                 各指标采集（按平台拆分文件）
  netstatic/            月度流量统计（内存聚合 + 定期落盘）
protocol/
  v2/jsonrpc.go         JSON-RPC 方法名与消息结构
  transport/compress.go gzip
terminal/               Web SSH（Unix pty / Windows conpty）
update/                 自更新（GitHub Releases + sha256 校验 + 原地替换）
dnsresolver/            自定义 DNS、IPv4/IPv6 偏好排序、HTTP 客户端
ws/                     线程安全的 WebSocket 包装
utils/                  IDN 转 ASCII 等小工具
```

## 三、启动流程（`cmd/root.go`）

```
main() → cmd.Execute() → RootCmd.RunE
  1. --show-warning 分支：只弹通知（Windows 辅助进程），不加载配置、不碰 token
  2. loadFromEnv()     读 AGENT_* 环境变量（覆盖命令行）
  3. --config <json>   读 JSON（覆盖环境变量）
  4. 校验 --prefer-ip-version；设置更新源仓库（本 fork 的 --update-repo）
  5. 注册 SIGINT/SIGTERM；构造 shutdown 协调器
  6. --month-rotate ≠ 0 → 启动 netstatic
  7. --custom-dns → 自定义 DNS
  8. --auto-discovery → 向面板注册换取 token（写入 auto-discovery.json）
  9. 保存启动参数快照（面板可查询，隐藏字段含 warning_panel_host 等）
 10. 记录挂载点 / 网卡列表
 11. 启动自更新协程（立即检查一次 + 每 6 小时）
 12. 启动基础信息上报协程（每 5 分钟）
 13. 死循环：上传基础信息 → EstablishWebSocketConnection（断开后重新进入）
```

### 配置优先级

**默认值 → 命令行参数 → 环境变量 → JSON 配置文件**（后者覆盖前者；JSON 优先级最高）。

### 主要配置项

| 参数 | 环境变量 | 默认 | 说明 |
| --- | --- | --- | --- |
| `--endpoint/-e` | `AGENT_ENDPOINT` | — | 面板地址 |
| `--token/-t` | `AGENT_TOKEN` | — | 令牌 |
| `--interval/-i` | `AGENT_INTERVAL` | 3s | 指标上报间隔 |
| `--reconnect-interval/-c` | `AGENT_RECONNECT_INTERVAL` | 5s | 重连间隔 |
| `--max-retries/-r` | `AGENT_MAX_RETRIES` | 3 | 重连次数上限 |
| `--info-report-interval` | `AGENT_INFO_REPORT_INTERVAL` | 5min | 基础信息周期 |
| `--disable-auto-update` | `AGENT_DISABLE_AUTO_UPDATE` | false | 关闭自更新 |
| `--disable-web-ssh` | `AGENT_DISABLE_WEB_SSH` | false | 关闭命令/终端/文件/切版本 |
| `--include-nics` / `--exclude-nics` | 同名 | — | 网卡过滤（逗号，支持通配） |
| `--include-mountpoint` | 同名 | — | 只统计指定挂载点（**分号**分隔） |
| `--month-rotate` | 同名 | 0 | 月流量重置日（1–31） |
| `--memory-include-cache` | 同名 | false | 内存含缓存口径 |
| `--memory-exclude-bcf` | 同名 | false | htop 口径 |
| `--custom-dns` | 同名 | — | 自定义 DNS |
| `--custom-ipv4/--custom-ipv6` | 同名 | — | 固定上报 IP |
| `--get-ip-addr-from-nic` | 同名 | false | 从网卡取 IP |
| `--gpu` | 同名 | false | 详细 GPU 采集 |
| `--ignore-unsafe-cert/-u` | 同名 | false | 跳过 TLS 校验 |
| `--prefer-ip-version` | 同名 | — | 连接优先 v4/v6 |
| `--config` | `AGENT_CONFIG_FILE` | — | JSON 配置路径 |
| `--auto-discovery` | 同名 | — | 自动注册密钥 |
| `--update-repo` | `AGENT_UPDATE_REPO` | `LHDyx/komari-agent`（本 fork 默认） | 自更新源仓库 |
| `--enable-security-warning` | `AGENT_ENABLE_SECURITY_WARNING` | **false**（本 fork 默认关闭） | 显示远程控制安全提示（Linux MOTD / Windows Toast） |

辅助：`check-mem`（内存口径对比）、`list-disk`。

## 四、连接与容错（`server/websocket.go`）

```
EstablishWebSocketConnection
 ├─ 1s ticker：未连接则重连（最多 max-retries 次，间隔 reconnect-interval）
 │             已连接且到上报时间 → 发送指标
 ├─ 30s ticker：WebSocket Ping 心跳
 ├─ 读协程结束 → 标记断开，下个 tick 重连
 └─ 重试耗尽 → runPostFallback（HTTP POST 回退）
```

POST 回退模式下并行两件事：

- **上报循环**：每 interval 一次 `agent.report`（请求/响应）
- **拉取循环**：持续 `agent.pull`，携带 `ack_event_ids` 确认事件
- 同时每 reconnect-interval 尝试恢复 WebSocket，成功即切回

其他细节：

- 事件按 id + 10 分钟 TTL 去重，避免重复执行
- 默认 gzip 压缩（`--disable-compression` 关闭）
- WebSocket 与 HTTP 共用自定义 DNS 和 IPv4/IPv6 排序逻辑
- 支持 IDN（中文域名）转 ASCII

## 五、自更新（`update/`）

- 启动后立即检查一次，之后每 **6 小时**
- 只跟进当前 `major.minor` 线内更高版本
- 本 fork 的过滤规则：自建仓库下只接受 tag 形如 `<base>-custom.<i>`；预览版与官方版本都不选
- 下载 `komari-agent-<os>-<arch>`，校验 GitHub 提供的 sha256 digest，`go-update` 原地替换
- 成功后进程以**退出码 42** 退出；systemd `Restart=always` / sm.exe（nssm）`AppExit Restart` 负责拉起
- 容器内（存在 `/.komari-agent-container`）一律跳过自更新
- 面板“切换版本”复用同一模块（`CheckAndUpdateForVersionLine`）

## 六、安全设计

1. **无入站端口**：所有能力只能由持 token 的面板经长连接触发
2. **`--disable-web-ssh` 总闸**：命令、终端、文件、切版本全部拒绝
3. **安装后安全提示（本 fork 默认关闭）**：需显式加 `--enable-security-warning` 才启用
   - Linux：向 `/etc/motd` 追加警示（面板地址 + 运行账号 + 卸载链接），关闭远程控制时移除；
     关闭该开关启动时会清理旧版本已写入的提示
   - Windows：向每个交互会话弹 Toast（详见 [windows-notification.md](windows-notification.md)）
   - macOS / FreeBSD：无提示
4. **不泄露凭据**：通知辅助进程不读取配置；启动配置回传与错误日志避免输出 token
5. **完整性**：更新包校验 sha256；文件传输使用独立的一次性 `transfer_token`

## 七、本 fork 与上游的差异

- 代码：新增 `--update-repo` / `AGENT_UPDATE_REPO`，默认指向本 fork；更新器增加 `isCustomReleaseVersion` 过滤
- 构建：`custom-build.yml` 手动触发，15 平台，预览/正式两条 tag 线（见 `CUSTOM-BUILD.md`）
- CI：上游继承的 `Build on Main`、`Publish Snapshot` 已改为仅手动触发；推送不构建
- 其余运行行为与上游一致；截至 2026-11-17，上游领先 2 个提交（`支持控制协议`）
