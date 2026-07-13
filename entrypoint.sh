#!/usr/bin/env bash
# KubicRend entrypoint: mode-driven DLL swap + config placement + launch under Wine.
set -uo pipefail

REND_DIR="${REND_DIR:-/opt/rend}"
REND_MODE="${REND_MODE:-modded}"
REND_GAME_PORT="${REND_GAME_PORT:-7777}"
REND_BEACON_PORT="${REND_BEACON_PORT:-15000}"
REND_USERDIR="${REND_USERDIR:-/data}"
REND_CONFIG_SRC="${REND_CONFIG_SRC:-/config}"
REND_EXTRA_ARGS="${REND_EXTRA_ARGS:-}"

SERVER_BIN="$REND_DIR/Otherlands/Binaries/Win64/OtherlandsServer-Win64-Shipping.exe"
DLL_DEST="$REND_DIR/Engine/Binaries/ThirdParty/PhysX3/Win64/VS2015/PhysX3Cooking_x64.dll"
MOD_DLL="/opt/rend-dll/PhysX3Cooking_x64.dll"
STOCK_DLL="/opt/rend-dll/PhysX3Cooking_x64.stock.dll"

# 1) DLL swap by mode. The stock DLL was backed up at build time.
NOEAC_ARG=""
case "$REND_MODE" in
  modded)
    echo "==> REND_MODE=modded: installing modified DLL + enabling -NoEAC"
    cp -f "$MOD_DLL" "$DLL_DEST"
    NOEAC_ARG="-NoEAC"
    ;;
  vanilla)
    echo "==> REND_MODE=vanilla: restoring stock DLL, EAC enabled"
    cp -f "$STOCK_DLL" "$DLL_DEST"
    ;;
  *)
    echo "!! Unknown REND_MODE='$REND_MODE' (want modded|vanilla)" >&2
    exit 2
    ;;
esac

# 2) Config placement. config.ini -> install root; the rest -> the -userdir Config tree.
if [[ -d "$REND_CONFIG_SRC" ]]; then
  if [[ -f "$REND_CONFIG_SRC/config.ini" ]]; then
    cp -f "$REND_CONFIG_SRC/config.ini" "$REND_DIR/config.ini"
  fi
  CFG_DEST="$REND_USERDIR/Saved/Config/WindowsServer"
  mkdir -p "$CFG_DEST"
  for f in Game.ini Server.ini Engine.ini Authentication.ini; do
    [[ -f "$REND_CONFIG_SRC/$f" ]] && cp -f "$REND_CONFIG_SRC/$f" "$CFG_DEST/$f"
  done
fi
mkdir -p "$REND_USERDIR"

# 3) Wine prefix warmup. On a fresh container the prefix must be initialized under
# its own throwaway Xvfb BEFORE the real launch; a single combined xvfb-run + wine
# leaves the server unable to spawn (no wineserver, silent hang). This mirrors the
# proven boot-spike sequence.
echo "==> Initializing Wine prefix..."
xvfb-run -a wineboot --init 2>&1 | tail -5 || true
wineserver -w || true

# 4) Launch. UE resolves its content paks by RELATIVE path (../../../Otherlands/
# Content/Paks/...), so the server MUST run from its Win64 binary dir. -userdir
# relocates the Saved tree (world + config + logs) onto the PVC at
# <userdir>/Saved/...; -log also writes <userdir>/Saved/Logs/Otherlands.log.
cd "$(dirname "$SERVER_BIN")" || { echo "!! cannot cd to server dir: $(dirname "$SERVER_BIN")" >&2; exit 4; }
echo "==> Launching Rend: mode=$REND_MODE game=$REND_GAME_PORT beacon=$REND_BEACON_PORT userdir=$REND_USERDIR"
# NOT exec'd: xvfb-run must run as a child so this script stays PID 1. As PID 1,
# xvfb-run mismanages wineserver's forking and the server never spawns. Running it
# as a child (and waiting) matches the proven boot sequence.
xvfb-run -a wine "$SERVER_BIN" -log \
  BeaconPort="$REND_BEACON_PORT" Port="$REND_GAME_PORT" \
  -userdir="$REND_USERDIR" $NOEAC_ARG $REND_EXTRA_ARGS &
wait $!
