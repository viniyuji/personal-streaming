#!/usr/bin/env bash
# Prepara o notebook servidor: Ubuntu 26.04, i5-8250U, UHD 620, 930MX.
# Rode no servidor, dentro do clone deste repositório:
#   ./scripts/install-host.sh
# A máquina de trabalho não é o alvo. O script para se a CPU não for o 8250U.
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Rode com o seu usuário, sem sudo: ./scripts/install-host.sh"
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

cpu="$(awk -F: '/model name/ { gsub(/^[ \t]+/, "", $2); print $2; exit }' /proc/cpuinfo)"
echo "CPU: ${cpu}"
if [[ "${cpu}" != *"8250U"* ]]; then
  echo "Este script é só do notebook servidor (i5-8250U)."
  echo "A máquina atual não é esse servidor. Nada foi instalado."
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Não achei /etc/os-release."
  exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
if [[ "${VERSION_ID:-}" != "26.04" ]]; then
  echo "Ubuntu esperado: 26.04 LTS. Encontrado: ${PRETTY_NAME:-desconhecido}."
  exit 1
fi

echo "Servidor confirmado: Ubuntu ${VERSION_ID} (${VERSION_CODENAME:-resolute})."
sudo -v

if lspci -nn | grep -qi '930MX'; then
  echo "930MX presente. Ela não entra no transcode: o chip GM108 não tem NVENC."
  echo "O Jellyfin usa a UHD 620 (/dev/dri)."
fi

install_docker() {
  if sudo docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    echo "Docker e o plugin Compose já estão instalados."
    sudo systemctl enable --now docker
    return
  fi

  local conflicts=() pkg
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    if dpkg -s "${pkg}" >/dev/null 2>&1; then
      conflicts+=("${pkg}")
    fi
  done
  if ((${#conflicts[@]})); then
    echo "Removendo pacotes que conflitam com o Docker oficial: ${conflicts[*]}"
    sudo apt-get remove -y "${conflicts[@]}"
  fi

  sudo apt-get update
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  local codename arch
  codename="${UBUNTU_CODENAME:-${VERSION_CODENAME}}"
  arch="$(dpkg --print-architecture)"
  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  sudo apt-get update
  sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
  sudo systemctl enable --now docker
  sudo docker run --rm hello-world
}

install_intel_vaapi() {
  sudo apt-get install -y intel-media-va-driver vainfo
  if [[ ! -e /dev/dri/renderD128 ]]; then
    echo "Não achei /dev/dri/renderD128. A UHD 620 não ficou disponível para o Jellyfin."
    exit 1
  fi
  echo "Dispositivos de vídeo:"
  ls -l /dev/dri
  local node
  for node in /dev/dri/renderD*; do
    echo "== ${node} =="
    sudo vainfo --display drm --device "${node}" || true
  done
}

set_env() {
  local key="$1" value="$2" file="$3"
  if grep -q "^${key}=" "${file}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
  else
    echo "${key}=${value}" >> "${file}"
  fi
}

install_docker
install_intel_vaapi

sudo usermod -aG docker,video,render "${USER}"

if [[ ! -f .env ]]; then
  cp .env.example .env
fi
set_env PUID "$(id -u)" .env
set_env PGID "$(id -g)" .env
set_env VIDEO_GID "$(getent group video | cut -d: -f3)" .env
set_env RENDER_GID "$(getent group render | cut -d: -f3)" .env

sudo mkdir -p /srv/streaming
sudo chown "${USER}:${USER}" /srv/streaming

echo
echo "Docker: $(sudo docker --version)"
echo "Compose: $(docker compose version)"
echo "PUID=$(id -u) PGID=$(id -g) VIDEO_GID=$(getent group video | cut -d: -f3) RENDER_GID=$(getent group render | cut -d: -f3)"
echo
echo "Saia da sessão e entre de novo para o grupo docker valer."
if ! mountpoint -q /mnt/media; then
  echo "O HD de 1 TB ainda não está montado em /mnt/media. Sem isso o make up gravaria no SSD."
  echo "Veja os discos com lsblk, formate em ext4 se precisar e acrescente no /etc/fstab:"
  echo "  UUID=... /mnt/media ext4 defaults,noatime 0 2"
else
  echo "/mnt/media está montado. Próximo passo, já de volta no servidor: make up"
fi
