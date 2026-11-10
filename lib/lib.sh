#!/bin/bash
# Versão traduzida para português do Brasil. Modificada a partir do Pelinstaller original (GPL-3.0).

set -e

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

# ------------------ Variables ----------------- #
# Versioning
export SCRIPT_RELEASE=${SCRIPT_RELEASE:-canary}

# Pelican versions
export PELICAN_PANEL_VERSION=""
export PELICAN_WINGS_VERSION=""

# Path (export everything that is possible, doesn't matter that it exists already)
export PATH="$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

# OS
export OS=""
export OS_VER_MAJOR=""
export CPU_ARCHITECTURE=""
export ARCH=""
export SUPPORTED=false

# Download URLs
export PANEL_DL_URL="${PANEL_DL_URL:-https://github.com/pelican/panel/releases/latest/download/panel.tar.gz}"
export WINGS_DL_URL="https://github.com/pelican/wings/releases/latest/download/wings_linux_"
# Repo arg defaults
export REPO="${REPO:-DenanHK1/Pelinstaller-pt-BR}"
export BRANCH="${BRANCH:-Production}"
export GIT_REPO_URL="${GIT_REPO_URL:-https://raw.githubusercontent.com/$REPO/$BRANCH}"

# Colors
COLOR_YELLOW='\033[1;33m'
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

# Email input validation regex
email_regex="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"

# Charset used to generate random passwords
password_charset='A-Za-z0-9'

# --------------------- Lib -------------------- #
lib_loaded() {
  return 0
}

# -------------- Visual functions -------------- #
output() {
  echo -e "* $1"
}

success() {
  echo ""
  output "${COLOR_GREEN}SUCESSO${COLOR_NC}: $1"
  echo ""
}

error() {
  echo ""
  echo -e "* ${COLOR_RED}ERRO${COLOR_NC}: $1" 1>&2
  echo ""
}

warning() {
  echo ""
  output "${COLOR_YELLOW}AVISO${COLOR_NC}: $1"
  echo ""
}

print_brake() {
  for ((n = 0; n < $1; n++)); do
    echo -n "#"
  done
  echo ""
}

print_list() {
  print_brake 30
  for word in $1; do
    output "$word"
  done
  print_brake 30
  echo ""
}

hyperlink() {
  echo -e "\e]8;;${1}\a${1}\e]8;;\a"
}

# First argument is wings / panel / neither
welcome() {
  get_latest_versions

  print_brake 70
  output "Script de instalação do Pelican Panel @ $SCRIPT_RELEASE"
  output ""
  output "Copyright (C) 2018 - 2024, Vilhelm Prytz, <vilhelm@prytznet.se>"
  output "Copyright (C) 2021 - 2026, Matthew Jacob, <git@matthew.network>"
  output "https://github.com/Zinidia/Pelinstaller"
  output ""
  output "Este script não tem relação com o projeto oficial do Pelican."
  output ""
  output "Usando o repositório $REPO (branch $BRANCH)."
  output "Executando em $OS, versão $OS_VER."
  if [ "$1" == "panel" ]; then
    output "Última versão do pelican/panel: $PELICAN_PANEL_VERSION"
  elif [ "$1" == "wings" ]; then
    output "Última versão do pelican/wings: $PELICAN_WINGS_VERSION"
  fi
  print_brake 70
}

# ---------------- Lib functions --------------- #
get_latest_release() {
  curl -sL "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                       # Get tag line
    sed -E 's/.*"([^"]+)".*/\1/'                               # Pluck JSON value
}

get_latest_versions() {
  output "Obtendo informações de versão .."
  PELICAN_PANEL_VERSION=$(get_latest_release "pelican/panel")
  PELICAN_WINGS_VERSION=$(get_latest_release "pelican/wings")
}

update_lib_source() {
  rm -rf /tmp/lib.sh
  curl -fsSL -o /tmp/lib.sh "$GIT_REPO_URL"/lib/lib.sh
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh
}

