#!/bin/sh
# install.sh — 安装 / 卸载 gocryptfs-ui（TUI + Web 二进制 + 单文件自包含 CLI）
#
# 两种来源：
#   * 本地源码：在仓库里执行 ./install.sh（需要 cargo）
#   * 官方 Release：./install.sh --from-release（不需要源码/工具链），
#     也可直接 `curl -LsSf <release>/gocryptfs-ui-install.sh | sh -s -- ...`
#
# 模式默认自动判断：curl|sh（无源码树）→ Release；仓库内执行 → 本地源码。
# 完整用法见 `./install.sh --help`（仅此一处，避免文档与实现漂移）。
set -eu

# 仓库 slug（改名后兼容旧环境变量名）
REPO="${GOCRYPTFS_UI_REPO:-${GOCRYPTFS_TUI_REPO:-${GOCRYPTFS_REPO:-lockejet/gocryptfs-ui}}}"
PREFIX="${PREFIX:-$HOME/.local}"
DO_BUILD=1
UNINSTALL=0
FROM_RELEASE=0
MODE=""          # 空 = 自动；local / release
INSTALL_WEB=1    # 是否一并安装 gocryptfs-web（--no-web 关闭）
RELEASE_BASE=""  # 覆盖 Release 下载根（镜像/离线测试）
RELEASE_VER=""
DEPS_CHECK=1

usage() {
    cat <<'USAGE_EOF'
install.sh — install / uninstall gocryptfs-ui (TUI + Web + standalone CLI)

Usage (one script, three modes):
  lazy    curl -LsSf <release>/gocryptfs-ui-install.sh | sh -s -- [--user|--system]
  clone   git clone … && ./install.sh --from-release [--user|--system]
  source  git clone … && make build && ./install.sh --local [--user|--system]

Prefix (default: --user):
  --user              install to ~/.local (default; no sudo)
  --system            install to /usr/local (sudo as needed)
  --prefix DIR        custom prefix

Mode and uninstall:
  ./install.sh --local                 force local-source mode (needs cargo)
  ./install.sh --from-release          no build: fetch the platform binary from GitHub Releases
  ./install.sh --from-release v0.4.2   pin a version (same as --version v0.4.2)
  ./install.sh --uninstall             uninstall using the install manifest
  ./install.sh --no-build              skip compilation, use existing artifacts
  ./install.sh --no-deps-check         skip the post-install dependency check
  ./install.sh --no-web                install only the TUI (skip gocryptfs-web)
  ./install.sh --release-base PATH     use a local directory or https mirror for Release assets

  # gocryptfs-cli is installed as one self-contained file in <prefix>/bin
  # (no symlink, no lib/ directory). --link-cli / --no-link-cli are accepted
  # for backwards compatibility but are now no-ops.

  # no source/toolchain needed (GitHub Release asset):
  curl -LsSf https://github.com/lockejet/gocryptfs-ui/releases/latest/download/gocryptfs-ui-install.sh \
    | sh -s -- --system

The mode is auto-detected: `curl … | sh` (no source tree) installs from the Release;
running `./install.sh` inside a checkout builds locally. Force with --local / --from-release.
POSIX sh (dash) compatible, so `curl ... | sh` works as-is.
USAGE_EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --uninstall|-u)  UNINSTALL=1 ;;
        --prefix)        PREFIX="${2:?--prefix needs a directory}"; shift ;;
        --prefix=*)      PREFIX="${1#--prefix=}" ;;
        --user)          PREFIX="$HOME/.local" ;;
        --system)        PREFIX="/usr/local" ;;
        --from-release)  FROM_RELEASE=1; MODE="release"
                         case "${2:-}" in v[0-9]*) RELEASE_VER="$2"; shift ;; esac ;;
        --from-release=*) FROM_RELEASE=1; MODE="release"; RELEASE_VER="${1#--from-release=}" ;;
        --version|-V)    RELEASE_VER="${2:?--version needs a version, e.g. v0.4.2}"; FROM_RELEASE=1; MODE="release"; shift ;;
        --release-version) RELEASE_VER="${2:?--release-version needs a version}"; MODE="release"; shift ;;
        --local)         MODE="local" ;;
        --no-build)      DO_BUILD=0
                         if [ -z "$MODE" ]; then MODE="local"; fi ;;
        --link-cli|--no-link-cli) : ;;   # 兼容旧参数：单文件 CLI 现在总是装为普通文件
        --no-deps-check) DEPS_CHECK=0 ;;
        --no-web)        INSTALL_WEB=0 ;;
        --release-base)  RELEASE_BASE="${2:?--release-base needs a URL}"; shift ;;
        --release-base=*) RELEASE_BASE="${1#--release-base=}" ;;
        -h|--help)       usage; exit 0 ;;
        *) echo "[!] unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

