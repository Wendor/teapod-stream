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
	s.stop()
	if got := cb.statuses(); len(got) != 1 {
		t.Fatalf("statuses %v, want only the failure: the stop of a failed start reports nothing", got)
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
	time.Sleep(50 * time.Millisecond) // the start's goroutine runs after the release
	if opened.Load() != 1 {
		t.Fatalf("opened %d, want the stopped start never to open", opened.Load())
	}
	if got := cb.statuses(); len(got) != 1 || got[0] != -1 {
		t.Fatalf("statuses %v, want only the cancellation: a 0 would read as a started core", got)
	}
}

// A replacement start returns while the running instance's open still hangs; that instance is
// closed once its open returns, and only then does the new one open.
func TestCoreSlotReplacementStartDoesNotWaitForAHungOpen(t *testing.T) {
	var c counter
	s := c.slot()
	entered, release := make(chan struct{}), make(chan struct{})
	s.start(nil, func() (int32, error) {
		close(entered)
		<-release
		return c.open()
	})
	<-entered
	returned := make(chan struct{})
	go func() {
		s.start(nil, c.open)
		close(returned)
	}()
	select {
	case <-returned:
	case <-time.After(time.Second):
		t.Fatal("start waited for the hung open")
	}
	close(release)
	waitFor(t, func() bool { inst, ok := s.get(); return ok && inst == 2 })
	if c.closed.Load() != 1 {
		t.Fatalf("closed %d, want the first instance closed", c.closed.Load())
	}
	s.stop()
}

// Starts racing each other and a final stop leave nothing open: each replaced run is closed by
// the call that replaced it.
func TestCoreSlotConcurrentStartsLeaveNoOrphan(t *testing.T) {
	var c counter
	s := c.slot()
	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			s.start(nil, c.open)
		}()
	}
	wg.Wait()
	waitFor(t, func() bool { _, ok := s.get(); return ok })
	s.stop()
	time.Sleep(50 * time.Millisecond)
	if c.opened.Load() != c.closed.Load() {
		t.Fatalf("opened %d, closed %d", c.opened.Load(), c.closed.Load())
	}
}

// Every start reports exactly one outcome, and a start that never opened never reports 0.
func TestCoreSlotEachStartReportsOneOutcome(t *testing.T) {
	var c counter
	s := c.slot()
	logs := make([]*statusLog, 100)
	for i := range logs {
		logs[i] = &statusLog{}
		s.start(logs[i], c.open)
		if i%3 == 0 {
			s.stop()
		}
	}
	s.stop()
	time.Sleep(100 * time.Millisecond)
	opened := 0
	for i, l := range logs {
		got := l.statuses()
		switch {
		case len(got) == 1 && got[0] == -1: // cancelled before it opened
		case len(got) == 2 && got[0] == 0 && got[1] == 0: // started, then stopped
			opened++
		default:
			t.Fatalf("start %d reported %v", i, got)
		}
	}
	if int32(opened) != c.opened.Load() || c.opened.Load() != c.closed.Load() {
		t.Fatalf("reported %d started, opened %d, closed %d", opened, c.opened.Load(), c.closed.Load())
	}
}
