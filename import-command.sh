#!/usr/bin/env bash
# 从官方安装命令中提取参数，然后用本仓库的 install.sh 安装。
#
# 用法：
#   sudo bash import-command.sh                     # 交互粘贴官方命令
#   sudo bash import-command.sh '<官方命令>'         # 直接传入
#   cat cmd.txt | sudo bash import-command.sh       # 从管道读取
#
# 选项：
#   --dry-run            只打印解析结果，不安装
#   --yes, -y            跳过确认
#   --install-url <url>  指定 install.sh 地址（默认本仓库 main 分支）
#
# 安全说明：只提取白名单内的 agent/安装参数，忽略脚本 URL、sudo、管道等噪声。
# 身份（token / 自动发现 key）在输出中会打码。
set -euo pipefail

REPO_OWNER="${KOMARI_REPO_OWNER:-LHDyx}"
REPO_NAME="${KOMARI_REPO_NAME:-komari-agent}"
INSTALL_URL="${KOMARI_INSTALL_URL:-https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/refs/heads/main/install.sh}"

DRY_RUN=0
ASSUME_YES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        --install-url) INSTALL_URL="$2"; shift 2 ;;
        --) shift; break ;;
        *) break ;;
    esac
done

CMD="$*"
if [ -z "$CMD" ]; then
    if [ ! -t 0 ]; then
        CMD="$(cat)"
    else
        printf '请粘贴官方安装命令，回车结束：\n> ' >&2
        IFS= read -r CMD
    fi
fi

CMD="$(printf '%s' "$CMD" | tr '\n' ' ')"

# PowerShell 风格：powershell ... -Command "iwr ...; & '.\install.ps1' '-e' ..."
# 外层双引号会把整段包成一个 token，这里先剥掉 -Command 的包裹。
if [[ "$CMD" =~ -Command[[:space:]]+\"(.*)\"[[:space:]]*$ ]]; then
    CMD="${BASH_REMATCH[1]}"
elif [[ "$CMD" =~ -Command[[:space:]]+\'(.*)\'[[:space:]]*$ ]]; then
    CMD="${BASH_REMATCH[1]}"
fi

if [ -z "$(printf '%s' "$CMD" | tr -d '[:space:]')" ]; then
    echo "没有收到命令。" >&2
    exit 2
fi

# 安全的 shell 风格分词：处理单/双引号和反斜杠，不执行任何内容
TOK_FILE="$(mktemp)"
trap 'rm -f "$TOK_FILE"' EXIT
printf '%s' "$CMD" | awk '
{
    n = length($0); i = 1; tok = ""; inq = ""
    while (i <= n) {
        c = substr($0, i, 1)
        if (inq == "") {
            if (c == " " || c == "\t") { if (tok != "") { print tok; tok = "" }; i++; continue }
            if (c == "\047" || c == "\"") { inq = c; i++; continue }
            if (c == "\\") { i++; tok = tok substr($0, i, 1); i++; continue }
            tok = tok c; i++
        } else {
            if (c == inq) { inq = ""; i++; continue }
            if (inq == "\"" && c == "\\") { i++; tok = tok substr($0, i, 1); i++; continue }
            tok = tok c; i++
        }
    }
    if (tok != "") print tok
}' > "$TOK_FILE"

mapfile -t TOKENS < "$TOK_FILE"

is_value_flag() {
    case "$1" in
        -e|--endpoint|-t|--token|-i|--interval|-r|--max-retries|-c|--reconnect-interval) return 0 ;;
        --auto-discovery|--info-report-interval|--include-nics|--exclude-nics) return 0 ;;
        --include-mountpoint|--month-rotate|--custom-dns|--custom-ipv4|--custom-ipv6) return 0 ;;
        --prefer-ip-version|--config|--update-repo|--install-dir|--install-service-name) return 0 ;;
        --install-ghproxy|--install-version|--install-repo) return 0 ;;
    esac
    return 1
}

