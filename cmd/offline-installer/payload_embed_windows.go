//go:build offline_payload && windows

package main

import "embed"

//go:embed payload/agent payload/install.ps1 payload/version.txt payload/sm.exe
var payloadFS embed.FS

func payloadAvailable() bool { return true }
