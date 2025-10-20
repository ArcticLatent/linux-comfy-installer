#!/usr/bin/env bash
set -euo pipefail

# ============================ helpers ============================
say()  { printf "\033[1;32m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }
ask()  { printf "\033[1;36m[?   ]\033[0m %s " "$*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; return 1; }; }

confirm_choice() {
  local prompt="$1" choices="$2" varname="$3" choice
  while true; do
    ask "$prompt"
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ " $choices " == *" $choice "* ]]; then
      printf -v "$varname" "%s" "$choice"
      break
    else
      warn "Invalid selection. Valid options: ${choices// /, }"
    fi
  done
}

# ============================ choose OS ============================
say "Which Linux distribution are you using?"
echo "  1) Fedora"
echo "  2) Ubuntu (22.04/24.04+)"
echo "  3) Arch-based (Arch/Manjaro/Endeavour)"
confirm_choice "Enter 1, 2, or 3:" "1 2 3" OS_CHOICE

case "$OS_CHOICE" in
  1) OS_NAME="fedora" ;;
  2) OS_NAME="ubuntu" ;;
  3) OS_NAME="arch" ;;
esac
say "Detected OS: $OS_NAME"

# ======================== choose GPU tier =========================
say "What NVIDIA GPU series are you using?"
echo "  1) NVIDIA 4000+ (includes 5000 series)"
echo "  2) NVIDIA 3000 and below"
confirm_choice "Enter 1 or 2:" "1 2" GPU_TIER

case "$GPU_TIER" in
  1) GPU_LABEL="4000+" ;;
  2) GPU_LABEL="3000_and_below" ;;
esac
say "GPU tier: $GPU_LABEL"

# ===================== dev tools per distro =======================
say "Installing development tool packages for $OS_NAME ..."
need_cmd sudo

if [[ "$OS_NAME" == "fedora" ]]; then
  # Detect dnf vs dnf5
  if command -v dnf5 >/dev/null 2>&1; then
    PM=dnf5
  else
    PM=dnf
  fi
  say "Using $PM on Fedora."
  # NOTE: NO zlib-devel (as requested)
  sudo "$PM" -y install git curl ffmpeg make gcc gcc-c++ cmake \
    openssl-devel bzip2-devel libffi-devel xz-devel readline-devel sqlite-devel tk-devel python3-devel
  # Ensure venv module exists for system python (pyenv will be used anyway)
  if ! python3 -c "import venv" 2>/dev/null; then
    warn "Python venv module missing; reinstalling python3..."
    sudo "$PM" -y reinstall python3
  fi

elif [[ "$OS_NAME" == "ubuntu" ]]; then
  sudo apt-get update
  sudo apt-get install -y build-essential git curl ffmpeg make cmake \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev tk-dev \
    libffi-dev xz-utils ca-certificates pkg-config

elif [[ "$OS_NAME" == "arch" ]]; then
  sudo pacman -Syu --noconfirm
  sudo pacman -S --noconfirm --needed base-devel git curl ffmpeg cmake \
    openssl zlib bzip2 xz tk sqlite
fi

# ====================== check NVIDIA driver =======================
if command -v nvidia-smi >/dev/null 2>&1; then
  say "NVIDIA driver detected:"
  nvidia-smi || true
else
  warn "NVIDIA driver not detected (nvidia-smi missing). GPU acceleration will not work until drivers are installed."
fi

# ============================ pyenv ===============================
PYENV_ROOT="${HOME}/.pyenv"
PYTHON_VERSION="3.12.6"

if ! command -v pyenv >/dev/null 2>&1; then
  say "Installing pyenv..."
  git clone https://github.com/pyenv/pyenv.git "$PYENV_ROOT"
  # Add to bashrc & zshrc so future shells can see pyenv
  {
    echo ''
    echo '# >>> pyenv >>>'
    echo "export PYENV_ROOT=\"$PYENV_ROOT\""
    echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"'
    echo 'eval "$(pyenv init -)"'
    echo '# <<< pyenv <<<'
  } >> "$HOME/.bashrc"
  if [[ -f "$HOME/.zshrc" ]]; then
    {
      echo ''
      echo '# >>> pyenv >>>'
      echo "export PYENV_ROOT=\"$PYENV_ROOT\""
      echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"'
      echo 'eval "$(pyenv init -)"'
      echo '# <<< pyenv <<<'
    } >> "$HOME/.zshrc"
  fi
  export PYENV_ROOT
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
else
  say "pyenv already installed."
  export PYENV_ROOT
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
fi