is_bool_flag() {
    case "$1" in
        --disable-auto-update|--disable-web-ssh|--ignore-unsafe-cert|-u|--gpu) return 0 ;;
        --memory-include-cache|--memory-exclude-bcf|--get-ip-addr-from-nic) return 0 ;;
        --disable-compression|--enable-security-warning) return 0 ;;
        --install-no-mirror|--install-no-verify|--install-keep-legacy|--install-no-hide|--install-no-sc-fallback|--install-allow-sc-fallback) return 0 ;;
    esac
    return 1
}

ARGS=()
i=0
while [ "$i" -lt "${#TOKENS[@]}" ]; do
    t="${TOKENS[$i]}"
    if is_value_flag "$t"; then
        if [ $((i + 1)) -ge "${#TOKENS[@]}" ]; then
            echo "参数 $t 缺少取值。" >&2
            exit 2
        fi
        ARGS+=("$t" "${TOKENS[$((i + 1))]}")
        i=$((i + 2))
        continue
    fi
    case "$t" in
        --*=*)
            flag="${t%%=*}"
            if is_value_flag "$flag"; then
                ARGS+=("$t")
            fi
            ;;
        *)
            if is_bool_flag "$t"; then
                ARGS+=("$t")
            fi
            ;;
    esac
    i=$((i + 1))
done

# 提取并校验关键参数
ENDPOINT=""
IDENTITY_KIND=""
IDENTITY_VALUE=""
last_flag=""
for ((j = 0; j < ${#ARGS[@]}; j++)); do
    a="${ARGS[$j]}"
    case "$a" in
        -e|--endpoint)
            ENDPOINT="${ARGS[$((j + 1))]:-}"
            ;;
        --endpoint=*)
            ENDPOINT="${a#*=}"
            ;;
        -t|--token)
            IDENTITY_KIND="token"
            IDENTITY_VALUE="${ARGS[$((j + 1))]:-}"
            ;;
        --token=*)
            IDENTITY_KIND="token"
            IDENTITY_VALUE="${a#*=}"
            ;;
        --auto-discovery)
            IDENTITY_KIND="auto-discovery"
            IDENTITY_VALUE="${ARGS[$((j + 1))]:-}"
            ;;
        --auto-discovery=*)
            IDENTITY_KIND="auto-discovery"
            IDENTITY_VALUE="${a#*=}"
            ;;
    esac
done

if [ -z "$ENDPOINT" ]; then
    echo "未能从命令中解析出端点（-e/--endpoint）。" >&2
    echo "解析到的参数：${ARGS[*]:-（空）}" >&2
    exit 2
fi
if [ -z "$IDENTITY_VALUE" ]; then
    echo "未能从命令中解析出 token（-t/--token）或自动发现 key。" >&2
    echo "解析到的参数：${ARGS[*]:-（空）}" >&2
    exit 2
fi

mask() {
    local v="$1"
    local n=${#v}
    if [ "$n" -le 8 ]; then
        printf '%s****' "${v:0:2}"
    else
        printf '%s****%s' "${v:0:4}" "${v: -2}"
    fi
}

echo "解析结果："
echo "  端点：${ENDPOINT}"
echo "  身份：${IDENTITY_KIND} $(mask "$IDENTITY_VALUE")"
echo "  参数：${ARGS[*]}"
echo "  安装脚本：${INSTALL_URL}"

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""
    echo "（dry-run，未执行安装）"
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "" >&2
    echo "需要 root 权限才能安装服务，请用 sudo 运行本脚本。" >&2
    exit 1
fi

if [ "$ASSUME_YES" -ne 1 ]; then
    if [ -r /dev/tty ]; then
        printf '继续安装？[y/N] ' > /dev/tty
        read -r answer < /dev/tty
        case "$answer" in
            y|Y|yes|YES) ;;
            *) echo "已取消。"; exit 1 ;;
        esac
    else
        echo "没有可用的交互终端，请加 --yes 确认。" >&2
        exit 1
    fi
fi

TMP_INSTALL="$(mktemp)"
trap 'rm -f "$TOK_FILE" "$TMP_INSTALL"' EXIT
echo "获取安装脚本 ..."
curl -fsSL --connect-timeout 20 -o "$TMP_INSTALL" "$INSTALL_URL"
sh "$TMP_INSTALL" "${ARGS[@]}"
