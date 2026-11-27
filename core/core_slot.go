package teapodcore

import (
	"log"
	"sync"
)

// coreSlot holds the one running instance of a core: xray and sing-box share this lifecycle.
// start replaces the running instance and opens the new one on its own goroutine; stop closes it.
// A stop that comes before that goroutine runs cancels the start: the instance it would open
// would have no reference left to close it, holding the SOCKS port and its upstream connections.
// The open waits for every stop begun before the start to finish closing, also one another caller
// began: the instance being closed may still hold the SOCKS port the new one needs. start itself
// doesn't wait, so a hung close holds only that open, which the caller's start deadline bounds
// (its stop then cancels the start).
type coreSlot[T any] struct {
	name  string        // log prefix
	close func(T) error // releases an opened instance

	mu  sync.Mutex // guards run and closed; coreRun.mu guards a run's fields
	run *coreRun[T]
	// closed is closed once every stop begun so far has finished closing its instance; nil — none yet.
	closed chan struct{}
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
	closed := s.closed
	s.mu.Unlock()

	go func() {
		if closed != nil {
			<-closed
		}
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

// stop closes the running instance; an open in progress finishes first.
func (s *coreSlot[T]) stop() {
	s.mu.Lock()
	run := s.run
	s.run = nil
	prev, done := s.closed, make(chan struct{})
	s.closed = done
	s.mu.Unlock()
	// done follows the earlier stops too, so a start waits for all of them.
	defer func() {
		go func() {
			if prev != nil {
				<-prev
			}
			close(done)
		}()
	}()
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

// get returns the running instance, false when none runs; an open in progress finishes first.
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
