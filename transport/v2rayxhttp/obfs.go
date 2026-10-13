package v2rayxhttp

// 闪连 / LightXtreme 私有 XHTTP 传输的 obfs 层 —— 逆向结果复刻。
//
//	key = sha256(obfs_key)[:16]        // AES-128
//	线上格式 = [16B IV][4B 同步标记密文][密文...]
//	明文前 4 字节固定为 0；标记密文 = keystream[0:4]；真正载荷从第 20 字节开始
//	（对应 CTR keystream 偏移 4）
//
// 对应私有内核里的 v2rayxhttp.obfsStream / (*obfsWriter).Write / (*obfsReader).Read。

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"io"
	"sync"

	E "github.com/sagernet/sing/common/exceptions"
)

const (
	obfsIVSize     = 16
	obfsMarkerSize = 4
	obfsHeaderSize = obfsIVSize + obfsMarkerSize
)

func obfsDeriveKey(obfsKey string) []byte {
	digest := sha256.Sum256([]byte(obfsKey))
	return digest[:16]
}

func obfsNewStream(key []byte, iv []byte) (cipher.Stream, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewCTR(block, iv), nil
}

type obfsWriter struct {
	writer io.Writer
	key    []byte
	stream cipher.Stream
	access sync.Mutex
}

func newObfsWriter(writer io.Writer, key []byte) *obfsWriter {
	return &obfsWriter{writer: writer, key: key}
}

func (w *obfsWriter) Write(p []byte) (int, error) {
	w.access.Lock()
	defer w.access.Unlock()
	if w.stream == nil {
		// 首包: 随机 IV + 4 字节零同步标记 + 加密载荷
		buffer := make([]byte, obfsHeaderSize+len(p))
		_, err := rand.Read(buffer[:obfsIVSize])
		if err != nil {
			return 0, E.Cause(err, "generate obfs iv")
		}
		stream, err := obfsNewStream(w.key, buffer[:obfsIVSize])
		if err != nil {
			return 0, E.Cause(err, "create obfs stream")
		}
		w.stream = stream
		// buffer[16:20] 全零 -> 异或后即为 keystream[0:4]，接收端解密回零
		stream.XORKeyStream(buffer[obfsIVSize:obfsHeaderSize], buffer[obfsIVSize:obfsHeaderSize])
		stream.XORKeyStream(buffer[obfsHeaderSize:], p)
		_, err = w.writer.Write(buffer)
		if err != nil {
			return 0, err
		}
		return len(p), nil
	}
	buffer := make([]byte, len(p))
	w.stream.XORKeyStream(buffer, p)
	_, err := w.writer.Write(buffer)
	if err != nil {
		return 0, err
	}
	return len(p), nil
}

type obfsReader struct {
	reader io.Reader
	key    []byte
	stream cipher.Stream
	access sync.Mutex
}

func newObfsReader(reader io.Reader, key []byte) *obfsReader {
	return &obfsReader{reader: reader, key: key}
}

func (r *obfsReader) Read(p []byte) (int, error) {
	r.access.Lock()
	defer r.access.Unlock()
	if r.stream == nil {
		header := make([]byte, obfsHeaderSize)
		_, err := io.ReadFull(r.reader, header)
		if err != nil {
			return 0, err
		}
		stream, err := obfsNewStream(r.key, header[:obfsIVSize])
		if err != nil {
			return 0, E.Cause(err, "create obfs stream")
		}
		r.stream = stream
		var marker [obfsMarkerSize]byte
		stream.XORKeyStream(marker[:], header[obfsIVSize:obfsHeaderSize])
		if marker != [obfsMarkerSize]byte{} {
			return 0, E.New("invalid obfs sync marker")
		}
	}
	n, err := r.reader.Read(p)
	if n > 0 {
		r.stream.XORKeyStream(p[:n], p[:n])
	}
	return n, err
}