run_installer() {
  bash <(curl -fsSL "$GIT_REPO_URL/installers/$1.sh")
}

valid_email() {
  [[ $1 =~ ${email_regex} ]]
}

invalid_ip() {
  ip route get "$1" >/dev/null 2>&1
  echo $?
}

gen_passwd() {
  local length=$1
  local password=""
  while [ ${#password} -lt "$length" ]; do
    password=$(echo "$password""$(head -c 100 /dev/urandom | LC_ALL=C tr -dc "$password_charset")" | fold -w "$length" | head -n 1)
  done
  echo "$password"
}

# -------------------- MYSQL ------------------- #
create_db_user() {
  local db_user_name="$1"
  local db_user_password="$2"
  local db_host="${3:-127.0.0.1}"

  output "Criando o usuário de banco de dados $db_user_name .."

  mariadb -u root -e "CREATE OR REPLACE USER '$db_user_name'@'$db_host' IDENTIFIED BY '$db_user_password';"
  mariadb -u root -e "FLUSH PRIVILEGES;"

  output "Usuário de banco de dados $db_user_name criado"
}

grant_all_privileges() {
  local db_name="$1"
  local db_user_name="$2"
  local db_host="${3:-127.0.0.1}"

  output "Concedendo todos os privilégios em $db_name a $db_user_name .."

  mariadb -u root -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user_name'@'$db_host' WITH GRANT OPTION;"
  mariadb -u root -e "FLUSH PRIVILEGES;"

  output "Privilégios concedidos"

}

create_db() {
  local db_name="$1"
  local db_user_name="$2"
  local db_host="${3:-127.0.0.1}"

  output "Criando o banco de dados $db_name .."

  mariadb -u root -e "CREATE DATABASE $db_name;"
  grant_all_privileges "$db_name" "$db_user_name" "$db_host"

  output "Banco de dados $db_name criado"
}

# --------------- Package Manager -------------- #
# Argument for quite mode
update_repos() {
  local args=""
  [[ $1 == true ]] && args="-qq"
  case "$OS" in
  debian | ubuntu)
    apt -y $args update
    ;;
  *)
    # Do nothing as AlmaLinux and RockyLinux update metadata before installing packages.
    ;;
  esac
}

# First argument list of packages to install, second argument for quite mode
install_packages() {
  local args=""
  if [[ $2 == true ]]; then
    case "$OS" in
    debian | ubuntu) args="-qq" ;;
    *) args="-q" ;;
    esac
  fi

  # Eval needed for proper expansion of arguments
  case "$OS" in
  debian | ubuntu)
    eval apt -y $args install "$1"
    ;;
  almalinux | rocky)
    eval dnf -y $args install "$1"
    ;;
  esac
}

install_docker_kernel_modules() {
  [[ "$OS" =~ ^(rocky|almalinux)$ && "$OS_VER_MAJOR" == "10" ]] || return 0
  modprobe xt_addrtype 2>/dev/null && return 0
  if dnf -q list --available "kernel-modules-extra-$(uname -r)" >/dev/null 2>&1; then
    install_packages "kernel-modules-$(uname -r) kernel-modules-extra-$(uname -r)"
    modprobe xt_addrtype && return 0
  fi
  install_packages "kernel kernel-modules kernel-modules-extra"
  error "O Docker precisa do módulo de kernel xt_addrtype, que não está disponível para o kernel em execução ($(uname -r)). Um kernel mais recente foi instalado: reinicie o computador e execute o instalador novamente."
  exit 1
}

# ------------ User input functions ------------ #
required_input() {
  local __resultvar=$1
  local result=''

  while [ -z "$result" ]; do
    echo -n "* ${2}"
    read -r result

    if [ -z "${3}" ]; then
      [ -z "$result" ] && result="${4}"
    else
      [ -z "$result" ] && error "${3}"
    fi
  done

  eval "$__resultvar="'$result'""
}

