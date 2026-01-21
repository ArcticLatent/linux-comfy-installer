# 🧊 Linux ComfyUI Installer
[![Shell Script](https://img.shields.io/badge/Shell-Bash%2FZsh%2FFish-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Fedora Supported](https://img.shields.io/badge/Fedora-41%2F42%2B-blue?logo=fedora&logoColor=white)
![Ubuntu Supported](https://img.shields.io/badge/Ubuntu-22.04%2F24.04%2B-E95420?logo=ubuntu&logoColor=white)
![Linux Mint Supported](https://img.shields.io/badge/Linux%20Mint-22%2B-87CF3E?logo=linuxmint&logoColor=white)
![Debian Supported](https://img.shields.io/badge/Debian-13%2B-A81D33?logo=debian&logoColor=white)
![Arch Supported](https://img.shields.io/badge/Arch%20Linux-Endeavour%2FManjaro-1793D1?logo=arch-linux&logoColor=white)
![GPU Support](https://img.shields.io/badge/NVIDIA-RTX%202000%2F3000%2F4000%2F5000-%2376B900?logo=nvidia&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.12.6-3776AB?logo=python&logoColor=white)
![PyTorch](https://img.shields.io/badge/PyTorch-2.8.0%2Bcu128-EE4C2C?logo=pytorch&logoColor=white)
![CUDA](https://img.shields.io/badge/CUDA-12.8-76B900?logo=nvidia&logoColor=white)

A **universal installer** for [ComfyUI](https://github.com/comfyanonymous/ComfyUI) that works seamlessly across **Fedora**, **Ubuntu/Linux Mint**, **Debian 13**, and **Arch-based** Linux distributions — with automatic NVIDIA GPU detection, proper CUDA-compatible PyTorch install, and clean `pyenv` isolation.

---

## 🚀 Features

- 🧠 **Distro-aware:** Detects and installs required packages for Fedora, Ubuntu/Linux Mint, Debian 13, or Arch-based systems.
- ⚙️ **Unified GPU stack:** Installs a single CUDA 12.8 stack (PyTorch 2.8.0 + cu128) that works on RTX 3000 / 4000 / 5000 series.
- 🐍 **Python isolation:** Uses **pyenv** to manage Python 3.12.6 safely without polluting your system.
- 🧩 **Dependencies handled:** Installs build tools, curl, git, ffmpeg, and all other required dev packages automatically.
- 🎮 **Three install modes:** Native PyTorch attention (no xformers); Sage Attention stack (Torch 2.8.0 cu128 + Triton via `assets/sage.txt`); Flash Attention stack (Torch 2.8.0 cu128 + Triton via `assets/flash.txt`). All avoid xformers by default.
- 📂 **Extra model folder:** Optionally writes `extra_model_paths.yaml` so you can point ComfyUI at a separate models directory (and even make it the default).
- 🧱 **Custom nodes bootstrap:** Drops in ComfyUI-Manager automatically so you have the essentials out of the box.
- 🌿 **Trellis.2 add-on:** Installs ComfyUI-TRELLIS2 + ComfyUI-GeometryPack + ComfyUI-UltraShape into an existing ComfyUI venv and installs their requirements.
- 💻 **Shell-aware aliases:** Creates/updates `comfyui-start` / `comfyui-venv` and, for Sage installs, `comfyui-start-sage` / `comfyui-start-sage-fp16`; for Flash installs, `comfyui-start-flash` / `comfyui-start-flash-fp16`. Suffixes are handled when multiple installs exist.
- 🧼 **Re-runnable:** Detects existing installs, reuses/updates aliases instead of duplicating them, and refreshes code in-place without deleting your `models/`.
- 🛡️ **Install guardrails:** Prompts before overwriting an existing ComfyUI folder; refreshes code while keeping your downloaded models intact.

---

## 📦 Supported distributions

| Distro | Package manager | Tested on |
|---------|-----------------|------------|
| Fedora 41 / 42 | `dnf5` | ✅ |
| Ubuntu 22.04 / 24.04 / Linux Mint 22+ | `apt` | ✅ |
| Debian 13 | `apt` | ✅ |
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
chmod +x install_comfyui.sh
./install_comfyui.sh
```

### Or run directly via curl

```bash
curl -fsSL https://raw.githubusercontent.com/ArcticLatent/linux-comfy-installer/main/install_comfyui.sh | bash
```

The script will:

- Present a main menu:
  1. **Install ComfyUI (native PyTorch attention)** — unified CUDA 12.8 stack (torch 2.8.0 cu128).
  2. **Install ComfyUI with Sage Attention** — uses bundled `assets/sage.txt` (torch 2.8.0 cu128 + Triton + SageAttention; native PyTorch attention without xformers) and adds `comfyui-start-sage` / `comfyui-start-sage-fp16` aliases.
  3. **Install ComfyUI with Flash Attention** — uses bundled `assets/flash.txt` (torch 2.8.0 cu128 + Triton + FlashAttention; native PyTorch attention without xformers) and adds `comfyui-start-flash` / `comfyui-start-flash-fp16` aliases.
  4. **Install precompiled wheels** — add InsightFace 0.7.3 to an existing ComfyUI venv.
  5. **Install LoRA trainers** — optional Fluxgym helper.
  6. **Install ArcticNodes into an existing ComfyUI** — point at your ComfyUI folder and it will clone/update `custom_nodes/ArcticNodes` there.
- Flow highlights:
  - Asks for your Linux distribution, installs build deps, and sets up `pyenv` with Python 3.12.6.
  - Clones or refreshes ComfyUI in-place; if the folder already contains ComfyUI, you can refresh without deleting `models/`.
  - Prompts to create `extra_model_paths.yaml` so you can store models on another drive and optionally make that path your default save/load location.
  - Optionally drops ArcticNodes under `custom_nodes/` for fresh installs (1/2/3) or via menu option 6 for existing setups.
  - Adds ComfyUI-Manager under `custom_nodes/`.
  - Creates or reuses shell aliases; if other installs already use `comfyui-start`, suffixes like `comfyui-start2` are assigned automatically. Sage installs add `comfyui-start-sage` / `comfyui-start-sage-fp16`; Flash installs add `comfyui-start-flash` / `comfyui-start-flash-fp16`.

---

## 🧠 Usage

After installation, launch ComfyUI by typing:

```bash
comfyui-start
```

This will:
- Activate the virtual environment
- Start ComfyUI with the correct PyTorch + CUDA stack

If you installed with the Sage Attention option, you also get:
- `comfyui-start-sage` (`--use-sage-attention`)
- `comfyui-start-sage-fp16` (`--use-sage-attention --fast`)

If you installed with the Flash Attention option, you also get:
- `comfyui-start-flash` (`--use-flash-attention`)
- `comfyui-start-flash-fp16` (`--use-flash-attention --fast`)

If suffixes were needed (e.g., `comfyui-start2`), use the names shown at the end of the installer output.

To deactivate the environment at any time:

```bash
deactivate
```

### Extra model folder (optional)

During install you’ll be asked whether to configure an extra models directory. If you say yes, the installer copies ComfyUI’s `extra_model_paths.yaml.example` to `extra_model_paths.yaml`, points `base_path` at the path you provide (e.g. `/mnt/cache/models`), and lets you decide if it should become the default save/load location (`is_default: true`). Choose no to skip and keep ComfyUI’s built-in `models/` folder.

Tip: This is handy when you run multiple ComfyUI installs—point them all to the same external models folder to avoid duplicate downloads.

---

### Precompiled wheel installer

Run the script again and pick option **4) Install precompiled wheels** to add extra packages to an existing ComfyUI setup. The installer will:

- Validate the ComfyUI directory and virtual environment you point it to.
- Offer the current catalog of Linux wheels:
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

Sage or Flash installs add their corresponding start aliases to the same shell config files.

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

Burce Boran 🎥 Asset Supervisor / VFX Artist | 🐧 Arctic Latent

[![YouTube – Arctic Latent](https://img.shields.io/badge/YouTube-%40ArcticLatent-FF0000?logo=youtube&logoColor=white)](https://youtube.com/@ArcticLatent)
[![Patreon – Arctic Latent](https://img.shields.io/badge/Patreon-Arctic%20Latent-FF424D?logo=patreon&logoColor=white)](https://patreon.com/ArcticLatent)
[![Hugging Face – Arctic Latent](https://img.shields.io/badge/HuggingFace-Arctic%20Latent-FFD21E?logo=huggingface&logoColor=white)](https://huggingface.co/arcticlatent)
[![Vimeo – Demo Reel](https://img.shields.io/badge/Vimeo-Demo%20Reel-1ab7ea?logo=vimeo&logoColor=white)](https://vimeo.com/1044521891)

---

## 🪪 License

MIT License © 2025 Burce Boran
You’re free to modify and redistribute — just credit the original source.
