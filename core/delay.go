package teapodcore

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"time"
)

// measureDelayVia — an HTTP probe through dial: the best of two attempts, ms.
func measureDelayVia(ctx context.Context, dial func(ctx context.Context, network, addr string) (net.Conn, error), url string) (int64, error) {
	tr := &http.Transport{
		TLSHandshakeTimeout: 6 * time.Second,
		DisableKeepAlives:   false,
		DialContext:         dial,
	}
	// A keep-alive connection holds the outbound session, and with it the connection to the server.
	defer tr.CloseIdleConnections()
	client := &http.Client{Transport: tr, Timeout: 12 * time.Second}

	if url == "" {
		url = "https://www.google.com/generate_204"
	}

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return -1, fmt.Errorf("failed to create request: %w", err)
	}

	var best int64 = -1
	var lastErr error
	for i := 0; i < 2; i++ {
		select {
		case <-ctx.Done():
			if best < 0 {
				return -1, ctx.Err()
			}
			return best, nil
		default:
		}

		start := time.Now()
		resp, err := client.Do(req)
		if err != nil {
			lastErr = err
			continue
		}
		_, err = io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
		if err != nil {
			// Headers came but the body stalled until the deadline: not a working path.
			lastErr = fmt.Errorf("read response body: %w", err)
			continue
		}

		if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
			lastErr = fmt.Errorf("unexpected status: %s", resp.Status)
			continue
		}

		ms := time.Since(start).Milliseconds()
		if best < 0 || ms < best {
			best = ms
		}
	}
	if best < 0 {
		return -1, lastErr
	}
	return best, nil
}
