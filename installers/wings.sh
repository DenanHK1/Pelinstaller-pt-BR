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

# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -fsSL "$GIT_REPO_URL"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERRO: Não foi possível carregar o script lib" && exit 1
fi

# ------------------ Variables ----------------- #
# Install MariaDB
export INSTALL_MARIADB=false

# Firewall
export CONFIGURE_FIREWALL=false

# TLS Cert
export CONFIGURE_LETSENCRYPT=false
export HOSTNAME=""
export EMAIL=""

# Database host
export CONFIGURE_DBHOST=false
export CONFIGURE_DB_FIREWALL=false
export MYSQL_DBHOST_HOST="127.0.0.1"
export MYSQL_DBHOST_USER="pelicanuser"
export MYSQL_DBHOST_PASSWORD=""

# ------------ User input functions ------------ #
ask_letsencrypt() {
  if [ "$CONFIGURE_FIREWALL" == false ]; then
    warning "O Let's Encrypt exige que as portas 80/443 estejam abertas! Você optou por não configurar o firewall automaticamente; use por sua conta e risco (se as portas 80/443 estiverem fechadas, o script falhará)!"
  fi

  warning "Não é possível usar o Let's Encrypt com um endereço IP como hostname! É necessário um FQDN (por exemplo, node01.example.com)."

  echo -e -n "* Deseja configurar o HTTPS automaticamente usando o Let's Encrypt? (s/N): "
  read -r CONFIRM_SSL

  if [[ "$CONFIRM_SSL" =~ [YySs] ]]; then
    CONFIGURE_LETSENCRYPT=true
  fi
}

ask_database_user() {
  echo -n "* Deseja configurar automaticamente um usuário para hosts de banco de dados? (s/N): "
  read -r CONFIRM_DBHOST

  if [[ "$CONFIRM_DBHOST" =~ [YySs] ]]; then
    ask_database_external
    CONFIGURE_DBHOST=true
  fi
}

ask_database_external() {
  echo -n "* Deseja configurar o MySQL para acesso externo? (s/N): "
  read -r CONFIRM_DBEXTERNAL

  if [[ "$CONFIRM_DBEXTERNAL" =~ [YySs] ]]; then
    echo -n "* Informe o endereço do painel (deixe em branco para qualquer endereço): "
    read -r CONFIRM_DBEXTERNAL_HOST
    if [ "$CONFIRM_DBEXTERNAL_HOST" == "" ]; then
      MYSQL_DBHOST_HOST="%"
    else
      MYSQL_DBHOST_HOST="$CONFIRM_DBEXTERNAL_HOST"
    fi
    [ "$CONFIGURE_FIREWALL" == true ] && ask_database_firewall
    return 0
  fi
}

ask_database_firewall() {
  warning "Permitir tráfego de entrada na porta 3306 (MySQL) pode ser um risco de segurança, a menos que você saiba o que está fazendo!"
  echo -n "* Deseja permitir tráfego de entrada na porta 3306? (s/N): "
  read -r CONFIRM_DB_FIREWALL
  if [[ "$CONFIRM_DB_FIREWALL" =~ [YySs] ]]; then
    CONFIGURE_DB_FIREWALL=true
  fi
}

# ----------- Installation functions ----------- #
enable_services() {
  [ "$INSTALL_MARIADB" == true ] && systemctl enable mariadb
  [ "$INSTALL_MARIADB" == true ] && systemctl start mariadb
  systemctl start docker
  systemctl enable docker
}

dep_install() {
  output "Instalando dependências para $OS $OS_VER .."

  [ "$CONFIGURE_FIREWALL" == true ] && install_firewall && firewall_ports

  case "$OS" in
  debian | ubuntu)
    install_packages "ca-certificates gnupg lsb-release"

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    ;;

  almalinux | rocky)
    install_packages "dnf-utils"
    dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "epel-release"

    install_packages "device-mapper-persistent-data lvm2"
    ;;
  esac

  # Update the new repos
  update_repos

  # Install dependencies
  install_packages "docker-ce docker-ce-cli containerd.io"

  # Install MariaDB if needed
  [ "$INSTALL_MARIADB" == true ] && install_packages "mariadb-server"
  [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot"

  enable_services

  success "Dependências instaladas!"
}

ptdl_dl() {
  echo "* Baixando o Pelican Wings.. "

  mkdir -p /etc/pelican /var/run/wings
  curl -fsSL --retry 5 --retry-all-errors --speed-limit 1024 --speed-time 30 -o /usr/local/bin/wings "$WINGS_DL_URL$ARCH"

  chmod u+x /usr/local/bin/wings

  success "Pelican Wings baixado com sucesso"
}

