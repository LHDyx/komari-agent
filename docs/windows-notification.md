# Windows 安装后的安全通知行为

> 结论先行：安装脚本本身**不弹通知**。通知由 **agent 服务在启动后**主动向每个交互式登录会话
> 注入一个辅助进程弹出 Windows Toast，条件是**没有启用 `--disable-web-ssh`**。
> 安装完成（`nssm start`）后，通常在 **3 秒内**当前已登录的桌面就会看到提示。

## 一、触发条件

| 条件 | 说明 |
| --- | --- |
| 平台 | 仅 Windows（`//go:build windows`） |
| 服务已启动 | `install.ps1` 最后执行 `nssm start komari-agent` |
| 未启用 `--disable-web-ssh` | 启用时 `startSecurityWarning` 直接返回空实现 |
| 存在交互式会话 | 会话状态必须是 `WTSActive` 且能取到用户名 |
| 系统通知可用 | 通知被系统/组策略/专注助手关闭时不会显示 |

## 二、代码位置

| 文件 | 作用 |
| --- | --- |
| `cmd/root.go` | 启动时调用 `startSecurityWarning(stopCtx)` |
| `cmd/warn_windows.go` | 会话枚举、跨会话启动辅助进程、Toast 实现 |
| `cmd/warning.go` | 通知文案（标题、面板地址、运行账号、卸载链接） |
| `cmd/warn.go` | 非 Windows 的 `ShowToast()` 空实现 |
| `cmd/warn_linux.go` | Linux 对应物：写入 `/etc/motd` |

## 三、完整时序

```
nssm start komari-agent
  └─ agent 服务进程（LocalSystem）
      └─ startSecurityWarning()
          ├─ flags.DisableWebSsh ? → 直接返回，不通知
          └─ go warnWindowsSessions()
              ├─ 启用 SeAssignPrimaryTokenPrivilege / SeIncreaseQuotaPrivilege
              ├─ 每 3 秒枚举 WTS 会话（WTSEnumerateSessionsW，State=WTSActive 且有用户名）
              └─ 发现"新"会话 → launchSelfInSession(sid)
                  ├─ WTSQueryUserToken(sid)
                  ├─ DuplicateTokenEx → TokenPrimary
                  ├─ CreateEnvironmentBlock
                  └─ CreateProcessAsUser(
                        komari-agent.exe
                        --show-warning
                        --warning-panel-host <面板主机>
                        --warning-run-as-user <运行账号>,
                        DETACHED_PROCESS, 桌面 winsta0\default)
                      └─ 子进程（用户会话内）
                          └─ RunE 首个分支：flags.ShowWarning → ShowToast()
                              ├─ 在开始菜单创建临时 .lnk（AUMID: Komari.Monitor.Agent）
                              ├─ 推送 Toast（Duration=Long，带"卸载"动作链接）
                              ├─ 等待 15 秒
                              └─ 删除 .lnk，退出
```

## 四、通知内容

标题：

```
[Komari] Remote control is enabled on this device
```

正文（`securityWarning.message()`）：

```
<面板主机> can execute commands and read or modify files on this device as <运行账号>.

If you did not set this up, your device may have been accessed without authorization.
Stop Komari Agent immediately and check your device for signs of compromise.

Uninstall Komari Agent: https://komari-document.pages.dev/en/faq/uninstall
```

- `<面板主机>`：从 `--endpoint` 解析出的 host（含端口，IDN 转 ASCII）
- `<运行账号>`：服务进程所在账号；nssm 默认是 **LocalSystem**，所以通常显示 `SYSTEM`
  （这如实反映了“远程命令以 SYSTEM 身份执行”）
- 动作按钮/点击链接：卸载说明页

## 五、什么时候会重复出现

服务进程内维护一个 `seen` 会话集合：

- 服务启动时，**当前所有活跃会话各弹一次**
- 用户注销后重新登录 → 视为新会话 → 再弹一次
- **服务重启/升级后会重新弹**（`seen` 重置）；自更新完成会以退出码 42 退出并由 nssm 拉起，
  因此每次自动更新后也会再看到一次通知
- 同一会话在服务生命周期内只弹一次
- 会话消失会从集合中清理，避免内存膨胀

## 六、失败时的表现

日志关键字（服务日志，nssm 默认在安装目录或 Windows 事件日志）：

| 日志 | 原因 |
| --- | --- |
| `[warn] enabling privileges failed: ...` | 服务账号缺少 `SeAssignPrimaryTokenPrivilege` / `SeIncreaseQuotaPrivilege` |
| `[warn] launch in session N failed: ...` | `WTSQueryUserToken` / `CreateProcessAsUser` 失败（常见于以普通用户身份运行服务） |
| `[warn] toast push failed: ...` | 通知被禁用、AUMID 注册失败、Toast 库调用失败 |
| `[warn] ensureStartMenuShortcut failed: ...` | 无法写入 `%APPDATA%\...\Start Menu\Programs` |
| `[info] launched toast helper in session N` | 正常，辅助进程已启动 |

通知失败**不影响监控上报**，只是用户看不到提示。

## 七、如何关闭

| 方式 | 效果 |
| --- | --- |
| 服务参数加 `--disable-web-ssh` | 同时关闭命令/终端/文件/切版本，并**完全不弹通知** |
| 卸载 | 停止服务；服务生成的临时 `.lnk` 正常会在 15 秒后删除，若进程被强行终止可能残留 |

没有单独的“只关通知”开关。

## 八、与 Linux 的差异

| 平台 | 行为 |
| --- | --- |
| Windows | 跨会话 Toast，服务每次启动/新登录各一次 |
| Linux | 向 `/etc/motd` 追加警示文本（终端登录可见），关闭远程控制时自动移除 |
| macOS / FreeBSD | 无任何提示（`warn_other.go` 空实现） |

## 九、实现上的几个细节

- **辅助进程不读配置**：`flags.ShowWarning` 分支在 `loadFromEnv()` 和读取配置文件之前，
  因此不会把 token 带进用户会话
- **不转发敏感参数**：只传 `--warning-panel-host` 与 `--warning-run-as-user` 两个隐藏参数
- **必须跨会话**：Windows 服务运行在 Session 0，不能直接显示 UI，所以用
  `WTSQueryUserToken` + `CreateProcessAsUser` 把自身以用户身份注入到 `winsta0\default`
- **AUMID 技巧**：`gopkg.in/toast.v1` 依赖一个带 AppUserModelID 的开始菜单快捷方式，
  代码临时创建它，15 秒后删除
- **文本转义**：Toast 库内部用 PowerShell here-string + CDATA，代码对 `` ` ``、`$`、`]]>` 做了转义
