# Introduction

Welcome! 🎉
This guide sets up the **DTX demo lab** on a **single local Ubuntu VM** (no Terraform, no cloud). You’ll get Docker, uv/Python, Node (via asdf), Go + AppSec tools, Ollama, NGINX, and the Detox labs cloned and ready. It’s copy-paste friendly and safe by default (SSH key auth, minimal open ports).

> Legal note: several tools are offensive-security utilities. Use only on systems you own or have explicit permission to test.

---

# Prerequisites

* **OS:** Ubuntu Server 22.04 or 24.04 (x86\_64)
* **Hardware (minimum):** **16 GB RAM**, **250+ GB disk**, **4+ vCPU**
* **Access:** `sudo` (root) on the VM
* **Network:** Outbound HTTPS allowed; inbound **SSH (22)** and **HTTP (80)** only
* **Packages:** `curl`, `git` (installed below if missing)
* **SSH key:** Have (or create) an Ed25519 keypair on your laptop; we’ll authorize its **public** key on the VM

Optional hardening:

```bash
sudo apt-get update
sudo apt-get install -y ufw
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw enable
```

---

# Config creation (username, SSH keys, secrets)

## 1) Generate or reuse an SSH key (on your laptop)

```bash
ssh-keygen -t ed25519 -C "lab-local" -f ~/.ssh/id_ed25519 -N ""
```

## 2) Create an env file on the VM

This keeps config tidy and avoids putting secrets in your shell history.

```bash
cat > ~/lab.env <<'EOF'
TARGET_USER=dtx
SSH_PUBLIC_KEY=__PASTE_YOUR_PUBLIC_KEY_LINE_HERE__
OPENAI_API_KEY=
GROQ_API_KEY=
ANTHROPIC_API_KEY=
ENVIRONMENT=local
EOF
```

> Replace `SSH_PUBLIC_KEY` with the single-line contents of your `~/.ssh/id_ed25519.pub`.
> Leave keys blank or use temporary throwaways; you can also add them later.

---

# Installation (single VM workflow)

## 3) Save the installer script on the VM

