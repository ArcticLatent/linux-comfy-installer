# 🧊 Linux ComfyUI Installer
[![Shell Script](https://img.shields.io/badge/Shell-Bash%2FZsh%2FFish-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Fedora Supported](https://img.shields.io/badge/Fedora-41%2F42%2B-blue?logo=fedora&logoColor=white)
![Ubuntu Supported](https://img.shields.io/badge/Ubuntu-22.04%2F24.04%2B-E95420?logo=ubuntu&logoColor=white)
![Linux Mint Supported](https://img.shields.io/badge/Linux%20Mint-22%2B-87CF3E?logo=linuxmint&logoColor=white)
![Arch Supported](https://img.shields.io/badge/Arch%20Linux-Endeavour%2FManjaro-1793D1?logo=arch-linux&logoColor=white)
![GPU Support](https://img.shields.io/badge/NVIDIA-RTX%202000%2F3000%2F4000%2F5000-%2376B900?logo=nvidia&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.12.6-3776AB?logo=python&logoColor=white)
![PyTorch](https://img.shields.io/badge/PyTorch-2.8.0%2Bcu128-EE4C2C?logo=pytorch&logoColor=white)
![CUDA](https://img.shields.io/badge/CUDA-12.8-76B900?logo=nvidia&logoColor=white)

A **universal installer** for [ComfyUI](https://github.com/comfyanonymous/ComfyUI) that works seamlessly across **Fedora**, **Ubuntu/Linux Mint**, and **Arch-based** Linux distributions — with automatic NVIDIA GPU detection, proper CUDA-compatible PyTorch install, and clean `pyenv` isolation.

---

## 🚀 Features

- 🧠 **Distro-aware:** Detects and installs required packages for Fedora, Ubuntu/Linux Mint, or Arch-based systems.
- ⚙️ **GPU detection:** Chooses the correct PyTorch + CUDA build depending on your GPU (3000-series or older / 4000/5000-series).
- 🐍 **Python isolation:** Uses **pyenv** to manage Python 3.12.6 safely without polluting your system.
- 🧩 **Dependencies handled:** Installs build tools, curl, git, ffmpeg, and all other required dev packages automatically.
- 🎮 **Native-attention setup:** Enables modern PyTorch attention optimizations (no xformers required).
- 🪄 **Precompiled wheels menu:** Install SageAttention 2.2.0 with alias integration or drop InsightFace 0.7.3 into an existing ComfyUI — all from option 2 of the script.
- 🧱 **Custom nodes bootstrap:** Drops in ComfyUI-Manager automatically so you have the essentials out of the box.
- 💻 **Shell-aware aliases:** Creates/updates a `comfyui-start` alias for Bash, Zsh, and Fish (and a `comfyui-venv` helper).
- 🧼 **Re-runnable:** Safe to execute multiple times — it checks for existing installs and skips redundant steps.
- 🛡️ **Install guardrails:** Refuses to overwrite an existing `ComfyUI` checkout so you don’t clobber your current setup by mistake.

---

## 📦 Supported distributions

| Distro | Package manager | Tested on |
|---------|-----------------|------------|
| Fedora 41 / 42 | `dnf5` | ✅ |
| Ubuntu 22.04 / 24.04 / Linux Mint 22+ | `apt` | ✅ |
| Arch / EndeavourOS / Manjaro | `pacman` | ✅ |

---

## 🔧 Requirements

- NVIDIA GPU (RTX 3000 series or newer recommended)
- CUDA 12.8 runtime drivers installed
- Internet connection (for PyTorch + ComfyUI clone)
- Bash, Zsh, or Fish shell

---

## 🧰 Installation

### Clone and run manually

```bash
git clone https://github.com/ArcticLatent/linux-comfy-installer.git
cd linux-comfy-installer
chmod +x install-comfy.sh
./install-comfy.sh
```

### Or run directly via curl

```bash
curl -fsSL https://raw.githubusercontent.com/ArcticLatent/linux-comfy-installer/main/install-comfy.sh | bash
```

The script will:

- Present a main menu so you can either install ComfyUI end-to-end or only add precompiled Linux wheels.
- When you choose **Install ComfyUI**, it will:
  1. Ask for your Linux distribution.
  2. Ask for your NVIDIA GPU generation.
  3. Offer to install the SageAttention 2.2.0 wheel (with hardware compatibility notes).
  4. Install all required dependencies.
  5. Set up `pyenv` and Python 3.12.6.
  6. Install ComfyUI inside a virtual environment and add ComfyUI-Manager under `custom_nodes/`.
  7. Create/update `comfyui-start` and `comfyui-venv` aliases for your shell (and append `--use-sage-attention` automatically when installed).
- When you choose **Install precompiled wheels**, it will:
  1. Confirm your existing ComfyUI directory (with venv).
  2. Let you install SageAttention 2.2.0 (alias-aware) or InsightFace 0.7.3 directly into that environment.

---

## 🧠 Usage

After installation, launch ComfyUI by typing:

```bash
comfyui-start
```

This will:
- Activate the virtual environment
- Start ComfyUI with the correct PyTorch + CUDA stack

To deactivate the environment at any time:

```bash
deactivate
```

---

### Precompiled wheel installer

Run the script again and pick option **2) Install precompiled wheels** to add extra packages to an existing ComfyUI setup. The installer will:

- Validate the ComfyUI directory and virtual environment you point it to.
- Offer the current catalog of Linux wheels:
  - SageAttention 2.2.0 (adds `--use-sage-attention` to your aliases automatically)
  - InsightFace 0.7.3

More wheels can be added later — rerun the installer whenever you need to update or install additional ones.

---

## 🔄 Keeping the Installer Updated

The installer now ships with a self-update mechanism so you always get the latest fixes and wheel catalogue.

- **Check for updates manually**
  ```bash
  ./install_comfyui.sh --check-update
  ```
  This compares your local `SCRIPT_VERSION` with the latest copy in the repo and lets you know whether an update is available.

- **Update in place**
  ```bash
  ./install_comfyui.sh --update
  ```
  The script will download the newest version from GitHub, replace itself, and then restart with the same arguments.

- **Automatic prompt**
  When you launch `./install_comfyui.sh` normally, it checks the remote version first. If a newer release exists, you'll be prompted:
  ```
  [WARN] A new installer version is available (1.0 -> 1.1).
  [?   ] Would you like to update now? (y/n):
  ```
  Choose `y` to upgrade on the spot or `n` to continue using your current copy.

If you’re running from a read-only location or behind a strict firewall, you can set `LINUX_COMFY_INSTALLER_SOURCE` to point the updater at a mirror of `install_comfyui.sh`.

---

## 🧩 Example alias summary

| Shell | Alias added | Location |
|--------|--------------|-----------|
| Bash | `comfyui-start`, `comfyui-venv` | `~/.bashrc` |
| Zsh | `comfyui-start`, `comfyui-venv` | `~/.zshrc` |
| Fish | `comfyui-start`, `comfyui-venv` | `~/.config/fish/config.fish` |

---

## 🧱 Uninstalling

To remove ComfyUI and the virtual environment:

```bash
rm -rf ~/ComfyUI ~/.pyenv
```

If needed, remove the alias manually from your shell config.

---

## 🖼️ Demo Preview

![ComfyUI Installer Preview](https://raw.githubusercontent.com/arcticlatent/linux-comfy-installer/main/assets/demo.png)

---

## 🧊 Author

**Burce Boran**
🎥 Asset Supervisor / VFX Artist | 🐧 Arctic Latent

🎥 [YouTube – Arctic Latent](https://youtube.com/@ArcticLatent)  
🧡 [Patreon – Arctic Latent](https://patreon.com/ArcticLatent)

---

## 🪪 License

MIT License © 2025 Burce Boran
You’re free to modify and redistribute — just credit the original source.