# Build Python (retry once if needed)
export CFLAGS="${CFLAGS:-} -O2"
if ! pyenv versions --bare | grep -qx "$PYTHON_VERSION"; then
  say "Installing Python $PYTHON_VERSION via pyenv (this may take a bit)..."
  if ! pyenv install -s "$PYTHON_VERSION"; then
    warn "First build failed, retrying..."
    pyenv install -s "$PYTHON_VERSION"
  fi
else
  say "Python $PYTHON_VERSION already present in pyenv."
fi

# =================== Ask for ComfyUI install location =============
DEFAULT_DIR="${HOME}/ComfyUI"
ask "Enter install location for ComfyUI [default: $DEFAULT_DIR]:"
read -r INSTALL_DIR
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_DIR}"
# Expand leading ~ to $HOME
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

# Sanity checks & prepare parent directories
if [[ -e "$INSTALL_DIR" && ! -d "$INSTALL_DIR" ]]; then
  err "Path exists and is not a directory: $INSTALL_DIR"
  exit 1
fi
mkdir -p "$(dirname "$INSTALL_DIR")"

# ======================= ComfyUI + venv ===========================
if [[ ! -d "$INSTALL_DIR" || ! -d "$INSTALL_DIR/.git" ]]; then
  say "Cloning ComfyUI into: $INSTALL_DIR"
  git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git "$INSTALL_DIR"
else
  say "ComfyUI directory exists; pulling latest..."
  git -C "$INSTALL_DIR" pull --ff-only || warn "git pull skipped."
fi

say "Creating Python virtual environment (pyenv $PYTHON_VERSION)..."
pyenv local "$PYTHON_VERSION"
PYBIN="$(pyenv prefix)/bin/python3"
VENV_DIR="$INSTALL_DIR/venv"
"$PYBIN" -m venv "$VENV_DIR"
# Activate (bash-style here; we'll do fish properly in aliases)
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip wheel setuptools

# ====================== final confirmation ========================
ask "All prerequisites are installed. Ready to install ComfyUI deps and PyTorch? (y/n):"
read -r READY
if [[ ! "$READY" =~ ^[Yy]$ ]]; then
  say "Exiting without installing Python dependencies."
  exit 0
fi

# =================== Select Torch/CUDA by GPU tier =================
# Defaults can still be overridden by env (TORCH_VER, etc.)
if [[ "${GPU_TIER}" == "2" ]]; then
  # NVIDIA 3000 and below → PyTorch 2.7.1 + CUDA 12.1 path
  TORCH_VER="${TORCH_VER:-2.7.1}"
  VISION_VER="${VISION_VER:-0.22.0}"
  AUDIO_VER="${AUDIO_VER:-2.7.1}"
  TRITON_VER="${TRITON_VER:-}"         # let pip resolve a compatible triton for 2.7.1 (or omit)
  TRY_CUDA_STREAMS=("cu121" "cu118")   # prefer cu121; fallback to cu118; CPU if both fail
else
  # NVIDIA 4000+ (your existing defaults)
  TORCH_VER="${TORCH_VER:-2.8.0}"
  VISION_VER="${VISION_VER:-0.23.0}"
  AUDIO_VER="${AUDIO_VER:-2.8.0}"
  TRITON_VER="${TRITON_VER:-3.4.0}"
  TRY_CUDA_STREAMS=("cu128" "cu126" "cu124")
fi

# =================== PyTorch stack (native attention) =============
say "Installing PyTorch ${TORCH_VER} (CUDA wheels), native attention (no xformers)..."

# Clean slate so the resolver can't fight older remnants
python - <<'PY'
import sys, subprocess
pkgs = ["xformers","triton","torch","torchvision","torchaudio",
        "nvidia-cublas-cu12","nvidia-cuda-nvrtc-cu12","nvidia-cuda-runtime-cu12",
        "nvidia-cuda-cupti-cu12","nvidia-cudnn-cu12","nvidia-cufft-cu12","nvidia-curand-cu12",
        "nvidia-cusolver-cu12","nvidia-cusparse-cu12","nvidia-cusparselt-cu12",
        "nvidia-nccl-cu12","nvidia-nvjitlink-cu12","nvidia-nvshmem-cu12","nvidia-nvtx-cu12"]
