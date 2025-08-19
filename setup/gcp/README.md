hey—welcome to your Google Cloud **lab**! 🎉
this guide follows your requested structure and starts with the simplest “no flags” workflow, then adds environments and multi-instance scaling, plus concrete verification steps (including what a good SSH session looks like).

You’ll use your Makefile + Terraform to spin up a lab on GCP, connect over SSH, validate the install, and later expand to multiple environments (dev/uat/prod) and many instances—then destroy it cleanly.

> quick safety note: restrict SSH to your own IP where possible, and avoid exposing RDP publicly—use the built-in SSH tunnel target instead.

# Prerequisites

* **Tools:** Terraform ≥ 1.5, Google Cloud SDK (`gcloud`), `jq`, OpenSSH.
* **GCP:** A project with billing enabled (know your **Project ID**).
* **APIs:**

  ```bash
  gcloud services enable compute.googleapis.com
  ```
* *(Optional, recommended)* Remote Terraform state in GCS (`backend "gcs"`).

# Config creation

*(tvars, SSH keys, etc.)*

## 1) Create `terraform.tfvars` from the example

```bash
cp terraform.tfvars.example terraform.tfvars
```

## 2) Edit `terraform.tfvars` (safe, minimal)

Use **either** a preset machine type **or** custom sizing (not both).

```hcl
# required
project_id = "<YOUR_GCP_PROJECT_ID>"     # gcloud config get-value project
region     = "us-central1"
zone       = "us-central1-a"

# choose ONE sizing method
machine_type = "e2-standard-4"
# custom_vcpus     = null
# custom_memory_mb = null
# -- OR --
# machine_type = null
# custom_vcpus     = 2
# custom_memory_mb = 4096

# basics
disk_size_gb = 100
prefix       = "emerson"
username     = "dtx"   # Makefile SSH targets assume this; keep in sync if you change it

# network (start tight)
allowed_ports     = [22]                 # add more only if truly needed
ssh_source_ranges = ["<YOUR_PUBLIC_IP>/32"]  # e.g. "203.0.113.5/32"
```

**Notes**

* Your Makefile **injects** the SSH public key at apply time, so you don’t need `ssh_public_key` in `terraform.tfvars`.
* Prefer SSH tunnels over opening ports like `3389`.

## 3) Generate SSH keys via the Makefile

```bash
make regen-key
```

This creates `id_ed25519` / `id_ed25519.pub` (and fixes permissions). The Makefile reads the public key and passes it to Terraform automatically.

# Login to gcloud

*(make auth, then init)*

```bash
gcloud config set project <YOUR_GCP_PROJECT_ID>
make auth     # application-default login for Terraform
make init     # terraform init (and backend init if configured)
```

---

# Workflow

This uses the Makefile defaults: `WORKSPACE=dev`, `INSTANCE_COUNT=1`.

```bash
# plan & apply (1 VM, dev workspace implicitly)
make plan
make apply
```

Connect and sanity-check:

```bash
# discover IPs/commands
make public-ips
make ssh-commands

# SSH into the first VM
make ssh
```

**What a good SSH session looks like (example):**

```
Welcome to Ubuntu 22.04.x LTS (GNU/Linux ... x86_64)
...
Last login: ...
dtx@emerson-dev-vm-1:~$
```

From the VM prompt, verify basics:

```bash
hostname
whoami                    # should be dtx
ip -4 addr show ens4      # expect an RFC1918 IP (e.g., 10.10.0.x)
df -h /                   # ~100G root if disk_size_gb = 100
uname -r                  # kernel version
```

If you have a validation script, run it:

```bash
./validate_installation.sh
# Expect a header like: "🔍 DTX Validation Log - <timestamp>" and success checks below
```

Exit the VM when done:

```bash
exit
```

Destroy when finished:

```bash
make destroy
```

---

# Introduce environments (workspaces) & multi-instances

## A) Environments (isolated dev / uat / prod)

Workspaces isolate state so you can apply the same code safely across envs.

Create/update:

```bash
# UAT example (5 nodes later in the next section)
make apply WORKSPACE=uat

# PROD example
make apply WORKSPACE=prod
```

Workspace helpers:

```bash
make workspace-list
make workspace-show
make workspace-create WORKSPACE=uat
make workspace-select WORKSPACE=prod
make workspace-delete WORKSPACE=uat
```

**Verify the active environment (locally):**

```bash
make workspace-show          # prints the current Terraform workspace (e.g., dev/uat/prod)
```

**Verify environment on the VM:**

* SSH in and confirm the hostname includes the env, e.g.:

  ```
  dtx@emerson-uat-vm-1:~$   # for UAT
  dtx@emerson-prod-vm-1:~$  # for PROD
  ```
* Optionally, expose the env via a file/tag you provision (e.g., `/etc/dtx_env`), then:

  ```bash
  cat /etc/dtx_env          # should read "uat" or "prod" if your userdata sets it
  ```

## B) Multi-instances (scale out)

Set `INSTANCE_COUNT` at plan/apply time.

```bash
# UAT with 5 instances
make apply WORKSPACE=uat INSTANCE_COUNT=5

# PROD with 20–22 instances (as in your history)
make apply WORKSPACE=prod INSTANCE_COUNT=20
make apply WORKSPACE=prod INSTANCE_COUNT=22
```

Operate across the fleet:

```bash
# list public IPs
make public-ips

# run a quick check on every node
make run-all CMD='hostname && uptime'
```

**Verify the scaled env:**

* Count IPs:

  ```bash
  make public-ips | wc -l    # should equal INSTANCE_COUNT
  ```
* Spot-check SSH:

  ```bash
  make ssh                    # to the first instance
  ```
* (Optional) From your laptop, confirm only intended ports respond on a sample IP.

Destroy a specific environment when done:

```bash
make destroy WORKSPACE=uat
make destroy WORKSPACE=prod
```
---

# Troubleshooting

* **SSH denied:** ensure `make regen-key` was run, keys are `0600`, user `dtx` exists, and your IP is allowed by `ssh_source_ranges`.
* **Quota errors:** try another zone/region or request quota increase.
* **Missing outputs:** ensure Terraform defines `public_ips`, `internal_ips`, `ssh_commands` to match the Make targets.

---

## Quick cheat-sheet

```bash
# first time
gcloud config set project <YOUR_PROJECT_ID>
make auth && make init
make regen-key
make apply                # dev, 1 instance
make ssh                  # verify VM shell: hostname, whoami, ./validate_installation.sh
make destroy

# later, env + scale
make apply WORKSPACE=uat INSTANCE_COUNT=5
make workspace-show
make public-ips | wc -l
make run-all CMD='hostname && uptime'
make destroy WORKSPACE=uat
```
