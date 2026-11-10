#!/bin/bash
# Versão traduzida para português do Brasil. Modificada a partir do Pelinstaller original (GPL-3.0).

set -eo pipefail

######################################################################################
#                                                                                    #
# Project 'Pelinstaller'                                                             #
#                                                                                    #
# Copyright (C) 2018 - 2024, Vilhelm Prytz, <vilhelm@prytznet.se>                    #
# Copyright (C) 2021 - 2026, Matthew Jacob, <git@matthew.network>                    #
#                                                                                    #
#   This program is free software: you can redistribute it and/or modify             #
#   it under the terms of the GNU General Public License as published by             #
#   the Free Software Foundation, either version 3 of the License, or                #
#   (at your option) any later version.                                              #
#                                                                                    #
#   This program is distributed in the hope that it will be useful,                  #
#   but WITHOUT ANY WARRANTY; without even the implied warranty of                   #
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                    #
#   GNU General Public License for more details.                                     #
#                                                                                    #
#   You should have received a copy of the GNU General Public License                #
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.           #
#                                                                                    #
# https://github.com/Zinidia/Pelinstaller/blob/Production/LICENSE.md                 #
#                                                                                    #
# This script is not associated with the official Pelican Project.                   #
# https://github.com/Zinidia/Pelinstaller                                            #
#                                                                                    #
######################################################################################

output() {
  echo "* ${1}"
}

error() {
  COLOR_RED='\033[0;31m'
  COLOR_NC='\033[0m'

  echo ""
  echo -e "* ${COLOR_RED}ERRO${COLOR_NC}: $1"
  echo ""
}

# Parse args
REPO="${REPO:-DenanHK1/Pelinstaller-pt-BR}"
BRANCH="${BRANCH:-Production}"
MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --repo=*) REPO="${1#*=}"; shift ;;
    --branch|--source) BRANCH="$2"; shift 2 ;;
    --branch=*|--source=*) BRANCH="${1#*=}"; shift ;;
    basic|docker|panel|wings|both|uninstall)
      MODE="$1"; shift ;;
    *) error "Argumento desconhecido: '$1'. Esperado um modo (basic, docker, panel, wings, both, uninstall) ou os argumentos --repo ou --branch."; exit 1 ;;
  esac
done

export REPO BRANCH
export GIT_REPO_URL="https://raw.githubusercontent.com/$REPO/$BRANCH"
LOG_PATH="/tmp/pelinstaller.log"

# Exit with error status code if user is not root
if [[ $EUID -ne 0 ]]; then
  error "Este script deve ser executado com privilégios de root (sudo)." 1>&2
  exit 1
fi

# Check for curl
if ! [ -x "$(command -v curl)" ]; then
  echo "* Instalando dependências."
  # Rockey / Alma
  if [ -n "$(command -v yum)" ]; then
    yum update -y >> /dev/null 2>&1
    yum -y install curl >> /dev/null 2>&1
  fi
  # Debian / Ubuntu
  if [ -n "$(command -v apt)" ]; then
    DEBIAN_FRONTEND=noninteractive apt update -y >> /dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends snapd cron curl wget gzip jq >> /dev/null 2>&1
  fi
  # Check if curl is installed
  if ! [ -x "$(command -v curl)" ]; then
    echo "* O curl é necessário para que este script funcione."
    echo "* instale usando apt (Debian e derivados) ou yum/dnf (CentOS)"
    exit 1
  fi
fi

# Lib Functions
LIB_PATH="/tmp/lib.sh"
curl -fsSL -o "$LIB_PATH" "$GIT_REPO_URL"/lib/lib.sh
trap 'rm -f "$LIB_PATH"' EXIT
# shellcheck source=lib/lib.sh
source "$LIB_PATH"

run_mode() {
  local mode="$1"
  local script
  script="$(mktemp)"
  curl -fsSL -o "$script" "$GIT_REPO_URL/installers/$mode.sh"
  echo -e "\n\n* Pelinstaller $(date) \n\n" >>"$LOG_PATH"
  bash "$script" 2>&1 | tee -a "$LOG_PATH"
  rm -f "$script"
}

