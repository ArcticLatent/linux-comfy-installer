#!/usr/bin/env bash
set -euo pipefail

# ============================ helpers ============================
say()  { printf "\033[1;32m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }
ask()  { printf "\033[1;36m[?   ]\033[0m %s " "$*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; return 1; }; }

append_line_if_missing() {
  local file="$1" line="$2"
  [[ -f "$file" ]] || touch "$file"
  if ! grep -Fqx "$line" "$file" 2>/dev/null; then
    {
      echo ""
      echo "$line"
    } >> "$file"
  fi
}

ensure_pyenv_shell_config() {
  local shell_type="$1" target="$2" pyenv_root="$3"
  [[ -n "$target" ]] || return 0
  if [[ "$shell_type" == "fish" ]]; then
    mkdir -p "$(dirname "$target")"
  fi
  [[ -f "$target" ]] || touch "$target"

  if grep -Fq '# >>> pyenv >>>' "$target"; then
    return
  fi

  case "$shell_type" in
    fish)
      {
        echo ''
        echo '# >>> pyenv >>>'
        printf 'set -gx PYENV_ROOT "%s"\n' "$pyenv_root"
        echo 'if test -d "$PYENV_ROOT/bin"'
        echo '  contains "$PYENV_ROOT/bin" $PATH; or set -gx PATH "$PYENV_ROOT/bin" $PATH'
        echo 'end'
        echo 'status --is-interactive; and . (pyenv init - | psub)'
        echo '# <<< pyenv <<<'
      } >> "$target"
      say "Configured pyenv environment for fish in $target"
      ;;
    *)
      {
        echo ''
        echo '# >>> pyenv >>>'
        echo "export PYENV_ROOT=\"$pyenv_root\""
        echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"'
        echo 'eval "$(pyenv init -)"'
        echo '# <<< pyenv <<<'
      } >> "$target"
      say "Configured pyenv environment for $shell_type in $target"
      ;;
  esac
}

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

DEFAULT_COMFY_DIR="${HOME}/ComfyUI"