case "$PREFIX" in
    ""|"/") echo "[!] invalid PREFIX: '${PREFIX}'" >&2; exit 1 ;;
esac
PREFIX="${PREFIX%/}"

BINDIR="$PREFIX/bin"
SHAREDIR="$PREFIX/share/gocryptfs-ui"
INSTALL_META="$SHAREDIR/install"
LIBDIR="$PREFIX/lib/gocryptfs-ui"          # ≤0.8 的后端/元数据位置（仅用于清理）
LEGACY_LIBDIR="$PREFIX/lib/gocryptfs-tui"  # ≤0.6
LEGACY_SHAREDIR="$PREFIX/share/gocryptfs-tui"
MANIFEST="$INSTALL_META/INSTALLED.json"
MANIFEST_FILES="$INSTALL_META/INSTALLED.files"
VERSION_FILE="$INSTALL_META/VERSION"

# 只操作已知的库/元数据目录，避免误删
case "$LIBDIR" in
    */lib/gocryptfs-ui|*/lib/gocryptfs-tui) ;;
    *) echo "[!] refusing to operate on unexpected path: $LIBDIR" >&2; exit 1 ;;
esac
case "$INSTALL_META" in
    */share/gocryptfs-ui/install|*/share/gocryptfs-tui/install) ;;
    *) echo "[!] refusing to operate on unexpected path: $INSTALL_META" >&2; exit 1 ;;
esac

# ---- 仅在目标不可写时提权 ----
probe="$PREFIX"
while [ ! -e "$probe" ] && [ "$probe" != "/" ]; do
    probe="$(dirname "$probe")"
