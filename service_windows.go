//go:build windows

package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"runtime/debug"
	"strings"
	"time"

	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"

	"github.com/komari-monitor/komari-agent/cmd"
)

const windowsServiceName = "kmr-ag"

var serviceLogFile *os.File

func serviceLogf(format string, args ...interface{}) {
	if serviceLogFile == nil {
		return
	}
	fmt.Fprintf(serviceLogFile, time.Now().Format("2006-01-02 15:04:05 ")+format+"\n", args...)
}

func openServiceLog() {
	exe, err := os.Executable()
	if err != nil {
		return
	}
	f, err := os.OpenFile(filepath.Join(filepath.Dir(exe), "kmr-service.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err == nil {
		serviceLogFile = f
		log.SetOutput(f)
	}
}

type agentService struct{}

// runAsServiceIfNeeded reports whether the process was started by the Windows
// Service Control Manager and, if so, runs the agent as a native service.
func runAsServiceIfNeeded() bool {
	isService, err := svc.IsWindowsService()
	if err != nil || !isService {
		return false
	}

	openServiceLog()
	serviceLogf("service mode starting, exe=%s", os.Args[0])

	name := windowsServiceName
	if detected, err := currentServiceName(); err == nil {
		name = detected
		serviceLogf("detected service name: %s", name)
	} else {
		serviceLogf("service name detection failed: %v (fallback %s)", err, name)
	}

	if err := svc.Run(name, &agentService{}); err != nil {
		log.Println("Windows service failed:", err)
		serviceLogf("svc.Run(%s) failed: %v", name, err)
	}
	serviceLogf("service mode exiting")
	return true
}

// currentServiceName finds the SCM service whose ImagePath points at this
// executable, so a custom service name (via --install-service-name) works.
func currentServiceName() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	exe = strings.ToLower(filepath.Clean(exe))

	m, err := mgr.Connect()
	if err != nil {
		return "", err
	}
	defer m.Disconnect()

	names, err := m.ListServices()
	if err != nil {
		return "", err
	}
	for _, name := range names {
		s, err := m.OpenService(name)
		if err != nil {
			continue
		}
		cfg, err := s.Config()
		s.Close()
		if err != nil {
			continue
		}
		if strings.ToLower(filepath.Clean(serviceExePath(cfg.BinaryPathName))) == exe {
			return name, nil
		}
	}
	return "", fmt.Errorf("no service points at %s", exe)
}

func serviceExePath(binaryPath string) string {
	p := strings.TrimSpace(binaryPath)
	if strings.HasPrefix(p, `"`) {
		if end := strings.Index(p[1:], `"`); end >= 0 {
			return p[1 : 1+end]
		}
	}
	if i := strings.IndexAny(p, " \t"); i >= 0 {
		return p[:i]
	}
	return p
}

func (s *agentService) Execute(args []string, requests <-chan svc.ChangeRequest, status chan<- svc.Status) (bool, uint32) {
	serviceLogf("handler start, os.Args=%v, svc args=%v", os.Args, args)
	status <- svc.Status{State: svc.StartPending}

	// Services start in System32; keep relative files (net_static.json etc.)
	// next to the executable instead.
	if exe, err := os.Executable(); err == nil {
		_ = os.Chdir(filepath.Dir(exe))
	}

	// os.Args already contains the ImagePath arguments (e.g. -e/-t); the
	// handler's args are SCM metadata (the service name), not CLI flags.

	done := make(chan struct{})
	go func() {
		defer func() {
			if r := recover(); r != nil {
				serviceLogf("panic: %v\n%s", r, debug.Stack())
			}
			serviceLogf("cmd.Execute returned")
			close(done)
		}()
		cmd.Execute()
	}()

	status <- svc.Status{State: svc.Running, Accepts: svc.AcceptStop | svc.AcceptShutdown}
	for {
		select {
		case request := <-requests:
			switch request.Cmd {
			case svc.Interrogate:
				status <- svc.Status{State: svc.Running, Accepts: svc.AcceptStop | svc.AcceptShutdown}
			case svc.Stop, svc.Shutdown:
				serviceLogf("stop requested")
				status <- svc.Status{State: svc.StopPending}
				cmd.RequestShutdown()
				select {
				case <-done:
				case <-time.After(15 * time.Second):
				}
				return false, 0
			}
		case <-done:
			return false, 0
		}
	}
}
