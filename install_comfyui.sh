#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="1.25"
SCRIPT_SOURCE_URL_DEFAULT="https://raw.githubusercontent.com/ArcticLatent/linux-comfy-installer/main/install_comfyui.sh"
SCRIPT_SOURCE_URL="${LINUX_COMFY_INSTALLER_SOURCE:-$SCRIPT_SOURCE_URL_DEFAULT}"
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
SAGE_ACCELERATOR_LOCAL_PATH="${SCRIPT_DIR}/assets/sage.txt"
FLASH_ACCELERATOR_LOCAL_PATH="${SCRIPT_DIR}/assets/flash.txt"

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

print_usage() {
  cat <<'EOF'
Usage: install_comfyui.sh [--update] [--check-update] [--version]
  --update        Download and apply the latest installer script, then restart.
  --check-update  Check whether a newer version is available and report status.
  --version       Print the current installer version.
EOF
}

resolve_script_path() {
  local script="$1" resolved=""
  if command -v realpath >/dev/null 2>&1; then
    resolved="$(realpath "$script" 2>/dev/null || true)"
  elif command -v readlink >/dev/null 2>&1; then
    resolved="$(readlink -f "$script" 2>/dev/null || true)"
  fi

  if [[ -n "$resolved" ]]; then
    printf '%s\n' "$resolved"
    return 0
  fi

  if [[ "$script" == */* ]]; then
    (
      cd "$(dirname "$script")" >/dev/null 2>&1 || return 1
      printf '%s/%s\n' "$(pwd)" "$(basename "$script")"
    )
  else
    printf '%s/%s\n' "$(pwd)" "$script"
  fi
}

fetch_latest_version() {
  local remote_contents="" version_line=""

  if command -v curl >/dev/null 2>&1; then
    if ! remote_contents="$(curl -fsSL "$SCRIPT_SOURCE_URL" 2>/dev/null)"; then
      return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! remote_contents="$(wget -qO- "$SCRIPT_SOURCE_URL" 2>/dev/null)"; then
      return 1
    fi
  else
    warn "Cannot check for updates automatically because neither curl nor wget is available."
    return 1
  fi

  version_line="$(printf '%s\n' "$remote_contents" | grep -m1 '^SCRIPT_VERSION=' || true)"
  if [[ -z "$version_line" ]]; then
    return 1
  fi

  version_line="${version_line#SCRIPT_VERSION=\"}"
  version_line="${version_line%\"}"
  printf '%s\n' "$version_line"
}

download_remote_script() {
  local url="$1" dest="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest" 2>/dev/null || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url" 2>/dev/null || return 1
  else
    warn "Cannot download updates because neither curl nor wget is available."
    return 1
  fi
}

perform_self_update() {
  local new_version="$1"
  shift || true
  local remaining_args=("$@")
  local script_path temp_file

  script_path="$(resolve_script_path "$0")" || script_path="$0"
  if [[ -z "$script_path" ]]; then
    err "Unable to resolve script path for self-update."
    return 1
  fi

  if [[ ! -w "$script_path" ]]; then
    err "Cannot self-update: insufficient permissions to modify $script_path."
    return 1
  fi

  temp_file="$(mktemp "${TMPDIR:-/tmp}/install_comfyui.sh.XXXXXX")" || {
    err "Unable to create temporary file for update."
    return 1
  }

  if ! download_remote_script "$SCRIPT_SOURCE_URL" "$temp_file"; then
    rm -f "$temp_file"
    err "Failed to download latest installer from $SCRIPT_SOURCE_URL."
    return 1
  fi

  chmod +x "$temp_file" 2>/dev/null || true
  if mv "$temp_file" "$script_path"; then
    say "Installer updated to version ${new_version:-unknown}."
    exec "$script_path" "${remaining_args[@]}"
  else
    err "Failed to replace existing installer at $script_path."
    rm -f "$temp_file"
    return 1
  fi
}

check_for_updates() {
  local remote_version=""

  remote_version="$(fetch_latest_version)" || return 0
  if [[ -z "$remote_version" || "$remote_version" == "$SCRIPT_VERSION" ]]; then
    return 0
  fi

  warn "A new installer version is available ($SCRIPT_VERSION -> $remote_version)."
  ask "Would you like to update now? (y/n):"
  if ! read -r update_choice; then
    warn "No response received; continuing with installer version $SCRIPT_VERSION."
    return 0
  fi
  if [[ "$update_choice" =~ ^[Yy]$ ]]; then
    if ! perform_self_update "$remote_version" "$@"; then
      warn "Self-update failed; continuing with current version $SCRIPT_VERSION."
    fi
  else
    say "Continuing with installer version $SCRIPT_VERSION."
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
INSTALL_ARCTIC_NODES=0

install_arctic_nodes() {
  local comfy_dir="$1"
  local custom_nodes_dir="${comfy_dir}/custom_nodes"
  local arctic_dir="${custom_nodes_dir}/ArcticNodes"

  [[ -n "$comfy_dir" ]] || return 1
  need_cmd git
  mkdir -p "$custom_nodes_dir"

  if [[ -d "$arctic_dir/.git" ]]; then
    say "ArcticNodes already present; pulling latest changes..."
    git -C "$arctic_dir" pull --ff-only || warn "ArcticNodes update skipped."
  elif [[ -e "$arctic_dir" ]]; then
    warn "ArcticNodes path already exists and is not a git repo; skipping clone."
    return 0
  else
    say "Cloning ArcticNodes into custom_nodes..."
    git clone --depth=1 https://github.com/ArcticLatent/ArcticNodes "$arctic_dir"
  fi
}

install_trellis2_nodes() {
  local comfy_dir="$1"
  local custom_nodes_dir="${comfy_dir}/custom_nodes"
  local trellis_dir="${custom_nodes_dir}/ComfyUI-TRELLIS2"
  local geometry_dir="${custom_nodes_dir}/ComfyUI-GeometryPack"
  local ultrashape1_dir="${custom_nodes_dir}/ComfyUI-UltraShape1"
  local venv_python="${comfy_dir}/venv/bin/python"
  local venv_activate="${comfy_dir}/venv/bin/activate"

  [[ -n "$comfy_dir" ]] || return 1
  need_cmd git
  if [[ ! -x "$venv_python" ]]; then
    err "ComfyUI venv python not found at ${venv_python}."
    return 1
  fi
  mkdir -p "$custom_nodes_dir"

  if [[ -d "$trellis_dir/.git" ]]; then
    say "ComfyUI-TRELLIS2 already present; pulling latest changes..."
    git -C "$trellis_dir" pull --ff-only || warn "ComfyUI-TRELLIS2 update skipped."
  elif [[ -e "$trellis_dir" ]]; then
    warn "ComfyUI-TRELLIS2 path already exists and is not a git repo; skipping clone."
  else
    say "Cloning ComfyUI-TRELLIS2 into custom_nodes..."
    git clone --depth=1 https://github.com/ArcticLatent/ComfyUI-TRELLIS2 "$trellis_dir"
  fi

  if [[ -f "$trellis_dir/requirements.txt" ]]; then
    say "Installing ComfyUI-TRELLIS2 requirements into ${comfy_dir} venv..."
    if [[ -f "$venv_activate" ]]; then
      (source "$venv_activate" && pip install -r "$trellis_dir/requirements.txt") || \
        warn "ComfyUI-TRELLIS2 requirements install failed."
    else
      "$venv_python" -m pip install -r "$trellis_dir/requirements.txt" || \
        warn "ComfyUI-TRELLIS2 requirements install failed."
    fi
  else
    warn "requirements.txt not found in ${trellis_dir}; skipping pip install."
  fi

  if [[ -d "$geometry_dir/.git" ]]; then
    say "ComfyUI-GeometryPack already present; pulling latest changes..."
    git -C "$geometry_dir" pull --ff-only || warn "ComfyUI-GeometryPack update skipped."
  elif [[ -e "$geometry_dir" ]]; then
    warn "ComfyUI-GeometryPack path already exists and is not a git repo; skipping clone."
  else
    say "Cloning ComfyUI-GeometryPack into custom_nodes..."
    git clone --depth=1 https://github.com/PozzettiAndrea/ComfyUI-GeometryPack "$geometry_dir"
  fi

  if [[ -f "$geometry_dir/requirements.txt" ]]; then
    say "Installing ComfyUI-GeometryPack requirements into ${comfy_dir} venv..."
    if [[ -f "$venv_activate" ]]; then
      (source "$venv_activate" && pip install -r "$geometry_dir/requirements.txt") || \
        warn "ComfyUI-GeometryPack requirements install failed."
    else
      "$venv_python" -m pip install -r "$geometry_dir/requirements.txt" || \
        warn "ComfyUI-GeometryPack requirements install failed."
    fi
  else
    warn "requirements.txt not found in ${geometry_dir}; skipping pip install."
  fi

  if [[ -d "$ultrashape1_dir/.git" ]]; then
    say "ComfyUI-UltraShape1 already present; pulling latest changes..."
    git -C "$ultrashape1_dir" pull --ff-only || warn "ComfyUI-UltraShape1 update skipped."
  elif [[ -e "$ultrashape1_dir" ]]; then
    warn "ComfyUI-UltraShape1 path already exists and is not a git repo; skipping clone."
  else
    say "Cloning ComfyUI-UltraShape1 into custom_nodes..."
    git clone --depth=1 https://github.com/jtydhr88/ComfyUI-UltraShape1 "$ultrashape1_dir"
  fi

  if [[ -f "$ultrashape1_dir/requirements.txt" ]]; then
    say "Installing ComfyUI-UltraShape1 requirements into ${comfy_dir} venv..."
    if [[ -f "$venv_activate" ]]; then
      (source "$venv_activate" && cd "$ultrashape1_dir" && pip install -r requirements.txt && \
        pip install -U accelerate) || \
        warn "ComfyUI-UltraShape1 requirements install failed."
    else
      (cd "$ultrashape1_dir" && "$venv_python" -m pip install -r requirements.txt && \
        "$venv_python" -m pip install -U accelerate) || \
        warn "ComfyUI-UltraShape1 requirements install failed."
    fi
  else
    warn "requirements.txt not found in ${ultrashape1_dir}; skipping pip install."
  fi

  local ultrashape_models_dir="${comfy_dir}/models/UltraShape"
  local ultrashape_model_file="${ultrashape_models_dir}/ultrashape_v1.pt"
  local ultrashape_model_url="https://huggingface.co/infinith/UltraShape/resolve/main/ultrashape_v1.pt"

  mkdir -p "$ultrashape_models_dir"
  if [[ -f "$ultrashape_model_file" ]]; then
    say "UltraShape model already present at ${ultrashape_model_file}; skipping download."
  else
    say "Downloading UltraShape model to ${ultrashape_model_file}..."
    if ! download_remote_script "$ultrashape_model_url" "$ultrashape_model_file"; then
      warn "UltraShape model download failed."
    fi
  fi
}

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

configure_extra_model_path() {
  local install_dir="$1"
  local example_path="${install_dir}/extra_model_paths.yaml.example"
  local target_path="${install_dir}/extra_model_paths.yaml"
  local choice="" extra_models_path="" default_choice="" is_default_value=""

  ask "Configure an extra model folder for ComfyUI? (y/n):"
  read -r choice
  if [[ ! "$choice" =~ ^[Yy]$ ]]; then
    return 0
  fi

  if [[ -f "$example_path" ]]; then
    mv "$example_path" "$target_path"
  elif [[ -f "$target_path" ]]; then
    say "Found existing extra_model_paths.yaml; it will be overwritten."
  else
    warn "extra_model_paths.yaml.example not found in ${install_dir}; skipping extra model path setup."
    return 0
  fi

  while true; do
    ask "Enter absolute path for extra model folder (e.g. /mnt/cache/models):"
    read -r extra_models_path
    if [[ -z "$extra_models_path" ]]; then
      warn "Path cannot be empty."
      continue
    fi
    if [[ "$extra_models_path" != /* ]]; then
      warn "Please enter a full absolute path starting with '/'."
      continue
    fi
    break
  done

  : > "$target_path"

  ask "Should this folder be the default models folder for ComfyUI? (y/n):"
  read -r default_choice
  if [[ "$default_choice" =~ ^[Yy]$ ]]; then
    is_default_value="true"
  else
    is_default_value="false"
  fi

  cat >> "$target_path" <<EOF
comfyui:
  base_path: ${extra_models_path}
  # Optional - makes these your main/default save/load location
  is_default: ${is_default_value}

  checkpoints: checkpoints
  text_encoders: |
    text_encoders
    clip             # legacy format still supported
  clip_vision: clip_vision
  configs: configs
  controlnet: controlnet
  diffusion_models: |
    diffusion_models
    unet
  embeddings: embeddings
  loras: loras
  upscale_models: upscale_models
  vae: vae
  audio_encoders: audio_encoders
  model_patches: model_patches
EOF

  say "extra_model_paths.yaml created at ${target_path}"
}

install_sageattention_into_comfy() {
  local comfy_dir="$1"
  local python_bin="${comfy_dir}/venv/bin/python"
  local sage_version="2.2.0"
  local sage_wheel_url="https://huggingface.co/arcticlatent/misc/resolve/main/sageattention-${sage_version}-cp312-cp312-linux_x86_64.whl"

  say "Installing SageAttention ${sage_version} into ${comfy_dir}..."
  if "${python_bin}" -m pip install --upgrade "${sage_wheel_url}"; then
    say "SageAttention ${sage_version} installed successfully."
  else
    err "Failed to install SageAttention ${sage_version} into ${comfy_dir}."
    return 1
  fi
}

install_insightface_into_comfy() {
  local comfy_dir="$1"
  local python_bin="${comfy_dir}/venv/bin/python"
  local pip_bin="${comfy_dir}/venv/bin/pip"
  local custom_nodes_dir="${comfy_dir}/custom_nodes"
  local insight_version="0.7.3"
  local insight_wheel_url="https://huggingface.co/arcticlatent/misc/resolve/main/insightface-${insight_version}-cp312-cp312-linux_x86_64.whl"

  say "Installing InsightFace ${insight_version} into ${comfy_dir}..."
  if "${python_bin}" -m pip install --upgrade "${insight_wheel_url}"; then
    say "InsightFace ${insight_version} installed successfully."
  else
    err "Failed to install InsightFace ${insight_version} into ${comfy_dir}."
    return 1
  fi

  # Optional PuLID Flux adjustments: install facenet-pytorch and patch signature if node exists
  if [[ ! -x "$pip_bin" ]]; then
    warn "ComfyUI venv pip not found at ${pip_bin}; skipping PuLID Flux tweaks."
    return 0
  fi
  if [[ ! -d "$custom_nodes_dir" ]]; then
    say "No custom_nodes directory found at ${custom_nodes_dir}; skipping PuLID Flux tweaks."
    return 0
  fi

  local pulid_dir=""
  while IFS= read -r node_path; do
    local base
    base="$(basename "$node_path")"
    if [[ "${base,,}" == "comfyui_pulid_flux_ll" ]]; then
      pulid_dir="$node_path"
      break
    fi
  done < <(find "$custom_nodes_dir" -maxdepth 1 -mindepth 1 -type d -print 2>/dev/null)

  if [[ -z "$pulid_dir" ]]; then
    err "you dont have ComfyUI_PuLID_Flux_ll custom node installed in your comfyui install. please first install the custom node using your comfyui manager"
    return 1
  fi

  say "Installing facenet-pytorch (no deps) inside ${pulid_dir}..."
  if ! "$pip_bin" install facenet-pytorch --no-deps; then
    warn "facenet-pytorch install failed in ${pulid_dir}; please install manually."
  fi

  local pulid_file="${pulid_dir}/pulidflux.py"
  if [[ ! -f "$pulid_file" ]]; then
    warn "pulidflux.py not found in ${pulid_dir}; skipping signature patch."
    return 0
  fi

  if "$python_bin" - "$pulid_file" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
old = "def pulid_outer_sample_wrappers_with_override(wrapper_executor, noise, latent_image, sampler, sigmas, denoise_mask=None, callback=None, disable_pbar=False, seed=None):"
new = "def pulid_outer_sample_wrappers_with_override(wrapper_executor, noise, latent_image, sampler, sigmas, denoise_mask=None, callback=None, disable_pbar=False, seed=None, latent_shapes=None):"
text = path.read_text()
if old not in text:
    print("PuLID Flux: target signature not found; no change made.")
    sys.exit(0)
path.write_text(text.replace(old, new, 1))
print("PuLID Flux: updated outer wrapper signature.")
PY
  then
    say "PuLID Flux signature patch complete in ${pulid_file}."
  else
    warn "Failed to patch pulidflux.py in ${pulid_dir}."
  fi
}

configure_comfy_aliases() {
  local install_dir="$1"
  local attention_mode="${2:-}"
  local venv_dir="${install_dir}/venv"
  local user_shell rc_file start_alias venv_alias start_attention_alias="" start_attention_fp16_alias=""
  local suffix_num="" max_suffix=0 has_alias_for_install=0 suffix_note=""
  local -a rc_candidates=()
  local attention_prefix=""
  local include_attention=0

  case "$attention_mode" in
    sage) attention_prefix="sage" ; include_attention=1 ;;
    flash) attention_prefix="flash" ; include_attention=1 ;;
    *) attention_mode="" ;;
  esac

  COMFY_ALIAS_START="${COMFY_ALIAS_START:-}"
  COMFY_ALIAS_SAGE="${COMFY_ALIAS_SAGE:-}"
  COMFY_ALIAS_SAGE_FP16="${COMFY_ALIAS_SAGE_FP16:-}"
  COMFY_ALIAS_FLASH="${COMFY_ALIAS_FLASH:-}"
  COMFY_ALIAS_FLASH_FP16="${COMFY_ALIAS_FLASH_FP16:-}"
  COMFY_ALIAS_VENV="${COMFY_ALIAS_VENV:-}"

  user_shell=$(basename "${SHELL:-bash}")

  [[ -f "$HOME/.bashrc" || "$user_shell" == "bash" ]] && rc_candidates+=("bash:$HOME/.bashrc")
  [[ -f "$HOME/.zshrc"  || "$user_shell" == "zsh"  ]] && rc_candidates+=("zsh:$HOME/.zshrc")
  [[ -f "$HOME/.config/fish/config.fish" || "$user_shell" == "fish" ]] && rc_candidates+=("fish:$HOME/.config/fish/config.fish")

  if [[ ${#rc_candidates[@]} -eq 0 ]]; then
    warn "No known shell rc files found; skipping alias setup."
    return 0
  fi

  # Determine suffix and whether aliases for this install already exist across rc files
  for entry in "${rc_candidates[@]}"; do
    local rc="${entry#*:}"
    [[ -f "$rc" ]] || continue
    if grep -Fq "$install_dir" "$rc"; then
      has_alias_for_install=1
    fi
    while read -r existing_alias; do
      local name part num
      name="${existing_alias#alias }"
      name="${name%%[ =]*}"
      part="${name#comfyui-start}"
      part="${part#-}"
      if [[ -z "$part" ]]; then
        num=1
      elif [[ "$part" =~ ^[0-9]+$ ]]; then
        num="$part"
      else
        continue
      fi
      if (( num > max_suffix )); then
        max_suffix="$num"
      fi
    done < <(grep -E '^alias[[:space:]]+comfyui-start-?[0-9]*\b' "$rc" || true)
  done

  # Reuse existing aliases for this install (no duplicates)
  if [[ "$has_alias_for_install" -eq 1 ]]; then
    for entry in "${rc_candidates[@]}"; do
      local rc="${entry#*:}"
      [[ -f "$rc" ]] || continue
      while read -r line; do
        local name
        [[ "$line" != *"$install_dir"* ]] && continue
        name="${line#alias }"
        name="${name%%[ =]*}"
        case "$name" in
          comfyui-start*) COMFY_ALIAS_START="${COMFY_ALIAS_START:-$name}" ;;
          comfyui-start-sage*) COMFY_ALIAS_SAGE="${COMFY_ALIAS_SAGE:-$name}" ;;
          comfyui-start-sage-fp16*) COMFY_ALIAS_SAGE_FP16="${COMFY_ALIAS_SAGE_FP16:-$name}" ;;
          comfyui-start-flash*) COMFY_ALIAS_FLASH="${COMFY_ALIAS_FLASH:-$name}" ;;
          comfyui-start-flash-fp16*) COMFY_ALIAS_FLASH_FP16="${COMFY_ALIAS_FLASH_FP16:-$name}" ;;
          comfyui-venv*) COMFY_ALIAS_VENV="${COMFY_ALIAS_VENV:-$name}" ;;
        esac
      done < <(grep -E '^alias[[:space:]]+comfyui-(start|venv)[^[:space:]]*' "$rc" || true)

      # Remove aliases that don't match current attention mode to avoid stale entries
      if [[ "$include_attention" -eq 0 ]]; then
        sed -i '/alias[[:space:]]\+comfyui-start-sage/d;/alias[[:space:]]\+comfyui-start-sage-fp16/d;/alias[[:space:]]\+comfyui-start-flash/d;/alias[[:space:]]\+comfyui-start-flash-fp16/d' "$rc"
        COMFY_ALIAS_SAGE=""
        COMFY_ALIAS_SAGE_FP16=""
        COMFY_ALIAS_FLASH=""
        COMFY_ALIAS_FLASH_FP16=""
      elif [[ "$attention_prefix" == "flash" ]]; then
        sed -i '/alias[[:space:]]\+comfyui-start-sage/d;/alias[[:space:]]\+comfyui-start-sage-fp16/d' "$rc"
        COMFY_ALIAS_SAGE=""
        COMFY_ALIAS_SAGE_FP16=""
      elif [[ "$attention_prefix" == "sage" ]]; then
        sed -i '/alias[[:space:]]\+comfyui-start-flash/d;/alias[[:space:]]\+comfyui-start-flash-fp16/d' "$rc"
        COMFY_ALIAS_FLASH=""
        COMFY_ALIAS_FLASH_FP16=""
      fi
    done
    # If attention run and aliases missing, add them to current shell rc
    if [[ "$include_attention" -eq 1 ]]; then
      local attention_alias_ref attention_alias_fp16_ref attention_flag=""
      if [[ "$attention_prefix" == "flash" ]]; then
        attention_alias_ref="COMFY_ALIAS_FLASH"
        attention_alias_fp16_ref="COMFY_ALIAS_FLASH_FP16"
        attention_flag="--use-flash-attention"
      else
        attention_alias_ref="COMFY_ALIAS_SAGE"
        attention_alias_fp16_ref="COMFY_ALIAS_SAGE_FP16"
        attention_flag="--use-sage-attention"
      fi

      local current_attention_alias="${!attention_alias_ref}"
      local current_attention_fp16_alias="${!attention_alias_fp16_ref}"

      if [[ -z "$current_attention_alias" || -z "$current_attention_fp16_alias" ]]; then
        if [[ "$user_shell" == "bash" ]]; then
          rc_file="$HOME/.bashrc"
        elif [[ "$user_shell" == "zsh" ]]; then
          rc_file="$HOME/.zshrc"
        elif [[ "$user_shell" == "fish" ]]; then
          rc_file="$HOME/.config/fish/config.fish"
        else
          warn "Unknown shell type ($user_shell); skipping attention alias setup."
          return 0
        fi
        [[ "$user_shell" == "fish" ]] && mkdir -p "$(dirname "$rc_file")"
        [[ -f "$rc_file" ]] || touch "$rc_file"

      # Derive suffix from existing comfyui-start alias if present
      suffix_num=""
      if [[ -n "$COMFY_ALIAS_START" ]]; then
        local part="${COMFY_ALIAS_START#comfyui-start}"
        part="${part#-}"
        if [[ "$part" =~ ^[0-9]+$ ]]; then
          suffix_num="$part"
        fi
      fi
      local suffix_fmt=""
      [[ -n "$suffix_num" ]] && suffix_fmt="-$suffix_num"
      local attention_alias_name="comfyui-start-${attention_prefix}${suffix_fmt}"
      local attention_alias_fp16_name="comfyui-start-${attention_prefix}-fp16${suffix_fmt}"

      if [[ "$attention_prefix" == "flash" ]]; then
        COMFY_ALIAS_FLASH="${COMFY_ALIAS_FLASH:-$attention_alias_name}"
        COMFY_ALIAS_FLASH_FP16="${COMFY_ALIAS_FLASH_FP16:-$attention_alias_fp16_name}"
      else
        COMFY_ALIAS_SAGE="${COMFY_ALIAS_SAGE:-$attention_alias_name}"
        COMFY_ALIAS_SAGE_FP16="${COMFY_ALIAS_SAGE_FP16:-$attention_alias_fp16_name}"
      fi

      if [[ "$user_shell" == "fish" ]]; then
        start_attention_alias="alias ${attention_alias_name} 'source ${venv_dir}/bin/activate.fish; python ${install_dir}/main.py --listen 0.0.0.0 --port 8188 ${attention_flag}'"
        start_attention_fp16_alias="alias ${attention_alias_fp16_name} 'source ${venv_dir}/bin/activate.fish; python ${install_dir}/main.py --listen 0.0.0.0 --port 8188 ${attention_flag} --fast'"
      else
        start_attention_alias="alias ${attention_alias_name}='source \"${venv_dir}/bin/activate\" && python \"${install_dir}/main.py\" --listen 0.0.0.0 --port 8188 ${attention_flag}'"
        start_attention_fp16_alias="alias ${attention_alias_fp16_name}='source \"${venv_dir}/bin/activate\" && python \"${install_dir}/main.py\" --listen 0.0.0.0 --port 8188 ${attention_flag} --fast'"
      fi
      if ! grep -Fq "alias ${attention_alias_name}" "$rc_file"; then
        echo "$start_attention_alias" >> "$rc_file"
      fi
      if ! grep -Fq "alias ${attention_alias_fp16_name}" "$rc_file"; then
        echo "$start_attention_fp16_alias" >> "$rc_file"
      fi
      say "Added ${attention_prefix^} aliases for accelerator install to $rc_file"
      COMFY_ALIAS_NOTE="Existing aliases reused; ${attention_prefix^} aliases added."
    else
      say "ComfyUI aliases already exist for $install_dir; skipping duplicate entries."
      COMFY_ALIAS_NOTE="Existing aliases reused; none added."
    fi

    # Ensure alias vars are populated for downstream messaging
    if [[ -z "$suffix_num" && -n "$COMFY_ALIAS_START" ]]; then
      part="${COMFY_ALIAS_START#comfyui-start}"
      part="${part#-}"
      if [[ "$part" =~ ^[0-9]+$ ]]; then
        suffix_num="$part"
      fi
    fi
    local suffix_fmt=""
    [[ -n "$suffix_num" ]] && suffix_fmt="-$suffix_num"
    COMFY_ALIAS_START="${COMFY_ALIAS_START:-comfyui-start${suffix_fmt}}"
    COMFY_ALIAS_VENV="${COMFY_ALIAS_VENV:-comfyui-venv${suffix_fmt}}"
    if [[ "$include_attention" -eq 1 ]]; then
      if [[ "$attention_prefix" == "flash" ]]; then
        COMFY_ALIAS_FLASH="${COMFY_ALIAS_FLASH:-comfyui-start-flash${suffix_fmt}}"
        COMFY_ALIAS_FLASH_FP16="${COMFY_ALIAS_FLASH_FP16:-comfyui-start-flash-fp16${suffix_fmt}}"
      else
        COMFY_ALIAS_SAGE="${COMFY_ALIAS_SAGE:-comfyui-start-sage${suffix_fmt}}"
        COMFY_ALIAS_SAGE_FP16="${COMFY_ALIAS_SAGE_FP16:-comfyui-start-sage-fp16${suffix_fmt}}"
      fi
    fi

    fi

    return 0
  fi

  if [[ "$max_suffix" -ge 1 ]]; then
    suffix_num=$((max_suffix + 1))
    suffix_note="Existing ComfyUI aliases point elsewhere; creating numbered aliases for this install."
  fi

  # Select rc file for current shell to write new aliases
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
  fi
  [[ -f "$rc_file" ]] || touch "$rc_file"

  local suffix_fmt=""
  [[ -n "$suffix_num" ]] && suffix_fmt="-$suffix_num"

  local start_name="comfyui-start${suffix_fmt}"
  local venv_name="comfyui-venv${suffix_fmt}"
  local start_attention_name=""
  local start_attention_fp16_name=""
  local attention_flag=""
  if [[ "$attention_prefix" == "flash" ]]; then
    attention_flag="--use-flash-attention"
  elif [[ "$attention_prefix" == "sage" ]]; then
    attention_flag="--use-sage-attention"
  fi
  if [[ "$include_attention" -eq 1 ]]; then
    start_attention_name="comfyui-start-${attention_prefix}${suffix_fmt}"
    start_attention_fp16_name="comfyui-start-${attention_prefix}-fp16${suffix_fmt}"
  fi

  if [[ "$user_shell" == "fish" ]]; then
    mkdir -p "$(dirname "$rc_file")"
    start_alias="alias ${start_name} 'source ${venv_dir}/bin/activate.fish; python ${install_dir}/main.py --listen 0.0.0.0 --port 8188'"
    venv_alias="alias ${venv_name} 'source ${venv_dir}/bin/activate.fish'"
    if [[ "$include_attention" -eq 1 ]]; then
      start_attention_alias="alias ${start_attention_name} 'source ${venv_dir}/bin/activate.fish; python ${install_dir}/main.py --listen 0.0.0.0 --port 8188 ${attention_flag}'"
      start_attention_fp16_alias="alias ${start_attention_fp16_name} 'source ${venv_dir}/bin/activate.fish; python ${install_dir}/main.py --listen 0.0.0.0 --port 8188 ${attention_flag} --fast'"
    fi
  else
    start_alias="alias ${start_name}='source \"${venv_dir}/bin/activate\" && python \"${install_dir}/main.py\" --listen 0.0.0.0 --port 8188'"
    venv_alias="alias ${venv_name}='source \"${venv_dir}/bin/activate\"'"
    if [[ "$include_attention" -eq 1 ]]; then
      start_attention_alias="alias ${start_attention_name}='source \"${venv_dir}/bin/activate\" && python \"${install_dir}/main.py\" --listen 0.0.0.0 --port 8188 ${attention_flag}'"
      start_attention_fp16_alias="alias ${start_attention_fp16_name}='source \"${venv_dir}/bin/activate\" && python \"${install_dir}/main.py\" --listen 0.0.0.0 --port 8188 ${attention_flag} --fast'"
    fi
  fi

  local -a new_aliases=()
  if ! grep -Fq "alias ${start_name}" "$rc_file"; then
    new_aliases+=("$start_alias")
  fi
  if [[ "$include_attention" -eq 1 && -n "$start_attention_alias" ]]; then
    if ! grep -Fq "alias ${start_attention_name}" "$rc_file"; then
      new_aliases+=("$start_attention_alias")
    fi
  fi
  if [[ "$include_attention" -eq 1 && -n "$start_attention_fp16_alias" ]]; then
    if ! grep -Fq "alias ${start_attention_fp16_name}" "$rc_file"; then
      new_aliases+=("$start_attention_fp16_alias")
    fi
  fi
  if ! grep -Fq "alias ${venv_name}" "$rc_file"; then
    new_aliases+=("$venv_alias")
  fi

  if [[ ${#new_aliases[@]} -eq 0 ]]; then
    say "ComfyUI aliases already present in $rc_file; skipping."
    return 0
  fi

  {
    echo ""
    echo "# >>> ComfyUI aliases >>>"
    for alias_line in "${new_aliases[@]}"; do
      echo "$alias_line"
    done
    echo "# <<< ComfyUI aliases <<<"
  } >> "$rc_file"

  say "Added ComfyUI aliases to $rc_file"
  if [[ -n "$suffix_note" ]]; then
    say "$suffix_note"
    say "New aliases: ${start_name}, ${venv_name}${start_attention_name:+, ${start_attention_name}}"
  fi
  say "Reload your shell or run: source '$rc_file' to enable them."

  COMFY_ALIAS_START="$start_name"
  COMFY_ALIAS_VENV="$venv_name"
  if [[ "$include_attention" -eq 1 ]]; then
    if [[ "$attention_prefix" == "flash" ]]; then
      COMFY_ALIAS_FLASH="$start_attention_name"
      COMFY_ALIAS_FLASH_FP16="$start_attention_fp16_name"
    else
      COMFY_ALIAS_SAGE="$start_attention_name"
      COMFY_ALIAS_SAGE_FP16="$start_attention_fp16_name"
    fi
  fi
  COMFY_ALIAS_NOTE="$suffix_note"
}

# Re-read aliases from rc files to ensure display uses actual names (handles suffixes across installs)
refresh_comfy_alias_vars() {
  local install_dir="$1"
  local attention_mode="${2:-}"
  local -a rc_candidates=()
  local user_shell
  local attention_prefix=""
  local include_attention=0

  COMFY_ALIAS_START=""
  COMFY_ALIAS_SAGE=""
  COMFY_ALIAS_SAGE_FP16=""
  COMFY_ALIAS_FLASH=""
  COMFY_ALIAS_FLASH_FP16=""
  COMFY_ALIAS_VENV=""

  case "$attention_mode" in
    sage) attention_prefix="sage" ; include_attention=1 ;;
    flash) attention_prefix="flash" ; include_attention=1 ;;
    *) attention_mode="" ;;
  esac

  user_shell=$(basename "${SHELL:-bash}")
  [[ -f "$HOME/.bashrc" || "$user_shell" == "bash" ]] && rc_candidates+=("$HOME/.bashrc")
  [[ -f "$HOME/.zshrc"  || "$user_shell" == "zsh"  ]] && rc_candidates+=("$HOME/.zshrc")
  [[ -f "$HOME/.config/fish/config.fish" || "$user_shell" == "fish" ]] && rc_candidates+=("$HOME/.config/fish/config.fish")

  for rc in "${rc_candidates[@]}"; do
    [[ -f "$rc" ]] || continue
    if ! grep -Fq "$install_dir" "$rc"; then
      continue
    fi
    while read -r line; do
      [[ "$line" != *"$install_dir"* ]] && continue
      local name
      name="${line#alias }"
      name="${name%%[ =]*}"
      case "$name" in
        comfyui-start*) COMFY_ALIAS_START="${COMFY_ALIAS_START:-$name}" ;;
        comfyui-start-sage*) COMFY_ALIAS_SAGE="${COMFY_ALIAS_SAGE:-$name}" ;;
        comfyui-start-sage-fp16*) COMFY_ALIAS_SAGE_FP16="${COMFY_ALIAS_SAGE_FP16:-$name}" ;;
        comfyui-start-flash*) COMFY_ALIAS_FLASH="${COMFY_ALIAS_FLASH:-$name}" ;;
        comfyui-start-flash-fp16*) COMFY_ALIAS_FLASH_FP16="${COMFY_ALIAS_FLASH_FP16:-$name}" ;;
        comfyui-venv*) COMFY_ALIAS_VENV="${COMFY_ALIAS_VENV:-$name}" ;;
      esac
    done < <(grep -E '^alias[[:space:]]+comfyui-(start|venv)[^[:space:]]*' "$rc" || true)
  done

  local suffix_num=""
  if [[ -n "$COMFY_ALIAS_START" ]]; then
    local part="${COMFY_ALIAS_START#comfyui-start}"
    part="${part#-}"
    if [[ "$part" =~ ^[0-9]+$ ]]; then
      suffix_num="$part"
    fi
  fi
  local suffix_fmt=""
  [[ -n "$suffix_num" ]] && suffix_fmt="-$suffix_num"
  COMFY_ALIAS_START="${COMFY_ALIAS_START:-comfyui-start${suffix_fmt}}"
  COMFY_ALIAS_VENV="${COMFY_ALIAS_VENV:-comfyui-venv${suffix_fmt}}"
  if [[ "$include_attention" -eq 1 ]]; then
    if [[ "$attention_prefix" == "flash" ]]; then
      COMFY_ALIAS_FLASH="${COMFY_ALIAS_FLASH:-comfyui-start-flash${suffix_fmt}}"
      COMFY_ALIAS_FLASH_FP16="${COMFY_ALIAS_FLASH_FP16:-comfyui-start-flash-fp16${suffix_fmt}}"
      COMFY_ALIAS_SAGE=""
      COMFY_ALIAS_SAGE_FP16=""
    else
      COMFY_ALIAS_SAGE="${COMFY_ALIAS_SAGE:-comfyui-start-sage${suffix_fmt}}"
      COMFY_ALIAS_SAGE_FP16="${COMFY_ALIAS_SAGE_FP16:-comfyui-start-sage-fp16${suffix_fmt}}"
      COMFY_ALIAS_FLASH=""
      COMFY_ALIAS_FLASH_FP16=""
    fi
  else
    COMFY_ALIAS_SAGE=""
    COMFY_ALIAS_SAGE_FP16=""
    COMFY_ALIAS_FLASH=""
    COMFY_ALIAS_FLASH_FP16=""
  fi
}

handle_precompiled_wheels_menu() {
  local wheel_choice="" has_comfy="" install_choice="" comfy_dir=""

  ask "Is ComfyUI already installed on this system? (y/n):"
  read -r has_comfy
  if [[ "${has_comfy}" =~ ^[Yy]$ ]]; then
    if prompt_existing_comfy_path comfy_dir; then
      say "Precompiled wheel options:"
      echo "  1) Install InsightFace 0.7.3"
      confirm_choice "Enter 1 to continue:" "1" wheel_choice

      case "${wheel_choice}" in
        1)
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

install_fluxgym_prereqs() {
  local detected_os="" pkg_cmd=""

  say "Detecting OS for Fluxgym prerequisites..."
  if ! detected_os="$(detect_os_family)"; then
    err "Fluxgym installer: unable to detect supported OS."
    return 1
  fi

  case "$detected_os" in
    arch)
      need_cmd sudo
      say "Installing Fluxgym build dependencies for Arch-based systems..."
      sudo pacman -S --needed base-devel cmake pkgconf gcc-fortran openblas lapack
      ;;
    fedora)
      need_cmd sudo
      if command -v dnf5 >/dev/null 2>&1; then
        pkg_cmd="dnf5"
      else
        pkg_cmd="dnf"
      fi
      say "Installing Fluxgym build dependencies for Fedora..."
      sudo "$pkg_cmd" install -y gcc-gfortran openblas-devel lapack-devel cmake pkgconf
      ;;
    ubuntu)
      need_cmd sudo
      say "Installing Fluxgym build dependencies for Ubuntu/Linux Mint..."
      sudo apt install -y build-essential gfortran \
        libopenblas-dev liblapack-dev \
        cmake pkg-config
      ;;
    *)
      err "Fluxgym installer: unsupported OS family '$detected_os'."
      return 1
      ;;
  esac

  say "Fluxgym prerequisites installed."
}

ensure_fluxgym_pyenv() {
  local pyenv_root="${HOME}/.pyenv"
  local current_shell

  if [[ -x "$pyenv_root/bin/pyenv" ]]; then
    export PYENV_ROOT="$pyenv_root"
    export PATH="$PYENV_ROOT/bin:$PATH"
    say "pyenv already installed at $pyenv_root."
    return 0
  fi

  if [[ -d "$pyenv_root" ]]; then
    say "Found existing pyenv directory at $pyenv_root; ensuring binary presence..."
  else
    say "pyenv not found at $pyenv_root; installing..."
    need_cmd git
    git clone https://github.com/pyenv/pyenv.git "$pyenv_root"
  fi

  export PYENV_ROOT="$pyenv_root"
  export PATH="$PYENV_ROOT/bin:$PATH"

  current_shell="$(basename "${SHELL:-bash}")"
  ensure_pyenv_shell_config "bash" "$HOME/.bashrc" "$PYENV_ROOT"
  if [[ "$current_shell" == "zsh" ]] || [[ -f "$HOME/.zshrc" ]]; then
    ensure_pyenv_shell_config "zsh" "$HOME/.zshrc" "$PYENV_ROOT"
  fi
  if [[ "$current_shell" == "fish" ]] || [[ -f "$HOME/.config/fish/config.fish" ]]; then
    ensure_pyenv_shell_config "fish" "$HOME/.config/fish/config.fish" "$PYENV_ROOT"
  fi

  if command -v pyenv >/dev/null 2>&1; then
    say "pyenv is ready for Fluxgym."
    return 0
  fi

  err "pyenv setup failed. Please verify $pyenv_root/bin/pyenv exists."
  return 1
}

FLUXGYM_DIR_DEFAULT="${HOME}/fluxgym"
FLUXGYM_DIR=""

prompt_fluxgym_install_dir() {
  local input=""
  local default_dir="${FLUXGYM_DIR_DEFAULT}"

  while true; do
    say "Enter install location for Fluxgym (absolute path). Press Enter to use ${default_dir}."
    ask "Fluxgym directory [${default_dir}]:"
    read -r input
    input="${input:-$default_dir}"
    if [[ "$input" != /* ]]; then
      warn "Please provide an absolute path starting with '/'."
      continue
    fi
    FLUXGYM_DIR="$input"
    say "Fluxgym will be installed at: $FLUXGYM_DIR"
    return 0
  done
}

install_fluxgym_repos() {
  local fluxgym_dir="${FLUXGYM_DIR:-${FLUXGYM_DIR_DEFAULT}}"
  local sd_scripts_dir="${fluxgym_dir}/sd-scripts"

  need_cmd git

  say "Preparing Fluxgym repository under ${fluxgym_dir}..."
  if [[ -d "${fluxgym_dir}/.git" ]]; then
    say "Fluxgym repository already exists at ${fluxgym_dir}; updating..."
    git -C "${fluxgym_dir}" pull --ff-only || warn "Fluxgym repository update skipped."
  else
    mkdir -p "$(dirname "$fluxgym_dir")"
    git clone https://github.com/cocktailpeanut/fluxgym "${fluxgym_dir}"
  fi

  say "Ensuring sd-scripts (sd3 branch) is present under ${sd_scripts_dir}..."
  if [[ -d "${sd_scripts_dir}/.git" ]]; then
    git -C "${sd_scripts_dir}" fetch --all --tags || true
    git -C "${sd_scripts_dir}" checkout sd3 || warn "sd-scripts sd3 checkout failed; please check manually."
    git -C "${sd_scripts_dir}" pull --ff-only || warn "sd-scripts update skipped."
  else
    git clone -b sd3 https://github.com/kohya-ss/sd-scripts "${sd_scripts_dir}"
  fi
}

install_arcticnodes_only() {
  local comfy_dir=""
  if prompt_existing_comfy_path comfy_dir; then
    install_arctic_nodes "$comfy_dir"
    say "ArcticNodes installation finished for ${comfy_dir}."
  else
    warn "Could not locate a valid ComfyUI install; skipping ArcticNodes."
  fi
}

install_trellis2_only() {
  local comfy_dir=""
  if prompt_existing_comfy_path comfy_dir; then
    install_trellis2_nodes "$comfy_dir"
    say "ComfyUI-TRELLIS2 installation finished for ${comfy_dir}."
  else
    warn "Could not locate a valid ComfyUI install; skipping ComfyUI-TRELLIS2."
  fi
}

install_fluxgym_python() {
  local fluxgym_dir="${FLUXGYM_DIR:-${FLUXGYM_DIR_DEFAULT}}"
  local target_python="3.11.10"

  if [[ ! -d "$fluxgym_dir" ]]; then
    err "Fluxgym directory not found at ${fluxgym_dir}; cannot set pyenv local."
    return 1
  fi
  if ! command -v pyenv >/dev/null 2>&1; then
    err "pyenv not available; cannot install Python ${target_python} for Fluxgym."
    return 1
  fi

  say "Ensuring Python ${target_python} is installed via pyenv for Fluxgym..."
  if ! pyenv versions --bare | grep -qx "${target_python}"; then
    pyenv install -s "${target_python}"
  fi

  say "Setting local Python ${target_python} in ${fluxgym_dir}..."
  (cd "${fluxgym_dir}" && pyenv local "${target_python}") || {
    err "Failed to set pyenv local ${target_python} in ${fluxgym_dir}."
    return 1
  }
}

verify_fluxgym_python() {
  local fluxgym_dir="${FLUXGYM_DIR:-${FLUXGYM_DIR_DEFAULT}}"
  local expected="3.11.10"
  local version_out=""

  if [[ ! -d "$fluxgym_dir" ]]; then
    err "Fluxgym directory not found at ${fluxgym_dir}; cannot verify Python version."
    return 1
  fi
  if ! command -v pyenv >/dev/null 2>&1; then
    err "pyenv not available; cannot verify Python version for Fluxgym."
    return 1
  fi

  if ! version_out=$(
    cd "$fluxgym_dir" && pyenv exec python --version 2>/dev/null
  ); then
    err "Failed to run python in ${fluxgym_dir} via pyenv."
    return 1
  fi

  say "Fluxgym python version: ${version_out}"
  if [[ "$version_out" != "Python ${expected}"* ]]; then
    err "Unexpected Python version for Fluxgym (expected ${expected})."
    return 1
  fi
}

create_fluxgym_venv() {
  local fluxgym_dir="${FLUXGYM_DIR:-${FLUXGYM_DIR_DEFAULT}}"

  if [[ ! -d "$fluxgym_dir" ]]; then
    err "Fluxgym directory not found at ${fluxgym_dir}; cannot create venv."
    return 1
  fi
  if ! command -v pyenv >/dev/null 2>&1; then
    err "pyenv not available; cannot create Fluxgym venv."
    return 1
  fi

  if [[ -d "${fluxgym_dir}/env" ]]; then
    say "Fluxgym virtual environment already exists at ${fluxgym_dir}/env; skipping creation."
    return 0
  fi

  say "Creating Fluxgym virtual environment using pyenv's Python..."
  if (cd "$fluxgym_dir" && pyenv exec python -m venv env); then
    say "Fluxgym virtual environment created at ${fluxgym_dir}/env"
    say "Activate with:"
    echo "  bash/zsh: source ${fluxgym_dir}/env/bin/activate"
    echo "  fish   : source ${fluxgym_dir}/env/bin/activate.fish"
  else
    err "Failed to create Fluxgym virtual environment."
    return 1
  fi
}

install_fluxgym_python_packages() {
  local fluxgym_dir="${FLUXGYM_DIR:-${FLUXGYM_DIR_DEFAULT}}"
  local venv_dir="${fluxgym_dir}/env"

  if [[ ! -x "${venv_dir}/bin/python" ]]; then
    err "Fluxgym venv not found at ${venv_dir}; cannot install packages."
    return 1
  fi

  say "Installing Fluxgym Python packages inside venv..."
  "${venv_dir}/bin/python" -m pip install --upgrade pip setuptools wheel
  "${venv_dir}/bin/python" -m pip install --only-binary=:all: "numpy<2" "scipy>=1.11,<2"
}

install_fluxgym_sd_scripts_requirements() {
  local fluxgym_dir="${FLUXGYM_DIR:-${FLUXGYM_DIR_DEFAULT}}"
  local sd_scripts_dir="${fluxgym_dir}/sd-scripts"
  local venv_python="${fluxgym_dir}/env/bin/python"

  if [[ ! -x "$venv_python" ]]; then
    err "Fluxgym venv python not found at $venv_python; cannot install sd-scripts requirements."
    return 1
  fi
  if [[ ! -d "$sd_scripts_dir" ]]; then
    err "sd-scripts directory not found at ${sd_scripts_dir}."
    return 1
  fi

  say "Installing kohya sd-scripts requirements inside Fluxgym venv..."
  (cd "$sd_scripts_dir" && "$venv_python" -m pip install -r requirements.txt)
}

install_fluxgym_requirements() {
  local fluxgym_dir="${FLUXGYM_DIR:-${FLUXGYM_DIR_DEFAULT}}"
  local venv_python="${fluxgym_dir}/env/bin/python"

  if [[ ! -x "$venv_python" ]]; then
    err "Fluxgym venv python not found at $venv_python; cannot install Fluxgym requirements."
    return 1
  fi
  if [[ ! -d "$fluxgym_dir" ]]; then
    err "Fluxgym directory not found at ${fluxgym_dir}."
    return 1
  fi

  say "Installing Fluxgym requirements inside venv..."
  (cd "$fluxgym_dir" && "$venv_python" -m pip install -r requirements.txt)
}

configure_fluxgym_aliases() {
  local user_shell rc_file start_alias stop_alias
  local fluxgym_dir="${FLUXGYM_DIR:-${FLUXGYM_DIR_DEFAULT}}"
  local marker_start="# >>> Fluxgym aliases >>>"
  local marker_end="# <<< Fluxgym aliases <<<"
  user_shell=$(basename "${SHELL:-bash}")

  case "$user_shell" in
    bash) rc_file="$HOME/.bashrc" ;;
    zsh)  rc_file="$HOME/.zshrc" ;;
    fish)
      rc_file="$HOME/.config/fish/config.fish"
      mkdir -p "$(dirname "$rc_file")"
      ;;
    *)
      warn "Unknown shell ($user_shell); skipping Fluxgym alias setup."
      return 0
      ;;
  esac

  [[ -f "$rc_file" ]] || touch "$rc_file"
  if [[ "$user_shell" == "fish" ]]; then
    start_alias="alias fluxgym-start 'cd \"$fluxgym_dir\"; and pyenv local 3.11.10; and source \"$fluxgym_dir/env/bin/activate.fish\"; and python app.py'"
    stop_alias="alias fluxgym-stop 'deactivate'"
  else
    start_alias="alias fluxgym-start='cd \"$fluxgym_dir\" && pyenv local 3.11.10 && source \"$fluxgym_dir/env/bin/activate\" && python app.py'"
    stop_alias="alias fluxgym-stop='deactivate'"
  fi

  if grep -Fq "alias fluxgym-start" "$rc_file"; then
    if grep -Fq "$fluxgym_dir" "$rc_file" && grep -Fq "python app.py" "$rc_file"; then
      say "Fluxgym aliases already present in $rc_file; skipping."
      return 0
    fi
    say "Updating existing Fluxgym aliases in $rc_file to use $fluxgym_dir"
    sed -i "/${marker_start}/,/${marker_end}/d" "$rc_file"
  fi

  # Clean up any empty alias blocks before writing
  if grep -Fq "$marker_start" "$rc_file"; then
    sed -i "/${marker_start}/,/${marker_end}/d" "$rc_file"
  fi

  {
    echo ""
    echo "$marker_start"
    echo "$start_alias"
    echo "$stop_alias"
    echo "$marker_end"
  } >> "$rc_file"

  say "Added Fluxgym aliases to $rc_file"
}

detect_fluxgym_gpu_tier() {
  local gpu_names="" tier=""

  if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_names="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | tr '\n' ' ' || true)"
  fi

  if [[ -n "$gpu_names" ]]; then
    while read -r name; do
      [[ -z "$name" ]] && continue
      if [[ "$name" =~ ([0-9]{4}) ]]; then
        local num="${BASH_REMATCH[1]}"
        if (( num >= 4000 )); then
          tier="4000_plus"
          break
        else
          tier="3000_or_lower"
        fi
      fi
    done <<< "$(printf '%s\n' "$gpu_names" | tr ',' '\n')"
  fi

  if [[ -z "$tier" ]]; then
    say "Could not automatically determine GPU series."
    echo "Select GPU tier for Fluxgym PyTorch install:"
    echo "  1) NVIDIA 4000 series or newer (includes 5000)"
    echo "  2) NVIDIA 3000 series or older"
    confirm_choice "Enter 1 or 2:" "1 2" tier_choice
    case "$tier_choice" in
      1) tier="4000_plus" ;;
      2) tier="3000_or_lower" ;;
    esac
  fi

  printf '%s\n' "$tier"
}

install_fluxgym_torch_stack() {
  local fluxgym_dir="${FLUXGYM_DIR:-${FLUXGYM_DIR_DEFAULT}}"
  local venv_python="${fluxgym_dir}/env/bin/python"
  local gpu_tier=""

  if [[ ! -x "$venv_python" ]]; then
    err "Fluxgym venv python not found at $venv_python; cannot install PyTorch stack."
    return 1
  fi

  gpu_tier="$(detect_fluxgym_gpu_tier)"
  if [[ -z "$gpu_tier" ]]; then
    err "Unable to determine GPU tier for Fluxgym."
    return 1
  fi

  case "$gpu_tier" in
    3000_or_lower)
      say "Installing PyTorch (cu121) for 3000-series or older GPUs..."
      "$venv_python" -m pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
      ;;
    4000_plus)
      say "Installing PyTorch nightly (cu128) for 4000/5000-series GPUs..."
      "$venv_python" -m pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128
      "$venv_python" -m pip install -U bitsandbytes
      ;;
    *)
      err "Unknown GPU tier '$gpu_tier'; skipping PyTorch install."
      return 1
      ;;
  esac
}

handle_lora_trainers_menu() {
  local trainer_choice=""

  say "LoRA trainer options:"
  echo "  1) Install Fluxgym"
  confirm_choice "Enter 1 to continue:" "1" trainer_choice

  case "$trainer_choice" in
    1)
      if prompt_fluxgym_install_dir \
        && install_fluxgym_prereqs \
        && ensure_fluxgym_pyenv \
        && install_fluxgym_repos \
        && install_fluxgym_python \
        && verify_fluxgym_python \
        && create_fluxgym_venv \
        && install_fluxgym_python_packages \
        && install_fluxgym_sd_scripts_requirements \
        && install_fluxgym_requirements \
        && install_fluxgym_torch_stack; then
        configure_fluxgym_aliases || warn "Fluxgym alias setup skipped."
        say "Fluxgym install steps completed."
        local fluxgym_dir="${FLUXGYM_DIR:-${FLUXGYM_DIR_DEFAULT}}"
        echo "You can manage Fluxgym with:"
        echo "  fluxgym-start  # activate venv in ${fluxgym_dir} and run python app.py"
        echo "  fluxgym-stop   # deactivate venv"
        echo "Fluxgym UI is available at http://localhost:7860"
      else
        err "Fluxgym prerequisites failed; aborting Fluxgym install."
      fi
      ;;
  esac
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
  local version_id="${VERSION_ID:-}"
  id_like="${id_like,,}"
  version_id="${version_id,,}"

  if [[ "$id" == "debian" ]]; then
    # Treat Debian 13 separately so we can install the correct ncurses package.
    if [[ "${version_id%%.*}" == "13" ]]; then
      echo "debian13"
      return 0
    fi
  fi

  case "$id" in
    fedora|rhel|centos|rocky|almalinux) echo "fedora"; return 0 ;;
    ubuntu|pop|linuxmint|elementary|zorin|neon) echo "ubuntu"; return 0 ;;
    arch|manjaro|endeavouros|garuda|arco|artix) echo "arch"; return 0 ;;
  esac

  for token in $id_like; do
    case "$token" in
      debian)
        if [[ "${version_id%%.*}" == "13" ]]; then
          echo "debian13"
          return 0
        fi
        ;;
      fedora|rhel|centos) echo "fedora"; return 0 ;;
      ubuntu|debian) echo "ubuntu"; return 0 ;;
      arch) echo "arch"; return 0 ;;
    esac
  done

  err "Unsupported or unrecognized Linux distribution (ID=$id, ID_LIKE=$id_like)."
  return 1
}

# ======================== argument handling =======================
POSITIONAL_ARGS=()
UPDATE_REQUESTED=0
CHECK_UPDATE_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update)
      UPDATE_REQUESTED=1
      shift
      ;;
    --check-update)
      CHECK_UPDATE_ONLY=1
      shift
      ;;
    --version)
      echo "$SCRIPT_VERSION"
      exit 0
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        POSITIONAL_ARGS+=("$1")
        shift
      done
      break
      ;;
    -*)
      err "Unknown option: $1"
      print_usage
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL_ARGS[@]} -gt 0 ]]; then
  err "This installer does not accept positional arguments: ${POSITIONAL_ARGS[*]}"
  print_usage
  exit 1
fi

if [[ $UPDATE_REQUESTED -eq 1 ]]; then
  if ! remote_version="$(fetch_latest_version)"; then
    err "Unable to determine latest installer version."
    exit 1
  fi
  if [[ "$remote_version" == "$SCRIPT_VERSION" ]]; then
    say "Installer is already up to date (version $SCRIPT_VERSION)."
    exit 0
  fi
  if ! perform_self_update "$remote_version"; then
    exit 1
  fi
  exit 0
fi

if [[ $CHECK_UPDATE_ONLY -eq 1 ]]; then
  if ! remote_version="$(fetch_latest_version)"; then
    err "Unable to determine latest installer version."
    exit 1
  fi
  if [[ "$remote_version" == "$SCRIPT_VERSION" ]]; then
    say "Installer version $SCRIPT_VERSION is up to date."
  else
    warn "Installer update available: $SCRIPT_VERSION -> $remote_version"
  fi
  exit 0
fi

check_for_updates

# ===================== primary action selection ====================
RUN_FULL_INSTALL=0
INSTALL_MODE="standard"

say "Choose what you would like to install:"
echo "  1) Install ComfyUI (native pytorch attention)"
echo "  2) Install ComfyUI with Sage Attention"
echo "  3) Install ComfyUI with Flash Attention"
echo "  4) Install precompiled wheels"
echo "  5) Install LoRA Trainers"
echo "  6) Install ArcticNodes into an existing ComfyUI"
echo "  7) Install Trellis.2 into an existing ComfyUI"
confirm_choice "Enter 1, 2, 3, 4, 5, 6, or 7:" "1 2 3 4 5 6 7" PRIMARY_ACTION

case "$PRIMARY_ACTION" in
  1)
    RUN_FULL_INSTALL=1
    INSTALL_MODE="standard"
    ;;
  2)
    RUN_FULL_INSTALL=1
    INSTALL_MODE="accelerator"
    ;;
  3)
    RUN_FULL_INSTALL=1
    INSTALL_MODE="flash"
    ;;
  4)
    handle_precompiled_wheels_menu
    ;;
  5)
    handle_lora_trainers_menu
    ;;
  6)
    install_arcticnodes_only
    exit 0
    ;;
  7)
    install_trellis2_only
    exit 0
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
echo "  4) Debian 13"
confirm_choice "Enter 1, 2, 3, or 4:" "1 2 3 4" OS_CHOICE

case "$OS_CHOICE" in
  1) OS_NAME="fedora" ;;
  2) OS_NAME="ubuntu" ;;
  3) OS_NAME="arch" ;;
  4) OS_NAME="debian13" ;;
esac
say "Selected OS: $OS_NAME"

if ! DETECTED_OS="$(detect_os_family)"; then
  err "Automatic OS verification failed. This installer currently supports Fedora, Ubuntu/Linux Mint, Debian 13, and Arch-based distributions."
  exit 1
fi

say "Detected OS: $DETECTED_OS"

if [[ "$DETECTED_OS" != "$OS_NAME" ]]; then
  err "Installer option '$OS_NAME' does not match detected system '$DETECTED_OS'. Please rerun and select the correct distribution."
  exit 1
fi

say "OS verification passed."

if [[ "$INSTALL_MODE" == "standard" ]]; then
# ======================== GPU stack note =========================
GPU_LABEL="unified (CUDA12.8 stack)"
say "Using unified NVIDIA stack: torch 2.8.0 CUDA12.8 for all supported GPUs (3000/4000/5000 series)."
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

elif [[ "$OS_NAME" == "debian13" ]]; then
  sudo apt-get update
  sudo apt-get install -y build-essential git curl ffmpeg make cmake \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev tk-dev \
    libffi-dev xz-utils ca-certificates pkg-config \
    liblzma-dev libgdbm-dev libnss3-dev libncurses-dev

elif [[ "$OS_NAME" == "arch" ]]; then
  sudo pacman -Syu --noconfirm
  if pacman -Qq zlib-ng-compat >/dev/null 2>&1; then
    zlib_replacement_pkgs=(zlib)
    if pacman -Qq lib32-zlib-ng-compat >/dev/null 2>&1; then
      zlib_replacement_pkgs+=(lib32-zlib)
    fi
    warn "Detected zlib-ng-compat, which conflicts with zlib required by this installer."
    say "Replacing zlib-ng-compat stack in a single pacman transaction..."
    set +o pipefail
    yes | sudo pacman -S --needed "${zlib_replacement_pkgs[@]}"
    pacman_replace_status=${PIPESTATUS[1]}
    set -o pipefail
    if [[ $pacman_replace_status -ne 0 ]]; then
      err "Automatic replacement of zlib-ng-compat failed."
      exit 1
    fi
  fi
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

ask "Would you like to install ArcticNodes custom nodes after ComfyUI is cloned? (y/n):"
read -r ARCTIC_CHOICE
if [[ "$ARCTIC_CHOICE" =~ ^[Yy]$ ]]; then
  INSTALL_ARCTIC_NODES=1
fi

OVERWRITE_EXISTING=0
# Sanity checks & prepare parent directories
if [[ -e "$INSTALL_DIR" && ! -d "$INSTALL_DIR" ]]; then
  err "Path exists and is not a directory: $INSTALL_DIR"
  exit 1
fi
if [[ -d "$INSTALL_DIR" ]]; then
  if [[ -f "$INSTALL_DIR/requirements.txt" ]]; then
    warn "Detected an existing ComfyUI installation in $INSTALL_DIR."
    ask "ComfyUI already installed in this directory. Do you want to overwrite it? (y/n):"
    read -r OVERWRITE_CHOICE
    if [[ "$OVERWRITE_CHOICE" =~ ^[Yy]$ ]]; then
      OVERWRITE_EXISTING=1
    else
      say "Exiting without changes."
      exit 0
    fi
  else
    err "Directory already exists at $INSTALL_DIR and is not empty."
    err "Please choose another location or remove the directory."
    exit 1
  fi
fi
mkdir -p "$(dirname "$INSTALL_DIR")"

# ======================= ComfyUI + venv ===========================
if [[ "$OVERWRITE_EXISTING" -eq 1 ]]; then
  say "Refreshing existing ComfyUI in $INSTALL_DIR; preserving models/..."
  TEMP_CLONE="$(mktemp -d "${TMPDIR:-/tmp}/comfyui.clone.XXXXXX")"
  git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git "$TEMP_CLONE"
  rm -rf "$TEMP_CLONE/.git"
  if [[ -d "$INSTALL_DIR" ]]; then
    say "Removing existing contents except models/..."
    find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 \
      ! -name "models" \
      -exec rm -rf {} +
  fi
  mkdir -p "$INSTALL_DIR"
  rm -rf "$TEMP_CLONE/models"
  cp -a "$TEMP_CLONE"/. "$INSTALL_DIR"/
  mkdir -p "$INSTALL_DIR/models" "$INSTALL_DIR/custom_nodes"
  rm -rf "$TEMP_CLONE"
else
  say "Cloning ComfyUI into: $INSTALL_DIR"
  git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git "$INSTALL_DIR"
fi

configure_extra_model_path "$INSTALL_DIR"

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

case "$INSTALL_MODE" in
  standard)
    # =================== Select Torch/CUDA stack (unified) =================
    TORCH_PAIRS=("2.8.0 0.23.0")
    AUDIO_VER="${AUDIO_VER:-2.8.0}"
    TRITON_VER="${TRITON_VER:-3.4.0}"
    TRY_CUDA_STREAMS=("cu128" "cu126" "cu124")

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
    # Strip any torch/vision/audio/xformers/triton entries so pip won't change our pins
    grep -viE '^(torch|torchvision|torchaudio|xformers|triton)([=<> ]|$)' "$INSTALL_DIR/requirements.txt" > "$FIL_REQ" || true

    # Keep chosen CUDA index for the rest
    export PIP_INDEX_URL="https://download.pytorch.org/whl/${CUDA_PICKED}"
    export PIP_EXTRA_INDEX_URL="https://pypi.org/simple"

    say "Installing ComfyUI requirements (respecting pins; avoiding xformers)..."
    python -m pip install --upgrade -r "$FIL_REQ" -c "$PIN_FILE"

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
    ;;
  accelerator)
    say "Installing ComfyUI with Sage Attention (Torch 2.8.0 CUDA 12.8 + Triton; native PyTorch attention)..."
    SAGE_FILE_PATH="${INSTALL_DIR}/sage_attention_stack.txt"
    if [[ ! -f "$SAGE_ACCELERATOR_LOCAL_PATH" ]]; then
      err "Sage attention requirements file not found at $SAGE_ACCELERATOR_LOCAL_PATH. Please ensure assets are present."
      exit 1
    fi
    cp "$SAGE_ACCELERATOR_LOCAL_PATH" "$SAGE_FILE_PATH"

    unset PIP_INDEX_URL PIP_EXTRA_INDEX_URL
    python -m pip install --upgrade pip wheel setuptools
    python -m pip install --no-cache-dir -r "$SAGE_FILE_PATH"

    PIN_FILE="$INSTALL_DIR/.torch-pins.txt"
    python - "$PIN_FILE" <<'PY'
import sys, importlib.metadata as md
names = ["torch","torchvision","torchaudio","triton","sageattention"]
pins = []
for name in names:
    try:
        pins.append(f"{name}=={md.version(name)}")
    except md.PackageNotFoundError:
        continue
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    for line in pins:
        fh.write(line + "\n")
if not pins:
    raise SystemExit("No accelerator packages detected; Accelerator install may have failed.")
PY

    FIL_REQ="$INSTALL_DIR/.requirements.notorch.txt"
    grep -viE '^(torch|torchvision|torchaudio|xformers|triton)([=<> ]|$)' "$INSTALL_DIR/requirements.txt" > "$FIL_REQ" || true

    say "Installing ComfyUI requirements (respecting accelerator pins)..."
    python -m pip install --upgrade -r "$FIL_REQ" -c "$PIN_FILE"
    ;;
  flash)
    say "Installing ComfyUI with Flash Attention (Torch 2.8.0 CUDA 12.8 + Triton)..."
    FLASH_FILE_PATH="${INSTALL_DIR}/flash_attention_stack.txt"
    if [[ ! -f "$FLASH_ACCELERATOR_LOCAL_PATH" ]]; then
      err "Flash attention requirements file not found at $FLASH_ACCELERATOR_LOCAL_PATH. Please ensure assets are present."
      exit 1
    fi
    cp "$FLASH_ACCELERATOR_LOCAL_PATH" "$FLASH_FILE_PATH"

    unset PIP_INDEX_URL PIP_EXTRA_INDEX_URL
    python -m pip install --upgrade pip wheel setuptools
    python -m pip install --no-cache-dir -r "$FLASH_FILE_PATH"

    PIN_FILE="$INSTALL_DIR/.torch-pins.txt"
    python - "$PIN_FILE" <<'PY'
import sys, importlib.metadata as md
names = ["torch","torchvision","torchaudio","triton","flash_attn"]
pins = []
for name in names:
    try:
        pins.append(f"{name}=={md.version(name)}")
    except md.PackageNotFoundError:
        continue
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    for line in pins:
        fh.write(line + "\n")
if not pins:
    raise SystemExit("No accelerator packages detected; Flash Attention install may have failed.")
PY

    FIL_REQ="$INSTALL_DIR/.requirements.notorch.txt"
    grep -viE '^(torch|torchvision|torchaudio|xformers|triton)([=<> ]|$)' "$INSTALL_DIR/requirements.txt" > "$FIL_REQ" || true

    say "Installing ComfyUI requirements (respecting accelerator pins)..."
    python -m pip install --upgrade -r "$FIL_REQ" -c "$PIN_FILE"
    ;;
  *)
    err "Unknown install mode: $INSTALL_MODE"
    exit 1
    ;;
esac

# Ensure PyYAML present (ComfyUI imports yaml)
python -m pip install --upgrade pyyaml

# ===================== Custom node bootstrap ======================
say "Setting up ComfyUI custom nodes..."
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

CUSTOM_NODES_DIR="$INSTALL_DIR/custom_nodes"
mkdir -p "$CUSTOM_NODES_DIR"

[[ "$INSTALL_ARCTIC_NODES" -eq 1 ]] && install_arctic_nodes "$INSTALL_DIR"

MANAGER_DIR="$CUSTOM_NODES_DIR/comfyui-manager"
if [[ ! -d "$MANAGER_DIR/.git" ]]; then
  say "Cloning ComfyUI-Manager into custom_nodes..."
  git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager "$MANAGER_DIR"
else
  say "ComfyUI-Manager already exists; pulling latest changes..."
  git -C "$MANAGER_DIR" pull --ff-only || warn "ComfyUI-Manager update skipped."
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
ATTENTION_ALIAS_MODE=""
if [[ "$INSTALL_MODE" == "accelerator" ]]; then
  ATTENTION_ALIAS_MODE="sage"
elif [[ "$INSTALL_MODE" == "flash" ]]; then
  ATTENTION_ALIAS_MODE="flash"
fi
configure_comfy_aliases "$INSTALL_DIR" "$ATTENTION_ALIAS_MODE"
refresh_comfy_alias_vars "$INSTALL_DIR" "$ATTENTION_ALIAS_MODE"
if [[ "$ATTENTION_ALIAS_MODE" == "sage" ]]; then
  say "Sage attention aliases:"
  say "  ${COMFY_ALIAS_START:-comfyui-start} uses native PyTorch attention (no xformers)."
  say "  ${COMFY_ALIAS_SAGE:-comfyui-start-sage} adds --use-sage-attention."
  say "  ${COMFY_ALIAS_SAGE_FP16:-comfyui-start-sage-fp16} adds --use-sage-attention with fp16 accumulation (--fast)."
elif [[ "$ATTENTION_ALIAS_MODE" == "flash" ]]; then
  say "Flash attention aliases:"
  say "  ${COMFY_ALIAS_START:-comfyui-start} uses native PyTorch attention (no xformers)."
  say "  ${COMFY_ALIAS_FLASH:-comfyui-start-flash} adds --use-flash-attention."
  say "  ${COMFY_ALIAS_FLASH_FP16:-comfyui-start-flash-fp16} adds --use-flash-attention with fp16 accumulation (--fast)."
fi

# ============================ finishing ===========================
say "ComfyUI is ready."

echo
say "How to run:"
USER_SHELL=$(basename "${SHELL:-bash}")
ALIAS_START="${COMFY_ALIAS_START:-comfyui-start}"
ALIAS_VENV="${COMFY_ALIAS_VENV:-comfyui-venv}"
ALIAS_SAGE="${COMFY_ALIAS_SAGE:-}"
ALIAS_SAGE_FP16="${COMFY_ALIAS_SAGE_FP16:-}"
ALIAS_FLASH="${COMFY_ALIAS_FLASH:-}"
ALIAS_FLASH_FP16="${COMFY_ALIAS_FLASH_FP16:-}"
case "$INSTALL_MODE" in
  accelerator) START_NOTE="with native attention (Sage Attention stack)" ;;
  flash) START_NOTE="with Flash Attention stack" ;;
  *) START_NOTE="with native attention" ;;
esac
echo "  1) Activate venv and start manually:"
if [[ "$USER_SHELL" == "fish" ]]; then
  echo "       source \"$VENV_DIR/bin/activate.fish\""
else
  echo "       source \"$VENV_DIR/bin/activate\""
fi
echo "       python \"$INSTALL_DIR/main.py\" --listen 0.0.0.0 --port 8188"
echo "  2) Or use the new aliases (after reloading your shell):"
echo "       ${ALIAS_START}        # activate venv + launch ${START_NOTE}"
case "$INSTALL_MODE" in
  accelerator)
    echo "       ${ALIAS_SAGE:-comfyui-start-sage}        # activate venv + launch with SageAttention (--use-sage-attention)"
    echo "       ${ALIAS_SAGE_FP16:-comfyui-start-sage-fp16}   # activate venv + launch with SageAttention with fp16 accumulation (--use-sage-attention --fast)"
    ;;
  flash)
    echo "       ${ALIAS_FLASH:-comfyui-start-flash}        # activate venv + launch with Flash Attention (--use-flash-attention)"
    echo "       ${ALIAS_FLASH_FP16:-comfyui-start-flash-fp16}   # activate venv + launch with Flash Attention with fp16 accumulation (--use-flash-attention --fast)"
    ;;
esac
echo "       ${ALIAS_VENV}         # activate venv only"