done
SUDO=""
if [ ! -w "$probe" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        echo "[!] running as root; this script must run as a normal user." >&2
        echo "    correct usage: ./install.sh (it uses sudo internally when needed)" >&2
        exit 1
    fi
    command -v sudo >/dev/null 2>&1 || {
        echo "[!] $PREFIX is not writable and sudo is not installed" >&2
        exit 1
    }
    SUDO="sudo"
fi

priv() { if [ -n "$SUDO" ]; then sudo "$@"; else "$@"; fi; }

STAGE="$(mktemp -d)"
DL=""
cleanup() { rm -rf "$STAGE"; if [ -n "$DL" ]; then rm -rf "$DL"; fi; }
trap cleanup EXIT

# ------------------------------------------------------------
# 工具函数
# ------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

download() { # download <url-or-path> <dest>
    case "$1" in
        https://*)
            if have curl; then
                curl -fsSL --proto '=https' --tlsv1.2 -o "$2" "$1"
            elif have wget; then
                wget -qO "$2" "$1"
            else
                echo "[!] --from-release requires curl or wget" >&2
                return 1
            fi ;;
        http://*)
            echo "[!] plain http is not allowed; use https:// or a local directory" >&2
            return 1 ;;
        *)
            # 本地目录镜像（离线/内网/测试）：--release-base /path/to/assets
            cp -f "$1" "$2" 2>/dev/null ;;
    esac
}

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# ------------------------------------------------------------
# 卸载：优先按安装清单精确删除
# ------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
    echo "==> uninstalling (PREFIX=$PREFIX)"
    removed=0
    # 新版清单在 share/<app>/install；≤0.8 的旧清单在 lib/gocryptfs-ui
    manifest_files=""
    for cand in "$MANIFEST_FILES" "$LIBDIR/INSTALLED.files"; do
        if [ -f "$cand" ]; then
            manifest_files="$cand"
            break
        fi
    done
    if [ -n "$manifest_files" ]; then
        echo "    using manifest: $manifest_files"
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            case "$f" in
                "$PREFIX"/*) ;;   # 只允许删除前缀内的路径
                *) echo "[!] skipping path outside prefix: $f" >&2; continue ;;
            esac
            if [ -e "$f" ] || [ -L "$f" ]; then
                priv rm -f "$f"
                echo "  removed $f"
                removed=1
            fi
        done < "$manifest_files"
        [ -f "$MANIFEST" ] && priv rm -f "$MANIFEST"
        if [ "$manifest_files" = "$MANIFEST_FILES" ]; then
            priv rm -f "$MANIFEST_FILES"
        else
            priv rm -f "$manifest_files" "$LIBDIR/INSTALLED.json"
        fi
    else
        echo "    (no install manifest found; using default paths)"
    fi
    # 无论有无清单都清理已知路径。
    # 注意：share/gocryptfs-ui 里还有运行期数据（backend/、state.json），
    # 所以只删安装元数据目录 install/，不删整个 share 目录。
    priv rm -f "$BINDIR/gocryptfs-cli" "$BINDIR/gocryptfs-tui" "$BINDIR/gocryptfs-web"
    priv rm -rf "$INSTALL_META"
    priv rm -rf "$LIBDIR" "$LEGACY_LIBDIR" "$LEGACY_SHAREDIR"
    # 只在确认为空时才删父目录（非空会失败，不影响其它文件）
    priv rmdir "$PREFIX/share" >/dev/null 2>&1 || true
    priv rmdir "$PREFIX/lib" >/dev/null 2>&1 || true
    priv rmdir "$BINDIR" >/dev/null 2>&1 || true
    echo "[OK] uninstalled:"
    echo "  $BINDIR/gocryptfs-tui"
    echo "  $BINDIR/gocryptfs-cli"
    echo "  $INSTALL_META"
    echo ""
    echo "[i] config/data/state directories were kept (remove them manually if needed):"
    echo "  ${XDG_CONFIG_HOME:-$HOME/.config}/gocryptfs-ui/"
    echo "  ${XDG_DATA_HOME:-$HOME/.local/share}/gocryptfs-ui/"
    echo "  ${XDG_STATE_HOME:-$HOME/.local/state}/gocryptfs-ui/"
    remaining="$(command -v gocryptfs-cli 2>/dev/null || true)"
    if [ -n "$remaining" ]; then
        echo ""
        echo "[!] PATH still resolves to: $remaining"
        echo "    if that is another/older install, uninstall it too to avoid a stale backend."
    fi
    exit 0
fi

# ------------------------------------------------------------
# 安装
# ------------------------------------------------------------
# ---- 运行时依赖（仅警告；真正的判定交给 TUI 的 --check-deps）----
echo "==> checking dependencies"
missing_deps=""
for cmd in gocryptfs fusermount rsync yq jq mountpoint; do
    have "$cmd" || missing_deps="$missing_deps $cmd"
done
if [ -n "$missing_deps" ]; then
    echo "[!] missing runtime dependencies:${missing_deps}"
    echo "    continuing; install the missing ones as suggested by 'gocryptfs-tui --check-deps'."
else
    echo "[OK] dependencies present"
fi

# ---- 模式自动判断 ----
# curl|sh 时没有源码树（$0 也不是可读文件），必须走 Release；否则在源码目录里就本地编译。
IN_REPO=0
# 源码树判定：workspace 根 Cargo.toml + shell 后端（对目录布局变化免疫：
# src/main.rs、crates/tui/src/main.rs 都能识别）
if [ -f Cargo.toml ] && [ -f shell/gocryptfs-cli ] && [ -f "$0" ] && [ -r "$0" ]; then
    IN_REPO=1
fi
if [ -z "$MODE" ]; then
    if [ "$IN_REPO" -eq 1 ] && { [ -f target/release/gocryptfs-tui ] || have cargo; }; then
        MODE="local"
    else
        MODE="release"
        if [ "$IN_REPO" -eq 1 ]; then
            echo "[i] no cargo and no target/release found; using the Release binary (use --local to force a local build)"
        fi
    fi
fi
if [ "$MODE" = "release" ]; then FROM_RELEASE=1; fi

# ---- 取二进制与单文件 CLI：本地构建 或 官方 Release ----
BIN_SRC=""
SHELL_DIR=""
SOURCE_DESC=""
BIN_VERSION=""
CLI_BUNDLE=""

if [ "$FROM_RELEASE" -eq 1 ]; then
    DL="$(mktemp -d)"

    # 目标三元组
    case "$(uname -m)" in
        x86_64|amd64)   arch="x86_64" ;;
        aarch64|arm64)  arch="aarch64" ;;
        *) echo "[!] unsupported architecture: $(uname -m)" >&2; exit 1 ;;
    esac
    if have ldd && ldd --version 2>&1 | grep -qi musl; then libc="musl"; else libc="gnu"; fi
    target="${arch}-unknown-linux-${libc}"
    # 0.7.0 起资产前缀是 gocryptfs-ui-*；旧版本（≤0.6.x）仍是 gocryptfs-tui-*
    asset_new="gocryptfs-ui-${target}.tar.xz"
    asset_old="gocryptfs-tui-${target}.tar.xz"
    asset=""

    # 未指定版本：在 git checkout 里优先用当前 tag（保证与该份源码对应），否则用 latest
    if [ -z "$RELEASE_VER" ] && have git && git rev-parse --git-dir >/dev/null 2>&1; then
        RELEASE_VER="$(git describe --tags --abbrev=0 2>/dev/null || true)"
    fi
    if [ -n "$RELEASE_BASE" ]; then
        base="$RELEASE_BASE"
        ver_label="${RELEASE_VER:-mirror}"
    elif [ -n "$RELEASE_VER" ]; then
        base="https://github.com/$REPO/releases/download/$RELEASE_VER"
        ver_label="$RELEASE_VER"
    else
        base="https://github.com/$REPO/releases/latest/download"
        ver_label="latest"
    fi

    echo "==> source: Release ($ver_label, $target)"
    # 先试新资产名，失败再回退旧名（兼容 0.6.x 及更早的 Release）
    for _a in "$asset_new" "$asset_old"; do
        if download "$base/$_a" "$DL/$_a"; then
            asset="$_a"
            break
        fi
    done
    if [ -z "$asset" ]; then
        echo "[!] download failed: $base/$asset_new (also tried $asset_old)" >&2
        echo "    download manually: https://github.com/$REPO/releases" >&2
        exit 1
    fi
    if [ -z "$RELEASE_BASE" ] && [ -z "$RELEASE_VER" ]; then
        # 解析 latest 实际指向的 tag（失败则退回 "latest"）
        ver_label="$(curl -fsSIL -o /dev/null -w '%{url_effective}' "$base/$asset" 2>/dev/null \
            | sed -n 's#.*/releases/download/\([^/]*\)/.*#\1#p' | head -1)"
        [ -n "$ver_label" ] || ver_label="latest"
    fi
    if download "$base/$asset.sha256" "$DL/$asset.sha256" 2>/dev/null; then
        ( cd "$DL" && sha256sum -c "$asset.sha256" >/dev/null ) \
            || { echo "[!] sha256 verification failed: $asset" >&2; exit 1; }
        echo "[OK] sha256 verified"
    else
        echo "[!] no .sha256 available; skipping verification" >&2
    fi
    tar -xJf "$DL/$asset" -C "$DL"
    BIN_SRC="$DL/${asset%.tar.xz}/gocryptfs-tui"
    WEB_SRC="$DL/${asset%.tar.xz}/gocryptfs-web"
    [ -f "$WEB_SRC" ] || WEB_SRC=""
    [ -f "$BIN_SRC" ] || { echo "[!] archive does not contain gocryptfs-tui" >&2; exit 1; }

    # 单文件 CLI：从同一 Release 的源码包取 shell/gocryptfs-cli.bundle
    echo "==> fetching the standalone CLI (from source.tar.gz)"
    if download "$base/source.tar.gz" "$DL/source.tar.gz"; then
        if download "$base/source.tar.gz.sha256" "$DL/source.tar.gz.sha256" 2>/dev/null; then
            ( cd "$DL" && sha256sum -c "source.tar.gz.sha256" >/dev/null ) \
                || { echo "[!] source.tar.gz verification failed" >&2; exit 1; }
        fi
        tar -xzf "$DL/source.tar.gz" -C "$DL"
        SHELL_DIR="$(find "$DL" -maxdepth 2 -type d -name shell | head -1)"
    fi
    if [ -z "$SHELL_DIR" ]; then
        echo "[!] could not extract shell/ from the source archive; installing the binaries only (no standalone CLI)" >&2
    fi
    SOURCE_DESC="release:$ver_label"
