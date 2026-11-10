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

CHECKIP_URL="https://ip.forestracks.net"
DNS_SERVER="9.9.9.9"

# Exit with error status code if user is not root
if [[ $EUID -ne 0 ]]; then
  echo "* Este script deve ser executado com privilégios de root (sudo)." 1>&2
  exit 1
fi

fail() {
  output "O registro DNS ($dns_record) não corresponde ao IP do seu servidor. Verifique se o FQDN $fqdn aponta para o IP do seu servidor, $ip"
  output "Se você usa o Cloudflare, desative o proxy ou opte por não usar o Let's Encrypt."

  echo -n "* Continuar mesmo assim (sua instalação ficará quebrada se você não souber o que está fazendo)? (s/N): "
  read -r override

  [[ ! "$override" =~ [YySs] ]] && error "FQDN ou registro DNS inválido" && exit 1
  return 0
}

dep_install() {
  update_repos true

  case "$OS" in
  debian | ubuntu)
    install_packages "dnsutils" true
    ;;
  almalinux | rocky)
    install_packages "bind-utils" true
    ;;
  esac

  return 0
}

confirm() {
  output "Este script fará uma requisição HTTPS ao endpoint $CHECKIP_URL"
  output "O serviço oficial de verificação de IP deste script: https://ip.forestracks.net"
  output "- O motivo é verificar se o seu domínio resolve corretamente para o IP deste sistema."
  output "- Os registros das requisições são armazenados por vários dias para mitigação de DDoS."
  output "- As requisições também podem ser registradas pelo Cloudflare e por outros provedores de trânsito."
  output "Se preferir usar outro serviço, altere a variável de ambiente CHECKIP_URL."

  echo -e -n "* Concordo que esta requisição HTTPS seja feita (s/N): "
  read -r confirm
  [[ "$confirm" =~ [YySs] ]] || (error "O usuário não concordou" && false)
}

dns_verify() {
  output "Resolvendo o DNS de $fqdn"
  ip=$(curl -4 -s $CHECKIP_URL)
  dns_record=$(dig +short @$DNS_SERVER "$fqdn" | tail -n1)
  [ "${ip}" != "${dns_record}" ] && fail
  output "DNS verificado!"
}

main() {
  fqdn="$1"
  confirm || exit 1
  dep_install
  dns_verify
  true
}

main "$1" "$2"
