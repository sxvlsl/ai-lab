#!/usr/bin/env bash
# Instalador del entorno para el roadmap de IA · CachyOS (Arch)
#
# Uso:   ./setup-ia.sh                 -> todos los grupos de Python
#        ./setup-ia.sh data ml         -> solo esos grupos
# Antes: ejecuta `update` (sudo pacman -Syu) para evitar actualizaciones parciales.
# Necesita el pyproject.toml en la misma carpeta que este script.
set -euo pipefail

LAB_DIR="${LAB_DIR:-$HOME/Projects/ai-lab}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_GROUPS=("$@")
if (( ${#PY_GROUPS[@]} == 0 )); then PY_GROUPS=(data ml dl nlp prod dev); fi

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# Instala los paquetes de los repos que existan y avisa de los que no
install_repo() {
  local ok=() missing=() p
  for p in "$@"; do
    if pacman -Si "$p" &>/dev/null; then ok+=("$p"); else missing+=("$p"); fi
  done
  if (( ${#missing[@]} )); then echo "No están en los repos (omitidos): ${missing[*]}"; fi
  if (( ${#ok[@]} )); then sudo pacman -S --needed "${ok[@]}"; fi
}

# ---------------------------------------------------------------- 1. Sistema
say "Herramientas del sistema"
install_repo uv github-cli git-lfs ripgrep fd fzf bat btop tmux neovim \
             graphviz sqlite docker-compose docker-buildx

# ---------------------------------------------------------------- 2. Docker
if command -v docker &>/dev/null; then
  say "Docker"
  sudo systemctl enable --now docker.service
  if ! id -nG "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    echo "Añadido al grupo docker: cierra sesión y vuelve a entrar para usarlo sin sudo."
  fi
fi

# ---------------------------------------------------------------- 3. Editor
if ! command -v code &>/dev/null; then
  read -rp "¿Instalar Visual Studio Code desde el AUR (visual-studio-code-bin)? [s/N] " r
  if [[ $r =~ ^[sSyY]$ ]]; then paru -S --needed visual-studio-code-bin; fi
fi
if command -v code &>/dev/null; then
  say "Extensiones de VS Code"
  for e in ms-python.python ms-toolsai.jupyter charliermarsh.ruff; do
    code --install-extension "$e" || true
  done
fi

# ---------------------------------------------------------------- 4. Python
say "Python 3.12 gestionado por uv"
uv python install 3.12

say "Entorno en $LAB_DIR (grupos: ${PY_GROUPS[*]})"
mkdir -p "$LAB_DIR"
if [[ ! -f $LAB_DIR/pyproject.toml ]]; then cp "$SCRIPT_DIR/pyproject.toml" "$LAB_DIR/"; fi
cd "$LAB_DIR"
echo 3.12 > .python-version
if [[ ! -d .git ]]; then git init -q; fi
if [[ ! -f .gitignore ]]; then
  printf '%s\n' '.venv/' '__pycache__/' '.ipynb_checkpoints/' 'data/' 'models/' 'mlruns/' 'runs/' > .gitignore
fi

args=()
for g in "${PY_GROUPS[@]}"; do args+=(--group "$g"); done
uv sync "${args[@]}"

if uv run --no-sync python -c 'import ipykernel' &>/dev/null; then
  uv run --no-sync python -m ipykernel install --user --name ai-lab --display-name "Python (ai-lab)"
fi

# ---------------------------------------------------------------- 5. Comprobación
say "Comprobación"
uv run --no-sync python - <<'PY'
import importlib
for m in ["numpy", "pandas", "matplotlib", "sklearn", "xgboost", "torch", "transformers", "fastapi"]:
    try:
        mod = importlib.import_module(m)
        print(f"ok   {m} {getattr(mod, '__version__', '')}")
    except ImportError:
        print(f"--   {m} (no instalado)")
try:
    import torch
    print("PyTorch solo CPU:", "+cpu" in torch.__version__, "| cuda disponible:", torch.cuda.is_available())
except ImportError:
    pass
PY

cat <<EOF

Listo. Para trabajar:
  cd $LAB_DIR && uv run jupyter lab
Para añadir más adelante un grupo (por ejemplo rl):
  cd $LAB_DIR && uv sync --group rl
EOF
