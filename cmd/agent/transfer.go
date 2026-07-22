package main

import (
	"archive/tar"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/ihxw/termiscope/internal/agenttransfer"
)

const agentTransferBufferSize = 4 * 1024 * 1024

var (
	agentTransferSwitchMu sync.Mutex
	agentTransferRuntime  struct {
		sync.RWMutex
		server      *http.Server
		port        int
		fingerprint string
	}
)

func startAgentTransferServer(port int) *http.Server {
	server, fingerprint, err := newAgentTransferServer(port)
	if err != nil {
		logError("Agent transfer listener unavailable on port %d: %v", port, err)
		setActiveAgentTransferServer(nil, 0, "")
		return nil
	}
	setActiveAgentTransferServer(server, port, fingerprint)
	return server
}

func newAgentTransferServer(port int) (*http.Server, string, error) {
	if port <= 0 || port > 65535 || secret == "" {
		return nil, "", errors.New("invalid transfer listener configuration")
	}
	certificate, fingerprint, err := newAgentTransferCertificate()
	if err != nil {
		return nil, "", fmt.Errorf("create transfer certificate: %w", err)
	}
	listener, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		return nil, "", err
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/transfer", serveAgentTransfer)
	server := &http.Server{
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       2 * time.Minute,
	}
	tlsListener := tls.NewListener(listener, &tls.Config{
		Certificates: []tls.Certificate{certificate},
		MinVersion:   tls.VersionTLS12,
	})
	go func() {
		if err := server.Serve(tlsListener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logError("Agent transfer server stopped: %v", err)
		}
	}()
	return server, fingerprint, nil
}

func setActiveAgentTransferServer(server *http.Server, port int, fingerprint string) *http.Server {
	agentTransferRuntime.Lock()
	previous := agentTransferRuntime.server
	agentTransferRuntime.server = server
	agentTransferRuntime.port = port
	agentTransferRuntime.fingerprint = fingerprint
	agentTransferPort = port
	agentTransferCertSHA256 = fingerprint
	agentTransferRuntime.Unlock()
	return previous
}

func activeAgentTransferSnapshot() (int, string) {
	agentTransferRuntime.RLock()
	defer agentTransferRuntime.RUnlock()
	return agentTransferRuntime.port, agentTransferRuntime.fingerprint
}

func reconfigureAgentTransferServer(port int) (bool, error) {
	if port <= 0 || port > 65535 {
		return false, errors.New("transfer port must be between 1 and 65535")
	}

	agentTransferSwitchMu.Lock()
	defer agentTransferSwitchMu.Unlock()

	currentPort, _ := activeAgentTransferSnapshot()
	if currentPort == port {
		if configPath == "" {
			return false, nil
		}
		return true, persistAgentTransferPort(configPath, port)
	}

	server, fingerprint, err := newAgentTransferServer(port)
	if err != nil {
		return false, err
	}
	if configPath != "" {
		if err := persistAgentTransferPort(configPath, port); err != nil {
			_ = server.Close()
			return false, fmt.Errorf("persist transfer port: %w", err)
		}
	}

	previous := setActiveAgentTransferServer(server, port, fingerprint)
	if previous != nil {
		go func() { _ = previous.Close() }()
	}
	return configPath != "", nil
}

func stopActiveAgentTransferServer() {
	agentTransferSwitchMu.Lock()
	defer agentTransferSwitchMu.Unlock()
	previous := setActiveAgentTransferServer(nil, 0, "")
	if previous != nil {
		_ = previous.Close()
	}
}

func newAgentTransferCertificate() (tls.Certificate, string, error) {
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return tls.Certificate{}, "", err
	}
	serialLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serial, err := rand.Int(rand.Reader, serialLimit)
	if err != nil {
		return tls.Certificate{}, "", err
	}
	now := time.Now()
	template := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: "TermiScope Agent Transfer"},
		NotBefore:    now.Add(-time.Minute),
		NotAfter:     now.AddDate(5, 0, 0),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, publicKey, privateKey)
	if err != nil {
		return tls.Certificate{}, "", err
	}
	fingerprint := sha256.Sum256(der)
	return tls.Certificate{Certificate: [][]byte{der}, PrivateKey: privateKey}, hex.EncodeToString(fingerprint[:]), nil
}

