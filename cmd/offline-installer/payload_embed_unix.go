//go:build offline_payload && !windows

package main

import "embed"

//go:embed payload/agent payload/install.sh payload/version.txt
var payloadFS embed.FS

func payloadAvailable() bool { return true }
