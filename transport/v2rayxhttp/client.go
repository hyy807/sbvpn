package v2rayxhttp

// 闪连 / LightXtreme 私有 XHTTP 客户端传输 (stream-up 模式)。
//
// 线上协议 (实测抓包 + 反汇编还原):
//   上行: POST https://<server><path>/<uuid4>   content-type: application/grpc
//         referer: https://<server><path>/?x_padding=XXXX...(重复 X)
//         body  = obfs 流 (见 obfs.go)，持续 DATA 帧
//   下行: GET  https://<download><dpath>/<uuid4>  同样的 referer 填充
//         响应 200 text/event-stream，body = 同一套 obfs 的裸字节流
//
// 上下行共用同一个 uuid4；TLS 一定是 h2 (ALPN)。

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/common/tls"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
	E "github.com/sagernet/sing/common/exceptions"
	"github.com/sagernet/sing/common/logger"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"

	"golang.org/x/net/http2"
)

var _ adapter.V2RayClientTransport = (*Client)(nil)

const (
	defaultPaddingMin = 100
	defaultPaddingMax = 1000
)

type Client struct {
	ctx          context.Context
	serverAddr   M.Socksaddr
	downloadAddr M.Socksaddr
	path         string
	downloadPath string
	obfsKey      []byte
	paddingMin   int
	paddingMax   int
	upload       *http2.Transport
	download     *http2.Transport
	closeOnce    sync.Once
}

func NewClient(ctx context.Context, dialer N.Dialer, serverAddr M.Socksaddr, options option.V2RayXHTTPOptions, tlsConfig tls.Config) (adapter.V2RayClientTransport, error) {
	if tlsConfig == nil {
		return nil, C.ErrTLSRequired
	}
	if !serverAddr.IsValid() {
		return nil, E.New("missing server address")
	}
	client := &Client{
		ctx:          ctx,
		serverAddr:   serverAddr,
		downloadAddr: serverAddr,
		path:         normalizePath(options.Path),
		downloadPath: normalizePath(options.Path),
		paddingMin:   defaultPaddingMin,
		paddingMax:   defaultPaddingMax,
	}
	if options.ObfsKey != "" {
		client.obfsKey = obfsDeriveKey(options.ObfsKey)
	}
	if options.PaddingMin > 0 && options.PaddingMax >= options.PaddingMin {
		client.paddingMin = options.PaddingMin
		client.paddingMax = options.PaddingMax
	}

	downloadTLS := tlsConfig
	if options.Download != nil {
		if options.Download.Server != "" {
			client.downloadAddr = options.Download.Build()
		}
		if options.Download.Path != "" {
			client.downloadPath = normalizePath(options.Download.Path)
		}
		if options.Download.TLS != nil && options.Download.TLS.Enabled {
			downloadTLSConfig, err := tls.NewClient(ctx, logger.NOP(), client.downloadAddr.AddrString(), *options.Download.TLS)
			if err != nil {
				return nil, E.Cause(err, "create download tls config")
			}
			downloadTLS = downloadTLSConfig
		} else {
			cloned := tlsConfig.Clone()
			cloned.SetServerName(client.downloadAddr.AddrString())
			downloadTLS = cloned
		}
	}

	var err error
	client.upload, err = newHTTP2Transport(dialer, tlsConfig, client.serverAddr)
	if err != nil {
		return nil, err
	}
	client.download, err = newHTTP2Transport(dialer, downloadTLS, client.downloadAddr)
	if err != nil {
		return nil, err
	}
	return client, nil
}

func newHTTP2Transport(dialer N.Dialer, tlsConfig tls.Config, serverAddr M.Socksaddr) (*http2.Transport, error) {
	cloned := tlsConfig.Clone()
	nextProtos := cloned.NextProtos()
	if len(nextProtos) == 0 {
		cloned.SetNextProtos([]string{http2.NextProtoTLS})
	}
	tlsDialer := tls.NewDialer(dialer, cloned)
	transport := &http2.Transport{
		DialTLSContext: func(ctx context.Context, network string, addr string, cfg *tls.STDConfig) (net.Conn, error) {
			return tlsDialer.DialTLSContext(ctx, serverAddr)
		},
	}
	return transport, nil
}

func normalizePath(path string) string {
	if path == "" {
		return "/"
	}
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	return strings.TrimSuffix(path, "/")
}

func (c *Client) buildReferer(host string, path string) string {
	length := c.paddingMin
	if c.paddingMax > c.paddingMin {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(c.paddingMax-c.paddingMin+1)))
		if err == nil {
			length += int(n.Int64())
		}
	}
	return fmt.Sprintf("https://%s%s/?x_padding=%s", host, path, strings.Repeat("X", length))
}

