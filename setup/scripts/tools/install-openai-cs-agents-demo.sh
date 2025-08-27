#!/usr/bin/env bash
# Installs detoxio-ai/openai-cs-agents-demo under ~/labs/webapps/,
# prepares python-backend/.venv with uv, installs UI deps,
# binds Next.js dev/prod to 0.0.0.0, and creates start.sh to run `npm run dev`.

set -euo pipefail

# --- Config (override via env) ---
BASE_DIR="${BASE_DIR:-$HOME/labs/webapps}"
REPO_URL="${REPO_URL:-https://github.com/detoxio-ai/openai-cs-agents-demo}"
CLONE_DIR="${CLONE_DIR:-openai-cs-agents-demo}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"

echo "==> Installing ${CLONE_DIR}"
echo "    BASE_DIR=${BASE_DIR}"
echo "    REPO_URL=${REPO_URL}"
echo "    PYTHON_VERSION=${PYTHON_VERSION}"

# --- Preflight ---
need(){ command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' is required."; exit 1; }; }
need git; need uv; need npm; need npx

# --- Clone repo ---
mkdir -p "${BASE_DIR}"
cd "${BASE_DIR}"
if [[ -d "${CLONE_DIR}" ]]; then
  echo "Repo dir exists: ${BASE_DIR}/${CLONE_DIR} (skipping clone)"
else
  git clone "${REPO_URL}" "${CLONE_DIR}"
fi

cd "${CLONE_DIR}"

# --- Backend setup: python-backend/.venv ---
if [[ ! -d python-backend ]]; then
  echo "ERROR: 'python-backend' directory not found." >&2
  exit 2
fi

pushd python-backend >/dev/null
uv venv .venv --python "${PYTHON_VERSION}"
# shellcheck disable=SC1091
source .venv/bin/activate
[[ -f requirements.txt ]] && uv pip install -r requirements.txt
# Ensure backend dev server deps
uv pip install "uvicorn[standard]" python-dotenv >/dev/null
popd >/dev/null

# --- UI deps ---
if [[ ! -d ui ]]; then
  echo "ERROR: 'ui' directory not found." >&2
  exit 3
fi

pushd ui >/dev/null
npm install
# ensure concurrently exists for combined dev script
npm install -D concurrently >/dev/null || true

# --- Bind Next.js to 0.0.0.0 in dev and prod ---
# Update "dev:next": npx next dev --hostname 0.0.0.0
if grep -q '"dev:next"' package.json; then
  sed -i -E \
    's/("dev:next"\s*:\s*")((npx\s+)?next dev)([^"]*)"/\1npx next dev --hostname 0.0.0.0\4"/' \
    package.json
else
  echo 'WARNING: Could not find "dev:next" in ui/package.json; skipping dev host patch.'
fi

# Update "start": next start --hostname 0.0.0.0
if grep -q '"start"' package.json; then
  sed -i -E \
    's/("start"\s*:\s*")((npx\s+)?next start|next start)([^"]*)"/\1next start --hostname 0.0.0.0\4"/' \
    package.json
fi
popd >/dev/null

# --- start.sh at repo root ---
cat > start.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Runs both frontend and backend via the ui package.json "dev" script.
cd "$(dirname "$0")/ui"

# If you keep OPENAI_API_KEY in ../python-backend/.env, python-dotenv will load it.
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "ℹ️  OPENAI_API_KEY not set in shell. If it's in python-backend/.env, that's fine."
fi

exec npm run dev
EOF
chmod +x start.sh

# --- optional backend .env template ---
if [[ ! -f python-backend/.env ]]; then
  cat > python-backend/.env <<'EOF'
OPENAI_API_KEY=replace_me
EOF
fi

echo ""
echo "✅ Install complete."
echo "Repo: ${BASE_DIR}/${CLONE_DIR}"
echo "Start script: ${BASE_DIR}/${CLONE_DIR}/start.sh"
echo ""
echo "Usage:"
echo "  # Option A: export your key in the shell"
echo "  export OPENAI_API_KEY=your_api_key"
echo "  ${BASE_DIR}/${CLONE_DIR}/start.sh"
echo ""
echo "  # Option B: put your key in ${BASE_DIR}/${CLONE_DIR}/python-backend/.env (already created)"
echo "  ${BASE_DIR}/${CLONE_DIR}/start.sh"
echo ""
echo "UI: Next.js dev binds to 0.0.0.0:3000"
echo "API: Uvicorn binds to 0.0.0.0:8000"

