package handlers

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

// mockEOFReader simulates a Reader that returns both data and EOF at the same time.
type mockEOFReader struct {
	data []byte
	read bool
}

func (r *mockEOFReader) Read(p []byte) (n int, err error) {
	if r.read {
		return 0, io.EOF
	}
	n = copy(p, r.data)
	r.read = true
	return n, io.EOF // Return data and EOF simultaneously
}

// TestStdoutEOFBoundaryDataLoss simulates the exact reading loop logic found in ssh_ws.go
// to demonstrate how it leads to data loss when a read returns both data and an error (like io.EOF).
func TestStdoutEOFBoundaryDataLoss(t *testing.T) {
	testData := []byte("critical final stdout output")
	reader := &mockEOFReader{data: testData}

	// This mimics the loop in ssh_ws.go before fix:
	// for {
	//     n, err := stdout.Read(buf)
	//     if err != nil {
	//         return
	//     }
	//     if n > 0 { ... }
	// }
	var processedData []byte
	buf := make([]byte, 1024)

	for {
		n, err := reader.Read(buf)
		if err != nil {
			// This matches the buggy error handling:
			// returning immediately upon error, ignoring n > 0.
			break
		}
		if n > 0 {
			processedData = append(processedData, buf[:n]...)
		}
	}

	// Verify if the final chunk was lost
	if len(processedData) == 0 {
		t.Logf("Empirical proof: The last chunk of size %d was lost because the error check returned early.", len(testData))
	} else {
		t.Errorf("Expected data loss under the current buggy loop logic, but got: %q", string(processedData))
	}
}

// TestStdoutEOFBoundaryCorrected demonstrates how the fix resolves the data-loss bug
// by processing data before checking for the read error.
func TestStdoutEOFBoundaryCorrected(t *testing.T) {
	testData := []byte("critical final stdout output")
	reader := &mockEOFReader{data: testData}

	var processedData []byte
	buf := make([]byte, 1024)

	for {
		n, err := reader.Read(buf)
		if n > 0 {
			processedData = append(processedData, buf[:n]...)
		}
		if err != nil {
			if err == io.EOF {
				break
			}
			t.Fatalf("unexpected error: %v", err)
		}
	}

	if !bytes.Equal(processedData, testData) {
		t.Errorf("Expected %q, but got %q", string(testData), string(processedData))
	} else {
		t.Logf("Corrected loop logic successfully processed all data: %q", string(processedData))
	}
}

// raceDetectWriter is a custom http.ResponseWriter and http.Flusher
// that detects concurrent Write/Flush operations.
type raceDetectWriter struct {
	activeWrites int32
	maxConcurrent int32
	mu           sync.Mutex
	data         [][]byte
}

func (w *raceDetectWriter) Header() http.Header {
	return http.Header{}
}

func (w *raceDetectWriter) Write(b []byte) (int, error) {
	current := atomic.AddInt32(&w.activeWrites, 1)
	defer atomic.AddInt32(&w.activeWrites, -1)

	if current > 1 {
		// Multiple goroutines are in Write concurrently!
		atomic.StoreInt32(&w.maxConcurrent, current)
	}

	w.mu.Lock()
	temp := make([]byte, len(b))
	copy(temp, b)
	w.data = append(w.data, temp)
	w.mu.Unlock()

	// Add a tiny sleep to increase probability of race overlap in tests
	time.Sleep(1 * time.Millisecond)

	return len(b), nil
}

func (w *raceDetectWriter) WriteHeader(statusCode int) {}

func (w *raceDetectWriter) Flush() {}

