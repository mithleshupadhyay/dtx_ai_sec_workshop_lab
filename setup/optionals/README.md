# Optionals — Extra Setup for GPUs & Online Models

These **optional** add-ons let you use cloud GPUs for heavy labs and connect to online model APIs. They’re not required for the core local or GCP setups, but they’ll make some exercises faster and more realistic.

---

## TL;DR

* **GPU compute (pick one):**

  * **Google Colab** — add \~\$10 in credits to access higher-tier GPUs (A100 availability varies by region & capacity).&#x20;
  * **Kaggle** — create an account and **verify your mobile number** to enable notebooks with GPU.&#x20;
* **Online models (pick any):**

  1. **Groq** — use the **Playground** and generate an **API key**.&#x20;
  2. **OpenAI** — create an **API key** (recommended).&#x20;
  3. **Detoxio AI Gateway** — centralized routing for multiple providers: [https://docs.detoxio.ai/dtx-gateway/](https://docs.detoxio.ai/dtx-gateway/)

> Keep keys out of Git. Use environment variables or a local, gitignored file.

---

## A) Cloud GPUs for Notebooks

### Option 1 — Google Colab

1. Sign in with a Google account and **add \~\$10 in credits** (any paid plan/credits that unlock premium GPUs is fine).&#x20;
2. Create a new notebook → **Runtime → Change runtime type → GPU** (A100 when available).
3. Verify GPU:

   ```python
   import torch, subprocess, sys
   print("CUDA:", torch.cuda.is_available())
   subprocess.run(["nvidia-smi"])
   ```

### Option 2 — Kaggle

1. Create a Kaggle account and **complete mobile phone verification** (required to use notebooks with GPU).&#x20;
2. Start a new **Notebook** → **Settings → Accelerator → GPU**.
3. Verify GPU:

   ```python
   import subprocess
   subprocess.run(["nvidia-smi"])
   ```

---

## B) Online Model Providers

### 1) Groq (Playground + API key)

* Create an account, open the **Playground**, and **generate an API key**.&#x20;
* Set your key locally:

  ```bash
  export GROQ_API_KEY="sk-...yourkey..."
  ```
* Quick test (OpenAI-compatible Chat Completions):

  ```bash
  curl https://api.groq.com/openai/v1/chat/completions \
    -H "Authorization: Bearer $GROQ_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "llama3-8b-8192",
      "messages": [{"role":"user","content":"Hello from Groq!"}]
    }'
  ```

### 2) OpenAI API key

* Create an **API key** in your OpenAI account (optional but recommended).&#x20;
* Set your key:

  ```bash
  export OPENAI_API_KEY="sk-...yourkey..."
  ```
* Quick test:

  ```bash
  curl https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "gpt-4o-mini",
      "messages": [{"role":"user","content":"Hello from OpenAI!"}]
    }'
  ```

### 3) Detoxio AI Gateway

* Docs: **[https://docs.detoxio.ai/dtx-gateway/](https://docs.detoxio.ai/dtx-gateway/)**
* Purpose: route requests to multiple providers behind one gateway, add org-wide policies, logging, and quotas.
* Typical env:

  ```bash
  export DTX_GATEWAY_URL="https://gateway.example.com"   # from your admin
  export DTX_API_KEY="dtx-...yourkey..."
  ```
* OpenAI-style request via the gateway:

  ```bash
  curl "$DTX_GATEWAY_URL/openai/v1/chat/completions" \
    -H "Authorization: Bearer $DTX_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "gpt-4o-mini",
      "messages": [{"role":"user","content":"Hello via Detoxio Gateway!"}]
    }'
  ```

---
