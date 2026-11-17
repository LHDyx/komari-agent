# 监控指标与远程控制

## 一、基础信息（`server/basicInfo.go`）

上报周期：**每 5 分钟**，以及**每次建立连接前**。

字段：

```
cpu_name, cpu_cores, cpu_physical_cores, arch, os, kernel_version,
ipv4, ipv6, mem_total, swap_total, disk_total, gpu_name, virtualization, version
```

### 公网 IP 的获取

`monitoring/unit/ip.go`：

1. `--get-ip-addr-from-nic` → 从允许的网卡取地址
2. `--custom-ipv4` / `--custom-ipv6` → 使用固定值
3. 否则依次请求公共回显接口，取第一个成功结果：
   `visa.cn`、`qualcomm.cn`、`toutiao`、`edge-ip.html.zone`、`vercel-ip.html.zone`、`ip.sb`、`ipify`
   （IPv4/IPv6 各自锁定协议栈）

> 这是代理除面板外唯一主动访问的外部服务。内网环境建议改用固定 IP 或网卡方式。

### 虚拟化检测

`monitoring/unit/virtualization.go`：优先 `systemd-detect-virt`，其次容器特征探测，
最后用 CPUID hypervisor 位 + 厂商映射；裸机返回 `none`。

## 二、实时指标（默认每 3 秒）

汇总在 `monitoring/monitoring.go`，结构：

| JSON 字段 | 说明 | 来源 |
| --- | --- | --- |
| `cpu.usage` | CPU 使用率（最低钳到 0.001） | gopsutil |
| `ram.total/used` | 内存 | 见下方三种口径 |
| `swap.total/used` | 交换 | `/proc/meminfo`（含 SwapCached），否则 gopsutil |
| `load.load1/5/15` | 负载 | gopsutil |
| `disk.total/used` | 磁盘 | 默认排除 tmpfs/网络盘；可指定挂载点 |
| `network.up/down` | 瞬时速率 | 相邻采样累计值差分 |
| `network.totalUp/totalDown` | 累计流量 | 开启月重置时取 netstatic 区间值 |
| `connections.tcp/udp` | 连接数 | Linux 优先读 `/proc/net/{tcp,udp}`，失败回退 gopsutil |
| `gpu` | 仅 `--gpu` 时详细上报 | 见 GPU |
| `uptime` | 运行秒数 | Linux 读 `/proc/uptime`（LXC 内为容器自身） |
| `process` | 进程数 | 各平台实现 |
| `message` | 采集错误汇总 | — |

### 内存口径

`monitoring/unit/mem.go`，优先级从高到低：

1. `--memory-include-cache`：`Total - Free`（含缓存，偏“已用”）
2. `--memory-exclude-bcf`：htop 口径，SReclaimable 计入 Cached，Zswap/Zram 不计入应用内存
3. 默认（Linux）：htop 口径；非 Linux 回退 gopsutil

可以用 `komari-agent check-mem` 打印 `/proc/meminfo` 与三种口径的实际数值。

### 磁盘与网卡过滤

- 挂载点：`--include-mountpoint`（**分号**分隔），不指定则自动排除临时/网络文件系统
- 网卡：`--include-nics` / `--exclude-nics`（逗号分隔，支持通配符），只影响统计，不影响连接

### GPU

- 基础信息里始终上报 GPU 名称（`gpu_name`）
- `--gpu` 时额外采集使用率、显存、温度、多卡明细
- 后端：NVIDIA `nvidia-smi`、AMD ROCm / sysfs、Windows WMI、macOS

## 三、月度流量（`monitoring/netstatic`）

由 `--month-rotate <1-31>` 启用：

- 每 **2 秒**采样一次网卡累计计数器，计算 delta 存内存
- 每 **600 秒**合并写入工作目录的 `net_static.json`
- 只保留最近 **31 天**，过期清理
- 启动时读文件续算；`Stop()` 时再写一次
- 文件名固定，位置取决于服务的工作目录（安装脚本设为 `/opt/komari`）
- 服务重启最多丢失一个保存周期（10 分钟）内的增量

## 四、协议（`protocol/v2`）

JSON-RPC 2.0，方法名：

| 方法 | 方向 | 作用 |
| --- | --- | --- |
| `agent.report` | agent → 面板 | 实时指标（POST 模式下带 `ack_event_ids`） |
| `agent.basicInfo` | agent → 面板 | 基础信息 |
| `agent.pingResult` | agent → 面板 | Ping 结果（`-1` 表示丢包） |
| `agent.taskResult` | agent → 面板 | 命令结果（stdout/stderr/退出码） |
| `agent.file.result` | agent → 面板 | 文件操作结果 |
| `agent.startupConfig.result` | agent → 面板 | 启动配置回传 |
| `agent.exec` | 面板 → agent | 执行命令 |
| `agent.ping` | 面板 → agent | Ping 探测 |
| `agent.terminal.request` | 面板 → agent | 打开终端 |
| `agent.file` | 面板 → agent | 文件操作 |
| `agent.startupConfig` | 面板 → agent | 查询启动配置 |
| `agent.switchVersion` | 面板 → agent | 切换版本 |
| `agent.pull` | agent → 面板 | POST 回退模式拉取事件 |

## 五、远程命令（`server/task.go`）

- Unix：`sh -s`，命令从 stdin 传入
- Windows：写临时 `.ps1`（UTF-8 BOM），用 `powershell -NoProfile -ExecutionPolicy Bypass -File` 执行
- 捕获 stdout/stderr，`\r\n` 归一化为 `\n`，回传退出码
- `--disable-web-ssh` 时直接返回 “Remote control is disabled.”

## 六、Ping（`server/task.go`）

支持 `icmp` / `tcp` / `http`：

- 域名先解析成 IP，计时不含 DNS
- 超时 3 秒
- 首测 >1000ms 会重试最多 3 次；TCP 若重试后延迟骤降 >800ms，判定为疑似握手重传并报错
- 结果 `-1` 表示失败（丢包），由面板统计

## 七、Web SSH（`terminal/`）

- 面板下发 `agent.terminal.request` → agent 连 `wss://<面板>/api/clients/terminal?token=...&id=...`
- Unix：`pty` + 登录 shell（带 MOTD 预置），支持窗口大小调整
- Windows：ConPTY
- 同一 request id 支持断线重连、多会话、优雅关闭

## 八、文件管理（`server/files.go` + `file_stream.go`）

元数据走 JSON-RPC，**文件内容走专用 HTTP 端点** `/api/clients/transfer/<id>`（带一次性 `transfer_token`）：

- 操作：`list`、`list_roots`、`stat`、`create`、`mkdir`、`delete`、`move`、`copy`、
  `chmod`、`chown`、`search`、`download_stream`、`upload_stream`、`upload_commit`、`upload_cancel`
- 上传：分块、可断点续写、可取消；512KB 缓冲，最多 8 路并发；取消记录保留 15 分钟
- 跨设备移动自动退化为“复制 + 删除”
- Windows 下 `/` 会被虚拟成盘符列表
- `--disable-web-ssh` 时全部拒绝

## 九、其他控制能力

- **启动配置回传**：面板可查询 agent 的生效配置（`server/startup_config.go`）
- **版本切换**：面板指定版本/版本线，agent 下载替换后以退出码 42 退出（`server/switch_version.go`）
- **消息/事件**：`agent.message`、`agent.event` 仅打印日志