```bash
cat > ~/install_lab_local.sh <<'EOF'
#!/usr/bin/env bash
set -euxo pipefail

# ---- Config (via env or ./lab.env) ----
if [ -f ./lab.env ]; then set -a; source ./lab.env; set +a; fi
TARGET_USER="${TARGET_USER:-dtx}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-$(cat ~/.ssh/id_ed25519.pub)}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
GROQ_API_KEY="${GROQ_API_KEY:-}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
ENVIRONMENT="${ENVIRONMENT:-local}"
GO_VERSION="1.24.5"

write_secret() {
  local name="$1" val="$2" dir="/home/$TARGET_USER/.secrets"
  [ -z "$val" ] && return 0
  mkdir -p "$dir"
  echo -n "$val" > "$dir/${name}.txt"
  chown "$TARGET_USER:$TARGET_USER" "$dir/${name}.txt"
  chmod 600 "$dir/${name}.txt"
}

# ---- Create user + SSH ----
if ! id -u "$TARGET_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$TARGET_USER"
fi
usermod -aG sudo "$TARGET_USER"

mkdir -p /home/$TARGET_USER/.ssh
echo "$SSH_PUBLIC_KEY" > /home/$TARGET_USER/.ssh/authorized_keys
chmod 700 /home/$TARGET_USER/.ssh
chmod 600 /home/$TARGET_USER/.ssh/authorized_keys
chown -R $TARGET_USER:$TARGET_USER /home/$TARGET_USER/.ssh

# passwordless sudo
echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-$TARGET_USER
chmod 440 /etc/sudoers.d/90-$TARGET_USER

# harden ssh
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# mark environment for verification
echo "$ENVIRONMENT" > /etc/dtx_env

# ---- Base packages ----
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release git sudo

# ---- Docker ----
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.gpg
gpg --batch --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg /tmp/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io
usermod -aG docker "$TARGET_USER"

# ---- ASDF ----
sudo -u $TARGET_USER git clone https://github.com/asdf-vm/asdf.git "/home/$TARGET_USER/.asdf" --branch v0.14.0
sudo -u $TARGET_USER bash -c 'echo ". $HOME/.asdf/asdf.sh" >> ~/.bashrc'
sudo -u $TARGET_USER bash -c 'echo ". $HOME/.asdf/completions/asdf.bash" >> ~/.bashrc'

# ---- uv ----
sudo -u $TARGET_USER bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
sudo -u $TARGET_USER bash -c 'echo "source \$HOME/.local/bin/env" >> ~/.bashrc'

# ---- Python via uv ----
sudo -u $TARGET_USER bash -lc 'source $HOME/.local/bin/env && uv python install 3.12'

# ---- Python tools via uv ----
sudo -u $TARGET_USER bash -lc 'source $HOME/.local/bin/env && \
  uv tool install "dtx[torch]>=0.26.0" && \
  uv tool install "garak" && \
  uv tool install "textattack[tensorflow]" && \
  uv tool install "huggingface_hub[cli,torch]"'

# ---- Node.js via ASDF + promptfoo ----
sudo -u $TARGET_USER bash -lc '. $HOME/.asdf/asdf.sh && \
  asdf plugin-add nodejs https://github.com/asdf-vm/asdf-nodejs.git || true && \
  bash $HOME/.asdf/plugins/nodejs/bin/import-release-team-keyring && \
  asdf install nodejs lts && asdf global nodejs lts && \
  npm install -g promptfoo'

# ---- Ollama ----
curl -fsSL https://ollama.com/install.sh | sh
systemctl enable ollama
systemctl start ollama

# Optional models (best-effort)
ollama pull smollm2 || true
ollama pull qwen3:0.6b || true
ollama pull llama-guard3:1b-q3_K_S || true

# ---- Shell PATHs ----
cat >> /home/$TARGET_USER/.bashrc <<'BRC'
export PATH="$HOME/.asdf/bin:$HOME/.asdf/shims:$PATH"
. "$HOME/.asdf/asdf.sh"
. "$HOME/.asdf/completions/asdf.bash"
export PATH="$HOME/.local/bin:$PATH"
source "$HOME/.local/bin/env" 2>/dev/null || true
export PATH="$HOME/.npm-global/bin:$PATH"
export PATH="$HOME/.ollama/bin:$PATH"
export GOBIN="$HOME/.local/bin"
export PATH="$GOBIN:$PATH"
BRC

# ---- Secrets -> files + export on login ----
SECRETS_DIR="/home/$TARGET_USER/.secrets"
mkdir -p "$SECRETS_DIR"
write_secret OPENAI_API_KEY "$OPENAI_API_KEY"
write_secret GROQ_API_KEY "$GROQ_API_KEY"
write_secret ANTHROPIC_API_KEY "$ANTHROPIC_API_KEY"
chown -R $TARGET_USER:$TARGET_USER "/home/$TARGET_USER/"
chmod 700 "$SECRETS_DIR" || true

cat >> /home/$TARGET_USER/.bashrc <<'BRC'
[ -f "$HOME/.secrets/OPENAI_API_KEY.txt" ] && export OPENAI_API_KEY=$(cat "$HOME/.secrets/OPENAI_API_KEY.txt")
[ -f "$HOME/.secrets/GROQ_API_KEY.txt" ]   && export GROQ_API_KEY=$(cat "$HOME/.secrets/GROQ_API_KEY.txt")
BRC

# ---- Labs repos ----
LABS_DIR="/home/$TARGET_USER/labs"
sudo -u "$TARGET_USER" bash -lc "mkdir -p '$LABS_DIR' && cd '$LABS_DIR' && \
  git clone https://github.com/detoxio-ai/ai-red-teaming-training.git || true && \
  git clone https://github.com/detoxio-ai/dtx_ai_sec_workshop_lab.git || true"

# ---- Run lab install scripts if present ----
INSTALL_DIR="/home/$TARGET_USER/labs/dtx_ai_sec_workshop_lab/setup/scripts/tools"
for script in install-dtx-demo-lab.sh install-pentagi.sh install-vulnhub-lab.sh; do
  if [ -f "$INSTALL_DIR/$script" ]; then
    echo "🚀 Running $script"
    chmod +x "$INSTALL_DIR/$script"
    sudo -u "$TARGET_USER" bash "$INSTALL_DIR/$script" || true
  fi
done

# ---- Copy validator if present ----
VALIDATE_SCRIPT="$INSTALL_DIR/../validate_installation.sh"
if [ -f "$VALIDATE_SCRIPT" ]; then
  cp "$VALIDATE_SCRIPT" "/home/$TARGET_USER/validate_installation.sh"
  chown "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/validate_installation.sh"
fi

# ---- Go via ASDF + tools ----
sudo -u $TARGET_USER bash -lc ". \$HOME/.asdf/asdf.sh && \
  asdf plugin add golang https://github.com/asdf-community/asdf-golang.git || true && \
  asdf install golang $GO_VERSION && asdf global golang $GO_VERSION && \
  export GOBIN=\$HOME/.local/bin && mkdir -p \$GOBIN && \
  go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest && \
  go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest && \
  go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest && \
  CGO_ENABLED=0 go install -v github.com/owasp-amass/amass/v5/cmd/amass@main"

# ---- LLM CLI + key ----
sudo -u $TARGET_USER bash -lc "source \$HOME/.local/bin/env && uv tool install 'llm'"
if [ -n "$OPENAI_API_KEY" ]; then
  sudo -u $TARGET_USER bash -lc "llm keys set openai --value '$OPENAI_API_KEY'"
fi

# ---- Extra tools ----
apt-get install -y nmap

# PentestGPT (best-effort)
sudo -u "$TARGET_USER" bash -lc '
TMP_DIR="$(mktemp -d)"
git clone --depth=1 https://github.com/GreyDGL/PentestGPT "$TMP_DIR/PentestGPT"
rm -rf "$TMP_DIR/PentestGPT/benchmark"
source $HOME/.local/bin/env
uv tool install "$TMP_DIR/PentestGPT"
rm -rf "$TMP_DIR"
'

# CAI framework
sudo -u $TARGET_USER bash -lc 'source $HOME/.local/bin/env && uv tool install "cai-framework"'

# Metasploit + searchsploit
sudo -u $TARGET_USER bash -lc '
curl -sSL https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall
chmod 755 msfinstall
sudo rm -f /usr/share/keyrings/metasploit-framework.gpg
yes | ./msfinstall > /dev/null 2>&1 || true
yes | msfdb init > /dev/null 2>&1 || true
'
sudo -u $TARGET_USER bash -lc 'sudo snap install searchsploit || true'

# Playwright (Chrome only)
sudo -u $TARGET_USER bash -lc '. $HOME/.asdf/asdf.sh && npm install playwright@latest && npx playwright install chrome || true'

# ---- NGINX serving ~/shared ----
sudo -u "$TARGET_USER" bash -lc '
set -e
SHARED_DIR=$HOME/shared
NGINX_CONF=/etc/nginx/sites-available/shared
sudo apt-get update && sudo apt-get install -y nginx
mkdir -p "$SHARED_DIR"
[ -f "$SHARED_DIR/index.html" ] || echo "<h1>Hello from shared!</h1>" > "$SHARED_DIR/index.html"
chmod o+x "$HOME" "$SHARED_DIR"
find "$SHARED_DIR" -type d -exec chmod o+x {} \;
find "$SHARED_DIR" -type f -exec chmod o+r {} \;
sudo bash -c "cat > $NGINX_CONF" <<NGX
server {
    listen 80 default_server;
    server_name _;
    root $HOME/shared;
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
    location /shared/ { alias $HOME/shared/; index index.html; autoindex on; autoindex_exact_size off; }
}
NGX
sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/shared
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
'

echo "✅ Lab install complete. Environment: $(cat /etc/dtx_env)"
EOF

chmod +x ~/install_lab_local.sh
```

