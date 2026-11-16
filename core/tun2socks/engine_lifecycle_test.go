package tun2socks

import (
	"errors"
	"os"
	"testing"
	"time"

	"golang.org/x/sys/unix"
)

// The wrapper starts the engine in a goroutine, so Stop can run first. Start must then
// not start workers, and Stop must still have released what NewEngine created.
func TestEngineStopBeforeStart(t *testing.T) {
	fds, err := unix.Socketpair(unix.AF_UNIX, unix.SOCK_DGRAM, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer unix.Close(fds[0])
	defer unix.Close(fds[1])
	e, err := NewEngine(fds[1], 1500, "127.0.0.1", 1080, "", "", false, false, NewEngineHook(16, 60))
	if err != nil {
		t.Fatal(err)
	}

	e.Stop()
	if _, err := e.tunFile.Write([]byte{0x45}); !errors.Is(err, os.ErrClosed) {
		t.Fatalf("TUN fd copy still open after Stop: write err = %v", err)
	}

	started := make(chan error, 1)
	go func() { started <- e.Start() }()
	select {
	case err := <-started:
		if err == nil {
			t.Fatal("Start after Stop returned nil; want an error")
		}
	case <-time.After(2 * time.Second):
		e.Stop()
		t.Fatal("Start after Stop is running with nothing left to stop it")
	}
	if e.IsRunning() {
		t.Fatal("engine reports running after Stop")
	}
}
