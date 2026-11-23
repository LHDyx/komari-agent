package main

import (
	"os"

	"github.com/komari-monitor/komari-agent/cmd"
)

func main() {
	// When started by the Windows SCM, run as a native service; otherwise the
	// normal CLI path applies (nssm/Task Scheduler launch the CLI as a child).
	if runAsServiceIfNeeded() {
		return
	}
	cmd.Execute()
	os.Exit(0)
}
