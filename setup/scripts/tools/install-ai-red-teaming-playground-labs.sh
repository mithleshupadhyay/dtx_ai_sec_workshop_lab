#!/usr/bin/env bash
# install-ai-red-teaming-playground-labs.sh
# Finbot-style installer for microsoft/AI-Red-Teaming-Playground-Labs:
# - clones into labs/webapps/
# - writes .env (uses ~/.secrets/OPENAI_API_KEY.txt if present)
# - creates start.sh/stop.sh (no compose overrides; mapping lives in your fork)
#
# After forking, ensure your docker-compose-openai.yaml maps:
#   - "${APP_PORT:-15000}:5000"
# and does NOT also publish 127.0.0.1:5000

set -euo pipefail

# --- Config (override via env) ---
BASE_DIR="${BASE_DIR:-labs/webapps}"
REPO_URL="${REPO_URL:-https://github.com/mithleshupadhyay/AI-Red-Teaming-Playground-Labs.git}"
CLONE_DIR_NAME="${CLONE_DIR_NAME:-AI-Red-Teaming-Playground-Labs}"
APP_PORT="${APP_PORT:-15000}"

OPENAI_TEXT_MODEL_DEFAULT="${OPENAI_TEXT_MODEL:-gpt-4o}"
OPENAI_EMBED_MODEL_DEFAULT="${OPENAI_EMBEDDING_MODEL:-text-embedding-3-small}"

echo "==> Installing AI-Red-Teaming-Playground-Labs"
echo "    BASE_DIR=${BASE_DIR}"
echo "    REPO_URL=${REPO_URL}"
echo "    CLONE_DIR_NAME=${CLONE_DIR_NAME}"
echo "    APP_PORT=${APP_PORT}"

# --- Preflight ---
command -v git >/dev/null 2>&1 || { echo "ERROR: git not found" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "ERROR: Docker Compose plugin not found" >&2; exit 1; }

# --- Create target dir ---
mkdir -p "${BASE_DIR}"
cd "${BASE_DIR}"

# --- Clone repo ---
if [[ -d "${CLONE_DIR_NAME}" ]]; then
  echo "Repo directory '${BASE_DIR}/${CLONE_DIR_NAME}' already exists. Skipping clone."
else
  echo "Cloning repository into ${BASE_DIR}/${CLONE_DIR_NAME} ..."
  git clone "${REPO_URL}" "${CLONE_DIR_NAME}"
fi
cd "${CLONE_DIR_NAME}"

# --- Build .env ---
# env var wins; fallback to file
OPENAI_FILE="$HOME/.secrets/OPENAI_API_KEY.txt"
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  OPENAI_API_KEY_VAL="$OPENAI_API_KEY"
elif [[ -f "$OPENAI_FILE" ]]; then
  OPENAI_API_KEY_VAL="$(<"$OPENAI_FILE")"
else
  OPENAI_API_KEY_VAL=""
fi

genhex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import secrets; print(secrets.token_hex(16))'
  elif command -v python >/dev/null 2>&1; then
    python -c 'import secrets; print(secrets.token_hex(16))'
  else
    date +%s%N | sha256sum | cut -c1-32
  fi
}

AUTH_KEY_VAL="${AUTH_KEY:-$(genhex)}"
SECRET_KEY_VAL="${SECRET_KEY:-$(genhex)}"
PUBLIC_HOST_VAL="${PUBLIC_HOST:-}"

cat > .env <<EOF
# ---- OpenAI (standard API) ----
OPENAI_API_KEY=${OPENAI_API_KEY_VAL}
OPENAI_TEXT_MODEL=${OPENAI_TEXT_MODEL_DEFAULT}
OPENAI_EMBEDDING_MODEL=${OPENAI_EMBED_MODEL_DEFAULT}

# ---- App login/session secrets ----
AUTH_KEY=${AUTH_KEY_VAL}
SECRET_KEY=${SECRET_KEY_VAL}

# ---- Host port for Home UI (container is 5000) ----
APP_PORT=${APP_PORT}

# ---- Optional public host for links (if empty, start.sh prints localhost) ----
PUBLIC_HOST=${PUBLIC_HOST_VAL}
EOF

echo "Wrote .env with APP_PORT=${APP_PORT}"

# --- start.sh ---
cat > start.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Read values needed for printing/overrides (don't export .env into the process)
APP_PORT_FILE="$(grep -E '^APP_PORT=' .env | cut -d= -f2- | tr -d '\r' || true)"
PUBLIC_HOST_FILE="$(grep -E '^PUBLIC_HOST=' .env | cut -d= -f2- | tr -d '\r' || true)"
AUTH_KEY="$(grep -E '^AUTH_KEY=' .env | cut -d= -f2- | tr -d '\r' || true)"

# Allow override at invocation: PORT=16000 ./start.sh
# Precedence: PORT env > existing APP_PORT env > .env value > 15000
export APP_PORT="${PORT:-${APP_PORT:-${APP_PORT_FILE:-15000}}}"

# Bring up the stack
# - docker compose reads .env automatically for substitutions
# - any exported env (e.g., OPENAI_API_KEY) overrides .env
docker compose -f docker-compose-openai.yaml up -d

# Compose done — print login URL
HOST_FOR_LINK="${PUBLIC_HOST:-${PUBLIC_HOST_FILE:-localhost}}"
LOGIN_URL="http://${HOST_FOR_LINK}:${APP_PORT}/login?auth=${AUTH_KEY}"

echo ""
echo "✅ Playground up. Login:"
echo "   ${LOGIN_URL}"
echo "   (Challenges spawn on ports like 14001–14012)"
echo ""
EOF
chmod +x start.sh

# --- stop.sh ---
cat > stop.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
docker compose -f docker-compose-openai.yaml down
EOF
chmod +x stop.sh

# --- Final notes ---
echo ""
echo "✅ Install complete."
echo "Repo: $(pwd)"
echo "Virtualenv: N/A (Docker/Compose app)"
echo "Start script: $(pwd)/start.sh (default port ${APP_PORT})"
echo ""
echo "To run:"
echo "  cd \"$(pwd)\""
echo "  PORT=${APP_PORT} ./start.sh"