func serveAgentTransfer(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	token := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
	claims, err := agenttransfer.VerifySourceToken(secret, token, time.Now())
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	sourcePath := localAgentTransferPath(claims.Path)
	info, err := os.Lstat(sourcePath)
	if err != nil || info.Mode()&os.ModeSymlink != 0 || info.IsDir() != claims.IsDir || (!info.IsDir() && !info.Mode().IsRegular()) {
		http.Error(w, "source unavailable", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("X-Termiscope-Mode", strconv.FormatUint(uint64(info.Mode().Perm()), 8))
	if info.IsDir() {
		w.Header().Set("X-Termiscope-Type", "directory")
		if err := writeDirectoryTar(r.Context(), w, sourcePath); err != nil {
			return
		}
		return
	}

	file, err := os.Open(sourcePath)
	if err != nil {
		http.Error(w, "source unavailable", http.StatusNotFound)
		return
	}
	defer file.Close()
	w.Header().Set("X-Termiscope-Type", "file")
	w.Header().Set("Content-Length", strconv.FormatInt(info.Size(), 10))
	_, _ = io.CopyBuffer(w, file, make([]byte, agentTransferBufferSize))
}

func writeDirectoryTar(ctx context.Context, output io.Writer, root string) error {
	writer := tar.NewWriter(output)
	walkErr := filepath.Walk(root, func(current string, info os.FileInfo, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if current == root {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		relative, err := filepath.Rel(root, current)
		if err != nil {
			return err
		}
		linkTarget := ""
		if info.Mode()&os.ModeSymlink != 0 {
			linkTarget, err = os.Readlink(current)
			if err != nil {
				return err
			}
		}
		header, err := tar.FileInfoHeader(info, linkTarget)
		if err != nil {
			return err
		}
		header.Name = filepath.ToSlash(relative)
		if err := writer.WriteHeader(header); err != nil {
			return err
		}
		if !info.Mode().IsRegular() {
			return nil
		}
		file, err := os.Open(current)
		if err != nil {
			return err
		}
		_, copyErr := io.CopyBuffer(writer, file, make([]byte, agentTransferBufferSize))
		closeErr := file.Close()
		if copyErr != nil {
			return copyErr
		}
		return closeErr
	})
	closeErr := writer.Close()
	if walkErr != nil {
		return walkErr
	}
	return closeErr
}

func executeAgentTransfer(reportClient *http.Client, command agenttransfer.Command) {
	if command.Mode == agenttransfer.ModeRelaySource {
		executeAgentRelaySource(reportClient, command)
		return
	}
	executeAgentDestinationTransfer(reportClient, command)
}

func executeAgentDestinationTransfer(reportClient *http.Client, command agenttransfer.Command) {
	if err := sendAgentTransferReport(reportClient, agenttransfer.Report{
		TransferID: command.TransferID, Status: "started", Total: command.TotalSize,
	}); err != nil {
		return
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var transferred atomic.Int64
	progressDone := make(chan struct{})
	progressErr := make(chan error, 1)
	var progressWG sync.WaitGroup
	progressWG.Add(1)
	go func() {
		defer progressWG.Done()
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		started := time.Now()
		for {
			select {
			case <-progressDone:
				return
			case <-ticker.C:
				written := transferred.Load()
				report := agenttransfer.Report{
					TransferID: command.TransferID,
					Status:     "progress", Transferred: written, Total: command.TotalSize,
					Speed: float64(written) / time.Since(started).Seconds(),
				}
				if err := sendAgentTransferReport(reportClient, report); err != nil {
					select {
					case progressErr <- err:
					default:
					}
					cancel()
					return
				}
			}
		}
	}()

	var err error
	if command.Mode == agenttransfer.ModeRelayDest {
		err = receiveAgentRelay(ctx, reportClient, command, &transferred)
	} else {
		err = receiveAgentTransfer(ctx, command, &transferred)
	}
	close(progressDone)
	progressWG.Wait()
	select {
	case reportErr := <-progressErr:
		if err == nil {
			err = reportErr
		}
	default:
	}
	if err != nil {
		_ = os.RemoveAll(localAgentTransferPath(command.DestPath))
		_ = sendAgentTransferReport(reportClient, agenttransfer.Report{
			TransferID: command.TransferID, Status: "error", Message: err.Error(),
			Transferred: transferred.Load(), Total: command.TotalSize,
		})
		return
	}
	if err := sendAgentTransferReport(reportClient, agenttransfer.Report{
		TransferID: command.TransferID, Status: "complete",
		Transferred: transferred.Load(), Total: command.TotalSize,
	}); err != nil {
		_ = os.RemoveAll(localAgentTransferPath(command.DestPath))
	}
}

type transferCountingReader struct {
	reader io.Reader
	count  *atomic.Int64
}

func (r transferCountingReader) Read(buffer []byte) (int, error) {
	n, err := r.reader.Read(buffer)
	if n > 0 {
		r.count.Add(int64(n))
	}
	return n, err
}

func receiveAgentTransfer(ctx context.Context, command agenttransfer.Command, transferred *atomic.Int64) error {
	fingerprint, ok := agenttransfer.NormalizeCertificateFingerprint(command.SourceCertSHA256)
	if !ok {
		return errors.New("invalid source certificate fingerprint")
	}
	transport := &http.Transport{TLSClientConfig: &tls.Config{
		MinVersion:         tls.VersionTLS12,
		InsecureSkipVerify: true,
		VerifyConnection: func(state tls.ConnectionState) error {
			if len(state.PeerCertificates) == 0 {
				return errors.New("source certificate missing")
			}
			observed := sha256.Sum256(state.PeerCertificates[0].Raw)
			if !strings.EqualFold(hex.EncodeToString(observed[:]), fingerprint) {
				return errors.New("source certificate fingerprint mismatch")
			}
			return nil
		},
	},
		DialContext:           (&net.Dialer{Timeout: 5 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		TLSHandshakeTimeout:   5 * time.Second,
		ResponseHeaderTimeout: 10 * time.Second,
	}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, command.SourceURL, nil)
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", "Bearer "+command.SourceToken)
	response, err := client.Do(request)
	if err != nil {
		return fmt.Errorf("connect source agent: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
		return fmt.Errorf("source agent returned %s", response.Status)
	}
	wantType := "file"
	if command.IsDir {
		wantType = "directory"
	}
	if response.Header.Get("X-Termiscope-Type") != wantType {
		return errors.New("source type changed during transfer")
	}

	return writeAgentTransferDestination(
		command,
		response.Body,
		response.Header.Get("X-Termiscope-Type"),
		response.Header.Get("X-Termiscope-Mode"),
		transferred,
	)
}

func writeAgentTransferDestination(command agenttransfer.Command, source io.Reader, entryType, modeValue string, transferred *atomic.Int64) error {
	wantType := "file"
	if command.IsDir {
		wantType = "directory"
	}
	if entryType != wantType {
		return errors.New("source type changed during transfer")
	}
	destPath := localAgentTransferPath(command.DestPath)
	reader := transferCountingReader{reader: source, count: transferred}
	mode := parseTransferMode(modeValue, 0600)
	if command.IsDir {
		if err := extractAgentTransferTar(reader, destPath, mode); err != nil {
			return err
		}
		_, err := io.Copy(io.Discard, reader)
		return err
	}
	if err := os.MkdirAll(filepath.Dir(destPath), 0755); err != nil {
		return err
	}
	file, err := os.OpenFile(destPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	_, copyErr := io.CopyBuffer(file, reader, make([]byte, agentTransferBufferSize))
	closeErr := file.Close()
	if copyErr != nil {
		return copyErr
	}
	return closeErr
}

func parseTransferMode(value string, fallback os.FileMode) os.FileMode {
	parsed, err := strconv.ParseUint(value, 8, 32)
	if err != nil {
		return fallback
	}
	return os.FileMode(parsed) & os.ModePerm
}

func localAgentTransferPath(remotePath string) string {
	if runtime.GOOS == "windows" && len(remotePath) >= 4 && remotePath[0] == '/' && remotePath[2] == ':' {
		letter := remotePath[1]
		if (letter >= 'a' && letter <= 'z') || (letter >= 'A' && letter <= 'Z') {
			remotePath = remotePath[1:]
		}
	}
	return filepath.FromSlash(remotePath)
}

type pendingTransferLink struct {
	path   string
	target string
}

type pendingTransferDir struct {
	path string
	mode os.FileMode
}

func extractAgentTransferTar(reader io.Reader, destination string, rootMode os.FileMode) error {
	if err := os.MkdirAll(destination, 0700); err != nil {
		return err
	}
	archive := tar.NewReader(reader)
	var links []pendingTransferLink
	dirs := []pendingTransferDir{{path: destination, mode: rootMode}}
	for {
		header, err := archive.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return err
		}
		target, err := safeAgentTransferPath(destination, header.Name)
		if err != nil {
			return err
		}
		mode := os.FileMode(header.Mode) & os.ModePerm
		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0700); err != nil {
				return err
			}
			dirs = append(dirs, pendingTransferDir{path: target, mode: mode})
		case tar.TypeReg, tar.TypeRegA:
			if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
				return err
			}
			file, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
			if err != nil {
				return err
			}
			_, copyErr := io.CopyBuffer(file, archive, make([]byte, agentTransferBufferSize))
			closeErr := file.Close()
			if copyErr != nil {
				return copyErr
			}
			if closeErr != nil {
				return closeErr
			}
		case tar.TypeSymlink:
			links = append(links, pendingTransferLink{path: target, target: header.Linkname})
		default:
			return fmt.Errorf("unsupported archive entry %q", header.Name)
		}
	}
	for _, link := range links {
		if err := os.MkdirAll(filepath.Dir(link.path), 0755); err != nil {
			return err
		}
		if err := os.Symlink(link.target, link.path); err != nil {
			return err
		}
	}
	for i := len(dirs) - 1; i >= 0; i-- {
		if err := os.Chmod(dirs[i].path, dirs[i].mode); err != nil && !errors.Is(err, os.ErrPermission) {
			return err
		}
	}
	return nil
}

func safeAgentTransferPath(root, name string) (string, error) {
	cleanName := filepath.Clean(filepath.FromSlash(name))
	if cleanName == "." || filepath.IsAbs(cleanName) || cleanName == ".." || strings.HasPrefix(cleanName, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("unsafe archive path %q", name)
	}
	target := filepath.Join(root, cleanName)
	relative, err := filepath.Rel(root, target)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("unsafe archive path %q", name)
	}
	return target, nil
}

func sendAgentTransferReport(client *http.Client, report agenttransfer.Report) error {
	payload, err := json.Marshal(report)
	if err != nil {
		return err
	}
	endpoint := fmt.Sprintf("%s/api/monitor/agent-transfer/report?host_id=%d", strings.TrimRight(serverURL, "/"), hostID)
	request, err := http.NewRequest(http.MethodPost, endpoint, strings.NewReader(string(payload)))
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", "Bearer "+secret)
	request.Header.Set("Content-Type", "application/json")
	response, err := client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("transfer report rejected: %s", response.Status)
	}
	return nil
}
