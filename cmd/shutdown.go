package cmd

import (
	"log"
	"sync"
)

var (
	externalStopMu sync.Mutex
	externalStop   func()
)

// RequestShutdown asks the running agent to shut down gracefully. It is used by
// the Windows service handler, where no signal is delivered.
func RequestShutdown() {
	externalStopMu.Lock()
	stop := externalStop
	externalStopMu.Unlock()
	if stop != nil {
		stop()
	}
}

func setExternalStop(stop func()) {
	externalStopMu.Lock()
	externalStop = stop
	externalStopMu.Unlock()
}

type shutdownCoordinator struct {
	mu            sync.Mutex
	once          sync.Once
	exitCode      int
	stopWarning   func()
	stopNetstatic func() error
	exit          func(int)
}

func newShutdownCoordinator(stopWarning func(), stopNetstatic func() error, exit func(int)) *shutdownCoordinator {
	return &shutdownCoordinator{
		stopWarning:   stopWarning,
		stopNetstatic: stopNetstatic,
		exit:          exit,
	}
}

func (s *shutdownCoordinator) shutdown(exitCode int) {
	s.mu.Lock()
	if exitCode > s.exitCode {
		s.exitCode = exitCode
	}
	s.mu.Unlock()

	s.once.Do(func() {
		s.stopWarning()
		if err := s.stopNetstatic(); err != nil {
			log.Printf("Failed to stop netstatic monitoring: %v", err)
		}

		s.mu.Lock()
		exitCode = s.exitCode
		s.mu.Unlock()
		s.exit(exitCode)
	})
}