email_input() {
  local __resultvar=$1
  local result=''

  while ! valid_email "$result"; do
    echo -n "* ${2}"
    read -r result

    valid_email "$result" || error "${3}"
  done

  eval "$__resultvar="'$result'""
}

password_input() {
  local __resultvar=$1
  local result=''
  local default="$4"

  while [ -z "$result" ]; do
    echo -n "* ${2}"

    # Modified from https://stackoverflow.com/a/22940001
    while IFS= read -r -s -n1 char; do
      [[ -z $char ]] && {
        printf '\n'
        break
      }                               # ENTER pressed; output \n and break.
      if [[ $char == $'\x7f' ]]; then # backspace was pressed
        # Only if variable is not empty
        if [ -n "$result" ]; then
          # Remove last char from output variable.
          [[ -n $result ]] && result=${result%?}
          # Erase '*' to the left.
          printf '\b \b'
        fi
      else
        # Add typed char to output variable.  [ -z "$result" ] && [ -n "
        result+=$char
        # Print '*' in its stead.
        printf '*'
      fi
    done
    [ -z "$result" ] && [ -n "$default" ] && result="$default"
    [ -z "$result" ] && error "${3}"
  done

  eval "$__resultvar="'$result'""
}

# ------------------ Firewall ------------------ #
ask_firewall() {
  local __resultvar=$1

  case "$OS" in
  debian | ubuntu)
    echo -e -n "* Deseja configurar o UFW (firewall) automaticamente? (s/N): "
    read -r CONFIRM_UFW

    if [[ "$CONFIRM_UFW" =~ [YySs] ]]; then
      eval "$__resultvar="'true'""
    fi
    ;;
  almalinux | rocky)
    echo -e -n "* Deseja configurar o firewall-cmd (firewall) automaticamente? (s/N): "
    read -r CONFIRM_FIREWALL_CMD

    if [[ "$CONFIRM_FIREWALL_CMD" =~ [YySs] ]]; then
      eval "$__resultvar="'true'""
    fi
    ;;
  esac
}

install_firewall() {
  case "$OS" in
  debian | ubuntu)
    output ""
    output "Instalando o Uncomplicated Firewall (UFW)"

    if ! [ -x "$(command -v ufw)" ]; then
      update_repos true
      install_packages "ufw" true
    fi

    ufw --force enable

    success "Uncomplicated Firewall (UFW) ativado"

    ;;
  almalinux | rocky)

    output ""
    output "Instalando o FirewallD"

    if ! [ -x "$(command -v firewall-cmd)" ]; then
      install_packages "firewalld" true
    fi

    systemctl --now enable firewalld >/dev/null

    success "FirewallD ativado"

    ;;
  esac
}

firewall_allow_ports() {
  case "$OS" in
  debian | ubuntu)
    for port in $1; do
      ufw allow "$port"
    done
    ufw --force reload
    ;;
  almalinux | rocky)
    for port in $1; do
      firewall-cmd --zone=public --add-port="$port"/tcp --permanent
    done
    firewall-cmd --reload -q
    ;;
  esac
}

# ---------------- System checks --------------- #
# Panel x86_64 check
check_os_x86_64() {
  if [ "${ARCH}" != "amd64" ]; then
    warning "Arquitetura de CPU detectada: $CPU_ARCHITECTURE"
    warning "Usar qualquer arquitetura diferente de 64 bits (x86_64) causará problemas."

    echo -e -n "* Tem certeza de que deseja continuar? (s/N): "
    read -r choice

    if [[ ! "$choice" =~ [YySs] ]]; then
      error "Instalação cancelada!"
      exit 1
    fi
  fi
}

