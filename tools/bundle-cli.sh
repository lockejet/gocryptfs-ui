#!/bin/sh
# bundle-cli.sh — 把 gocryptfs-cli 及 shell 库打包成单文件自包含脚本
#
# 背景：gocryptfs-cli 原本是「主脚本 + lib/gocryptfs-lib.sh + lib/i18n.sh」多文件，
# 安装到 <prefix>/lib/ 后必须靠 <prefix>/bin 里的符号链接才能调用。打包成单文件后：
#   * <prefix>/bin/gocryptfs-cli 是真正的可执行文件（不再是链接）；
#   * 内嵌进 TUI/Web 二进制时只需释放一个文件（<data_dir>/backend/gocryptfs-cli）；
#   * 与版本绑定，避免"脚本 + 库"版本错配。
#
# 生成物：shell/gocryptfs-cli.bundle（提交仓库；CI 用 --check 校验是否最新）。
# 版本：默认写入占位符 @"VERSION"@，安装器/内嵌释放时替换为字面版本；
#       本地调试也可用 --version X 直接烘焙。
#
# 用法：
#   sh tools/bundle-cli.sh                                  # 生成（占位版本）
#   sh tools/bundle-cli.sh --version 0.9.0 -o /tmp/cli     # 烘焙版本到指定文件
#   sh tools/bundle-cli.sh --check                          # 校验仓库产物是否最新
set -eu

ROOT=$(cd -P "$(dirname "$0")/.." && pwd)
MAIN="$ROOT/shell/gocryptfs-cli"
LIB="$ROOT/shell/lib/gocryptfs-lib.sh"
I18N="$ROOT/shell/lib/i18n.sh"
OUT="$ROOT/shell/gocryptfs-cli.bundle"
VERSION='@VERSION@'
CHECK=0

usage() {
    cat <<'EOF'
bundle-cli.sh — bundle gocryptfs-cli + shell libs into one self-contained script

Usage:
  sh tools/bundle-cli.sh [--version V] [-o FILE] [--check]

  --version V   bake version V (default: @VERSION@ placeholder)
  -o, --output  output file (default: shell/gocryptfs-cli.bundle)
  --check       verify the committed bundle is up to date (exit 1 if not)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            [ $# -ge 2 ] || { echo "[!] --version needs a value" >&2; exit 2; }
            VERSION="$2"; shift ;;
        --version=*) VERSION="${1#--version=}" ;;
        -o|--output)
            [ $# -ge 2 ] || { echo "[!] $1 needs a value" >&2; exit 2; }
            OUT="$2"; shift ;;
        --output=*) OUT="${1#--output=}" ;;
        --check) CHECK=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[!] unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

for f in "$MAIN" "$LIB" "$I18N"; do
    [ -f "$f" ] || { echo "[!] missing source file: $f" >&2; exit 1; }
done

# 输出去掉 shebang 的库文件内容（库不重复写 shebang）
strip_shebang() {
    awk 'NR == 1 && /^#!/ { next } { print }' "$1"
}

# 主脚本：去掉 shebang / set -euo pipefail，删除源码模式的 loader 段，
# 版本段替换为字面版本，其余原样保留。
main_body() {
    awk -v ver="$VERSION" '
        NR == 1 && /^#!/ { next }
        NR == 2 && /^set -euo pipefail$/ { next }
        /^# >>> BUNDLE:LOADER >>>$/    { in_loader = 1; next }
        /^# <<< BUNDLE:LOADER <<<$/    { in_loader = 0; next }
        /^# >>> BUNDLE:VERSION >>>$/   {
            print "# 版本：单文件包，打包时已写入字面版本（不依赖同目录 VERSION）"
            printf "CLI_VERSION=\"%s\"\n", ver
            print "VERSION_FILE=\"\""
            in_version = 1
            next
        }
        /^# <<< BUNDLE:VERSION <<<$/   { in_version = 0; next }
        in_loader { next }
        in_version { next }
        { print }
    ' "$MAIN"
}

generate() {
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' '# 单文件自包含 gocryptfs-cli —— 由 tools/bundle-cli.sh 生成，请勿手工编辑。'
    printf '%s\n' '# 源码：shell/gocryptfs-cli（主程序）+ shell/lib/gocryptfs-lib.sh + shell/lib/i18n.sh'
    printf '%s\n' '# 已内联，无需 lib/ 目录，也不依赖同目录 VERSION 文件。'
    printf '%s\n' 'set -euo pipefail'
    printf '%s\n\n' 'GFS_BUNDLED=1'
    strip_shebang "$I18N"
    printf '\n'
    strip_shebang "$LIB"
    printf '\n'
    main_body
}

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
generate > "$TMP"

if [ "$CHECK" -eq 1 ]; then
    if [ ! -f "$OUT" ]; then
        echo "[!] $OUT is missing; run: make cli-bundle" >&2
        exit 1
    fi
    if ! cmp -s "$TMP" "$OUT"; then
        echo "[!] $OUT is out of date; run: make cli-bundle" >&2
        exit 1
    fi
    echo "[OK] $OUT is up to date"
    exit 0
fi

cat "$TMP" > "$OUT"
chmod 0755 "$OUT"
echo ">>> wrote $OUT (version: $VERSION)"