prompt_existing_comfy_path() {
  local result_name="$1"
  local comfy_path
  local default_dir="${DEFAULT_COMFY_DIR}"

  if [[ -z "$result_name" ]]; then
    err "prompt_existing_comfy_path requires a result variable name."
    return 1
  fi

  local -n result_ref="$result_name"

  while true; do
    ask "Enter install location for ComfyUI (absolute path, e.g. /home/${USER:-user}/ComfyUI) [default: ${default_dir}]:"
    read -r comfy_path
    comfy_path="${comfy_path:-${default_dir}}"
    if [[ "${comfy_path}" != /* ]]; then
      warn "Please enter a full absolute path starting with '/'."
      continue
    fi
    if [[ ! -d "${comfy_path}" ]]; then
      warn "Directory not found: ${comfy_path}"
      continue
    fi
    if [[ ! -x "${comfy_path}/venv/bin/python" ]]; then
      warn "Missing virtual environment python binary at ${comfy_path}/venv/bin/python"
      continue
    fi
    if [[ ! -f "${comfy_path}/main.py" ]]; then
      warn "ComfyUI main.py not found in ${comfy_path}. Is this the correct directory?"
      continue
    fi
    result_ref="${comfy_path}"
    return 0
  done
}

install_sageattention_into_comfy() {
  local comfy_dir="$1"
  local python_bin="${comfy_dir}/venv/bin/python"
  local sage_version="2.2.0"
  local sage_wheel_url="https://huggingface.co/arcticlatent/misc/resolve/main/sageattention-${sage_version}-cp312-cp312-linux_x86_64.whl"

  say "Installing SageAttention ${sage_version} into ${comfy_dir}..."
  if "${python_bin}" -m pip install --upgrade "${sage_wheel_url}"; then
    say "SageAttention ${sage_version} installed successfully."
    configure_comfy_aliases "${comfy_dir}" " --use-sage-attention"
  else
    err "Failed to install SageAttention ${sage_version} into ${comfy_dir}."
    return 1
  fi
}

install_insightface_into_comfy() {
  local comfy_dir="$1"
  local python_bin="${comfy_dir}/venv/bin/python"
  local insight_version="0.7.3"
  local insight_wheel_url="https://huggingface.co/arcticlatent/misc/resolve/main/insightface-${insight_version}-cp312-cp312-linux_x86_64.whl"

  say "Installing InsightFace ${insight_version} into ${comfy_dir}..."
  if "${python_bin}" -m pip install --upgrade "${insight_wheel_url}"; then
    say "InsightFace ${insight_version} installed successfully."
  else
    err "Failed to install InsightFace ${insight_version} into ${comfy_dir}."
    return 1
  fi
}

configure_comfy_aliases() {
  local install_dir="$1"
  local sage_flag="${2:-}"
  local venv_dir="${install_dir}/venv"
  local user_shell rc_file start_alias venv_alias

  user_shell=$(basename "${SHELL:-bash}")

  if [[ "$user_shell" == "bash" ]]; then
    rc_file="$HOME/.bashrc"
  elif [[ "$user_shell" == "zsh" ]]; then
    rc_file="$HOME/.zshrc"
  elif [[ "$user_shell" == "fish" ]]; then
    rc_file="$HOME/.config/fish/config.fish"
  else
    warn "Unknown shell type ($user_shell); skipping automatic alias setup."
    return 0
  fi

  if [[ "$user_shell" == "fish" ]]; then
    mkdir -p "$(dirname "$rc_file")"
    start_alias="alias comfyui-start 'source ${venv_dir}/bin/activate.fish; python ${install_dir}/main.py --listen 0.0.0.0 --port 8188${sage_flag}'"
    venv_alias="alias comfyui-venv 'source ${venv_dir}/bin/activate.fish'"
  else
    start_alias="alias comfyui-start='source \"${venv_dir}/bin/activate\" && python \"${install_dir}/main.py\" --listen 0.0.0.0 --port 8188${sage_flag}'"
    venv_alias="alias comfyui-venv='source \"${venv_dir}/bin/activate\"'"
  fi

  [[ -f "$rc_file" ]] || touch "$rc_file"

  if grep -Fq "alias comfyui-start" "$rc_file"; then
    if [[ -n "$sage_flag" ]] && ! grep -Fq -- "--use-sage-attention" "$rc_file"; then
      sed -i "s|--port 8188'|--port 8188${sage_flag}'|" "$rc_file"
      say "Updated comfyui-start alias in $rc_file to enable SageAttention."
    else
      say "ComfyUI aliases already present in $rc_file; skipping."
    fi
    return 0
  fi

  {
    echo ""
    echo "# >>> ComfyUI aliases >>>"
    if [[ "$user_shell" == "fish" ]]; then
      echo "$start_alias"
      echo "$venv_alias"
    else
      echo "$start_alias"
      echo "$venv_alias"
    fi
    echo "# <<< ComfyUI aliases <<<"
  } >> "$rc_file"

  say "Added ComfyUI aliases to $rc_file"
  say "Reload your shell or run: source '$rc_file' to enable them."
}

handle_precompiled_wheels_menu() {
  local wheel_choice="" has_comfy="" install_choice="" comfy_dir=""

  ask "Is ComfyUI already installed on this system? (y/n):"
  read -r has_comfy
  if [[ "${has_comfy}" =~ ^[Yy]$ ]]; then
    if prompt_existing_comfy_path comfy_dir; then
      say "Precompiled wheel options:"
      echo "  1) Install SageAttention 2.2.0"
      echo "  2) Install InsightFace 0.7.3"
      confirm_choice "Enter 1 or 2:" "1 2" wheel_choice

      case "${wheel_choice}" in
        1)
          if install_sageattention_into_comfy "${comfy_dir}"; then
            say "Precompiled wheel installation finished."
          else
            err "Precompiled wheel installation failed."
          fi
          ;;
        2)
          if install_insightface_into_comfy "${comfy_dir}"; then
            say "Precompiled wheel installation finished."
          else
            err "Precompiled wheel installation failed."
          fi
          ;;
      esac
    fi
    return 0
  fi

  ask "Would you like to install ComfyUI now? (y/n):"
  read -r install_choice
  if [[ "${install_choice}" =~ ^[Yy]$ ]]; then
    say "Continuing with full ComfyUI installation..."
    RUN_FULL_INSTALL=1
    return 0
  fi

  warn "Cannot install precompiled wheels without a ComfyUI installation."
  say "Exiting without changes."
  return 0
}

detect_os_family() {
  if [[ ! -r /etc/os-release ]]; then
    err "Unable to determine OS: /etc/os-release not found."
    return 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  local id="${ID,,}"
  local id_like="${ID_LIKE:-}"
  id_like="${id_like,,}"

  case "$id" in
    fedora|rhel|centos|rocky|almalinux) echo "fedora"; return 0 ;;
    ubuntu|pop|linuxmint|elementary|zorin|neon) echo "ubuntu"; return 0 ;;
    arch|manjaro|endeavouros|garuda|arco|artix) echo "arch"; return 0 ;;
  esac

  for token in $id_like; do
    case "$token" in
      fedora|rhel|centos) echo "fedora"; return 0 ;;
      ubuntu|debian) echo "ubuntu"; return 0 ;;
      arch) echo "arch"; return 0 ;;
    esac
  done

  err "Unsupported or unrecognized Linux distribution (ID=$id, ID_LIKE=$id_like)."
  return 1
}

# ===================== primary action selection ====================
RUN_FULL_INSTALL=0

say "Choose what you would like to install:"
echo "  1) Install ComfyUI"
echo "  2) Install precompiled wheels"
confirm_choice "Enter 1 or 2:" "1 2" PRIMARY_ACTION

case "$PRIMARY_ACTION" in
  1)
    RUN_FULL_INSTALL=1
    ;;
  2)
    handle_precompiled_wheels_menu
    ;;
esac

if [[ "${RUN_FULL_INSTALL:-0}" -ne 1 ]]; then
  exit 0
fi

# ============================ choose OS ============================
say "Which Linux distribution are you using?"
echo "  1) Fedora"
echo "  2) Ubuntu (22.04/24.04+) / Linux Mint 22+"
echo "  3) Arch-based (Arch/Manjaro/Endeavour)"
confirm_choice "Enter 1, 2, or 3:" "1 2 3" OS_CHOICE

case "$OS_CHOICE" in
  1) OS_NAME="fedora" ;;
  2) OS_NAME="ubuntu" ;;
  3) OS_NAME="arch" ;;
esac
say "Selected OS: $OS_NAME"

if ! DETECTED_OS="$(detect_os_family)"; then
  err "Automatic OS verification failed. This installer currently supports Fedora, Ubuntu/Linux Mint, and Arch-based distributions."
  exit 1
fi

say "Detected OS: $DETECTED_OS"

if [[ "$DETECTED_OS" != "$OS_NAME" ]]; then
  err "Installer option '$OS_NAME' does not match detected system '$DETECTED_OS'. Please rerun and select the correct distribution."
  exit 1
fi

say "OS verification passed."

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

say "SageAttention compatibility:"
echo "  - RTX 40xx and 50xx: Fully supported with the latest software."
echo "  - RTX 30xx        : Fully supported."
echo "  - RTX 20xx and older: Limited compatibility; older drivers/software may be required."
ask "Would you like to install SageAttention 2.2.0? You can always install it later via the precompiled wheel installer option. (y/n):"
read -r INSTALL_SAGE_CHOICE
if [[ "$INSTALL_SAGE_CHOICE" =~ ^[Yy]$ ]]; then
  INSTALL_SAGE_ATTENTION=1
  say "SageAttention installation enabled."
else
  INSTALL_SAGE_ATTENTION=0
  say "Skipping SageAttention installation."
fi

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

  FEDORA_PKGS=(git curl make gcc gcc-c++ cmake
    openssl-devel bzip2-devel libffi-devel xz-devel readline-devel sqlite-devel tk-devel python3-devel)

  if rpm -q --quiet ffmpeg; then
    say "Detected RPM Fusion ffmpeg already installed; skipping package add."
  elif rpm -q --quiet ffmpeg-free; then
    say "Detected Fedora ffmpeg-free already installed; swapping to ffmpeg..."
    sudo "$PM" swap -y ffmpeg-free ffmpeg --allowerasing
  else
    FFMPEG_CANDIDATE=""
    if "$PM" list --available ffmpeg >/dev/null 2>&1; then
      FFMPEG_CANDIDATE="ffmpeg"
    elif "$PM" list --available ffmpeg-free >/dev/null 2>&1; then
      FFMPEG_CANDIDATE="ffmpeg-free"
    fi
    if [[ -n "$FFMPEG_CANDIDATE" ]]; then
      say "Queueing $FFMPEG_CANDIDATE for install."
      FEDORA_PKGS+=("$FFMPEG_CANDIDATE")
    else
      warn "Could not find an ffmpeg package in enabled repositories; continuing without it."
    fi
  fi

  sudo "$PM" -y install "${FEDORA_PKGS[@]}"
  # Ensure venv module exists for system python (pyenv will be used anyway)
  if ! python3 -c "import venv" 2>/dev/null; then
    warn "Python venv module missing; reinstalling python3..."
    sudo "$PM" -y reinstall python3
  fi

elif [[ "$OS_NAME" == "ubuntu" ]]; then
  sudo apt-get update
  sudo apt-get install -y build-essential git curl ffmpeg make cmake \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev tk-dev \
    libffi-dev xz-utils ca-certificates pkg-config \
    liblzma-dev libgdbm-dev libnss3-dev libncursesw5-dev

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

export PYENV_ROOT

if [[ -d "$PYENV_ROOT/bin" ]]; then
  export PATH="$PYENV_ROOT/bin:$PATH"
fi

if command -v pyenv >/dev/null 2>&1; then
  say "pyenv already installed."
else
  if [[ -d "$PYENV_ROOT" ]]; then
    say "Found existing pyenv directory; reusing it."
  else
    say "Installing pyenv..."
    git clone https://github.com/pyenv/pyenv.git "$PYENV_ROOT"
  fi
  export PATH="$PYENV_ROOT/bin:$PATH"
fi

ensure_pyenv_shell_config "bash" "$HOME/.bashrc" "$PYENV_ROOT"
CURRENT_LOGIN_SHELL="$(basename "${SHELL:-bash}")"
if [[ -f "$HOME/.zshrc" ]] || [[ "$CURRENT_LOGIN_SHELL" == "zsh" ]]; then
  ensure_pyenv_shell_config "zsh" "$HOME/.zshrc" "$PYENV_ROOT"
fi
FISH_CONFIG_PATH="$HOME/.config/fish/config.fish"
if [[ -f "$FISH_CONFIG_PATH" ]] || [[ "$CURRENT_LOGIN_SHELL" == "fish" ]]; then
  ensure_pyenv_shell_config "fish" "$FISH_CONFIG_PATH" "$PYENV_ROOT"
fi

if ! command -v pyenv >/dev/null 2>&1; then
  err "pyenv binary not found even after setup. Please check your installation."
  exit 1
fi

eval "$(pyenv init -)"

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
DEFAULT_DIR="${DEFAULT_COMFY_DIR}"
while true; do
  ask "Enter install location for ComfyUI (absolute path, e.g. /home/${USER:-user}/ComfyUI) [default: $DEFAULT_DIR]:"
  read -r INSTALL_DIR
  INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_DIR}"
  if [[ "$INSTALL_DIR" != /* ]]; then
    warn "Please enter a full absolute path starting with '/'."
    continue
  fi
  break
done

# Sanity checks & prepare parent directories
if [[ -e "$INSTALL_DIR" && ! -d "$INSTALL_DIR" ]]; then
  err "Path exists and is not a directory: $INSTALL_DIR"
  exit 1
fi
if [[ -d "$INSTALL_DIR" && -d "$INSTALL_DIR/.git" ]]; then
  warn "ComfyUI appears to already be installed at: $INSTALL_DIR"
  warn "Please remove or rename the existing directory before rerunning this installer."
  exit 0
fi
mkdir -p "$(dirname "$INSTALL_DIR")"

# ======================= ComfyUI + venv ===========================
say "Cloning ComfyUI into: $INSTALL_DIR"
git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git "$INSTALL_DIR"

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
# For option 2, we use version PAIRS with fallback to avoid resolver errors.
if [[ "${GPU_TIER}" == "2" ]]; then
  TORCH_PAIRS=("2.7.1 0.22.1" "2.7.0 0.22.0")   # (torch vision)
  AUDIO_VER="${AUDIO_VER:-2.7.1}"
  TRITON_VER="${TRITON_VER:-}"                  # let pip resolve or omit for 2.7.x
  TRY_CUDA_STREAMS=("cu121" "cu118")            # CUDA streams to try
else
  TORCH_PAIRS=("2.8.0 0.23.0")
  AUDIO_VER="${AUDIO_VER:-2.8.0}"
  TRITON_VER="${TRITON_VER:-3.4.0}"
  TRY_CUDA_STREAMS=("cu128" "cu126" "cu124")
fi

# =================== PyTorch stack (native attention) =============
say "Installing PyTorch (CUDA wheels), native attention (no xformers)..."

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
TORCH_VER=""
VISION_VER=""

# Try GPU streams with version pairs
for pair in "${TORCH_PAIRS[@]}"; do
  TORCH_VER="${pair%% *}"
  VISION_VER="${pair##* }"
  for stream in "${TRY_CUDA_STREAMS[@]}"; do
    export PIP_INDEX_URL="https://download.pytorch.org/whl/${stream}"
    export PIP_EXTRA_INDEX_URL="https://pypi.org/simple"
    say "Trying torch==${TORCH_VER}, torchvision==${VISION_VER} on ${stream} ..."
    install_cmd=(python -m pip install --no-cache-dir --force-reinstall
                 "torch==${TORCH_VER}" "torchvision==${VISION_VER}" "torchaudio==${AUDIO_VER}")
    if [[ -n "${TRITON_VER:-}" ]]; then install_cmd+=("triton==${TRITON_VER}"); fi
    if "${install_cmd[@]}"; then
      CUDA_PICKED="$stream"
      PYTORCH_OK=1
      break 2
    fi
  done
done

# If all CUDA streams failed, try CPU wheels with the same version pairs
if [[ $PYTORCH_OK -ne 1 ]]; then
  warn "CUDA wheels failed; trying CPU-only wheels..."
  export PIP_INDEX_URL="https://download.pytorch.org/whl/cpu"
  export PIP_EXTRA_INDEX_URL="https://pypi.org/simple"
  for pair in "${TORCH_PAIRS[@]}"; do
    TORCH_VER="${pair%% *}"
    VISION_VER="${pair##* }"
    say "Trying torch==${TORCH_VER}, torchvision==${VISION_VER} on CPU ..."
    install_cmd=(python -m pip install --no-cache-dir --force-reinstall
                 "torch==${TORCH_VER}" "torchvision==${VISION_VER}" "torchaudio==${AUDIO_VER}")
    if [[ -n "${TRITON_VER:-}" ]]; then install_cmd+=("triton==${TRITON_VER}"); fi
    if "${install_cmd[@]}"; then
      CUDA_PICKED="cpu"
      PYTORCH_OK=1
      break
    fi
  done
fi

if [[ $PYTORCH_OK -ne 1 ]]; then
  err "Could not install PyTorch stack."
  exit 1
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

# ===================== Custom node bootstrap ======================
say "Setting up ComfyUI custom nodes (Manager only)..."
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

CUSTOM_NODES_DIR="$INSTALL_DIR/custom_nodes"
mkdir -p "$CUSTOM_NODES_DIR"

MANAGER_DIR="$CUSTOM_NODES_DIR/comfyui-manager"
if [[ ! -d "$MANAGER_DIR/.git" ]]; then
  say "Cloning ComfyUI-Manager into custom_nodes..."
  git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager "$MANAGER_DIR"
else
  say "ComfyUI-Manager already exists; pulling latest changes..."
  git -C "$MANAGER_DIR" pull --ff-only || warn "ComfyUI-Manager update skipped."
fi

# ===================== SageAttention (optional) ===================
if [[ "${INSTALL_SAGE_ATTENTION:-0}" -eq 1 ]]; then
  SAGE_VERSION="2.2.0"
  SAGE_WHEEL_URL="https://huggingface.co/arcticlatent/misc/resolve/main/sageattention-${SAGE_VERSION}-cp312-cp312-linux_x86_64.whl"
  say "Installing SageAttention ${SAGE_VERSION} precompiled wheel..."
  if python -m pip install --upgrade "$SAGE_WHEEL_URL"; then
    say "SageAttention ${SAGE_VERSION} installed successfully from precompiled wheel."
    SAGE_FLAG=" --use-sage-attention"
  else
    warn "Failed to install SageAttention ${SAGE_VERSION} from precompiled wheel."
    SAGE_FLAG=""
  fi
else
  SAGE_FLAG=""
fi

# ====================== Modernize NVML binding ====================
say "Replacing deprecated pynvml package with nvidia-ml-py..."
python - <<'PY'
import subprocess, sys
try:
    import importlib.metadata as metadata
except ImportError:  # pragma: no cover
    import importlib_metadata as metadata

def have(dist: str) -> bool:
    try:
        metadata.version(dist)
        return True
    except metadata.PackageNotFoundError:
        return False

if have("pynvml"):
    subprocess.check_call([sys.executable, "-m", "pip", "uninstall", "-y", "pynvml"])

subprocess.check_call([sys.executable, "-m", "pip", "install", "--upgrade", "nvidia-ml-py"])
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
configure_comfy_aliases "$INSTALL_DIR" "${SAGE_FLAG:-}"

# ============================ finishing ===========================
say "ComfyUI is ready."

echo
say "How to run:"
USER_SHELL=$(basename "${SHELL:-bash}")
echo "  1) Activate venv and start manually:"
if [[ "$USER_SHELL" == "fish" ]]; then
  echo "       source \"$VENV_DIR/bin/activate.fish\""
else
  echo "       source \"$VENV_DIR/bin/activate\""
fi
echo "       python \"$INSTALL_DIR/main.py\" --listen 0.0.0.0 --port 8188${SAGE_FLAG}"
echo "  2) Or use the new aliases (after reloading your shell):"
echo "       comfyui-start      # activate venv + launch ComfyUI"
echo "       comfyui-venv       # activate venv only"
