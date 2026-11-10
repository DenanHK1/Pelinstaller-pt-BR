#!/bin/bash
# Versão traduzida para português do Brasil. Modificada a partir do Pelinstaller original (GPL-3.0).

# Pelinstaller
# Copyright Matthew Jacob 2021-2026

set -e

export PATH="$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"
export GIT_REPO_URL="${GIT_REPO_URL:-https://raw.githubusercontent.com/${REPO:-Zinidia/Pelinstaller}/${BRANCH:-Production}}"

# -------------- Load Lib -------------- #
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -fsSL "$GIT_REPO_URL"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERRO: Não foi possível carregar o script lib" && exit 1
fi

check_os_x86_64

# ------------------ Variables ----------------- #
INSTALL_DIR="${INSTALL_DIR:-/opt/pelican}"
COMPOSE_URL="$GIT_REPO_URL/configs/docker-compose.yml"

# Default settings
HOSTNAME="${FQDN:-$(hostname -I | awk '{print $1}')}"
EMAIL="${EMAIL:-admin@example.com}"
USER_PASSWORD="${USER_PASSWORD:-$(gen_passwd 32)}"
APP_URL="${APP_URL:-http://$HOSTNAME}"
LE_EMAIL="${LE_EMAIL:-}"
DB_PASSWORD="${DB_PASSWORD:-$(gen_passwd 64)}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-$(gen_passwd 64)}"
TIMEZONE="${TIMEZONE:-$(cat /etc/timezone 2>/dev/null || echo UTC)}"

# ------------ User input functions ------------ #
collect_input() {
  # Domain name / IP
  local default_ip
  default_ip="$(hostname -I | awk '{print $1}')"

  required_input HOSTNAME "FQDN ou IP do painel [$default_ip]: " "" "$default_ip"

  # IPs / localhost uses http or FQDNs use https
  if [[ "$HOSTNAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$HOSTNAME" == *:* ]] || [ "$HOSTNAME" == "localhost" ]; then
    APP_URL="http://$HOSTNAME"
    CONFIGURE_LETSENCRYPT=false
  else
    APP_URL="https://$HOSTNAME"
    CONFIGURE_LETSENCRYPT=true
  fi

  # Admin account and Let's Encrypt email
  if [ "$CONFIGURE_LETSENCRYPT" == true ]; then
    email_input EMAIL "Informe o endereço de e-mail que será usado para configurar o Let's Encrypt e o Pelican: " "O e-mail não pode estar vazio nem ser inválido"
    LE_EMAIL="$EMAIL"
  else
    required_input EMAIL "E-mail do administrador [admin@example.com]: " "" "admin@example.com"
    LE_EMAIL=""
  fi

  password_input USER_PASSWORD "Senha da conta de administrador (deixe em branco para gerar automaticamente): " "" "$(gen_passwd 32)"
}

# ------------------ Docker engine ------------------ #
install_docker() {
  install_docker_kernel_modules
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    success "Docker já instalado"
    return
  fi
  output "Instalando o Docker Engine .."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
  success "Docker instalado"
}

# ------------------ Compose file ------------------ #
write_compose() {
  output "Gravando o arquivo docker compose em $INSTALL_DIR .."
  mkdir -p "$INSTALL_DIR"
  curl -fsSL -o "$INSTALL_DIR/docker-compose.yml" "$COMPOSE_URL"

  sed -i \
    -e "s|<app_url>|$APP_URL|g" \
    -e "s|<le_email>|$LE_EMAIL|g" \
    -e "s|<timezone>|$TIMEZONE|g" \
    -e "s|<db_password>|$DB_PASSWORD|g" \
    -e "s|<db_root_password>|$DB_ROOT_PASSWORD|g" \
    "$INSTALL_DIR/docker-compose.yml"

  success "Arquivo compose gravado"
}

# ------------------ Bring the stack up ------------------ #
compose_up() {
  DC="docker compose"
  docker compose version >/dev/null 2>&1 || DC="docker-compose"

  cd "$INSTALL_DIR" || exit 1
  output "Baixando as imagens .."
  $DC pull
  output "Iniciando os contêineres .."
  $DC up -d
}

# ------------------ Migrate + admin user ------------------ #
configure_panel() {
  output "Aguardando o painel e o banco de dados terminarem de ser configurados .."
  local ready=false
  for _ in $(seq 1 60); do
    if $DC exec -T panel php artisan p:user:make \
        --email="$EMAIL" \
        --username="admin" \
        --password="$USER_PASSWORD" \
        --admin=1 >/dev/null 2>&1; then
      ready=true
      break
    fi
    sleep 5
  done

  if [ "$ready" != true ]; then
    error "O painel não foi configurado a tempo. Verifique os logs com 'cd $INSTALL_DIR && $DC logs panel'."
    exit 1
  fi

  success "Painel configurado"
}

# ------------------ Firewall ------------------ #
open_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    ufw allow 80 >/dev/null 2>&1 || true
    ufw allow 443 >/dev/null 2>&1 || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --zone=public --add-port=80/tcp --permanent >/dev/null 2>&1 || true
    firewall-cmd --zone=public --add-port=443/tcp --permanent >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi
}

# ------------------ Run ------------------ #
main() {
  # Check for existing installation
  if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    warning "Uma instalação existente foi encontrada em $INSTALL_DIR. Continuar a sobrescreverá."
    echo -e -n "* Tem certeza de que deseja continuar? (s/N): "
    read -r CONFIRM_PROCEED || true
    if [[ ! "$CONFIRM_PROCEED" =~ [YySs] ]]; then
      error "Instalação cancelada!"
      exit 1
    fi
  fi

  welcome "panel"
  collect_input

  export INSTALL_DIR HOSTNAME EMAIL USER_PASSWORD APP_URL LE_EMAIL

  # Confirm installation
  echo -e -n "\n* Configuração inicial concluída. Deseja continuar com a instalação? (s/N): "
  read -r CONFIRM || true
  if [[ "$CONFIRM" =~ [YySs] ]]; then
    output "Iniciando a instalação do Pelican Panel via Docker .."
    install_docker
    write_compose
    compose_up
    configure_panel
    open_firewall

    success "Instalação do Pelican Panel concluída. URL: $APP_URL"
  else
    error "Instalação cancelada."
    exit 1
  fi

  summary
}

summary() {
  print_brake 62
  output "Pelican Panel instalado com sucesso!"
  output "URL do painel: $APP_URL"
  output "Usuário: admin"
  output "E-mail: $EMAIL"
  output "Senha: $USER_PASSWORD"
  output ""
  output "Gerencie com: cd $INSTALL_DIR && docker compose [ps|logs|restart|down]"
  print_brake 62
}

# Run script
main