else
    if [ "$DO_BUILD" -eq 1 ]; then
        if ! have cargo; then
            echo "[!] local mode needs the Rust toolchain, but cargo was not found." >&2
            echo "    without source/toolchain, install from the Release:" >&2
            echo "      curl -LsSf https://github.com/$REPO/releases/latest/download/gocryptfs-ui-install.sh \\" >&2
            echo "        | sh -s -- --from-release --system" >&2
            exit 1
        fi
        echo "==> building gocryptfs-tui (local source mode)"
        cargo build --release
    else
        echo "==> skipping build (--no-build)"
    fi
    BIN_SRC="target/release/gocryptfs-tui"
    WEB_SRC="target/release/gocryptfs-web"
    [ -f "$WEB_SRC" ] || WEB_SRC=""
    SHELL_DIR="shell"
    SOURCE_DESC="local:$BIN_SRC"
    echo "==> source: local build ($BIN_SRC)"
    [ -f "$BIN_SRC" ] || { echo "[!] $BIN_SRC not found (run make build first, or drop --no-build)" >&2; exit 1; }
fi

BIN_VERSION="$("$BIN_SRC" --version 2>/dev/null | sed -n 's/^gocryptfs-tui //p' || true)"
[ -n "$BIN_VERSION" ] || BIN_VERSION="$SOURCE_DESC"

