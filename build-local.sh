#!/usr/bin/env bash
# 本地交叉编译，用于日常改动验证（CI 已改为只在手动触发时构建）。
#
# 用法：
#   ./build-local.sh                              # 默认 linux/amd64
#   ./build-local.sh linux/amd64 linux/arm64      # 指定多个目标
#   ./build-local.sh windows/amd64 darwin/arm64
#   VERSION=1.5.11-custom.9 ./build-local.sh      # 指定内嵌版本号
#   OUT=/tmp/out ./build-local.sh                 # 指定输出目录
#
# 产物在 ./build/（已 gitignore），每个二进制附带同名 .sha256。
set -euo pipefail
cd "$(dirname "$0")"

GO_BIN="${GO_BIN:-/home/dyx/toolchains/go1.25.11/bin/go}"
if [ ! -x "$GO_BIN" ]; then
  GO_BIN="$(command -v go || true)"
fi
[ -n "$GO_BIN" ] || { echo "找不到 go，可用 GO_BIN=/path/to/go 指定" >&2; exit 1; }

# 基础版本取最近的正式 tag（与 CI 一致），未发布版本用 -local.<sha> 后缀。
BASE="$(git tag --merged HEAD --sort=-v:refname | grep -Ex '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"
BASE="${BASE:-0.0.0}"
VERSION="${VERSION:-${BASE}-local.$(git rev-parse --short HEAD)}"
OUT="${OUT:-build}"

TARGETS=("$@")
[ "${#TARGETS[@]}" -gt 0 ] || TARGETS=("linux/amd64")

mkdir -p "$OUT"
for t in "${TARGETS[@]}"; do
  os="${t%%/*}"
  arch="${t##*/}"
  [ "$os" != "$t" ] || { echo "目标需写成 GOOS/GOARCH，例如 linux/amd64" >&2; exit 2; }

  name="komari-agent-${os}-${arch}"
  [ "$os" = "windows" ] && name="${name}.exe"

  echo "==> ${os}/${arch}"
  CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" "$GO_BIN" build -trimpath \
    -ldflags="-s -w -X github.com/komari-monitor/komari-agent/update.CurrentVersion=${VERSION}" \
    -o "${OUT}/${name}" .
  sha256sum "${OUT}/${name}" > "${OUT}/${name}.sha256"
done

echo "完成：${#TARGETS[@]} 个目标，版本 ${VERSION}，输出目录 ${OUT}/"
