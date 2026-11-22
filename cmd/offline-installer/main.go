// Command offline-installer installs the Komari Agent from embedded files,
// without contacting GitHub. One binary is built per OS/arch and carries the
// matching agent binary, install scripts, version file and (on Windows) nssm.
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

type options struct {
	extract     string
	dryRun      bool
	keepTemp    bool
	showVersion bool
	agentArgs   []string
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "ERROR:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	opts, err := parseArgs(args)
	if err != nil {
		return err
	}

	if opts.showVersion {
		v, _ := payloadVersion()
		fmt.Printf("offline installer: %s/%s\nagent version: %s\n", runtime.GOOS, runtime.GOARCH, v)
		return nil
	}

	if !payloadAvailable() {
		return errors.New("this binary was built without an embedded payload; rebuild with -tags offline_payload after preparing cmd/offline-installer/payload")
	}

	if opts.extract != "" {
		dir, err := filepath.Abs(opts.extract)
		if err != nil {
			return err
		}
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
		info, err := writePayload(dir)
		if err != nil {
			return err
		}
		fmt.Printf("已释放离线安装文件到 %s\n\n", dir)
		fmt.Printf("拷贝该目录到离线机器后执行：\n")
		if runtime.GOOS == "windows" {
			fmt.Printf("  .\\install.ps1 --install-file .\\%s --install-sm-exe .\\sm.exe -e <面板> -t <TOKEN>\n", filepath.Base(info.AgentPath))
		} else {
			fmt.Printf("  sudo sh ./install.sh --install-file ./%s -e <面板> -t <TOKEN>\n", filepath.Base(info.AgentPath))
		}
		return nil
	}

	if opts.dryRun {
		v, _ := payloadVersion()
		fmt.Printf("offline installer target: %s/%s\n", runtime.GOOS, runtime.GOARCH)
		fmt.Printf("embedded agent version: %s\n", v)
		fmt.Printf("agent args: %s\n", strings.Join(opts.agentArgs, " "))
		fmt.Println("(dry run, nothing installed)")
		return nil
	}

	tmp, err := os.MkdirTemp("", "kmr-offline-*")
	if err != nil {
		return err
	}
	if !opts.keepTemp {
		defer os.RemoveAll(tmp)
	} else {
		fmt.Println("临时目录保留在:", tmp)
	}

	info, err := writePayload(tmp)
	if err != nil {
		return err
	}

	scriptArgs := append([]string{
		"--install-file", info.AgentPath,
	}, opts.agentArgs...)
	if info.SmPath != "" {
		scriptArgs = append([]string{
			"--install-file", info.AgentPath,
			"--install-sm-exe", info.SmPath,
		}, opts.agentArgs...)
	}

	return runInstallScript(info.ScriptPath, scriptArgs)
}

func parseArgs(args []string) (options, error) {
	var opts options
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "-h" || a == "--help":
			printUsage()
			os.Exit(0)
		case a == "--version":
			opts.showVersion = true
		case a == "--dry-run":
			opts.dryRun = true
		case a == "--keep-temp":
			opts.keepTemp = true
		case a == "--extract":
			if i+1 >= len(args) {
				return opts, errors.New("--extract requires a directory")
			}
			opts.extract = args[i+1]
			i++
		case strings.HasPrefix(a, "--extract="):
			opts.extract = strings.TrimPrefix(a, "--extract=")
		default:
			// 其余参数原样交给 install.sh / install.ps1（也是 agent 参数）
			opts.agentArgs = append(opts.agentArgs, a)
		}
	}
	return opts, nil
}

func printUsage() {
	fmt.Print(`Komari Agent Offline Installer

Usage:
  kmari-agent-installer-linux-amd64 -e https://panel -t TOKEN [-i 10]
  komari-agent-installer-windows-amd64.exe -e https://panel -t TOKEN

Installer options:
  --extract <dir>   只释放离线文件，不安装
  --dry-run         只显示目标、内嵌版本和参数
  --keep-temp       安装后保留临时目录
  --version         显示内嵌 agent 版本
  -h, --help        显示帮助

All other flags are passed to install.sh / install.ps1:
  --install-dir, --install-service-name, --auto-discovery,
  --disable-auto-update, --disable-web-ssh, --enable-security-warning,
  --month-rotate, --gpu, --custom-dns, ...
`)
}

type payloadInfo struct {
	AgentPath  string
	ScriptPath string
	SmPath     string
}

func writePayload(dir string) (payloadInfo, error) {
	var info payloadInfo

	agentName := "lh_kmr_ag"
	scriptName := "install.sh"
	if runtime.GOOS == "windows" {
		agentName += ".exe"
		scriptName = "install.ps1"
	}
	info.AgentPath = filepath.Join(dir, agentName)
	info.ScriptPath = filepath.Join(dir, scriptName)

	if err := writeEmbedded("payload/agent", info.AgentPath, 0o755); err != nil {
		return info, err
	}
	if err := writeEmbedded("payload/"+scriptName, info.ScriptPath, 0o755); err != nil {
		return info, err
	}
	if err := writeEmbedded("payload/version.txt", filepath.Join(dir, "version.txt"), 0o644); err != nil {
		return info, err
	}
	if runtime.GOOS == "windows" {
		info.SmPath = filepath.Join(dir, "sm.exe")
		if err := writeEmbedded("payload/sm.exe", info.SmPath, 0o755); err != nil {
			return info, err
		}
	}

	sum, err := fileSHA256(info.AgentPath)
	if err != nil {
		return info, err
	}
	shaLine := fmt.Sprintf("%s  %s\n", sum, filepath.Base(info.AgentPath))
	if err := os.WriteFile(info.AgentPath+".sha256", []byte(shaLine), 0o644); err != nil {
		return info, err
	}

	readme := fmt.Sprintf(`Komari Agent 离线安装包
agent version: %s
平台: %s/%s

Linux/macOS/FreeBSD:
  sudo sh ./%s --install-file ./%s -e <面板> -t <TOKEN> [-i 10]

Windows（管理员 PowerShell）:
  .\%s --install-file .\%s -e <面板> -t <TOKEN> [-i 10]
`, mustVersion(), runtime.GOOS, runtime.GOARCH, scriptName, filepath.Base(info.AgentPath), scriptName, filepath.Base(info.AgentPath))
	_ = os.WriteFile(filepath.Join(dir, "README.txt"), []byte(readme), 0o644)

	return info, nil
}

func writeEmbedded(name, dst string, mode os.FileMode) error {
	data, err := fs.ReadFile(payloadFS, name)
	if err != nil {
		return fmt.Errorf("embedded %s missing: %w", name, err)
	}
	if err := os.WriteFile(dst, data, mode); err != nil {
		return err
	}
	return os.Chmod(dst, mode)
}

func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func payloadVersion() (string, error) {
	data, err := fs.ReadFile(payloadFS, "payload/version.txt")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}

func mustVersion() string {
	v, err := payloadVersion()
	if err != nil {
		return "unknown"
	}
	return v
}