subprocess.call([sys.executable,"-m","pip","uninstall","-y"]+pkgs)
PY

PYTORCH_OK=0
CUDA_PICKED=""

for stream in "${TRY_CUDA_STREAMS[@]}"; do
  export PIP_INDEX_URL="https://download.pytorch.org/whl/${stream}"
  export PIP_EXTRA_INDEX_URL="https://pypi.org/simple"
  say "Trying $stream ..."
  # Build install command with optional triton pin
  install_cmd=(python -m pip install --no-cache-dir --force-reinstall
               "torch==${TORCH_VER}" "torchvision==${VISION_VER}" "torchaudio==${AUDIO_VER}")
  if [[ -n "${TRITON_VER:-}" ]]; then
    install_cmd+=("triton==${TRITON_VER}")
  fi
  if "${install_cmd[@]}"; then
    CUDA_PICKED="$stream"
    PYTORCH_OK=1
    break
  fi
done

if [[ $PYTORCH_OK -ne 1 ]]; then
  warn "CUDA wheels failed; trying CPU-only wheels..."
  export PIP_INDEX_URL="https://download.pytorch.org/whl/cpu"
  export PIP_EXTRA_INDEX_URL="https://pypi.org/simple"
  install_cmd=(python -m pip install --no-cache-dir --force-reinstall
               "torch==${TORCH_VER}" "torchvision==${VISION_VER}" "torchaudio==${AUDIO_VER}")
  if [[ -n "${TRITON_VER:-}" ]]; then
    install_cmd+=("triton==${TRITON_VER}")
  fi
  if ! "${install_cmd[@]}"; then
    err "Could not install PyTorch stack."
    exit 1
  fi
  CUDA_PICKED="cpu"
fi
say "PyTorch install target: ${CUDA_PICKED}"

# ========== Install ComfyUI requirements (respect Torch pins) ==========
PIN_FILE="$INSTALL_DIR/.torch-pins.txt"
{
  echo "torch==${TORCH_VER}"
  echo "torchvision==${VISION_VER}"
  echo "torchaudio==${AUDIO_VER}"
  if [[ -n "${TRITON_VER:-}" ]]; then
    echo "triton==${TRITON_VER}"
  fi
} > "$PIN_FILE"

FIL_REQ="$INSTALL_DIR/.requirements.notorch.txt"
# Strip any torch/vision/audio/xformers entries so pip won't change our pins
grep -viE '^(torch|torchvision|torchaudio|xformers)([=<> ]|$)' "$INSTALL_DIR/requirements.txt" > "$FIL_REQ" || true

# Keep chosen CUDA index for the rest
export PIP_INDEX_URL="https://download.pytorch.org/whl/${CUDA_PICKED}"
export PIP_EXTRA_INDEX_URL="https://pypi.org/simple"

say "Installing ComfyUI requirements (respecting pins; avoiding xformers)..."
python -m pip install --upgrade -r "$FIL_REQ" -c "$PIN_FILE"

# Ensure PyYAML present (ComfyUI imports yaml)
python -m pip install --upgrade pyyaml

# Ensure xformers stays out (we want native SDPA)
python - <<'PY'
import importlib, subprocess, sys
try:
    importlib.import_module("xformers")
    print("[WARN] xformers detected; removing to force native PyTorch attention.")
    subprocess.check_call([sys.executable,"-m","pip","uninstall","-y","xformers"])
except ImportError:
    pass
PY

# ========================== Verify stack ==========================
python - <<'PY'
import importlib, torch
def v(m):
    try: return importlib.import_module(m).__version__
    except Exception as e: return f"MISSING ({e})"
print("torch      :", v("torch"))
print("torchvision:", v("torchvision"))
print("torchaudio :", v("torchaudio"))
try:
    import triton  # noqa
    print("triton     :", v("triton"))
except Exception as e:
    print("triton     :", f"not pinned ({e})")
