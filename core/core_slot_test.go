package teapodcore

import (
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type statusLog struct {
	mu  sync.Mutex
	got []int64
}

func (l *statusLog) OnStatus(status int64, _ string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.got = append(l.got, status)
}

func (l *statusLog) statuses() []int64 {
	l.mu.Lock()
	defer l.mu.Unlock()
	return append([]int64(nil), l.got...)
}

// counter opens numbered instances and counts the closed ones.
type counter struct{ opened, closed atomic.Int32 }

func (c *counter) slot() *coreSlot[int32] {
	return &coreSlot[int32]{name: "test", close: func(int32) error { c.closed.Add(1); return nil }}
}

func (c *counter) open() (int32, error) { return c.opened.Add(1), nil }

// waitFor polls cond for up to a second: the start runs on its own goroutine.
func waitFor(t *testing.T, cond func() bool) {
	t.Helper()
	for deadline := time.Now().Add(time.Second); !cond(); {
		if time.Now().After(deadline) {
			t.Fatal("condition not reached")
		}
		time.Sleep(time.Millisecond)
	}
}

func TestCoreSlotStartsAndStops(t *testing.T) {
	var c counter
	s := c.slot()
	cb := &statusLog{}
	s.start(cb, c.open)
	waitFor(t, func() bool { _, ok := s.get(); return ok })
	if inst, _ := s.get(); inst != 1 {
		t.Fatalf("instance %d, want 1", inst)
	}
	s.stop()
	if _, ok := s.get(); ok {
		t.Fatal("still running after stop")
	}
	if c.closed.Load() != 1 {
		t.Fatalf("closed %d, want 1", c.closed.Load())
	}
	if got := cb.statuses(); len(got) != 2 || got[0] != 0 || got[1] != 0 {
		t.Fatalf("statuses %v, want started and stopped", got)
	}
}

func TestCoreSlotStartReplacesTheRunningInstance(t *testing.T) {
	var c counter
	s := c.slot()
	s.start(nil, c.open)
	waitFor(t, func() bool { _, ok := s.get(); return ok })
	s.start(nil, c.open)
	waitFor(t, func() bool { inst, ok := s.get(); return ok && inst == 2 })
	if c.closed.Load() != 1 {
		t.Fatalf("closed %d, want the first instance closed", c.closed.Load())
	}
	s.stop()
}

func TestCoreSlotFailedOpenReportsTheError(t *testing.T) {
	s := (&counter{}).slot()
	cb := &statusLog{}
	s.start(cb, func() (int32, error) { return 0, errors.New("boom") })
	waitFor(t, func() bool { return len(cb.statuses()) == 1 })
	if got := cb.statuses(); got[0] != -1 {
		t.Fatalf("status %d, want -1", got[0])
	}
	if _, ok := s.get(); ok {
		t.Fatal("a failed start reads as running")
	}
}

// A stop racing the start's goroutine either cancels the start or closes what it opened:
// nothing is left open either way.
func TestCoreSlotStopRightAfterStartLeavesNothingOpen(t *testing.T) {
	var c counter
	s := c.slot()
	for i := 0; i < 200; i++ {
		s.start(nil, c.open)
		s.stop()
	}
	// A cancelled start's goroutine may still be about to check; give it time, then compare.
	time.Sleep(50 * time.Millisecond)
	if _, ok := s.get(); ok {
		t.Fatal("running after the last stop")
	}
	if c.opened.Load() != c.closed.Load() {
		t.Fatalf("opened %d, closed %d", c.opened.Load(), c.closed.Load())
	}
}

// A stop during the open waits for it and closes the instance it returns.
func TestCoreSlotStopDuringOpenClosesTheOpenedInstance(t *testing.T) {
	var c counter
	s := c.slot()
	entered, release := make(chan struct{}), make(chan struct{})
	s.start(nil, func() (int32, error) {
		close(entered)
		<-release
		return c.open()
	})
	<-entered
	stopped := make(chan struct{})
	go func() { s.stop(); close(stopped) }()
	select {
	case <-stopped:
		t.Fatal("stop returned while the open was running")
	case <-time.After(20 * time.Millisecond):
	}
	close(release)
	<-stopped
	if c.opened.Load() != 1 || c.closed.Load() != 1 {
		t.Fatalf("opened %d, closed %d, want 1 and 1", c.opened.Load(), c.closed.Load())
	}
}

// A start while another caller's stop is still closing the instance opens the new one only after
// that close returned (the old instance may still hold the port), and start itself doesn't wait.
func TestCoreSlotOpenWaitsForAStopInProgress(t *testing.T) {
	var opened atomic.Int32
	closing, release := make(chan struct{}), make(chan struct{})
	s := &coreSlot[int32]{name: "test", close: func(int32) error {
		close(closing)
		<-release
		return nil
	}}
	s.start(nil, func() (int32, error) { return opened.Add(1), nil })
	waitFor(t, func() bool { _, ok := s.get(); return ok })

	go s.stop()
	<-closing
	s.start(nil, func() (int32, error) { return opened.Add(1), nil }) // returns at once
	time.Sleep(20 * time.Millisecond)
	if opened.Load() != 1 {
		t.Fatalf("opened %d before the close returned, want 1", opened.Load())
	}
	close(release)
	waitFor(t, func() bool { inst, ok := s.get(); return ok && inst == 2 })
}

// A start given up while it waits for a hung close (its caller's deadline passed and it stopped)
// never opens, even when the close finally returns.
func TestCoreSlotStartStoppedWhileWaitingNeverOpens(t *testing.T) {
	var opened atomic.Int32
	closing, release := make(chan struct{}), make(chan struct{})
	s := &coreSlot[int32]{name: "test", close: func(int32) error {
		if opened.Load() == 1 {
			close(closing)
			<-release
		}
		return nil
	}}
	s.start(nil, func() (int32, error) { return opened.Add(1), nil })
	waitFor(t, func() bool { _, ok := s.get(); return ok })

	go s.stop()
	<-closing
	cb := &statusLog{}
	s.start(cb, func() (int32, error) { return opened.Add(1), nil })
	s.stop() // the caller's deadline: returns although the earlier close still hangs
	close(release)
	waitFor(t, func() bool { return len(cb.statuses()) == 2 })
	if opened.Load() != 1 {
		t.Fatalf("opened %d, want the stopped start never to open", opened.Load())
	}
	if got := cb.statuses(); got[0] != 0 || got[1] != -1 {
		t.Fatalf("statuses %v, want stopped then cancelled", got)
	}
}
