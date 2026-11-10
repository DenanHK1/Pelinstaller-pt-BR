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
# Domain name / IP
export HOSTNAME=""

# Default MySQL credentials
export MYSQL_DB=""
export MYSQL_USER=""
export MYSQL_PASSWORD=""

# Environment
export email=""

# Initial admin account
export user_email=""
export user_username=""
export user_firstname=""
export user_lastname=""
export user_password=""

# Assume SSL, will fetch different config if true
export ASSUME_SSL=false
export CONFIGURE_LETSENCRYPT=false

# Firewall
export CONFIGURE_FIREWALL=false

# ------------ User input functions ------------ #
ask_letsencrypt() {
  if [ "$CONFIGURE_FIREWALL" == false ]; then
    warning "O Let's Encrypt exige que as portas 80/443 estejam abertas! Você optou por não configurar o firewall automaticamente; use por sua conta e risco (se as portas 80/443 estiverem fechadas, o script falhará)!"
  fi

  echo -e -n "* Deseja configurar o HTTPS automaticamente usando o Let's Encrypt? (s/N): "
  read -r CONFIRM_SSL

  if [[ "$CONFIRM_SSL" =~ [YySs] ]]; then
    CONFIGURE_LETSENCRYPT=true
    ASSUME_SSL=false
  fi
}

ask_assume_ssl() {
  output "O Let's Encrypt não será configurado automaticamente por este script (o usuário optou por não usar)."
  output "Você pode 'assumir' o Let's Encrypt: o script baixará uma configuração do nginx preparada para usar um certificado do Let's Encrypt, mas não obterá o certificado para você."
  output "Se você assumir o SSL e não obtiver o certificado, a instalação não funcionará."
  echo -n "* Assumir o SSL? (s/N): "
  read -r ASSUME_SSL_INPUT

  [[ "$ASSUME_SSL_INPUT" =~ [YySs] ]] && ASSUME_SSL=true
  true
}

check_FQDN_SSL() {
  if [[ $(invalid_ip "$HOSTNAME") == 1 && $HOSTNAME != 'localhost' ]]; then
    SSL_AVAILABLE=true
  else
    warning "* O Let's Encrypt não está disponível para endereços IP."
    output "Para usar o Let's Encrypt, você precisa usar um nome de domínio válido."
  fi
}

# --------- Main installation functions -------- #
install_composer() {
  output "Instalando o composer .."
  curl -fsS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
  success "Composer instalado!"
}

ptdl_dl() {
  output "Baixando os arquivos do Pelican Panel .. "
  mkdir -p /var/www/pelican/storage/framework/cache/data/{9c,9c/a8,8a,8a/69}
  cd /var/www/pelican || exit

  curl -fL --retry 5 --retry-all-errors --speed-limit 1024 --speed-time 30 -o panel.tar.gz "$PANEL_DL_URL"
  tar -xzvf panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/

  cp .env.example .env

  success "Arquivos do Pelican Panel baixados!"
}

install_composer_deps() {
  output "Instalando as dependências do composer .."
  [ "$OS" == "rocky" ] || [ "$OS" == "almalinux" ] && export PATH=/usr/local/bin:$PATH
  local attempt
  for attempt in 1 2 3; do
    COMPOSER_ALLOW_SUPERUSER=1 timeout 600 composer install --no-dev --optimize-autoloader && break
    [ "$attempt" == 3 ] && error "Falha no composer install" && exit 1
    warning "O composer install falhou ou travou, tentando novamente .."
  done
  success "Dependências do composer instaladas!"
}

# Configure environment
configure() {
  output "Configurando o ambiente .."

  local app_url="http://$HOSTNAME"
  [ "$ASSUME_SSL" == true ] && app_url="https://$HOSTNAME"
  [ "$CONFIGURE_LETSENCRYPT" == true ] && app_url="https://$HOSTNAME"

  # Generate encryption key
  php artisan key:generate --force

  # Fill in environment:setup automatically
  php artisan p:environment:setup -n --url="$app_url"
  sed -i "s|^APP_INSTALLED=false|APP_INSTALLED=true|" .env

  # Fill in environment:database credentials automatically
  yes | php artisan p:environment:database \
    --driver="mysql" \
    --host="127.0.0.1" \
    --port="3306" \
    --database="$MYSQL_DB" \
    --username="$MYSQL_USER" \
    --password="$MYSQL_PASSWORD"

  # Configure database
  php artisan migrate --seed --force

  # Create user account
  php artisan p:user:make \
    --email="$user_email" \
    --username="$user_username" \
    --password="$user_password" \
    --admin=1

  success "Ambiente configurado!"
}

