# Pelinstaller

[![License: GPL v3](https://img.shields.io/github/license/Zinidia/Pelinstaller)](LICENSE.md)

## Installation

1) To get started, it's important to ensure that your machine is freshly reinstalled if you've made any changes to it beforehand.
2) Point a DNS A-Record to your machine's IP address, like panel.example.com to 192.168.53.72.
3) To download and run the installer, simply enter the following command into your terminal and follow the prompts:

```bash
bash <(curl -Ss https://raw.githubusercontent.com/Zinidia/Pelinstaller/Production/install.sh || wget -O - https://raw.githubusercontent.com/Zinidia/Pelinstaller/Production/install.sh)
```

_Note: On some systems, it's required to be already logged in as root before executing the one-line command (where `sudo` is in front of the command does not work)._

⚠️ Troubleshooting: If you encounter any issues during installation or while using Pelican, first check the Pelican logs and review the official [Pelican Troubleshooting Guide](https://pelican.dev/docs/troubleshooting/). If you're still unable to resolve the problem, please open an issue on the [PelInstaller GitHub repository](https://github.com/Zinidia/Pelinstaller) and share any relevant logs.

Here is a [YouTube Video](https://www.youtube.com/watch?v=E8UJhyUFoHM) that illustrates the installation process.

## Features

- Automatic installation of the Pelican Panel (dependencies, database, cronjob, nginx).
- Automatic installation of the Pelican Wings (Docker, systemd).
- Panel: (optional) automatic configuration of Let's Encrypt.
- Panel: (optional) automatic configuration of firewall.
- Uninstallation support for both panel and wings.

## Help and support

For help and support regarding the script itself and **not the official Pelican project**, create a [Github Issue](https://github.com/Zinidia/Pelinstaller/issues).

## Supported installations

List of supported installation setups for panel and Wings (installations supported by this installation script).

### Supported panel and wings operating systems

| Operating System | Version | Supported          | PHP Version |
| ---------------- | ------- | ------------------ | ----------- |
| Ubuntu           | 22.04   | :white_check_mark: | 8.5         |
|                  | 24.04   | :white_check_mark: | 8.5         |
|                  | 26.04   | :white_check_mark: | 8.5         |
| Debian           | 11      | :white_check_mark: | 8.5         |
|                  | 12      | :white_check_mark: | 8.5         |
|                  | 13      | :white_check_mark: | 8.5         |
| Rocky Linux      | 8       | :white_check_mark: | 8.5         |
|                  | 9       | :white_check_mark: | 8.5         |
|                  | 10      | :white_check_mark: | 8.5         |
| AlmaLinux        | 8       | :white_check_mark: | 8.5         |
|                  | 9       | :white_check_mark: | 8.5         |
|                  | 10      | :white_check_mark: | 8.5         |

_\* Indicates an operating system and release that previously was supported by this script._

## Firewall setup

The installation scripts can install and configure a firewall for you. The script will ask whether you want this or not. It is highly recommended to opt-in for the automatic firewall setup.

## Production & Ops

### Creating a release

In `install.sh` github source and script release variables should change every release. Firstly, update the `CHANGELOG.md` so that the release date and release tag are both displayed. No changes should be made to the changelog points themselves. Secondly, update `GITHUB_SOURCE` and `SCRIPT_RELEASE` in `install.sh`. Finally, you can now push a commit with the message `Release vX.Y.Z`. Create a release on GitHub. See [this commit](https://github.com/Zinidia/Pelinstaller/commit/90aaae10785f1032fdf90b216a4a8d8ca64e6d44) for reference.


## Sponsors ✨

I would like to extend my sincere thanks to the following sponsors for helping fund Pelinstaller's development.
[Interested in becoming a sponsor?](mailto:git@matthew.network)

| Company                                                   | About                                                                                                                                                                                                                                           |
|-----------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [**ForestRacks**](https://forestracks.com/vps)  | Looking for a place to host your Pelican Panel? Try out a ForestRacks VPS, ForestRacks is a US-based 5-Star hosting provider offering services globally since 2019. |

## Contributors ✨

We would like to thank the following contributors for their work in maintaining and creating this installer:
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