## 4. Run the installer

```bash
cd ~
sudo -E ./install_lab_local.sh     # uses values from ./lab.env
```

---

# Verification

After the script completes:

```bash
# confirm environment marker
cat /etc/dtx_env           # -> local

# basic health
whoami                     # -> dtx (or your TARGET_USER)
hostname
docker --version
uv --version
node -v && npm -v
go version

# ollama & models (optional)
ollama list || true

# nginx serves ~/shared
curl -I http://localhost/ | head -n1   # HTTP/1.1 200 OK
```

If a validator was copied:

```bash
chmod +x ~/validate_installation.sh
~/validate_installation.sh
```

You should see a header like:

```
🔍 DTX Validation Log - <timestamp>
==================================
```

---

# Daily use

* **SSH into the VM** using your private key from your laptop:

  ```bash
  ssh -i ~/.ssh/id_ed25519 dtx@<vm-ip-or-hostname>
  ```
* **Serve/share files** via `~/shared` at `http://<vm-ip>/`.
* **Update tools** periodically:

  ```bash
  sudo apt-get update && sudo apt-get upgrade -y
  sudo -u dtx bash -lc '. $HOME/.asdf/asdf.sh && asdf update && asdf plugin-update --all'
  ```

---

# Troubleshooting

* **SSH “permission denied”**
  Ensure your public key was pasted correctly in `lab.env`; check:

  ```bash
  sudo tail -n+1 /home/dtx/.ssh/authorized_keys
  sudo grep -i PasswordAuthentication /etc/ssh/sshd_config
  ```

  Should be `PasswordAuthentication no`. Restart: `sudo systemctl restart sshd`.

* **Docker permission denied**
  Re-login so the `docker` group takes effect: `exit` then SSH back.

* **Low disk/RAM**
  Expand the VM’s disk to **250+ GB**, allocate **16+ GB RAM**.

* **NGINX not serving**

  ```bash
  sudo nginx -t && sudo systemctl reload nginx
  sudo tail -n 200 /var/log/nginx/error.log
  ```

---

# Cleanup

* Stop services:

  ```bash
  sudo systemctl stop nginx ollama
  ```
* Remove lab repos and secrets:

  ```bash
  sudo rm -rf /home/dtx/labs /home/dtx/.secrets
  ```
* Remove the user entirely (careful—deletes home):

  ```bash
  sudo userdel -r dtx
  ```
