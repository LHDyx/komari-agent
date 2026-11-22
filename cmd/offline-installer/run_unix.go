//go:build !windows

package main

import (
	"fmt"
	"os"
	"os/exec"
)

func runInstallScript(script string, args []string) error {
	if os.Geteuid() != 0 {
		return fmt.Errorf("需要 root 权限才能安装服务，请用 sudo 运行本安装器")
	}
	cmd := exec.Command("sh", append([]string{script}, args...)...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("install script failed: %w", err)
	}
	return nil
}
