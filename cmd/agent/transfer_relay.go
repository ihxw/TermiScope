package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"hash"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync/atomic"

	"github.com/ihxw/termiscope/internal/agenttransfer"
)

type localAgentTransferSource struct {
	io.ReadCloser
	entryType string
	mode      string
}

func openLocalAgentTransferSource(ctx context.Context, remotePath string, isDir bool) (*localAgentTransferSource, error) {
	localPath := localAgentTransferPath(remotePath)
	info, err := os.Lstat(localPath)
	if err != nil || info.Mode()&os.ModeSymlink != 0 || info.IsDir() != isDir || (!info.IsDir() && !info.Mode().IsRegular()) {
		return nil, errors.New("source unavailable")
	}
	entryType := "file"
	mode := strconv.FormatUint(uint64(info.Mode().Perm()), 8)
	if !isDir {
		file, openErr := os.Open(localPath)
		if openErr != nil {
			return nil, openErr
		}
		return &localAgentTransferSource{ReadCloser: file, entryType: entryType, mode: mode}, nil
	}

	entryType = "directory"
	reader, writer := io.Pipe()
	go func() {
		err := writeDirectoryTar(ctx, writer, localPath)
		_ = writer.CloseWithError(err)
	}()
	return &localAgentTransferSource{ReadCloser: reader, entryType: entryType, mode: mode}, nil
}

func executeAgentRelaySource(reportClient *http.Client, command agenttransfer.Command) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	source, err := openLocalAgentTransferSource(ctx, command.SourcePath, command.IsDir)
	if err == nil {
		defer source.Close()
		err = uploadAgentRelayChunks(reportClient, command, source)
	}
	if err != nil {
		_ = sendAgentTransferReport(reportClient, agenttransfer.Report{
			TransferID: command.TransferID,
			Status:     "source_error",
			Message:    err.Error(),
			Total:      command.TotalSize,
		})
	}
}

func uploadAgentRelayChunks(client *http.Client, command agenttransfer.Command, source *localAgentTransferSource) error {
	buffer := make([]byte, agenttransfer.RelayChunkSize)
	digest := sha256.New()
	var sequence uint64
	for {
		n, readErr := io.ReadFull(source, buffer)
		if n > 0 {
			chunk := buffer[:n]
			_, _ = digest.Write(chunk)
			if err := sendAgentRelayChunk(client, command, sequence, chunk, false, "", source); err != nil {
				return err
			}
			sequence++
		}
		if errors.Is(readErr, io.EOF) || errors.Is(readErr, io.ErrUnexpectedEOF) {
			break
		}
		if readErr != nil {
			return readErr
		}
	}
	return sendAgentRelayChunk(client, command, sequence, nil, true, hex.EncodeToString(digest.Sum(nil)), source)
}

func sendAgentRelayChunk(
	baseClient *http.Client,
	command agenttransfer.Command,
	sequence uint64,
	data []byte,
	final bool,
	digest string,
	source *localAgentTransferSource,
) error {
	endpoint := strings.TrimRight(serverURL, "/") + "/api/monitor/agent-transfer/relay/" + url.PathEscape(command.TransferID) + "/source"
	query := url.Values{
		"host_id":  []string{strconv.FormatUint(hostID, 10)},
		"sequence": []string{strconv.FormatUint(sequence, 10)},
	}
	request, err := http.NewRequest(http.MethodPost, endpoint+"?"+query.Encode(), bytes.NewReader(data))
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", "Bearer "+secret)
	request.Header.Set("Content-Type", "application/octet-stream")
	request.Header.Set("X-Termiscope-Type", source.entryType)
	request.Header.Set("X-Termiscope-Mode", source.mode)
	if final {
		request.Header.Set("X-Termiscope-Relay-Final", "1")
		request.Header.Set("X-Termiscope-Relay-Digest", digest)
	}
	response, err := agentTransferLongClient(baseClient).Do(request)
	if err != nil {
		return fmt.Errorf("upload relay chunk %d: %w", sequence, err)
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("relay source rejected chunk %d: %s", sequence, response.Status)
	}
	return nil
}

