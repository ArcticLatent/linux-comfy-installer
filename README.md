# 🧊 Linux ComfyUI Installer
[![Shell Script](https://img.shields.io/badge/Shell-Bash%2FZsh%2FFish-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Fedora Supported](https://img.shields.io/badge/Fedora-41%2F42-blue?logo=fedora&logoColor=white)
![Ubuntu Supported](https://img.shields.io/badge/Ubuntu-22.04%2F24.04-E95420?logo=ubuntu&logoColor=white)
![Arch Supported](https://img.shields.io/badge/Arch%20Linux-Endeavour%2FManjaro-1793D1?logo=arch-linux&logoColor=white)
![GPU Support](https://img.shields.io/badge/NVIDIA-RTX%203000%2F4000%2F5000-%2376B900?logo=nvidia&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.12.6-3776AB?logo=python&logoColor=white)
![PyTorch](https://img.shields.io/badge/PyTorch-2.8.0%2Bcu128-EE4C2C?logo=pytorch&logoColor=white)
![CUDA](https://img.shields.io/badge/CUDA-12.8-76B900?logo=nvidia&logoColor=white)

A **universal installer** for [ComfyUI](https://github.com/comfyanonymous/ComfyUI) that works seamlessly across **Fedora**, **Ubuntu**, and **Arch-based** Linux distributions — with automatic NVIDIA GPU detection, proper CUDA-compatible PyTorch install, and clean `pyenv` isolation.

---

## 🚀 Features

- 🧠 **Distro-aware:** Detects and installs required packages for Fedora, Ubuntu, or Arch-based systems.
- ⚙️ **GPU detection:** Chooses the correct PyTorch + CUDA build depending on your GPU (3000-series or 4000/5000-series).
- 🐍 **Python isolation:** Uses **pyenv** to manage Python 3.12.6 safely without polluting your system.
- 🧩 **Dependencies handled:** Installs build tools, curl, git, ffmpeg, and all other required dev packages automatically.
- 🎮 **Native-attention setup:** Enables modern PyTorch attention optimizations (no xformers required).
- 💻 **Shell-aware aliases:** Creates a convenient `comfyui-start` alias for Bash, Zsh, and Fish users.
- 🧼 **Re-runnable:** Safe to execute multiple times — it checks for existing installs and skips redundant steps.

---

## 📦 Supported distributions

| Distro | Package manager | Tested on |
|---------|-----------------|------------|
| Fedora 41 / 42 | `dnf5` | ✅ |
| Ubuntu 22.04 / 24.04 | `apt` | ✅ |
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
3. Install all required dependencies.
4. Set up `pyenv` and Python 3.12.6.
5. Install ComfyUI inside a virtual environment.
6. Create a `comfyui-start` alias for your shell.

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
| Bash | `comfyui-start` | `~/.bashrc` |
| Zsh | `comfyui-start` | `~/.zshrc` |
| Fish | `comfyui-start` | `~/.config/fish/config.fish` |

---

## 🧱 Uninstalling

To remove ComfyUI and the virtual environment:

```bash
rm -rf ~/ComfyUI ~/.pyenv
```

If needed, remove the alias manually from your shell config.

---

## 🧭 Troubleshooting

| Issue | Cause | Fix |
|--------|--------|-----|
| `torchvision requires torch==2.9.0` | PyTorch version mismatch | The script pins `torch==2.8.0+cu128` for stability |
| `pyenv build failed` | Missing SSL/zlib dev packages | Automatically fixed by the script |
| `alias not found` | Shell didn’t reload | Restart terminal or run `source ~/.bashrc` (or your shell config) |

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