execute_arg() {
  case "$1" in
    basic)     run_mode "basic" ;;
    docker)    run_mode "docker" ;;
    panel)     run_mode "panel" ;;
    wings)     run_mode "wings" ;;
    both)      run_mode "panel"; run_mode "wings" ;;
    uninstall) run_mode "uninstall" ;;
    *) error "Opção inválida '$1'. Esperado um destes: basic, docker, panel, wings, both, uninstall."; exit 1 ;;
  esac
}

welcome ""

# ----------------- Non-interactive CLI args ----------------- #
if [[ -n "$MODE" ]]; then
  execute_arg "$MODE"
  exit 0
fi

# Check for existing installation
if [ -d "/var/www/pelican" ]; then
  existing_choice=""
  while [ -z "$existing_choice" ]; do
    error "O script detectou que você já tem o painel Pelican instalado neste sistema!"
    output "[1] Desinstalar o Pelican - Tentar a desinstalação automática do Pelican."
    output "[2] Continuar mesmo assim - Ignorar os avisos e tentar instalar o Pelican."
    output "[3] Sair do instalador - Cancelar o processo de instalação."

    echo -n "* Digite de 1 a 3: "
    read -r action || true
    case "$action" in
      1)
        existing_choice="uninstall"
        echo "Tentando desinstalar .."
        run_mode "uninstall"
        echo -e -n "* Pelican desinstalado com sucesso. Deseja tentar instalar agora? (s/N): "
        read -r CONFIRM_PROCEED || true
        if [[ ! "$CONFIRM_PROCEED" =~ [YySs] ]]; then
          error "Instalação cancelada!"
          exit 1
        fi
        ;;
      2)
        existing_choice="continue"
        echo "Tentando continuar mesmo assim .."
        ;;
      3)
        echo "Saindo do instalador .."
        exit 1
        ;;
      *)
        error "Opção inválida. Digite um número de 1 a 3."
        ;;
    esac
  done
fi

# ----------------- Stage 1: Panel install mode ----------------- #
panel_mode=""
while [ -z "$panel_mode" ]; do
  output "Qual modo de instalação do painel você deseja usar?"
  output "[0] Pular - Não instalar o painel (padrão)"
  output "[1] Básico - Sem perguntas, ambiente de desenvolvimento (painel + wings, somente HTTP)"
  output "[2] Docker (Recomendado) - Docker compose usando as imagens oficiais do ghcr"
  output "[3] Bare metal - Instalação padrão sem Docker (pergunta FQDN/SSL)"

  echo -n "* Digite de 0 a 3 [0]: "
  read -r action || true
  [ -z "$action" ] && action=0

  case "$action" in
    0) panel_mode="skip" ;;
    1) panel_mode="basic" ;;
    2) panel_mode="docker" ;;
    3) panel_mode="panel" ;;
    *) error "Opção inválida" ;;
  esac
done

# ----------------- Stage 2: Wings install ----------------- #
wings_mode="skip"
# Basic mode automatically installs wings
if [ "$panel_mode" != "basic" ]; then
  chosen=""
  while [ -z "$chosen" ]; do
    output "Deseja instalar o Wings (o daemon da máquina)?"
    output "[0] Pular - Não instalar o wings (padrão)"
    output "[1] Instalar o Wings"

    echo -n "* Digite 0 ou 1 [0]: "
    read -r action || true
    [ -z "$action" ] && action=0

    case "$action" in
      0) chosen="skip" ;;
      1) chosen="wings"; wings_mode="wings" ;;
      *) error "Opção inválida" ;;
    esac
  done
fi

# ----------------- Execute selections ----------------- #
case "$panel_mode" in
  basic)  run_mode "basic" ;;
  docker) run_mode "docker" ;;
  panel)  run_mode "panel" ;;
  skip)   output "Pulando a instalação do painel." ;;
esac

[ "$wings_mode" == "wings" ] && run_mode "wings"

if [ "$panel_mode" == "skip" ] && [ "$wings_mode" == "skip" ]; then
  output "Nada selecionado. Saindo."
fi
