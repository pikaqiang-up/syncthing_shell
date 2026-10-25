#!/usr/bin/env bash
# 探测本地 syncthing 的 REST API，把所有端点的 JSON 响应快照到 docs/api-snapshot/<版本>/。
# 用途：
#   1. 开发时生成模型层的权威依据
#   2. 升级 syncthing 后重跑，diff 新旧快照即可发现 API 变化（配合 update_syncthing.sh）
#
# 用法: tools/probe_api.sh [tar.gz路径]  （默认 third_party/syncthing/syncthing-linux-amd64-*.tar.gz）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAR="${1:-$(ls "$ROOT"/third_party/syncthing/syncthing-linux-amd64-*.tar.gz | head -1)}"
WORK="$ROOT/tools/host-syncthing"
PORT=18384
BASE="http://127.0.0.1:$PORT"

VERSION=$(basename "$TAR" | sed -E 's/.*-v([0-9.]+)\.tar\.gz/\1/')
OUT="$ROOT/docs/api-snapshot/v$VERSION"
mkdir -p "$OUT" "$WORK"

if [ ! -x "$WORK/syncthing" ]; then
  if [ -x "$TAR" ]; then
    # 直接给的就是可执行文件
    cp "$TAR" "$WORK/syncthing"
  else
    rm -rf "$WORK/extract"
    mkdir -p "$WORK/extract"
    tar -xzf "$TAR" -C "$WORK/extract" --strip-components=1
    mv "$WORK/extract/syncthing" "$WORK/syncthing"
    rm -rf "$WORK/extract"
  fi
  chmod +x "$WORK/syncthing"
fi

HOME_DIR="$WORK/probe-home"
rm -rf "$HOME_DIR"
mkdir -p "$HOME_DIR"

STNORESTART=1 STNOUPGRADE=1 "$WORK/syncthing" generate --home "$HOME_DIR" --no-port-probing >/dev/null
APIKEY=$(sed -nE 's/.*<apikey>([^<]+)<\/apikey>.*/\1/p' "$HOME_DIR/config.xml" | head -1)
echo "版本: $VERSION  apikey: ${APIKEY:0:8}..."

STNORESTART=1 STNOUPGRADE=1 "$WORK/syncthing" serve --home "$HOME_DIR" --gui-address="127.0.0.1:$PORT" \
  >"$WORK/probe-serve.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT

# 等待就绪
for i in $(seq 1 30); do
  if curl -s -m 2 -H "X-API-Key: $APIKEY" "$BASE/rest/system/ping" | grep -q pong; then
    break
  fi
  sleep 1
done

AUTH=(-H "X-API-Key: $APIKEY")
snap() { # snap <name> <curl args...>
  local name="$1"; shift
  curl -s -m 15 "${AUTH[@]}" "$@" >"$OUT/$name.json" || echo '(failed)' >"$OUT/$name.json"
  echo "  $name.json  ($(wc -c <"$OUT/$name.json") bytes)"
}

echo "快照输出到 $OUT:"
snap system-version   "$BASE/rest/system/version"
snap system-status    "$BASE/rest/system/status"
snap system-connections "$BASE/rest/system/connections"
snap system-config    "$BASE/rest/system/config"
snap config           "$BASE/rest/config"
snap config-insync    "$BASE/rest/config/restart-required"
snap defaults-folder  "$BASE/rest/config/defaults/folder"
snap defaults-device  "$BASE/rest/config/defaults/device"
snap defaults-ignores "$BASE/rest/config/defaults/ignores"
snap system-log       "$BASE/rest/system/log"
snap system-error     "$BASE/rest/system/error"
snap system-paths     "$BASE/rest/system/paths"
snap system-discovery "$BASE/rest/system/discovery"
snap system-loglevels "$BASE/rest/system/loglevels"
snap cluster-pending-devices "$BASE/rest/cluster/pending/devices"
snap cluster-pending-folders "$BASE/rest/cluster/pending/folders"
snap stats-device    "$BASE/rest/stats/device"
snap stats-folder    "$BASE/rest/stats/folder"
snap svc-report      "$BASE/rest/svc/report"

# 建一个示例文件夹以捕获 db 类端点的形状（browse/status/ignores 等
# 只有存在文件夹时才返回有效结构——曾因缺这一步漏掉 v2 browse 形状变化）
PROBE_DIR="$WORK/probe-folder"
mkdir -p "$PROBE_DIR"
curl -s -m 15 "${AUTH[@]}" -X POST -H "Content-Type: application/json" \
  -d "{\"id\":\"probe-1\",\"label\":\"probe\",\"path\":\"$PROBE_DIR\",\"type\":\"sendreceive\"}" \
  "$BASE/rest/config/folders" >/dev/null
sleep 3

snap system-browse  "$BASE/rest/system/browse?current=/"
snap db-status      "$BASE/rest/db/status?folder=probe-1"
snap db-browse      "$BASE/rest/db/browse?folder=probe-1&levels=1"
snap db-ignores     "$BASE/rest/db/ignores?folder=probe-1"
snap db-completion  "$BASE/rest/db/completion?device=none&folder=probe-1"
snap folder-errors  "$BASE/rest/folder/errors?folder=probe-1"
snap folder-versions "$BASE/rest/folder/versions?folder=probe-1"
echo "完成。"
