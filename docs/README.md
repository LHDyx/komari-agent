# Komari Agent 文档

本目录记录本 fork（`LHDyx/komari-agent`）对上游 [komari-monitor/komari-agent](https://github.com/komari-monitor/komari-agent)
的理解与自用约定。上游代码为 AGPL-3.0。

| 文档 | 内容 |
| --- | --- |
| [overview.md](overview.md) | 项目定位、代码结构、启动流程、配置优先级、连接与自更新 |
| [monitoring-and-control.md](monitoring-and-control.md) | 上报的指标、协议方法、远程命令/终端/文件传输 |
| [install.md](install.md) | `install.sh` / `install.ps1` 逐段行为、各平台服务管理、Docker |
| [windows-notification.md](windows-notification.md) | **Windows 安装后弹通知的完整行为**（触发条件、实现、时序、限制） |
| [../CUSTOM-BUILD.md](../CUSTOM-BUILD.md) | 本 fork 的构建、版本号、预览/正式发布与自动更新约定 |
| [../CLAUDE.md](../CLAUDE.md) | 项目当前状态与红线（给 coding agent 用） |

## 一句话概括

Komari Agent 是**只出站、无入站端口**的监控代理：通过 WebSocket（失败时回退 HTTP POST）连面板，
周期上报资源指标，并作为面板的“手”执行命令、Ping、Web SSH 和文件管理。

## 常用本地命令

```bash
./build-local.sh                       # 本地交叉编译（不消耗 Actions）
go test ./...                          # 单测（server 包的 ping 测试需外网）
./sync-upstream.sh --check             # 查看落后上游多少提交
```
