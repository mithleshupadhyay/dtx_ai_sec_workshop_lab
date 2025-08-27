#!/usr/bin/env bash
# install_openai-cs-agents-demo.sh
# Installs openai-cs-agents-demo under ~/labs/webapps/, sets up .venv for backend,
# installs UI deps, and writes start.sh to run backend server.

set -euo pipefail

# --- Config (override via env) ---
BASE_DIR="${BASE_DIR:-$HOME/labs/webapps}"
REPO_URL="${REPO_URL:-https://github.com/openai/openai-cs-agents-demo}"
CLONE_DIR="${CLONE_DIR:-openai-cs-agents-demo}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
APP_PORT="${APP_PORT:-10002}"   # choose port for backend

echo "==> Installing openai-cs-agents-demo"
echo "    BASE_DIR=${BASE_DIR}"
echo "    REPO_URL=${REPO_URL}"
echo "    CLONE_DIR=${CLONE_DIR}"
echo "    PYTHON_VERSION=${PYTHON_VERSION}"
echo "    APP_PORT=${APP_PORT}"

# --- Preflight ---
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required but not found." >&2
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "ERROR: uv is not installed. See https://docs.astral.sh/uv/." >&2
  exit 1
fi

# --- Ensure base dir ---
mkdir -p "${BASE_DIR}"
cd "${BASE_DIR}"

# --- Clone repo ---
if [[ -d "$CLONE_DIR" ]]; then
  echo "Repo directory already exists: ${BASE_DIR}/${CLONE_DIR}"
else
  git clone "$REPO_URL" "$CLONE_DIR"
fi

cd "$CLONE_DIR"

# --- Setup backend ---
cd python-backend
uv venv .venv --python "$PYTHON_VERSION"
# shellcheck disable=SC1091
source .venv/bin/activate
uv pip install -r requirements.txt

# Ensure gunicorn is installed
uv pip install gunicorn python-dotenv

# --- Create start.sh in repo root ---
cd ..
cat > start.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/python-backend"

export PORT="${PORT:-10002}"

# shellcheck disable=SC1091
source .venv/bin/activate

echo "🚀 Starting backend on port $PORT ..."
exec uv run gunicorn app:app \
  --bind "0.0.0.0:${PORT}" \
  --workers 2 \
  --timeout 120
EOF
chmod +x start.sh

# --- Install UI deps ---
cd ui
npm install || true

# --- Done ---
echo ""
echo "✅ Install complete."
echo "Repo: ${BASE_DIR}/${CLONE_DIR}"
echo "Backend venv: ${BASE_DIR}/${CLONE_DIR}/python-backend/.venv"
echo "Start script: ${BASE_DIR}/${CLONE_DIR}/start.sh"
echo ""
echo "👉 To run the backend:"
echo "   cd ${BASE_DIR}/${CLONE_DIR}"
echo "   export OPENAI_API_KEY=your_api_key"
echo "   ./start.sh"
echo ""
echo "👉 To run the UI:"
echo "   cd ${BASE_DIR}/${CLONE_DIR}/ui"
echo "   npm run dev"

