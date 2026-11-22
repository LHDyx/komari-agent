//go:build !offline_payload

package main

import "embed"

// 普通构建（不嵌入 payload）时使用；离线安装器必须带 -tags offline_payload。
var payloadFS embed.FS

func payloadAvailable() bool { return false }