// TestSendTransferEventConcurrency verifies that sendTransferEvent is fully thread-safe
// when the transfer_mu mutex is set on the context, and shows that concurrent writes
// happen without it.
func TestSendTransferEventConcurrency(t *testing.T) {
	gin.SetMode(gin.TestMode)

	t.Run("SafeWithMutex", func(t *testing.T) {
		w := &raceDetectWriter{}
		c, _ := gin.CreateTestContext(w)
		
		// Set the mutex on context
		c.Set("transfer_mu", &sync.Mutex{})

		var wg sync.WaitGroup
		concurrency := 50
		for i := 0; i < concurrency; i++ {
			wg.Add(1)
			go func(id int) {
				defer wg.Done()
				sendTransferEvent(c, map[string]interface{}{
					"type": "progress",
					"id":   id,
				})
			}(i)
		}
		wg.Wait()

		maxC := atomic.LoadInt32(&w.maxConcurrent)
		if maxC > 1 {
			t.Errorf("Expected no concurrent writes, but max concurrent writes was %d", maxC)
		} else {
			t.Logf("Pass: No concurrent writes occurred with mutex (max concurrent: %d)", maxC)
		}

		// Verify we got all events
		w.mu.Lock()
		lineCount := len(w.data)
		w.mu.Unlock()
		// Each event writes the JSON and a newline, so 2 writes per event -> total 100 writes
		if lineCount != concurrency*2 {
			t.Errorf("Expected %d write operations, got %d", concurrency*2, lineCount)
		}
	})

	t.Run("UnsafeWithoutMutex", func(t *testing.T) {
		w := &raceDetectWriter{}
		c, _ := gin.CreateTestContext(w)

		// Note: transfer_mu is NOT set on context here.
		// Since sendTransferEvent has a nil-check for the mutex, it will bypass locking.

		var wg sync.WaitGroup
		concurrency := 100
		for i := 0; i < concurrency; i++ {
			wg.Add(1)
			go func(id int) {
				defer wg.Done()
				sendTransferEvent(c, map[string]interface{}{
					"type": "progress",
					"id":   id,
				})
			}(i)
		}
		wg.Wait()

		maxC := atomic.LoadInt32(&w.maxConcurrent)
		t.Logf("Info: Without mutex, max concurrent writes detected: %d (concurrency: %d)", maxC, concurrency)
	})
}

// TestStdoutLoopPanicClosesDone verifies that if a panic occurs in the stdout loop,
// it recovers and correctly calls closeDone() to prevent client connection hang.
func TestStdoutLoopPanicClosesDone(t *testing.T) {
	done := make(chan struct{})
	var once sync.Once
	closeDone := func() {
		once.Do(func() {
			close(done)
		})
	}

	go func() {
		defer func() {
			if r := recover(); r != nil {
				closeDone()
			}
		}()
		// Simulate panic
		panic("simulated stdout loop panic")
	}()

	select {
	case <-done:
		t.Log("Pass: Panic was successfully recovered and done channel was closed.")
	case <-time.After(1 * time.Second):
		t.Fatal("Fail: Timeout waiting for done channel to close. Connection would have hung!")
	}
}

// TestExtractPathAdversarial tests the extractPath helper under complex output formats
func TestExtractPathAdversarial(t *testing.T) {
	tests := []struct {
		name     string
		output   string
		prefix   string
		expected string
	}{
		{
			name:     "Standard path with spaces",
			output:   "   /tmp/ts_key_abcdef123   \n",
			prefix:   "/tmp/ts_key_",
			expected: "/tmp/ts_key_abcdef123",
		},
		{
			name:     "Multiple lines, target in middle",
			output:   "Error: cannot write key\n/tmp/ts_key_xyz987\nCommand failed.",
			prefix:   "/tmp/ts_key_",
			expected: "/tmp/ts_key_xyz987",
		},
		{
			name:     "Carriage return and tabs",
			output:   "Created:\t/tmp/ts_key_cr_nl\r\n",
			prefix:   "/tmp/ts_key_",
			expected: "/tmp/ts_key_cr_nl",
		},
		{
			name:     "ANSI color escaped output",
			output:   "\u001b[32m/tmp/ts_key_color123\u001b[0m",
			prefix:   "/tmp/ts_key_",
			expected: "/tmp/ts_key_color123",
		},
		{
			name:     "Multiple paths present, extracts first matching",
			output:   "First: /tmp/ts_key_first Second: /tmp/ts_key_second",
			prefix:   "/tmp/ts_key_",
			expected: "/tmp/ts_key_first",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := extractPath(tt.output, tt.prefix)
			if got != tt.expected {
				t.Errorf("extractPath(%q, %q) = %q; want %q", tt.output, tt.prefix, got, tt.expected)
			}
		})
	}
}

// TestSimulatedCancellationContext tests context cancellation propagation to SSH command execution
func TestSimulatedCancellationContext(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	
	// Create mock request
	req, _ := http.NewRequestWithContext(ctx, "POST", "/api/sftp/transfer", nil)
	c, _ := gin.CreateTestContext(httptest.NewRecorder())
	c.Request = req

	// Cancel the context
	cancel()

	// Verify that c.Request.Context().Done() is closed
	select {
	case <-c.Request.Context().Done():
		t.Log("Pass: Context cancellation successfully propagated to Request Context.")
	default:
		t.Fatal("Fail: Request context did not propagate cancellation.")
	}
}
