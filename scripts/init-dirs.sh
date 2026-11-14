#!/usr/bin/env bash
# Cria a árvore de config e de mídia usada pelo compose.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

CONFIG_ROOT="${CONFIG_ROOT:-./config}"
DATA_ROOT="${DATA_ROOT:-./data}"

dirs=(
  "$CONFIG_ROOT/qbittorrent"
  "$CONFIG_ROOT/prowlarr"
  "$CONFIG_ROOT/flaresolverr"
  "$CONFIG_ROOT/sonarr"
  "$CONFIG_ROOT/radarr"
  "$CONFIG_ROOT/bazarr"
  "$CONFIG_ROOT/jellyfin"
  "$CONFIG_ROOT/seerr"
  "$CONFIG_ROOT/plex"
  "$CONFIG_ROOT/gluetun"
  "$DATA_ROOT/torrents/incomplete"
  "$DATA_ROOT/torrents/tv"
  "$DATA_ROOT/torrents/movies"
  "$DATA_ROOT/media/tv"
  "$DATA_ROOT/media/movies"
)

mkdir -p "${dirs[@]}"

if [[ "$(id -u)" -eq 0 ]]; then
  chown -R "${PUID:-1000}:${PGID:-1000}" "$CONFIG_ROOT" "$DATA_ROOT"
  echo "Dono definido para ${PUID:-1000}:${PGID:-1000}."
else
  echo "Diretórios criados. Se os containers recusarem escrita, rode:"
  echo "  sudo chown -R ${PUID:-1000}:${PGID:-1000} ${CONFIG_ROOT} ${DATA_ROOT}"
fi

echo "Config: ${CONFIG_ROOT}"
echo "Dados:  ${DATA_ROOT}"
echo "Torrents e a biblioteca precisam estar no mesmo filesystem para hardlinks."