print("cuda.is_available:", torch.cuda.is_available())
try:
    from torch.nn.functional import scaled_dot_product_attention
    print("SDPA available  :", True)
except Exception as e:
    print("SDPA available  :", False, e)
PY

# ====================== Shell alias setup =========================
say "Setting up ComfyUI aliases for your shell..."

USER_SHELL=$(basename "${SHELL:-bash}")  # fallback to bash if SHELL unset
# For bash/zsh we can source activate; for fish we must source activate.fish
if [[ "$USER_SHELL" == "fish" ]]; then
  ACTIVATE_CMD="source \"$VENV_DIR/bin/activate.fish\""
else
  ACTIVATE_CMD="source \"$VENV_DIR/bin/activate\""
fi

# Safer update command: use our filtered requirements + pins and keep CUDA index
READONLY_UPDATE="PIP_INDEX_URL=${PIP_INDEX_URL} PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL} \
pip install -r \"$FIL_REQ\" -c \"$PIN_FILE\" && pip install --upgrade pyyaml"

COMFY_ALIAS_BASHZSH="
alias comfyui-start='${ACTIVATE_CMD} && python \"$INSTALL_DIR/main.py\" --listen 0.0.0.0 --port 8188'
alias comfyui-venv='${ACTIVATE_CMD}'
alias comfyui-update='git -C \"$INSTALL_DIR\" pull --ff-only && ${READONLY_UPDATE}'
"

if [[ "$USER_SHELL" == "bash" ]]; then
  RC_FILE="$HOME/.bashrc"
elif [[ "$USER_SHELL" == "zsh" ]]; then
  RC_FILE="$HOME/.zshrc"
elif [[ "$USER_SHELL" == "fish" ]]; then
  RC_FILE="$HOME/.config/fish/config.fish"
else
  warn "Unknown shell type ($USER_SHELL); skipping automatic alias setup."
  RC_FILE=""
fi

if [[ -n "$RC_FILE" ]]; then
  if [[ "$USER_SHELL" == "fish" ]]; then
    mkdir -p "$(dirname "$RC_FILE")"
    {
      echo ""
      echo "# >>> ComfyUI aliases >>>"
      echo "alias comfyui-start 'source $VENV_DIR/bin/activate.fish; python $INSTALL_DIR/main.py --listen 0.0.0.0 --port 8188'"
      echo "alias comfyui-venv 'source $VENV_DIR/bin/activate.fish'"
      echo "alias comfyui-update 'git -C $INSTALL_DIR pull --ff-only; env PIP_INDEX_URL=$PIP_INDEX_URL PIP_EXTRA_INDEX_URL=$PIP_EXTRA_INDEX_URL pip install -r $FIL_REQ -c $PIN_FILE; pip install --upgrade pyyaml'"
      echo "# <<< ComfyUI aliases <<<"
    } >> "$RC_FILE"
  else
    {
      echo ""
      echo "# >>> ComfyUI aliases >>>"
      echo "$COMFY_ALIAS_BASHZSH"
      echo "# <<< ComfyUI aliases <<<"
    } >> "$RC_FILE"
  fi
  say "Added ComfyUI aliases to $RC_FILE"
  say "Reload your shell or run: source '$RC_FILE' to enable them."
fi

# ============================ finishing ===========================
say "ComfyUI is ready."

echo
say "How to run:"
echo "  1) Activate venv and start manually:"
if [[ "$USER_SHELL" == "fish" ]]; then
  echo "       source \"$VENV_DIR/bin/activate.fish\""
else
  echo "       source \"$VENV_DIR/bin/activate\""
fi
echo "       python \"$INSTALL_DIR/main.py\" --listen 0.0.0.0 --port 8188"
echo "  2) Or use the new aliases (after reloading your shell):"
echo "       comfyui-start      # activate venv + launch ComfyUI"
echo "       comfyui-venv       # activate venv only"
echo "       comfyui-update     # git pull + reinstall deps (pins respected)"
echo
say "If you need CUDA-index for extra installs later:"
echo "  export PIP_INDEX_URL=${PIP_INDEX_URL:-https://download.pytorch.org/whl/cu121}"
echo "  export PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL:-https://pypi.org/simple}"