systemd_file() {
  output "Instalando o serviço systemd .."

  curl -fsSL -o /etc/systemd/system/wings.service "$GIT_REPO_URL"/configs/wings.service
  systemctl daemon-reload
  systemctl enable wings

  success "Serviço systemd instalado!"
}

firewall_ports() {
  output "Abrindo as portas 22 (SSH), 8080 (porta do Wings) e 2022 (porta SFTP do Wings)"

  [ "$CONFIGURE_LETSENCRYPT" == true ] && firewall_allow_ports "80 443"
  [ "$CONFIGURE_DB_FIREWALL" == true ] && firewall_allow_ports "3306"

  firewall_allow_ports "22 8080 2022"

  success "Portas do firewall abertas!"
}

letsencrypt() {
  FAILED=false

  output "Configurando o Let's Encrypt .."

  # If user has nginx
  systemctl stop nginx || true

  # Obtain certificate
  certbot certonly --no-eff-email --email "$EMAIL" --standalone -d "$HOSTNAME" || FAILED=true

  systemctl start nginx || true

  # Check if it succeded
  if [ ! -d "/etc/letsencrypt/live/$HOSTNAME/" ] || [ "$FAILED" == true ]; then
    warning "Falha ao obter o certificado do Let's Encrypt!"
  else
    success "Certificado do Let's Encrypt obtido com sucesso!"
  fi
}

configure_mysql() {
  output "Configurando o MySQL.."

  create_db_user "$MYSQL_DBHOST_USER" "$MYSQL_DBHOST_PASSWORD" "$MYSQL_DBHOST_HOST"
  grant_all_privileges "*" "$MYSQL_DBHOST_USER" "$MYSQL_DBHOST_HOST"

  if [ "$MYSQL_DBHOST_HOST" != "127.0.0.1" ]; then
    echo "* Alterando o endereço de bind do MySQL .."

    case "$OS" in
    debian | ubuntu)
      sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/mariadb.conf.d/50-server.cnf
      ;;
    almalinux | rocky)
      sed -i 's/^#bind-address=0.0.0.0$/bind-address=0.0.0.0/' /etc/my.cnf.d/mariadb-server.cnf
      ;;
    esac

    systemctl restart mariadb
  fi

  success "MySQL configurado!"
}

perform_install() {
  output "Instalando o Pelican Wings .."
  dep_install
  ptdl_dl
  systemd_file
  [ "$CONFIGURE_DBHOST" == true ] && configure_mysql
  [ "$CONFIGURE_LETSENCRYPT" == true ] && letsencrypt

  return 0
}

