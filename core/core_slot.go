package teapodcore

import (
	"log"
	"sync"
)

// coreSlot holds the one running instance of a core: xray and sing-box share this lifecycle.
// start replaces the running instance and opens the new one on its own goroutine; stop closes it.
// A stop that comes before that goroutine runs cancels the start: the instance it would open
// would have no reference left to close it, holding the SOCKS port and its upstream connections.
type coreSlot[T any] struct {
	name  string        // log prefix
	close func(T) error // releases an opened instance

	mu  sync.Mutex // guards run itself; coreRun.mu guards its fields
	run *coreRun[T]
}

type coreRun[T any] struct {
	mu   sync.Mutex // held through the whole start and stop: readers wait for a start in progress
	inst T
	open bool // inst is set
	cb   statusCallback
}

// statusCallback is XrayCallback (android-only, with the rest of the gomobile API).
type statusCallback interface {
	OnStatus(status int64, message string)
}

func (s *coreSlot[T]) current() *coreRun[T] {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.run
}

// start stops the running instance, then opens a new one with open on a new goroutine. cb gets
// 0 once it runs, or -1 with open's error or the cancellation.
func (s *coreSlot[T]) start(cb statusCallback, open func() (T, error)) {
	s.stop()

	run := &coreRun[T]{cb: cb}
	s.mu.Lock()
	s.run = run
	s.mu.Unlock()

	go func() {
		run.mu.Lock()
		defer run.mu.Unlock()

		if s.current() != run {
			if cb != nil {
				cb.OnStatus(-1, "start cancelled: core was stopped")
			}
			return
		}
		inst, err := open()
		if err != nil {
			log.Printf("[%s] %v", s.name, err)
			if cb != nil {
				cb.OnStatus(-1, err.Error())
			}
			return
		}
		run.inst, run.open = inst, true
		log.Printf("[%s] started successfully", s.name)
		if cb != nil {
			cb.OnStatus(0, "Started successfully, running")
		}
	}()
}

// stop closes the running instance; a start in progress finishes first.
func (s *coreSlot[T]) stop() {
	s.mu.Lock()
	run := s.run
	s.run = nil
	s.mu.Unlock()
	if run == nil {
		return
	}

	run.mu.Lock()
	defer run.mu.Unlock()
	if run.open {
		if err := s.close(run.inst); err != nil {
			log.Printf("[%s] shutdown error: %v", s.name, err)
		}
		var zero T
		run.inst, run.open = zero, false
	}
	if run.cb != nil {
		run.cb.OnStatus(0, "Core stopped")
	}
}

// get returns the running instance, false when none runs; a start in progress finishes first.
func (s *coreSlot[T]) get() (T, bool) {
	run := s.current()
	if run == nil {
		var zero T
		return zero, false
	}
	run.mu.Lock()
	defer run.mu.Unlock()
	return run.inst, run.open
}
