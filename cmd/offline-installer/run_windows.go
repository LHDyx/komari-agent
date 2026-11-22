//go:build windows

package main

import (
	"fmt"
	"os"
	"os/exec"
)

func runInstallScript(script string, args []string) error {
	cmdArgs := append([]string{
		"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script,
	}, args...)
	cmd := exec.Command("powershell.exe", cmdArgs...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("install script failed: %w", err)
	}
	return nil
}