# Set proper directory permissions for distro
set_folder_permissions() {
  # Assign directory user
  case "$OS" in
  debian | ubuntu)
    chown -R www-data:www-data ./
    ;;
  almalinux | rocky)
    chown -R nginx:nginx ./
    ;;
  esac
}

insert_cronjob() {
  output "Instalando o cronjob.. "

  local web_user
  case "$OS" in
  debian | ubuntu)
    web_user="www-data"
    ;;
  almalinux | rocky)
    web_user="nginx"
    ;;
  esac

  (crontab -u "$web_user" -l 2>/dev/null || true) | {
    cat
    echo "* * * * * php /var/www/pelican/artisan schedule:run >> /dev/null 2>&1"
  } | crontab -u "$web_user" -

  success "Cronjob instalado!"
}

install_pelican_queue() {
  output "Instalando o serviço pelican-queue .."

  local web_user
  case "$OS" in
  debian | ubuntu)
    web_user="www-data"
    ;;
  almalinux | rocky)
    web_user="nginx"
    ;;
  esac

  php /var/www/pelican/artisan p:environment:queue-service --user="$web_user" --group="$web_user" --overwrite -n

  systemctl daemon-reload
  systemctl enable pelican-queue.service
  systemctl start pelican-queue

  success "pelican-queue instalado!"
}

# -------- OS specific install functions ------- #
enable_services() {
  case "$OS" in
  debian | ubuntu)
    systemctl enable redis-server
    systemctl start redis-server
    ;;
  almalinux | rocky)
    systemctl enable "$REDIS_PACKAGE"
    systemctl start "$REDIS_PACKAGE"
    ;;
  esac
  systemctl enable nginx
  systemctl enable mariadb
  systemctl start mariadb
}

selinux_allow() {
  setsebool -P httpd_can_network_connect 1 || true # these commands can fail OK
  setsebool -P httpd_execmem 1 || true
  setsebool -P httpd_unified 1 || true
}

php_fpm_conf() {
  curl -o /etc/php-fpm.d/www-pelican.conf "$GIT_REPO_URL"/configs/www-pelican.conf

  systemctl enable php-fpm
  systemctl restart php-fpm
}

ubuntu_dep() {
  # Install deps for adding repos
  install_packages "software-properties-common apt-transport-https ca-certificates gnupg"

  # Add Ubuntu universe repo
  add-apt-repository universe -y

  # Add PHP PPA
  if curl -fsSL "https://ppa.launchpadcontent.net/ondrej/php/ubuntu/dists/${UBUNTU_CODENAME}/Release" >/dev/null; then
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
  else
    warning "O PPA Ondrej PHP não suporta ${UBUNTU_CODENAME}; usando os pacotes do Ubuntu."
  fi
}

debian_dep() {
  # Install deps for adding repos
  install_packages "dirmngr ca-certificates apt-transport-https lsb-release"

  # Install PHP 8.5 using sury's repo
  curl -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
  echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
}

alma_rocky_dep() {
  # SELinux tools
  install_packages "policycoreutils selinux-policy selinux-policy-targeted \
    setroubleshoot-server setools setools-console mcstrans"

  # Add remi repo
  install_packages "epel-release dnf-plugins-core https://rpms.remirepo.net/enterprise/remi-release-$OS_VER_MAJOR.rpm"
  if [ "$OS_VER_MAJOR" -ge 9 ]; then
    dnf config-manager --set-enabled crb
  fi
  dnf module enable -y php:remi-8.5
}

