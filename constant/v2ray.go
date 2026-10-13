package constant

const (
	V2RayTransportTypeHTTP        = "http"
	V2RayTransportTypeWebsocket   = "ws"
	V2RayTransportTypeQUIC        = "quic"
	V2RayTransportTypeGRPC        = "grpc"
	V2RayTransportTypeHTTPUpgrade = "httpupgrade"

	// LightXtreme / 闪连 私有 XHTTP 传输。
	// 类型名刻意与上游 / Xray 的 "xhttp" 区分开，避免将来上游实现 xhttp 时冲突；
	// V2RayTransportTypeXHTTPCompat / V2RayTransportTypeXHTTPCN 作为兼容别名一并接受。
	V2RayTransportTypeXHTTP       = "lx-xhttp"
	V2RayTransportTypeXHTTPCompat = "xhttp"
	V2RayTransportTypeXHTTPCN     = "闪电旋风劈"
)