# ---- 清理旧安装并安装 ----
echo "==> installing to $PREFIX"
priv mkdir -p "$BINDIR" "$INSTALL_META"
# ≤0.8 的布局：<prefix>/lib/gocryptfs-ui/（cli + lib/*.sh + 清单）；升到 0.9 时清理
priv rm -rf "$LIBDIR" "$LEGACY_LIBDIR" "$LEGACY_SHAREDIR"

# 已安装文件清单（供 INSTALLED.files / --uninstall 使用）
: > "$STAGE/files"
record() { printf '%s\n' "$1" >> "$STAGE/files"; }

# 单文件自包含 CLI：装到 <prefix>/bin/gocryptfs-cli（真实文件，不是符号链接）
if [ -n "$SHELL_DIR" ]; then
    CLI_BUNDLE="$SHELL_DIR/gocryptfs-cli.bundle"
    if [ ! -f "$CLI_BUNDLE" ]; then
        # 源码包里没有提交的产物时现场打包（tools/bundle-cli.sh 与 shell/ 同级）
        TOOLS_DIR="$(dirname "$SHELL_DIR")/tools"
        if [ -f "$TOOLS_DIR/bundle-cli.sh" ]; then
            echo "==> bundling the standalone CLI (shell/gocryptfs-cli.bundle missing)"
            sh "$TOOLS_DIR/bundle-cli.sh" --version "$BIN_VERSION" -o "$STAGE/gocryptfs-cli" >/dev/null
            CLI_BUNDLE="$STAGE/gocryptfs-cli"
        fi
    fi
fi
if [ -n "$CLI_BUNDLE" ] && [ -f "$CLI_BUNDLE" ]; then
    if [ "$CLI_BUNDLE" != "$STAGE/gocryptfs-cli" ]; then
        sed "s|^CLI_VERSION=\"@VERSION@\"$|CLI_VERSION=\"$BIN_VERSION\"|" "$CLI_BUNDLE" > "$STAGE/gocryptfs-cli"
    fi
    chmod 0755 "$STAGE/gocryptfs-cli"
    # ≤0.8 的 gocryptfs-cli 是指向 lib/gocryptfs-ui 的符号链接；上面已清理 LIBDIR，
    # 残留的悬空链接会让 cp 拒绝写入（"not writing through dangling symlink"）。
    priv rm -f "$BINDIR/gocryptfs-cli"
    priv cp -f "$STAGE/gocryptfs-cli" "$BINDIR/gocryptfs-cli"
    priv chmod 0755 "$BINDIR/gocryptfs-cli"
    record "$BINDIR/gocryptfs-cli"
elif [ -n "$SHELL_DIR" ]; then
    echo "[!] no standalone CLI bundle available; installing the binaries only" >&2
fi

priv cp -f "$BIN_SRC" "$BINDIR/gocryptfs-tui"
priv chmod 0755 "$BINDIR/gocryptfs-tui"
record "$BINDIR/gocryptfs-tui"

if [ "$INSTALL_WEB" = "1" ] && [ -n "$WEB_SRC" ]; then
    priv cp -f "$WEB_SRC" "$BINDIR/gocryptfs-web"
    priv chmod 0755 "$BINDIR/gocryptfs-web"
    record "$BINDIR/gocryptfs-web"
elif [ "$INSTALL_WEB" = "1" ]; then
    echo "[i] gocryptfs-web is not in this archive (older release); installing the TUI only"
fi

printf '%s\n' "$BIN_VERSION" > "$STAGE/VERSION"
priv cp -f "$STAGE/VERSION" "$VERSION_FILE"
record "$VERSION_FILE"