dep_install() {
  output "Instalando dependências para $OS $OS_VER .."

  # Update repos before installing
  update_repos

  [ "$CONFIGURE_FIREWALL" == true ] && install_firewall && firewall_ports

  case "$OS" in
  debian | ubuntu)
    [ "$OS" == "ubuntu" ] && ubuntu_dep
    [ "$OS" == "debian" ] && debian_dep

    update_repos

    # Install dependencies
    install_packages "php8.5 php8.5-{cli,common,gd,intl,sqlite3,mysql,mbstring,bcmath,xml,fpm,curl,zip} \
      mariadb-common mariadb-server mariadb-client \
      nginx \
      redis-server \
      zip unzip tar \
      git cron"

    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot python3-certbot-nginx"

    ;;
  almalinux | rocky)
    alma_rocky_dep

    # Install dependencies
    install_packages "php php-{common,fpm,cli,json,intl,mysqlnd,mcrypt,gd,mbstring,pdo,zip,bcmath,dom,opcache,posix} \
      mariadb mariadb-server \
      nginx \
      $REDIS_PACKAGE \
      zip unzip tar \
      git cronie"

    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot python3-certbot-nginx"

    # Allow nginx
    selinux_allow

    # Create config for PHP FPM
    php_fpm_conf
    ;;
  esac

  enable_services

  success "Dependências instaladas!"
}

# --------------- Other functions -------------- #
firewall_ports() {
  output "Abrindo as portas: 22 (SSH), 80 (HTTP) e 443 (HTTPS)"

  firewall_allow_ports "22 80 443"

  success "Portas do firewall abertas!"
}

letsencrypt() {
  FAILED=false

  output "Configurando o Let's Encrypt .."

  # Obtain certificate
  certbot --nginx --redirect --no-eff-email --email "$email" -d "$HOSTNAME" || FAILED=true

  # Check if it succeded
  if [ ! -d "/etc/letsencrypt/live/$HOSTNAME/" ] || [ "$FAILED" == true ]; then
    warning "Falha ao obter o certificado do Let's Encrypt!"
    echo -n "* Assumir o SSL mesmo assim? (s/N): "
    read -r CONFIGURE_SSL

    if [[ "$CONFIGURE_SSL" =~ [YySs] ]]; then
      ASSUME_SSL=true
      CONFIGURE_LETSENCRYPT=false
      configure_nginx
    else
      ASSUME_SSL=false
      CONFIGURE_LETSENCRYPT=false
    fi
  else
    success "Certificado do Let's Encrypt obtido com sucesso!"
  fi
}

# ------ Webserver configuration functions ----- #
configure_nginx() {
  output "Configurando o nginx .."

  if [ "$ASSUME_SSL" == true ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then
    DL_FILE="nginx_ssl.conf"
  else
    DL_FILE="nginx.conf"
  fi

  case "$OS" in
  debian | ubuntu)
    PHP_SOCKET="/run/php/php8.5-fpm.sock"
    CONFIG_PATH_AVAIL="/etc/nginx/sites-available"
    CONFIG_PATH_ENABL="/etc/nginx/sites-enabled"
    ;;
  almalinux | rocky)
    PHP_SOCKET="/var/run/php-fpm/pelican.sock"
    CONFIG_PATH_AVAIL="/etc/nginx/conf.d"
    CONFIG_PATH_ENABL="$CONFIG_PATH_AVAIL"
    ;;
  esac

  rm -rf "$CONFIG_PATH_ENABL"/default

  curl -o "$CONFIG_PATH_AVAIL"/pelican.conf "$GIT_REPO_URL"/configs/$DL_FILE

  sed -i -e "s@<domain>@${HOSTNAME}@g" "$CONFIG_PATH_AVAIL"/pelican.conf

  sed -i -e "s@<php_socket>@${PHP_SOCKET}@g" "$CONFIG_PATH_AVAIL"/pelican.conf

  case "$OS" in
  debian | ubuntu)
    ln -sf "$CONFIG_PATH_AVAIL"/pelican.conf "$CONFIG_PATH_ENABL"/pelican.conf
    ;;
  esac

  if [ "$ASSUME_SSL" == true ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then
    if nginx -t; then
      systemctl restart nginx
    else
      warning "A configuração do Nginx foi gravada, mas não foi recarregada. Instale os arquivos do certificado SSL e reinicie o nginx."
    fi
  else
    nginx -t
    systemctl restart nginx
  fi

  success "Nginx configurado!"
}

# --------------- Main functions --------------- #
perform_install() {
  output "Iniciando a instalação.. isso pode demorar um pouco!"
  dep_install
  install_composer
  ptdl_dl
  install_composer_deps
  create_db_user "$MYSQL_USER" "$MYSQL_PASSWORD"
  create_db "$MYSQL_DB" "$MYSQL_USER"
  configure
  insert_cronjob
  install_pelican_queue
  configure_nginx
  [ "$CONFIGURE_LETSENCRYPT" == true ] && letsencrypt
  set_folder_permissions
  return 0
}

