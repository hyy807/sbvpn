package option

import (
	"reflect"
	"strconv"
	"strings"

	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/schema"
	E "github.com/sagernet/sing/common/exceptions"
	"github.com/sagernet/sing/common/json"
	"github.com/sagernet/sing/common/json/badjson"
	"github.com/sagernet/sing/common/json/badoption"
)

type _V2RayTransportOptions struct {
	Type               string                  `json:"type" enum:"http,ws,quic,grpc,httpupgrade"`
	HTTPOptions        V2RayHTTPOptions        `json:"-"`
	WebsocketOptions   V2RayWebsocketOptions   `json:"-"`
	QUICOptions        V2RayQUICOptions        `json:"-"`
	GRPCOptions        V2RayGRPCOptions        `json:"-"`
	HTTPUpgradeOptions V2RayHTTPUpgradeOptions `json:"-"`
	XHTTPOptions       V2RayXHTTPOptions       `json:"-"`
}

type V2RayTransportOptions _V2RayTransportOptions

func (o V2RayTransportOptions) MarshalJSON() ([]byte, error) {
	var v any
	switch o.Type {
	case C.V2RayTransportTypeHTTP:
		v = o.HTTPOptions
	case C.V2RayTransportTypeWebsocket:
		v = o.WebsocketOptions
	case C.V2RayTransportTypeQUIC:
		v = o.QUICOptions
	case C.V2RayTransportTypeGRPC:
		v = o.GRPCOptions
	case C.V2RayTransportTypeHTTPUpgrade:
		v = o.HTTPUpgradeOptions
	case C.V2RayTransportTypeXHTTP, C.V2RayTransportTypeXHTTPCompat, C.V2RayTransportTypeXHTTPCN:
		v = o.XHTTPOptions
	case "":
		return nil, E.New("missing transport type")
	default:
		return nil, E.New("unknown transport type: " + o.Type)
	}
	return badjson.MarshallObjects(_V2RayTransportOptions(o), v)
}

func (o *V2RayTransportOptions) UnmarshalJSON(bytes []byte) error {
	err := json.Unmarshal(bytes, (*_V2RayTransportOptions)(o))
	if err != nil {
		return err
	}
	var v any
	switch o.Type {
	case C.V2RayTransportTypeHTTP:
		v = &o.HTTPOptions
	case C.V2RayTransportTypeWebsocket:
		v = &o.WebsocketOptions
	case C.V2RayTransportTypeQUIC:
		v = &o.QUICOptions
	case C.V2RayTransportTypeGRPC:
		v = &o.GRPCOptions
	case C.V2RayTransportTypeHTTPUpgrade:
		v = &o.HTTPUpgradeOptions
	case C.V2RayTransportTypeXHTTP, C.V2RayTransportTypeXHTTPCompat, C.V2RayTransportTypeXHTTPCN:
		v = &o.XHTTPOptions
	default:
		return E.New("unknown transport type: " + o.Type)
	}
	err = badjson.UnmarshallExcluded(bytes, (*_V2RayTransportOptions)(o), v)
	if err != nil {
		return err
	}
	return nil
}

func (o V2RayTransportOptions) DescribeSchema(builder schema.Builder) (*schema.Node, error) {
	return builder.Define("V2RayTransport", func() (*schema.Node, error) {
		return schema.DiscriminatedUnion(builder, "type", true, []schema.UnionVariant{
			{Value: C.V2RayTransportTypeHTTP, StructType: reflect.TypeFor[V2RayHTTPOptions]()},
			{Value: C.V2RayTransportTypeWebsocket, StructType: reflect.TypeFor[V2RayWebsocketOptions]()},
			{Value: C.V2RayTransportTypeQUIC, StructType: reflect.TypeFor[V2RayQUICOptions]()},
			{Value: C.V2RayTransportTypeGRPC, StructType: reflect.TypeFor[V2RayGRPCOptions]()},
			{Value: C.V2RayTransportTypeHTTPUpgrade, StructType: reflect.TypeFor[V2RayHTTPUpgradeOptions]()},
		}, nil)
	})
}

type V2RayHTTPOptions struct {
	Host        badoption.Listable[string] `json:"host,omitempty"`
	Path        string                     `json:"path,omitempty"`
	Method      string                     `json:"method,omitempty"`
	Headers     badoption.HTTPHeader       `json:"headers,omitempty"`
	IdleTimeout badoption.Duration         `json:"idle_timeout,omitempty"`
	PingTimeout badoption.Duration         `json:"ping_timeout,omitempty"`
}

type V2RayWebsocketOptions struct {
	Path                string               `json:"path,omitempty"`
	Headers             badoption.HTTPHeader `json:"headers,omitempty"`
	MaxEarlyData        uint32               `json:"max_early_data,omitempty"`
	EarlyDataHeaderName string               `json:"early_data_header_name,omitempty"`
}

type V2RayQUICOptions struct{}

type V2RayGRPCOptions struct {
	ServiceName         string             `json:"service_name,omitempty"`
	IdleTimeout         badoption.Duration `json:"idle_timeout,omitempty"`
	PingTimeout         badoption.Duration `json:"ping_timeout,omitempty"`
	PermitWithoutStream bool               `json:"permit_without_stream,omitempty"`
	ForceLite           bool               `json:"-"` // for test
}

type V2RayHTTPUpgradeOptions struct {
	Host    string               `json:"host,omitempty"`
	Path    string               `json:"path,omitempty"`
	Headers badoption.HTTPHeader `json:"headers,omitempty"`
}

// LightXtreme / 闪连 VPN 私有 XHTTP 传输选项。
//
// 语义与 Xray 的 XHTTP stream-up 一致: 上行 POST 流 + 下行 GET(裸 obfs 流)。
type V2RayXHTTPOptions struct {
	Path       string                     `json:"path,omitempty"`
	Mode       string                     `json:"mode,omitempty"`
	ObfsKey    string                     `json:"obfs_key,omitempty"`
	PaddingMin int                        `json:"padding_min,omitempty"`
	PaddingMax int                        `json:"padding_max,omitempty"`
	XMux       *V2RayXHTTPMuxOptions      `json:"xmux,omitempty"`
	Download   *V2RayXHTTPDownloadOptions `json:"download,omitempty"`
}

type V2RayXHTTPMuxOptions struct {
	MaxConcurrency XMuxConcurrency `json:"max_concurrency,omitempty"`
}

type V2RayXHTTPDownloadOptions struct {
	ServerOptions
	Path string                `json:"path,omitempty"`
	TLS  *OutboundTLSOptions   `json:"tls,omitempty"`
	XMux *V2RayXHTTPMuxOptions `json:"xmux,omitempty"`
}

// XMuxConcurrency 同时接受 JSON 数字与字符串 (原版配置里是字符串 "8")。
type XMuxConcurrency int

func (c *XMuxConcurrency) UnmarshalJSON(data []byte) error {
	value := strings.Trim(string(data), `"`)
	if value == "" || value == "null" {
		return nil
	}
	n, err := strconv.Atoi(value)
	if err != nil {
		return E.Cause(err, "invalid max_concurrency")
	}
	*c = XMuxConcurrency(n)
	return nil
}

func (c XMuxConcurrency) MarshalJSON() ([]byte, error) {
	return json.Marshal(strconv.Itoa(int(c)))
}