# Wings virtualization check
check_virt() {
  output "Instalando o virt-what .."

  update_repos true
  install_packages "virt-what" true

  # Export sbin for virt-what
  export PATH="$PATH:/sbin:/usr/sbin"

  virt_serv=$(virt-what)

  case "$virt_serv" in
  *openvz* | *lxc*)
    warning "Tipo de virtualização não suportado detectado. Consulte o seu provedor de hospedagem para saber se o seu servidor consegue executar o Docker. Prossiga por sua conta e risco."
    echo -e -n "* Tem certeza de que deseja continuar? (s/N): "
    read -r CONFIRM_PROCEED
    if [[ ! "$CONFIRM_PROCEED" =~ [YySs] ]]; then
      error "Instalação cancelada!"
      exit 1
    fi
    ;;
  *)
    [ "$virt_serv" != "" ] && warning "Virtualização detectada: $virt_serv."
    ;;
  esac

  if uname -r | grep -q "xxxx"; then
    error "Kernel não suportado detectado."
    exit 1
  fi

  success "O sistema é compatível com o Docker"
}

# Exit with error status code if user is not root
if [[ $EUID -ne 0 ]]; then
  error "Este script deve ser executado com privilégios de root."
  exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
  # freedesktop.org and systemd
  . /etc/os-release
  OS=$(echo "$ID" | awk '{print tolower($0)}')
  OS_VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
  # linuxbase.org
  OS=$(lsb_release -si | awk '{print tolower($0)}')
  OS_VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
  # For some versions of Debian/Ubuntu without lsb_release command
  . /etc/lsb-release
  OS=$(echo "$DISTRIB_ID" | awk '{print tolower($0)}')
  OS_VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
  # Older Debian/Ubuntu/etc.
  OS="debian"
  OS_VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
  # Older SuSE/etc.
  OS="SuSE"
  OS_VER="?"
elif [ -f /etc/redhat-release ]; then
  # Older Red Hat, CentOS, etc.
  OS="Red Hat/CentOS"
  OS_VER="?"
else
  # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
  OS=$(uname -s)
  OS_VER=$(uname -r)
fi

OS=$(echo "$OS" | awk '{print tolower($0)}')
OS_VER_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
CPU_ARCHITECTURE=$(uname -m)

case "$CPU_ARCHITECTURE" in
x86_64)
  ARCH=amd64
  ;;
arm64 | aarch64)
  ARCH=arm64
  ;;
*)
  error "Apenas x86_64 e arm64 são suportados!"
  exit 1
  ;;
esac

case "$OS" in
ubuntu)
  [ "$OS_VER_MAJOR" == "20" ] && SUPPORTED=true
  [ "$OS_VER_MAJOR" == "22" ] && SUPPORTED=true
  [ "$OS_VER_MAJOR" == "24" ] && SUPPORTED=true
  [ "$OS_VER_MAJOR" == "26" ] && SUPPORTED=true
  export DEBIAN_FRONTEND=noninteractive
  ;;
debian)
  [ "$OS_VER_MAJOR" == "10" ] && SUPPORTED=true
  [ "$OS_VER_MAJOR" == "11" ] && SUPPORTED=true
  [ "$OS_VER_MAJOR" == "12" ] && SUPPORTED=true
  [ "$OS_VER_MAJOR" == "13" ] && SUPPORTED=true
  export DEBIAN_FRONTEND=noninteractive
  ;;
almalinux | rocky)
  [ "$OS_VER_MAJOR" == "8" ] && SUPPORTED=true
  [ "$OS_VER_MAJOR" == "9" ] && SUPPORTED=true
  [ "$OS_VER_MAJOR" == "10" ] && SUPPORTED=true
  export REDIS_PACKAGE=redis
  [ "$OS_VER_MAJOR" == "10" ] && REDIS_PACKAGE=valkey
  ;;
*)
  SUPPORTED=false
  ;;
esac

# Exit if not supported
if [ "$SUPPORTED" == false ]; then
  output "$OS $OS_VER não é suportado"
  error "Sistema operacional não suportado"
  exit 1
fi