# ---- 写安装清单（供 --uninstall 精确删除）----
{
    printf '{\n'
    printf '  "app": "gocryptfs-ui",\n'
    printf '  "version": "%s",\n' "$(json_escape "$BIN_VERSION")"
    printf '  "prefix": "%s",\n' "$(json_escape "$PREFIX")"
    printf '  "source": "%s",\n' "$(json_escape "$SOURCE_DESC")"
    printf '  "installed_at": "%s",\n' "$(date -Iseconds)"
    printf '  "files": [\n'
    n=0
    total=$(wc -l < "$STAGE/files" | tr -d ' ')
    while IFS= read -r f; do
        n=$((n + 1))
        sep=","
        if [ "$n" -eq "$total" ]; then sep=""; fi
        printf '    "%s"%s\n' "$(json_escape "$f")" "$sep"
    done < "$STAGE/files"
    printf '  ]\n'
    printf '}\n'
} > "$STAGE/INSTALLED.json"
priv cp -f "$STAGE/INSTALLED.json" "$MANIFEST"
priv cp -f "$STAGE/files" "$MANIFEST_FILES"

# ---- 自检 ----
echo ""
echo "==> self-check"
if [ -x "$BINDIR/gocryptfs-cli" ]; then
    if "$BINDIR/gocryptfs-cli" --help 2>&1 | grep -q -- '--lang'; then
        echo "[OK] standalone CLI works (single file, i18n enabled)"
    else
        echo "[!] $BINDIR/gocryptfs-cli --help does not provide --lang"
    fi
    cli_version="$("$BINDIR/gocryptfs-cli" --version 2>/dev/null | sed -n 's/^gocryptfs-cli //p' || true)"
    if [ -n "$cli_version" ]; then
        echo "[OK] CLI version: $cli_version"
    else
        echo "[!] $BINDIR/gocryptfs-cli --version did not report a version"
    fi
    resolved="$(command -v gocryptfs-cli 2>/dev/null || true)"
    if [ -z "$resolved" ]; then
        echo "[i] $BINDIR is not on PATH; add it to use gocryptfs-cli directly"
    elif [ "$resolved" != "$BINDIR/gocryptfs-cli" ]; then
        echo "[!] PATH resolves to: $resolved"
        echo "    which is not this install's $BINDIR/gocryptfs-cli; a stale backend may be used"
    else
        echo "[OK] PATH resolves to this install's gocryptfs-cli"
    fi
else
    echo "[i] no standalone CLI installed (the TUI/Web use the embedded backend)"
fi

if [ "$DEPS_CHECK" -eq 1 ]; then
    echo ""
    echo "==> runtime dependency check"
    if "$BINDIR/gocryptfs-tui" --check-deps; then
        :
    else
        rc=$?
        if [ "$rc" -eq 1 ]; then
            echo ""
            echo "[!] missing runtime dependencies; install them as shown above before running gocryptfs-tui"
        elif [ -x "$BINDIR/gocryptfs-cli" ]; then
            # 旧版二进制不认识 --check-deps：退回单文件 CLI 的检查
            echo "[i] this TUI binary does not support --check-deps; falling back to the shell backend"
            "$BINDIR/gocryptfs-cli" --check-deps \
                || echo "[!] missing runtime dependencies; install them as shown above"
        fi
    fi
fi

echo ""
echo "[OK] installed (source: $SOURCE_DESC, version: $BIN_VERSION)"
echo "  TUI:  $BINDIR/gocryptfs-tui"
if [ -x "$BINDIR/gocryptfs-web" ]; then
    echo "  Web:  $BINDIR/gocryptfs-web (see 'gocryptfs-web --help')"
fi
if [ -x "$BINDIR/gocryptfs-cli" ]; then
    echo "  CLI:  $BINDIR/gocryptfs-cli (single-file, self-contained)"
else
    echo "  CLI:  (embedded backend only; extracted to the data dir on first run)"
fi
echo "  manifest: $MANIFEST"
echo ""
echo "==> installed files"
find "$INSTALL_META" -type f | sort
find "$BINDIR" -maxdepth 1 -type f -name 'gocryptfs-*' | sort
echo ""
echo "Run:  gocryptfs-tui"
if [ -f "$0" ] && [ -r "$0" ]; then
    echo "Uninstall: $0 --uninstall --prefix $PREFIX"
else
    echo "Uninstall: curl -LsSf https://github.com/$REPO/releases/latest/download/gocryptfs-ui-install.sh \\"
    echo "             | sh -s -- --uninstall --prefix $PREFIX"
fi
