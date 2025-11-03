# 🧊 Linux ComfyUI Installer
[![Shell Script](https://img.shields.io/badge/Shell-Bash%2FZsh%2FFish-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Fedora Supported](https://img.shields.io/badge/Fedora-41%2F42-blue?logo=fedora&logoColor=white)
![Ubuntu Supported](https://img.shields.io/badge/Ubuntu-22.04%2F24.04-E95420?logo=ubuntu&logoColor=white)
![Linux Mint Supported](https://img.shields.io/badge/Linux%20Mint-22%2B-87CF3E?logo=linuxmint&logoColor=white)
![Arch Supported](https://img.shields.io/badge/Arch%20Linux-Endeavour%2FManjaro-1793D1?logo=arch-linux&logoColor=white)
![GPU Support](https://img.shields.io/badge/NVIDIA-RTX%203000%2F4000%2F5000-%2376B900?logo=nvidia&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.12.6-3776AB?logo=python&logoColor=white)
![PyTorch](https://img.shields.io/badge/PyTorch-2.8.0%2Bcu128-EE4C2C?logo=pytorch&logoColor=white)
![CUDA](https://img.shields.io/badge/CUDA-12.8-76B900?logo=nvidia&logoColor=white)

A **universal installer** for [ComfyUI](https://github.com/comfyanonymous/ComfyUI) that works seamlessly across **Fedora**, **Ubuntu/Linux Mint**, and **Arch-based** Linux distributions — with automatic NVIDIA GPU detection, proper CUDA-compatible PyTorch install, and clean `pyenv` isolation.

---

## 🚀 Features

- 🧠 **Distro-aware:** Detects and installs required packages for Fedora, Ubuntu/Linux Mint, or Arch-based systems.
- ⚙️ **GPU detection:** Chooses the correct PyTorch + CUDA build depending on your GPU (3000-series or 4000/5000-series).
- 🐍 **Python isolation:** Uses **pyenv** to manage Python 3.12.6 safely without polluting your system.
- 🧩 **Dependencies handled:** Installs build tools, curl, git, ffmpeg, and all other required dev packages automatically.
- 🎮 **Native-attention setup:** Enables modern PyTorch attention optimizations (no xformers required).
- 🪄 **Optional SageAttention:** One prompt installs the precompiled SageAttention 2.2.0 wheel and updates launch aliases to pass `--use-sage-attention`.
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

1. Ask for your Linux distribution.
2. Ask for your NVIDIA GPU generation.
3. Offer to install the SageAttention 2.2.0 precompiled wheel (with hardware compatibility notes).
4. Install all required dependencies.
5. Set up `pyenv` and Python 3.12.6.
6. Install ComfyUI inside a virtual environment and add ComfyUI-Manager under `custom_nodes/`.
7. Create/update `comfyui-start` and `comfyui-venv` aliases for your shell (and append `--use-sage-attention` automatically when installed).

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

Follow my AI + Linux VFX workflows on
🔗 [YouTube – Arctic Latent](https://youtube.com/@ArcticLatent)

---

## 🪪 License

MIT License © 2025 Burce Boran
You’re free to modify and redistribute — just credit the original source.