type agentRelayChunkReader struct {
	ctx        context.Context
	client     *http.Client
	command    agenttransfer.Command
	sequence   uint64
	current    *bytes.Reader
	currentEnd bool
	finished   bool
	digest     hash.Hash
	wantDigest string
	entryType  string
	mode       string
}

func newAgentRelayChunkReader(ctx context.Context, client *http.Client, command agenttransfer.Command) (*agentRelayChunkReader, error) {
	reader := &agentRelayChunkReader{ctx: ctx, client: agentTransferLongClient(client), command: command, digest: sha256.New()}
	if err := reader.fetch(); err != nil {
		return nil, err
	}
	return reader, nil
}

func (r *agentRelayChunkReader) Read(buffer []byte) (int, error) {
	for {
		if r.finished {
			return 0, io.EOF
		}
		if r.current != nil && r.current.Len() > 0 {
			n, err := r.current.Read(buffer)
			if n > 0 {
				_, _ = r.digest.Write(buffer[:n])
			}
			return n, err
		}
		if r.currentEnd {
			observed := hex.EncodeToString(r.digest.Sum(nil))
			if !strings.EqualFold(observed, r.wantDigest) {
				return 0, errors.New("relay checksum mismatch")
			}
			r.finished = true
			return 0, io.EOF
		}
		if err := r.fetch(); err != nil {
			return 0, err
		}
	}
}

func (r *agentRelayChunkReader) fetch() error {
	endpoint := strings.TrimRight(serverURL, "/") + "/api/monitor/agent-transfer/relay/" + url.PathEscape(r.command.TransferID) + "/destination"
	query := url.Values{
		"host_id":  []string{strconv.FormatUint(hostID, 10)},
		"sequence": []string{strconv.FormatUint(r.sequence, 10)},
	}
	request, err := http.NewRequestWithContext(r.ctx, http.MethodGet, endpoint+"?"+query.Encode(), nil)
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", "Bearer "+secret)
	response, err := r.client.Do(request)
	if err != nil {
		return fmt.Errorf("download relay chunk %d: %w", r.sequence, err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
		return fmt.Errorf("relay destination rejected chunk %d: %s", r.sequence, response.Status)
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, agenttransfer.RelayChunkSize+1))
	if err != nil || len(data) > agenttransfer.RelayChunkSize {
		return errors.New("invalid relay chunk response")
	}
	entryType := response.Header.Get("X-Termiscope-Type")
	mode := response.Header.Get("X-Termiscope-Mode")
	if r.sequence == 0 {
		r.entryType = entryType
		r.mode = mode
	} else if entryType != r.entryType || mode != r.mode {
		return errors.New("relay metadata changed during transfer")
	}
	r.current = bytes.NewReader(data)
	r.currentEnd = response.Header.Get("X-Termiscope-Relay-Final") == "1"
	if r.currentEnd {
		r.wantDigest = strings.ToLower(strings.TrimSpace(response.Header.Get("X-Termiscope-Relay-Digest")))
		decoded, decodeErr := hex.DecodeString(r.wantDigest)
		if decodeErr != nil || len(decoded) != sha256.Size || len(data) != 0 {
			return errors.New("invalid final relay chunk")
		}
	} else if len(data) == 0 {
		return errors.New("empty non-final relay chunk")
	}
	r.sequence++
	return nil
}

func receiveAgentRelay(ctx context.Context, reportClient *http.Client, command agenttransfer.Command, transferred *atomic.Int64) error {
	reader, err := newAgentRelayChunkReader(ctx, reportClient, command)
	if err != nil {
		return err
	}
	if err := writeAgentTransferDestination(command, reader, reader.entryType, reader.mode, transferred); err != nil {
		return err
	}
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
		return nil
	}
}

func agentTransferLongClient(base *http.Client) *http.Client {
	return &http.Client{Transport: base.Transport, CheckRedirect: base.CheckRedirect}
}