main() {
  # Check for existing installation
  if [ -d "/var/www/pelican" ]; then
    warning "O script detectou que você já tem o painel Pelican instalado neste sistema! Não é possível executar o script várias vezes, ele falhará!"
    echo -e -n "* Tem certeza de que deseja continuar? (s/N): "
    read -r CONFIRM_PROCEED || true
    if [[ ! "$CONFIRM_PROCEED" =~ [YySs] ]]; then
      error "Instalação cancelada!"
      exit 1
    fi
  fi

  welcome "panel"

  check_os_x86_64

  # Set database credentials
  MYSQL_DB="panel"
  MYSQL_USER="pelican"
  MYSQL_PASSWORD="$(gen_passwd 64)"

  email_input email "Informe o endereço de e-mail que será usado para configurar o Let's Encrypt e o Pelican: " "O e-mail não pode estar vazio nem ser inválido"

  # Initial admin account
  user_email="$email"
  user_username="admin"
  password_input user_password "Senha da conta de administrador (deixe em branco para gerar automaticamente): " "" "$(gen_passwd 32)"

  print_brake 72

  # Set FQDN
  while [ -z "$HOSTNAME" ]; do
    echo -n "* FQDN ou IP do painel: "
    read -r HOSTNAME
    [ -z "$HOSTNAME" ] && error "O FQDN não pode estar vazio"
  done

  # Check if SSL is available
  check_FQDN_SSL

  # Ask if firewall is needed
  ask_firewall CONFIGURE_FIREWALL

  # Only ask about SSL if it is available
  if [ "$SSL_AVAILABLE" == true ]; then
    # Ask if letsencrypt is needed
    ask_letsencrypt
    # If it's already true, this should be a no-brainer
    [ "$CONFIGURE_LETSENCRYPT" == false ] && ask_assume_ssl
  fi

  # Verify FQDN if user has selected to assume SSL or configure Let's Encrypt
  [ "$CONFIGURE_LETSENCRYPT" == true ] || [ "$ASSUME_SSL" == true ] && bash <(curl -fsSL "$GIT_REPO_URL"/lib/fqdn.sh) "$HOSTNAME"

  # Summary
  summary

  # Confirm installation
  echo -e -n "\n* Configuração inicial concluída. Deseja continuar com a instalação? (s/N): "
  read -r CONFIRM
  if [[ "$CONFIRM" =~ [YySs] ]]; then
    perform_install
  else
    error "Instalação cancelada."
    exit 1
  fi
}

summary() {
  print_brake 62
  output "Pelican panel $PELICAN_PANEL_VERSION com nginx em $OS"
  output "Nome do banco de dados: $MYSQL_DB"
  output "Usuário do banco de dados: $MYSQL_USER"
  output "Senha do banco de dados: (oculta)"
  output "E-mail: $email"
  output "E-mail do usuário: $user_email"
  output "Nome de usuário: $user_username"
  output "Senha do usuário: (oculta)"
  output "Hostname/FQDN: $HOSTNAME"
  output "Configurar firewall? $CONFIGURE_FIREWALL"
  output "Configurar Let's Encrypt? $CONFIGURE_LETSENCRYPT"
  output "Assumir SSL? $ASSUME_SSL"
  print_brake 62
}

goodbye() {
  print_brake 62
  output "Instalação do painel concluída"
  output ""

  [ "$CONFIGURE_LETSENCRYPT" == true ] && output "Seu painel deve estar acessível em $(hyperlink "$HOSTNAME")"
  [ "$ASSUME_SSL" == true ] && [ "$CONFIGURE_LETSENCRYPT" == false ] && output "Você optou por usar SSL, mas não automaticamente pelo Let's Encrypt. Seu painel não funcionará até que o SSL seja configurado."
  [ "$ASSUME_SSL" == false ] && [ "$CONFIGURE_LETSENCRYPT" == false ] && output "Seu painel deve estar acessível em $(hyperlink "$HOSTNAME")"

  output ""
  output "A instalação está usando nginx em $OS"
  output "Obrigado por usar este script."
  [ "$CONFIGURE_FIREWALL" == false ] && echo -e "* ${COLOR_RED}Nota${COLOR_NC}: Se você não configurou o firewall, as portas 80/443 (HTTP/HTTPS) precisam estar abertas!"
  print_brake 62
}

# Run script
main
goodbye
