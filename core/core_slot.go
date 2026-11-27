package teapodcore

import (
	"log"
	"sync"
)

// coreSlot holds the one running instance of a core: xray and sing-box share this lifecycle.
//
// A start or stop swaps the run under mu in one step, so every replaced run is closed by whoever
// replaced it and none is left behind by two calls racing. stop closes the run it took before it
// returns; start returns at once, and its goroutine closes the run it replaced, waits until every
// earlier stop has finished closing (the closing instance may still hold the SOCKS port), and only
// then opens — if its run is still the current one. A hung close therefore holds only that open,
// which the caller's start deadline bounds; the stop the caller then sends cancels the start.
type coreSlot[T any] struct {
	name  string        // log prefix
	close func(T) error // releases an opened instance

	mu  sync.Mutex // guards run and closed; coreRun.mu guards a run's fields
	run *coreRun[T]
	// closed is closed once every run replaced so far has been closed; nil — none yet.
	closed chan struct{}
}

type coreRun[T any] struct {
	mu   sync.Mutex // held through the open and the close: readers wait for an open in progress
	inst T
	open bool // inst is set
	// ended: the start's outcome other than a running core — cancelled before it opened or a failed
	// open — is reported; nothing else is reported for this run and the open never runs.
	ended bool
	cb    statusCallback
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

// swap makes next the current run and returns the one it replaced, with the channel of the closes
// before it and the one to close once that run is closed too.
func (s *coreSlot[T]) swap(next *coreRun[T]) (old *coreRun[T], prev, done chan struct{}) {
	s.mu.Lock()
	defer s.mu.Unlock()
	old, s.run = s.run, next
	prev, done = s.closed, make(chan struct{})
	s.closed = done
	return old, prev, done
}

// chain closes done once prev is: done then follows every earlier close as well.
func chain(prev, done chan struct{}) {
	if prev != nil {
		<-prev
	}
	close(done)
}

// closeRun closes run's instance (after an open in progress) and reports the stop. A run taken
// before it opened reports only the cancellation (-1): a 0 would read as a successful start.
func (s *coreSlot[T]) closeRun(run *coreRun[T]) {
	if run == nil {
		return
	}
	run.mu.Lock()
	defer run.mu.Unlock()
	if !run.open {
		if !run.ended {
			run.ended = true
			if run.cb != nil {
				run.cb.OnStatus(-1, "start cancelled: core was stopped")
			}
		}
		return
	}
	if err := s.close(run.inst); err != nil {
		log.Printf("[%s] shutdown error: %v", s.name, err)
	}
	var zero T
	run.inst, run.open = zero, false
	if run.cb != nil {
		run.cb.OnStatus(0, "Core stopped")
	}
}

// start replaces the running instance with one opened by open, on a new goroutine. cb gets 0
// once it runs, or -1 with open's error or the cancellation.
func (s *coreSlot[T]) start(cb statusCallback, open func() (T, error)) {
	run := &coreRun[T]{cb: cb}
	old, prev, done := s.swap(run)
	go func() {
		s.closeRun(old)
		chain(prev, done)

		run.mu.Lock()
		defer run.mu.Unlock()
		if run.ended {
			return
		}
		if s.current() != run { // replaced already: its replacer's closeRun finds it ended
			run.ended = true
			if cb != nil {
				cb.OnStatus(-1, "start cancelled: core was stopped")
			}
			return
		}
		inst, err := open()
		if err != nil {
			run.ended = true
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

// stop closes the running instance before it returns; an open in progress finishes first.
func (s *coreSlot[T]) stop() {
	old, prev, done := s.swap(nil)
	s.closeRun(old)
	go chain(prev, done)
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
