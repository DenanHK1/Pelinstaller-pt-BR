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
export RM_PANEL=false
export RM_WINGS=false

# ---------- Uninstallation functions ---------- #
rm_panel_files() {
  output "Removendo os arquivos do painel .."
  rm -rf /var/www/pelican /usr/local/bin/composer
  case "$OS" in
  debian | ubuntu)
    rm -f /etc/nginx/sites-enabled/pelican.conf
    rm -f /etc/nginx/sites-available/pelican.conf
    [ -e /etc/nginx/sites-available/default ] && ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    ;;
  almalinux | rocky)
    rm -f /etc/nginx/conf.d/pelican.conf
    ;;
  esac
  systemctl restart nginx
  success "Arquivos do painel removidos."
}

rm_docker_containers() {
  output "Removendo contêineres e imagens do Docker .."

  docker system prune -a -f

  success "Contêineres e imagens do Docker removidos."
}

rm_wings_files() {
  output "Removendo os arquivos do wings .."

  # Stop and remove wings service
  systemctl disable --now wings || true
  rm -rf /etc/systemd/system/wings.service

  rm -rf /etc/pelican /usr/local/bin/wings /var/lib/pelican
  success "Arquivos do wings removidos."
}

rm_services() {
  output "Removendo os serviços .."
  systemctl disable --now pelican-queue || true
  rm -rf /etc/systemd/system/pelican-queue.service
  case "$OS" in
  debian | ubuntu)
    systemctl disable --now redis-server || true
    ;;
  almalinux | rocky)
    systemctl disable --now "$REDIS_PACKAGE" || true
    systemctl disable --now php-fpm || true
    rm -rf /etc/php-fpm.d/www-pelican.conf
    ;;
  esac
  success "Serviços removidos."
}

rm_cron() {
  output "Removendo os cron jobs .."
  local web_user=www-data
  [[ "$OS" =~ ^(rocky|almalinux)$ ]] && web_user=nginx
  (crontab -u "$web_user" -l 2>/dev/null || true) | grep -vF "/var/www/pelican/artisan schedule:run" | crontab -u "$web_user" -
  success "Cron jobs removidos."
}

rm_database() {
  output "Removendo o banco de dados .."
  valid_db=$(mariadb -u root -e "SELECT schema_name FROM information_schema.schemata;" | grep -v -E -- 'schema_name|information_schema|performance_schema|mysql' || true)
  warning "Cuidado! Este banco de dados será apagado!"
  if [[ "$valid_db" == *"panel"* ]]; then
    echo -n "* Foi detectado um banco de dados chamado panel. Ele é o banco de dados do Pelican? (s/N): "
    read -r is_panel
    if [[ "$is_panel" =~ [YySs] ]]; then
      DATABASE=panel
    else
      print_list "$valid_db"
    fi
  else
    print_list "$valid_db"
  fi
  while [ -z "$DATABASE" ] || [[ $valid_db != *"$database_input"* ]]; do
    echo -n "* Escolha o banco de dados do painel (para pular, não digite nada): "
    read -r database_input
    if [[ -n "$database_input" ]]; then
      DATABASE="$database_input"
    else
      break
    fi
  done
  [[ -n "$DATABASE" ]] && mariadb -u root -e "DROP DATABASE $DATABASE;"
  # Exclude usernames User and root (Hope no one uses username User)
  output "Removendo o usuário do banco de dados .."
  valid_users=$(mariadb -u root -e "SELECT user FROM mysql.user;" | grep -v -E -- 'user|root' || true)
  warning "Cuidado! Este usuário será apagado!"
  if [[ "$valid_users" == *"pelican"* ]]; then
    echo -n "* Foi detectado um usuário chamado pelican. Ele é o usuário do pelican? (s/N): "
    read -r is_user
    if [[ "$is_user" =~ [YySs] ]]; then
      DB_USER=pelican
    else
      print_list "$valid_users"
    fi
  else
    print_list "$valid_users"
  fi
  while [ -z "$DB_USER" ] || [[ $valid_users != *"$user_input"* ]]; do
    echo -n "* Escolha o usuário do painel (para pular, não digite nada): "
    read -r user_input
    if [[ -n "$user_input" ]]; then
      DB_USER=$user_input
    else
      break
    fi
  done
  [[ -n "$DB_USER" ]] && mariadb -u root -e "DROP USER $DB_USER@'127.0.0.1';"
  mariadb -u root -e "FLUSH PRIVILEGES;"
  success "Banco de dados e usuário do banco de dados removidos."
}

# --------------- Main functions --------------- #
perform_uninstall() {
  [ "$RM_PANEL" == true ] && rm_panel_files
  [ "$RM_PANEL" == true ] && rm_cron
  [ "$RM_PANEL" == true ] && rm_database
  [ "$RM_PANEL" == true ] && rm_services
  [ "$RM_WINGS" == true ] && rm_docker_containers
  [ "$RM_WINGS" == true ] && rm_wings_files

  return 0
}

# ------------------ Uninstall ----------------- #
main() {
  welcome ""

  # Check for existing installation
  if [ -d "/var/www/pelican" ]; then
    output "Foi detectada uma instalação do painel."
    echo -e -n "* Deseja remover o painel? (s/N): "
    read -r RM_PANEL_INPUT
    [[ "$RM_PANEL_INPUT" =~ [YySs] ]] && RM_PANEL=true
  fi

  if [ -d "/etc/pelican" ]; then
    output "Foi detectada uma instalação do Wings."
    warning "Isso removerá todos os servidores!"
    echo -e -n "* Deseja remover o Wings (daemon)? (s/N): "
    read -r RM_WINGS_INPUT
    [[ "$RM_WINGS_INPUT" =~ [YySs] ]] && RM_WINGS=true
  fi

  if [ "$RM_PANEL" == false ] && [ "$RM_WINGS" == false ]; then
    error "Nada para desinstalar!"
    exit 1
  fi

  summary

  # Confirm uninstallation
  echo -e -n "* Deseja continuar com a desinstalação? (s/N): "
  read -r CONFIRM
  if [[ "$CONFIRM" =~ [YySs] ]]; then
    perform_uninstall
  else
    error "Desinstalação cancelada."
    exit 1
  fi
}

summary() {
  print_brake 30
  output "Desinstalar o painel? $RM_PANEL"
  output "Desinstalar o wings? $RM_WINGS"
  print_brake 30
}

goodbye() {
  print_brake 62
  [ "$RM_PANEL" == true ] && output "Desinstalação do painel concluída"
  [ "$RM_WINGS" == true ] && output "Desinstalação do wings concluída"
  output "Obrigado por usar este script."
  print_brake 62
}

main
goodbye