# --------------- Main functions --------------- #
main() {
  # Check for existing installation
  if [ -f "/usr/local/bin/wings" ]; then
    warning "O script detectou que você já tem o Wings instalado neste sistema! Não é possível executar o script várias vezes, ele falhará!"
    echo -e -n "* Tem certeza de que deseja continuar? (s/N): "
    read -r CONFIRM_PROCEED || true
    if [[ ! "$CONFIRM_PROCEED" =~ [YySs] ]]; then
      error "Instalação cancelada!"
      exit 1
    fi
  fi

  welcome "wings"

  check_virt
  install_docker_kernel_modules

  echo "* "
  echo "* O instalador instalará o Docker, as dependências necessárias do Wings"
  echo "* e o próprio Wings. Mesmo assim, ainda é necessário criar o node"
  echo "* no painel e depois colocar o arquivo de configuração no node manualmente, após"
  echo "* o fim da instalação. Saiba mais sobre esse processo na"
  echo "* documentação oficial: $(hyperlink 'https://pelican.dev/docs/wings/install#configure')"
  echo "* "
  echo -e "* ${COLOR_RED}Nota${COLOR_NC}: este script não iniciará o Wings automaticamente (ele instala o serviço systemd, mas não o inicia)."
  echo -e "* ${COLOR_RED}Nota${COLOR_NC}: este script não ativará o swap (para o Docker)."
  print_brake 42

  ask_firewall CONFIGURE_FIREWALL

  ask_database_user

  if [ "$CONFIGURE_DBHOST" == true ]; then
    type mysql >/dev/null 2>&1 && HAS_MYSQL=true || HAS_MYSQL=false

    if [ "$HAS_MYSQL" == false ]; then
      INSTALL_MARIADB=true
    fi

    MYSQL_DBHOST_USER="pelicanuser"
    MYSQL_DBHOST_PASSWORD="$(gen_passwd 64)"
  fi

  ask_letsencrypt

  if [ "$CONFIGURE_LETSENCRYPT" == true ]; then
    while [ "$CONFIGURE_LETSENCRYPT" == true ] && [ -z "$HOSTNAME" ]; do
      echo -n "* Defina o FQDN a ser usado no Let's Encrypt (node.example.com): "
      read -r HOSTNAME

      ASK=false

      [ -z "$HOSTNAME" ] && error "O FQDN não pode estar vazio"                                                            # Check if FQDN is empty
      bash <(curl -fsSL "$GIT_REPO_URL"/lib/fqdn.sh) "$HOSTNAME" || ASK=true                                 # Check if FQDN is valid
      [ -d "/etc/letsencrypt/live/$HOSTNAME/" ] && error "Já existe um certificado para este FQDN!" && ASK=true # Check if cert exists

      [ "$ASK" == true ] && HOSTNAME=""
      [ "$ASK" == true ] && echo -e -n "* Ainda deseja configurar o HTTPS automaticamente usando o Let's Encrypt? (s/N): "
      [ "$ASK" == true ] && read -r CONFIRM_SSL

      if [[ ! "$CONFIRM_SSL" =~ [YySs] ]] && [ "$ASK" == true ]; then
        CONFIGURE_LETSENCRYPT=false
        HOSTNAME=""
      fi
    done
  fi

  if [ "$CONFIGURE_LETSENCRYPT" == true ]; then
    # Email
    while ! valid_email "$EMAIL"; do
      echo -n "* Informe o endereço de e-mail para o Let's Encrypt: "
      read -r EMAIL

      valid_email "$EMAIL" || error "O e-mail não pode estar vazio nem ser inválido"
    done
  fi

  echo -n "* Deseja continuar com a instalação? (s/N): "

  read -r CONFIRM
  if [[ "$CONFIRM" =~ [YySs] ]]; then
    # Firewall
    CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-false}"

    # TLS Cert
    CONFIGURE_LETSENCRYPT="${CONFIGURE_LETSENCRYPT:-false}"
    EMAIL="${EMAIL:-}"

    # Database
    INSTALL_MARIADB="${INSTALL_MARIADB:-false}"
    CONFIGURE_DBHOST="${CONFIGURE_DBHOST:-false}"
    CONFIGURE_DB_FIREWALL="${CONFIGURE_DB_FIREWALL:-false}"
    MYSQL_DBHOST_HOST="${MYSQL_DBHOST_HOST:-127.0.0.1}"
    MYSQL_DBHOST_USER="${MYSQL_DBHOST_USER:-pelicanuser}"
    MYSQL_DBHOST_PASSWORD="${MYSQL_DBHOST_PASSWORD:-}"

    if [[ $CONFIGURE_DBHOST == true && -z "${MYSQL_DBHOST_PASSWORD}" ]]; then
      error "A senha do usuário do host de banco de dados MySQL é obrigatória"
      exit 1
    fi

    # ---------------- Installation ---------------- #
    perform_install
  else
    error "Instalação cancelada."
    exit 1
  fi
}

function goodbye {
  echo ""
  print_brake 70
  echo "* Instalação do Wings concluída"
  echo "*"
  echo "* Para continuar, você precisa configurar o Wings para funcionar com o seu painel"
  echo "* Consulte o guia oficial: $(hyperlink 'https://pelican.dev/docs/wings/install#configure')"
  echo "* "
  echo "* Você pode copiar manualmente o arquivo de configuração do painel para /etc/pelican/config.yml"
  echo "* ou usar o botão \"auto deploy\" do painel e simplesmente colar o comando neste terminal"
  echo "* "
  echo "* Depois, você pode iniciar o Wings manualmente para verificar se está funcionando"
  echo "*"
  echo "* sudo wings"
  echo "*"
  echo "* Depois de verificar que está funcionando, use CTRL+C e inicie o Wings como serviço (executa em segundo plano)"
  echo "*"
  echo "* systemctl start wings"
  echo "*"
  echo -e "* ${COLOR_RED}Nota${COLOR_NC}: Recomenda-se ativar o swap (para o Docker; saiba mais na documentação oficial)."
  [ "$CONFIGURE_FIREWALL" == false ] && echo -e "* ${COLOR_RED}Nota${COLOR_NC}: Se você não configurou o firewall, as portas 8080 e 2022 precisam estar abertas."
  print_brake 70
  echo ""
}

# Run script
main
goodbye
