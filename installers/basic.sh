#!/bin/bash
# Versão traduzida para português do Brasil. Modificada a partir do Pelinstaller original (GPL-3.0).

# Pelican Installer
# Copyright Matthew Jacob 2021-2026

set -e

# ------------------ Variables ----------------- #
# Path (export everything that is possible, doesn't matter that it exists already)
export PATH="$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

# Download URLs
export PANEL_DL_URL="${PANEL_DL_URL:-https://github.com/pelican/panel/releases/latest/download/panel.tar.gz}"
export WINGS_DL_URL="${WINGS_DL_URL:-https://github.com/pelican/wings/releases/latest/download/wings_linux_}"
export GIT_REPO_URL="${GIT_REPO_URL:-https://raw.githubusercontent.com/${REPO:-Zinidia/Pelinstaller}/${BRANCH:-Production}}"

# Colors
COLOR_YELLOW='\033[1;33m'
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

# Domain name / IP
HOSTNAME="${FQDN:-$(hostname -I | awk '{print $1}')}"

# Default User credentials
MYSQL_PASSWORD=$(head -c 100 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9!"#%&()*+,-./:;<=>?@[\]^_`{|}~' | fold -w 32 | head -n 1)
USER_PASSWORD=$(head -c 100 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | fold -w 32 | head -n 1)

# Database host
MYSQL_DBHOST_HOST="127.0.0.1"
MYSQL_DBHOST_USER="pelicanuser"
MYSQL_DBHOST_PASSWORD="${MYSQL_DBHOST_PASSWORD:-}"

# -------------- Load Lib -------------- #
# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -fsSL "$GIT_REPO_URL"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERRO: Não foi possível carregar o script lib" && exit 1
fi

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

# ------------------ Firewall ------------------ #
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

firewall_ports() {
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

# --------- Main installation functions -------- #
install_composer() {
  output "Instalando o composer .."
  curl -fsS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
  success "Composer instalado!"
}

panel_dl() {
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
configure_env() {
  output "Configurando o ambiente .."

  local app_url="http://$HOSTNAME"

  # Generate encryption key
  php artisan key:generate --force

  # Replace the egg docker images with ForestRacks's optimized images
  for file in /var/www/pelican/database/Seeders/eggs/*/*.json; do
    # Skip when nothing is matched
    [ -e "$file" ] || continue
    # Extract the docker_images field from the file using jq
    docker_images=$(jq -r '.docker_images' "$file")

    # Check if the replacement match exists in the docker_images field
    if echo "$docker_images" | grep -q "ghcr.io/pelican/yolks:java_" || echo "$docker_images" | grep -q "quay.io/pelican/core:rust" || echo "$docker_images" | grep -q "quay.io/pelican/games:source" || echo "$docker_images" | grep -q "ghcr.io/pelican/games:source" || echo "$docker_images" | grep -q "quay.io/parkervcp/pelican-images:debian_source"; then
      # Read the contents of the file into a variable
      contents=$(<"$file")

      # Update the docker_images object using multiple jq filters
      contents=$(echo "$contents" | jq '.docker_images |= map_values(. | gsub("ghcr.io/pelican/yolks:java_"; "ghcr.io/forestracks/java:"))' | jq '.docker_images |= map_values(. | gsub("quay.io/pelican/core:rust"; "ghcr.io/forestracks/games:rust"))' | jq '.docker_images |= map_values(. | gsub("quay.io/pelican/games:source"; "ghcr.io/forestracks/games:steam"))' | jq '.docker_images |= map_values(. | gsub("ghcr.io/pelican/games:source"; "ghcr.io/forestracks/games:steam"))' | jq '.docker_images |= map_values(. | gsub("quay.io/parkervcp/pelican-images:debian_source"; "ghcr.io/forestracks/base:main"))')

      # Replace the forward slashes in the docker_images object using sed
      contents=$(echo "$contents" | sed 's/\//\\\//g')

      # Write the modified contents back to the file
      echo "$contents" > "$file"
    fi
  done

  # Fill in environment:setup automatically
  php artisan p:environment:setup -n --url="$app_url"
  sed -i "s|^APP_INSTALLED=false|APP_INSTALLED=true|" .env

  # Configure database and backup credentials
  yes | php artisan p:environment:database \
    --driver="mysql" \
    --host="127.0.0.1" \
    --port="3306" \
    --database="panel" \
    --username="pelican" \
    --password="$MYSQL_PASSWORD"
  # cp /var/www/pelican/.env /etc/pelican/.env

  # Seed database
  php artisan migrate --seed --force

  # Create user account
  php artisan p:user:make \
    --email="admin@example.com" \
    --username="admin" \
    --password="$USER_PASSWORD" \
    --admin=1

  # Create a node
  php artisan p:node:make -n \
    --name="Node01" \
    --description="First Node" \
    --fqdn="$HOSTNAME" \
    --public=1 \
    --scheme="http" \
    --proxy=0 \
    --maintenance=0 \
    --maxMemory="$(free -m | awk 'FNR == 2 {print $2}')" \
    --overallocateMemory=0 \
    --maxDisk="$(df --total -m | tail -n 1 | awk '{print $2}')" \
    --overallocateDisk=0 \
    --maxCpu=0 \
    --overallocateCpu=0 \
    --uploadSize=10240 \
    --daemonListeningPort=8080 \
    --daemonConnectingPort=8080 \
    --daemonSFTPPort=2022 \
    --daemonBase="/var/lib/pelican/volumes"

  # Fetch wings configuration
  mkdir -p /etc/pelican
  php artisan p:node:configuration 1 >/etc/pelican/config.yml

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

pelican_queue_systemd() {
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

  success "Serviço systemd do pelican-queue instalado!"
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
  setsebool -P httpd_can_network_connect 1 || true # These commands can fail OK
  setsebool -P httpd_execmem 1 || true
  setsebool -P httpd_unified 1 || true
}

php_fpm_conf() {
  curl -f -o /etc/php-fpm.d/www-pelican.conf "$GIT_REPO_URL"/configs/www-pelican.conf

  systemctl enable php-fpm
  systemctl restart php-fpm
}

ubuntu_dep() {
  # Install deps for adding repos
  install_packages "software-properties-common apt-transport-https ca-certificates gnupg jq"

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
  install_packages "dirmngr ca-certificates apt-transport-https lsb-release jq"

  # Install PHP 8.5 using sury's repo
  curl -f -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
  echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
}

alma_rocky_dep() {
  # SELinux tools
  install_packages "policycoreutils selinux-policy selinux-policy-targeted \
    setroubleshoot-server setools setools-console mcstrans jq"

  # Add remi repo
  install_packages "epel-release dnf-plugins-core https://rpms.remirepo.net/enterprise/remi-release-$OS_VER_MAJOR.rpm"
  if [ "$OS_VER_MAJOR" -ge 9 ]; then
    dnf config-manager --set-enabled crb
  fi
  dnf module enable -y php:remi-8.5
}

panel_deps() {
  output "Instalando dependências para $OS $OS_VER .."

  # Update repos before installing
  update_repos

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

    # Allow Nginx
    selinux_allow

    # Create config for PHP FPM
    php_fpm_conf
    ;;
  esac

  enable_services

  success "Dependências instaladas!"
}

# ------ Webserver configuration functions ----- #
configure_nginx() {
  output "Configurando o nginx .."

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
  curl -f -o "$CONFIG_PATH_AVAIL"/pelican.conf "$GIT_REPO_URL"/configs/nginx.conf
  sed -i -e "s@<domain>@${HOSTNAME}@g" "$CONFIG_PATH_AVAIL"/pelican.conf
  sed -i -e "s@<php_socket>@${PHP_SOCKET}@g" "$CONFIG_PATH_AVAIL"/pelican.conf

  case "$OS" in
  debian | ubuntu)
    ln -sf "$CONFIG_PATH_AVAIL"/pelican.conf "$CONFIG_PATH_ENABL"/pelican.conf
    ;;
  esac

  systemctl restart nginx
  success "Nginx configurado!"
}


# --------------- Wings functions --------------- #
wings_deps() {
  output "Instalando dependências para $OS $OS_VER .."

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

    install_packages "device-mapper-persistent-data lvm2"
    ;;
  esac

  # Update the new repos
  update_repos

  # Install dependencies
  install_packages "docker-ce docker-ce-cli containerd.io"

  systemctl start docker
  systemctl enable docker

  success "Dependências instaladas!"
}

wings_dl() {
  echo "* Baixando o Pelican Wings.. "

  mkdir -p /etc/pelican /var/run/wings
  curl -fsSL --retry 5 --retry-all-errors --speed-limit 1024 --speed-time 30 -o /usr/local/bin/wings "$WINGS_DL_URL$ARCH"

  chmod u+x /usr/local/bin/wings

  success "Pelican Wings baixado com sucesso"
}

wings_systemd() {
  output "Instalando o serviço systemd .."

  curl -f -o /etc/systemd/system/wings.service "$GIT_REPO_URL"/configs/wings.service
  systemctl daemon-reload
  systemctl enable wings

  sleep 3
  systemctl start wings

  success "Serviço systemd do wings instalado!"
}

# ------------ Summary ------------ #
summary() {
  print_brake 62
  output "Pelican Panel instalado com sucesso!"
  output "URL do painel: http://$HOSTNAME"
  output "Usuário: admin"
  output "Senha: $USER_PASSWORD"
  print_brake 62
}

# ------------ User inputs ------------ #
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

  welcome "basic"
  check_os_x86_64
  install_docker_kernel_modules

  # --------------- Execute functions --------------- #
  output "Iniciando a instalação do Pelican Panel.. isso pode demorar um pouco!"
  panel_deps
  install_composer
  panel_dl
  install_composer_deps
  create_db_user "pelican" "$MYSQL_PASSWORD"
  create_db "panel" "pelican"
  configure_env
  insert_cronjob
  pelican_queue_systemd
  configure_nginx
  install_firewall
  firewall_ports "22 80 443 8080 2022"
  output "Instalando o Pelican Wings .."
  wings_deps
  wings_dl
  wings_systemd
  set_folder_permissions
  summary
}

# Run script
main
