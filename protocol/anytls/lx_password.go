package anytls

// LightXtreme / 闪连VPN 私有 anytls 口令变换 —— 逆向自 lightningx 内核的
// protocol/anytls.applyAnyTLSHexPassword (该函数名在私有内核里被混淆)。
//
//	raw = hex_decode(password)          // 配置中 32 字符 hex -> 16 字节
//	n   = 当前 unix 毫秒
//	K   = u64be(n*10 + 3) || u64be(n)   // 两档时间戳
//	passwordSha256 = raw || (K ^ raw)   // 32 字节
//
// 上游 sing-box 发送的是 sha256(password_string)，服务端会 0.1s 内关闭连接；
// 私有内核发送上面这个时间掩码后的 32 字节，服务端才放行。
//
// sing-anytls 的 Client.passwordSha256 是未导出字段，这里用 reflect+unsafe
// 直接改写（与原版 fork 的做法一致）。

import (
	"encoding/binary"
	"encoding/hex"
	"reflect"
	"time"
	"unsafe"

	anytls "github.com/sagernet/sing-anytls"
)

func lxPasswordSHA256(password string) ([]byte, bool) {
	if len(password) != 32 {
		return nil, false
	}
	raw, err := hex.DecodeString(password)
	if err != nil {
		return nil, false
	}
	n := uint64(time.Now().UnixMilli())
	k := make([]byte, 16)
	binary.BigEndian.PutUint64(k[0:8], n*10+3)
	binary.BigEndian.PutUint64(k[8:16], n)
	out := make([]byte, 32)
	copy(out, raw)
	for i := 0; i < 16; i++ {
		out[16+i] = k[i] ^ raw[i]
	}
	return out, true
}

func applyLXPassword(client *anytls.Client, password string) {
	blob, ok := lxPasswordSHA256(password)
	if !ok {
		return
	}
	elem := reflect.ValueOf(client).Elem()
	for _, name := range []string{"password", "passwordSha256"} {
		field := elem.FieldByName(name)
		if !field.IsValid() {
			continue
		}
		target := reflect.NewAt(field.Type(), unsafe.Pointer(field.UnsafeAddr())).Elem()
		switch field.Kind() {
		case reflect.Array:
			if field.Len() != len(blob) {
				continue
			}
			reflect.Copy(target.Slice(0, len(blob)), reflect.ValueOf(blob))
			return
		case reflect.Slice:
			target.SetBytes(blob)
			return
		}
	}
}
