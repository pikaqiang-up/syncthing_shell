#!/usr/bin/env bash
# 获取/升级内嵌的 Syncthing 二进制（面向 AI/自动化执行设计，幂等）。
#
# 用法: scripts/update_syncthing.sh [版本号]   例: scripts/update_syncthing.sh 2.1.7
#       不带版本号则自动取 Termux 仓库最新版。
#
# 这个脚本是克隆本仓库后构建 APK 的**第一步**（仓库不含二进制，见 .gitignore）。
# 它会：从 Termux 仓库下载 aarch64 二进制 → sha256 校验 → 安装到 jniLibs。
# 可选：如果装有 Go 工具链，额外构建探测二进制并生成 REST API 快照用于升级对比。
set -euo pipefail

VER="${1:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TP="$ROOT/third_party/syncthing"
VER="${VER#v}"

# ---------------------------------------------------------------------------
echo "== 1/4 获取 Termux 包索引 =="
MIRRORS=(
  "https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
  "https://mirrors.ustc.edu.cn/termux/apt/termux-main"
  "https://packages.termux.dev/apt/termux-main"
)
MIR=""
for m in "${MIRRORS[@]}"; do
  if curl -sfL --connect-timeout 8 -m 90 \
      "$m/dists/stable/main/binary-x86_64/Packages" -o /tmp/termux-pkgs.txt; then
    MIR="$m"; echo "镜像: $m"; break
  fi
done
[ -n "$MIR" ] || { echo "错误: 所有 Termux 镜像不可达"; exit 1; }

if [ -z "$VER" ]; then
  VER=$(grep -A1 "^Package: syncthing$" /tmp/termux-pkgs.txt | grep "^Version:" | head -1 | cut -d' ' -f2)
  echo "Termux 最新版: $VER"
fi
echo "目标版本: $VER"

fetch_deb() { # fetch_deb <abi>
  local abi="$1" entry fname sha
  curl -sfL -m 90 "$MIR/dists/stable/main/binary-$abi/Packages" -o "/tmp/termux-pkgs-$abi.txt"
  entry=$(grep -A22 "^Package: syncthing$" "/tmp/termux-pkgs-$abi.txt" | grep "^Version: $VER" -A20)
  [ -n "$entry" ] || { echo "错误: Termux 仓库没有 syncthing $VER ($abi)"; exit 1; }
  fname=$(echo "$entry" | grep "^Filename:" | head -1 | cut -d' ' -f2)
  sha=$(echo "$entry" | grep "^SHA256:" | head -1 | cut -d' ' -f2)
  curl -fL --connect-timeout 8 -m 600 -o "/tmp/syncthing-$abi.deb" "$MIR/$fname"
  echo "$sha  /tmp/syncthing-$abi.deb" | sha256sum -c - || { echo "sha256 校验失败 ($abi)"; exit 1; }
}

echo "== 2/4 下载并安装 arm64 二进制 =="
mkdir -p "$TP/prebuilt" /tmp/st-extract
fetch_deb "aarch64"
rm -rf /tmp/st-extract && mkdir -p /tmp/st-extract
(cd /tmp/st-extract && ar x "/tmp/syncthing-aarch64.deb" && tar -xJf data.tar.xz)
bin=/tmp/st-extract/data/data/com.termux/files/usr/bin/syncthing
[ -f "$bin" ] || { echo "错误: deb 中找不到二进制"; exit 1; }
align=$(readelf -lW "$bin" | grep -m1 '^  LOAD' | awk '{print $NF}')
[ "$align" = "0x4000" ] || echo "警告: aarch64 对齐为 $align（期望 0x4000）"
cp "$bin" "$TP/prebuilt/syncthing-$VER-aarch64"

mkdir -p "$ROOT/android/app/src/main/jniLibs/arm64-v8a"
cp "$TP/prebuilt/syncthing-$VER-aarch64" "$ROOT/android/app/src/main/jniLibs/arm64-v8a/libsyncthing.so"
chmod 644 "$ROOT/android/app/src/main/jniLibs/arm64-v8a/libsyncthing.so"

cat > "$TP/BINARY.txt" <<EOF
内嵌二进制：syncthing $VER（Termux 官方包构建）
来源：Termux 主仓库 termux-main（sha256 与官方索引核对）
  构建方式：GOOS=android + NDK clang（bionic PIE，16K 对齐，[noupgrade]）
升级脚本：scripts/update_syncthing.sh
EOF

# ---------------------------------------------------------------------------
# 可选步骤：需要 Go 工具链；仅生成 REST API 快照用于升级对比，不影响 APK 构建
if command -v go >/dev/null 2>&1; then
  echo "== 3/4 （可选）构建本地探测二进制 =="
  cd "$TP"
  SRC_TAR="syncthing-source-v$VER.tar.gz"
  DL_URL="https://github.com/syncthing/syncthing/releases/download/v$VER/$SRC_TAR"
  [ -f "$SRC_TAR" ] || {
    curl -fsSL --connect-timeout 10 -m 600 -o "$SRC_TAR" "$DL_URL" \
      || curl -fsSL --connect-timeout 10 -m 600 -o "$SRC_TAR" "https://gh-proxy.com/$DL_URL" \
      || python3 "$ROOT/tools/parallel_dl.py" "$DL_URL,https://gh-proxy.com/$DL_URL" "$SRC_TAR" "" 16
  }
  rm -rf src && mkdir src && tar -xzf "$SRC_TAR" -C src --strip-components=1
  (cd src && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -mod=vendor -trimpath \
    -tags noupgrade -ldflags "-s -w" -o "../build/syncthing-linux-amd64" ./cmd/syncthing)

  echo "== 4/4 （可选）生成 API 快照并对比 =="
  "$ROOT/tools/probe_api.sh" "$TP/build/syncthing-linux-amd64" >/dev/null
  SNAP_DIR="$ROOT/docs/api-snapshot/$(basename "$TP/build/syncthing-linux-amd64")"
  [ -d "$SNAP_DIR" ] && mv "$SNAP_DIR" "$ROOT/docs/api-snapshot/v$VER" || true
  PREV=$(ls -d "$ROOT"/docs/api-snapshot/v* 2>/dev/null | grep -v "v$VER" | sort -V | tail -1 || true)
  if [ -n "$PREV" ]; then
    echo "与 $(basename "$PREV") 的差异端点:"
    for f in "$ROOT/docs/api-snapshot/v$VER"/*.json; do
      n=$(basename "$f")
      diff -q "$PREV/$n" "$f" >/dev/null 2>&1 || echo "  [CHANGED] $n"
    done
  fi
else
  echo "== 3-4/4 跳过 API 快照（未安装 go 工具链；不影响 APK 构建） =="
fi

echo
echo "✅ 完成 $VER。接下来:"
echo "   flutter pub get && flutter build apk --release"