func newSessionID() (string, error) {
	var raw [16]byte
	_, err := rand.Read(raw[:])
	if err != nil {
		return "", err
	}
	raw[6] = (raw[6] & 0x0f) | 0x40
	raw[8] = (raw[8] & 0x3f) | 0x80
	encoded := hex.EncodeToString(raw[:])
	return encoded[0:8] + "-" + encoded[8:12] + "-" + encoded[12:16] + "-" + encoded[16:20] + "-" + encoded[20:32], nil
}

func (c *Client) DialContext(ctx context.Context) (net.Conn, error) {
	sessionID, err := newSessionID()
	if err != nil {
		return nil, E.Cause(err, "generate session id")
	}
	uploadURL := fmt.Sprintf("https://%s%s/%s", c.uploadHost(), c.path, sessionID)
	downloadURL := fmt.Sprintf("https://%s%s/%s", c.downloadHost(), c.downloadPath, sessionID)

	requestCtx, cancel := context.WithCancel(c.ctx)

	pipeReader, pipeWriter := io.Pipe()
	var uploadWriter io.Writer = pipeWriter
	if c.obfsKey != nil {
		uploadWriter = newObfsWriter(pipeWriter, c.obfsKey)
	}

	uploadDone := make(chan error, 1)
	go func() {
		request, err := http.NewRequestWithContext(requestCtx, http.MethodPost, uploadURL, pipeReader)
		if err != nil {
			uploadDone <- err
			pipeReader.CloseWithError(err)
			return
		}
		request.Header.Set("content-type", "application/grpc")
		request.Header.Set("accept-encoding", "gzip")
		request.Header.Set("referer", c.buildReferer(c.uploadHost(), c.path))
		response, err := c.upload.RoundTrip(request)
		if err != nil {
			uploadDone <- err
			pipeReader.CloseWithError(err)
			return
		}
		io.Copy(io.Discard, response.Body)
		response.Body.Close()
		uploadDone <- nil
	}()

	downloadRequest, err := http.NewRequestWithContext(requestCtx, http.MethodGet, downloadURL, nil)
	if err != nil {
		cancel()
		return nil, err
	}
	downloadRequest.Header.Set("accept-encoding", "gzip")
	downloadRequest.Header.Set("referer", c.buildReferer(c.downloadHost(), c.downloadPath))
	downloadResponse, err := c.download.RoundTrip(downloadRequest)
	if err != nil {
		cancel()
		return nil, E.Cause(err, "open download stream")
	}
	if downloadResponse.StatusCode != http.StatusOK {
		downloadResponse.Body.Close()
		cancel()
		return nil, E.New("unexpected download status: ", downloadResponse.Status)
	}

	var downloadReader io.Reader = downloadResponse.Body
	if c.obfsKey != nil {
		downloadReader = newObfsReader(downloadResponse.Body, c.obfsKey)
	}

	return &clientConn{
		reader:       downloadReader,
		writer:       uploadWriter,
		pipeWriter:   pipeWriter,
		downloadBody: downloadResponse.Body,
		cancel:       cancel,
		local:        M.Socksaddr{},
		remote:       c.serverAddr,
	}, nil
}

func (c *Client) uploadHost() string {
	return c.serverAddr.AddrString()
}

func (c *Client) downloadHost() string {
	return c.downloadAddr.AddrString()
}

func (c *Client) Close() error {
	c.closeOnce.Do(func() {
		if c.upload != nil {
			c.upload.CloseIdleConnections()
		}
		if c.download != nil {
			c.download.CloseIdleConnections()
		}
	})
	return nil
}

var _ net.Conn = (*clientConn)(nil)

type clientConn struct {
	reader       io.Reader
	writer       io.Writer
	pipeWriter   *io.PipeWriter
	downloadBody io.Closer
	cancel       context.CancelFunc
	local        M.Socksaddr
	remote       M.Socksaddr
	closeOnce    sync.Once
}

func (c *clientConn) Read(p []byte) (int, error) {
	return c.reader.Read(p)
}

func (c *clientConn) Write(p []byte) (int, error) {
	return c.writer.Write(p)
}

func (c *clientConn) Close() error {
	c.closeOnce.Do(func() {
		c.cancel()
		c.pipeWriter.Close()
		c.downloadBody.Close()
	})
	return nil
}

func (c *clientConn) LocalAddr() net.Addr  { return c.local }
func (c *clientConn) RemoteAddr() net.Addr { return c.remote }

func (c *clientConn) SetDeadline(t time.Time) error      { return nil }
func (c *clientConn) SetReadDeadline(t time.Time) error  { return nil }
func (c *clientConn) SetWriteDeadline(t time.Time) error { return nil }
