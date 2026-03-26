# GitHub Copilot CLI Setup for Termux

This repository contains a setup script to install and configure the **GitHub Copilot CLI** on **Termux** (Android). It automates the installation of system dependencies, builds required native modules, and sets up the environment for a smooth experience.

## Overview

The `setup.sh` script performs the following tasks:
- Installs Node.js and build tools (clang, make, python, rust).
- Installs system libraries (glib, libvips, pkg-config).
- Installs the `@github/copilot` CLI globally.
- Compiles and configures native Node.js modules:
  - **node-pty**: For pseudo-terminal support.
  - **sharp**: For image processing.
  - **keytar**: Credential storage via a file-based JS bypass (no `libsecret` required).
- Sets up a clipboard wrapper using `termux-api`.
- Configures `ripgrep` for code search.
- Sets `NODE_OPTIONS` in `~/.bash_profile` and `~/.bashrc` to load the keytar bypass.

## Installation

> **Note:** The script must run from Termux's internal storage (`~/` or a subdirectory). Android mounts external storage with `noexec`, so the script cannot execute from `/sdcard` or an SD card.

**One-liner (recommended):**
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USER/copilot-termux-setup/main/setup.sh | bash
```

**Or clone and run:**
```bash
cd ~
git clone https://github.com/YOUR_USER/copilot-termux-setup.git
bash copilot-termux-setup/setup.sh
```

The script will guide you through the installation process. It may take several minutes to compile the native modules.

## Usage

Once the installation is complete, you can start the GitHub Copilot CLI by running:

```bash
copilot
```
