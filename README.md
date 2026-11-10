# Pelinstaller (português do Brasil)

[![License: GPL v3](https://img.shields.io/github/license/Zinidia/Pelinstaller)](LICENSE.md)

> **Sobre esta tradução:** esta é uma versão em português do Brasil do [Pelinstaller](https://github.com/Zinidia/Pelinstaller), de Matthew Jacob e colaboradores, distribuída sob a mesma licença (GPL-3.0). Apenas os textos exibidos na tela foram traduzidos; a lógica do instalador não foi alterada, com uma exceção: as perguntas de sim/não agora aparecem como `(s/N)` e aceitam **s** ou **y** como "sim". Este projeto não tem relação com o projeto oficial do Pelican.

## Instalação

1) Para começar, é importante que a máquina esteja recém-instalada, caso você tenha feito alguma alteração nela antes.
2) Aponte um registro DNS do tipo A para o IP da sua máquina, por exemplo panel.example.com para 192.168.53.72.
3) Para baixar e executar o instalador, digite o comando abaixo no terminal e siga as instruções:

```bash
bash <(curl -Ss https://raw.githubusercontent.com/DenanHK1/Pelinstaller-pt-BR/Production/install.sh || wget -O - https://raw.githubusercontent.com/DenanHK1/Pelinstaller/Production/install.sh)
```


_Nota: em alguns sistemas é necessário já estar logado como root antes de executar o comando em uma linha (usar `sudo` na frente do comando não funciona)._

⚠️ Solução de problemas: se você tiver qualquer problema durante a instalação ou ao usar o Pelican, primeiro verifique os logs do Pelican e consulte o [Guia oficial de solução de problemas do Pelican](https://pelican.dev/docs/troubleshooting/). Se ainda não conseguir resolver, abra uma issue no [repositório do PelInstaller no GitHub](https://github.com/Zinidia/Pelinstaller) e compartilhe os logs relevantes.

Este [vídeo no YouTube](https://www.youtube.com/watch?v=E8UJhyUFoHM) (em inglês) mostra o processo de instalação.

## Recursos

- Instalação automática do Pelican Panel (dependências, banco de dados, cronjob, nginx).
- Instalação automática do Pelican Wings (Docker, systemd).
- Painel: configuração automática (opcional) do Let's Encrypt.
- Painel: configuração automática (opcional) do firewall.
- Suporte à desinstalação do painel e do wings.

## Ajuda e suporte

Para ajuda e suporte sobre o script em si, e **não sobre o projeto oficial do Pelican**, crie uma [issue no GitHub](https://github.com/Zinidia/Pelinstaller/issues). Dúvidas específicas desta tradução devem ir para o repositório onde ela foi publicada.

## Instalações suportadas

Lista das configurações suportadas para o painel e o Wings (instalações suportadas por este script).

### Sistemas operacionais suportados para o painel e o wings

| Sistema operacional | Versão | Suportado          | Versão do PHP |
| ------------------- | ------ | ------------------ | ------------- |
| Ubuntu              | 22.04  | :white_check_mark: | 8.5           |
|                     | 24.04  | :white_check_mark: | 8.5           |
|                     | 26.04  | :white_check_mark: | 8.5           |
| Debian              | 11     | :white_check_mark: | 8.5           |
|                     | 12     | :white_check_mark: | 8.5           |
|                     | 13     | :white_check_mark: | 8.5           |
| Rocky Linux         | 8      | :white_check_mark: | 8.5           |
|                     | 9      | :white_check_mark: | 8.5           |
|                     | 10     | :white_check_mark: | 8.5           |
| AlmaLinux           | 8      | :white_check_mark: | 8.5           |
|                     | 9      | :white_check_mark: | 8.5           |
|                     | 10     | :white_check_mark: | 8.5           |

_\* Indica um sistema operacional e uma versão que já foram suportados por este script._

## Configuração do firewall

Os scripts de instalação podem instalar e configurar um firewall para você. O script vai perguntar se você quer isso ou não. É altamente recomendado aceitar a configuração automática do firewall.

## Publicando a sua versão

O instalador baixa os próprios arquivos (`lib/lib.sh`, `installers/*.sh` e `configs/*`) do GitHub durante a execução. Por isso, para que a versão traduzida seja a que roda, você precisa publicá-la em um repositório seu (por exemplo, um fork) e apontar o script para ele:

1. Faça um fork do repositório original ou envie estes arquivos para um repositório seu, na branch `Production`.
2. Troque `Zinidia/Pelinstaller` por `SEU_USUARIO/Pelinstaller` nos valores padrão de `REPO`:
   - `install.sh` (linha 47)
   - `lib/lib.sh` (linha 55)
   - `installers/basic.sh` (linha 16)
   - `installers/docker.sh` (linha 10)
3. Alternativa sem editar nada: execute o `install.sh` com `--repo SEU_USUARIO/Pelinstaller`.
4. Mantenha o arquivo `LICENSE.md` e os avisos de copyright, como exige a GPL-3.0.

## Produção e operações

### Criando uma release

No `install.sh`, as variáveis de origem do GitHub e de release do script devem mudar a cada release. Primeiro, atualize o `CHANGELOG.md` para que a data e a tag da release sejam exibidas. Nenhuma alteração deve ser feita nos itens do changelog em si. Depois, atualize `GITHUB_SOURCE` e `SCRIPT_RELEASE` no `install.sh`. Por fim, envie um commit com a mensagem `Release vX.Y.Z` e crie uma release no GitHub. Veja [este commit](https://github.com/Zinidia/Pelinstaller/commit/90aaae10785f1032fdf90b216a4a8d8ca64e6d44) como referência.

## Patrocinadores ✨

Meus sinceros agradecimentos aos patrocinadores a seguir por ajudarem a financiar o desenvolvimento do Pelinstaller.
[Quer se tornar um patrocinador?](mailto:git@matthew.network)

| Empresa                                         | Sobre                                                                                                                                                                         |
|-------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [**ForestRacks**](https://forestracks.com/vps)  | Procurando um lugar para hospedar o seu Pelican Panel? Experimente uma VPS da ForestRacks, uma provedora de hospedagem americana de 5 estrelas que atende o mundo todo desde 2019. |

## Colaboradores ✨

Agradecemos aos colaboradores a seguir pelo trabalho na manutenção e criação deste instalador:
1) [Matthew Jacob](https://github.com/Zinidia)
2) [Vilhelm Prytz](https://github.com/vilhelmprytz)
3) [Linux123123](https://github.com/Linux123123)
4) [ImGreen](https://github.com/GreenDiscord)
5) [Neon](https://github.com/DeveloperNeon)
6) [sam1370](https://github.com/sam1370)
7) [Linux123123](https://github.com/Linux123123)
8) [sinjs](https://github.com/sinjs)

Copyright (C) 2018 - 2024, Vilhelm Prytz
Copyright (C) 2021 - 2026, Matthew Jacob
