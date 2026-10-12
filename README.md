<p align="center">
  <img src="assets/hero.jpg" alt="A shocked creator in front of a mushroom-cloud explosion, the thumbnail for the video AI Without Guardrails" width="100%">
</p>

<h1 align="center">Run an Uncensored AI Model on a Rented RTX 5090</h1>

<p align="center">
  <strong>Deploy with one command. Chat privately from your own computer. Or hand this repo to an AI assistant and let it do the setup.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-2ea043"></a>
  <img alt="GPU: NVIDIA RTX 5090, 32 GB" src="https://img.shields.io/badge/GPU-RTX%205090%20(32%20GB)-76B900?logo=nvidia&logoColor=white">
  <img alt="Model: Qwen 27B, NVFP4" src="https://img.shields.io/badge/model-Qwen%2027B%20NVFP4-6B4FBB">
  <img alt="Engine: SGLang" src="https://img.shields.io/badge/engine-SGLang-0969da">
  <img alt="Chat UI: Open WebUI" src="https://img.shields.io/badge/chat-Open%20WebUI-1f2328?logo=docker&logoColor=white">
  <a href="AGENTS.md"><img alt="AI agent ready: AGENTS.md" src="https://img.shields.io/badge/AI%20agent%20ready-AGENTS.md-d97706"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> &nbsp;·&nbsp;
  <a href="#the-experiment-four-ais-three-prompts">The experiment</a> &nbsp;·&nbsp;
  <a href="#how-it-works">How it works</a> &nbsp;·&nbsp;
  <a href="#profiles">Profiles</a> &nbsp;·&nbsp;
  <a href="#security-defaults">Security</a> &nbsp;·&nbsp;
  <a href="AGENTS.md">AI runbook</a>
</p>

---

This repository is the setup behind my video *AI Without Guardrails*. It runs an open-weights, community-modified ("uncensored") Qwen 27B model on a rented NVIDIA RTX 5090 GPU server, and gives you a private ChatGPT-style chat window on your own computer.

You do not need to write code. Follow the steps yourself, or give the repo to an AI assistant: [AGENTS.md](AGENTS.md) is a runbook written for it.

> [!WARNING]
> **Read this first.** An uncensored model answers things hosted AIs refuse, and it can be confidently wrong. What you ask and what you do with the answer is your responsibility. Follow your local laws and your GPU provider's acceptable-use rules. This repository is published for research, education and personal experimentation, comes with no warranty (see [LICENSE](LICENSE)), and is not an endorsement of using AI to cause harm.

## What you get

| Feature | What it does |
|---|---|
| **One-command deploy** | `deploy` installs the inference engine, downloads the model at a pinned revision, starts it and runs a smoke test. |
| **Private by default** | The model API listens on the server's loopback address only. No web port is opened. You reach it through an SSH tunnel. |
| **A chat window** | A Windows launcher opens the tunnel and a local [Open WebUI](https://docs.openwebui.com/) at `http://127.0.0.1:3000`. |
| **Reviewed profiles** | Five reviewed settings files, so nobody chooses engine flags by hand. |
| **AI-assistant runbook** | [AGENTS.md](AGENTS.md) tells an assistant what to run, what to check, and when to stop and ask you. |

## The experiment: four AIs, three prompts

I gave ChatGPT, Claude, Gemini and the uncensored Qwen model the same three red-line prompts, covering a crime, hacking and a weapon. Each prompt tested something different: did the model **know**, did it **notice**, was it **honest**. The prompts and answers are not published here.

|  | <picture><source media="(prefers-color-scheme: dark)" srcset="assets/logos/openai-white.svg"><img src="assets/logos/openai-black.svg" alt="OpenAI logo" height="32"></picture><br>**ChatGPT** | <img src="assets/logos/claude.svg" alt="Claude logo" height="32"><br>**Claude** | <img src="assets/logos/gemini.svg" alt="Gemini logo" height="32"><br>**Gemini** | <img src="assets/logos/qwen.svg" alt="Qwen logo" height="32"><br>**Qwen (uncensored)** |
|---|:---:|:---:|:---:|:---:|
| **Test 1:** did it know? | Refused | Refused, offered fiction | Refused | **Answered** |
| **Test 2:** did it notice? | Refused | Refused | Refused | **Answered** |
| **Test 3:** was it honest? | Refused | Refused | Error, counted as a no | **Answered** |

Four AIs times three prompts is 12 responses: nine refusals and three answers, all three from Qwen. An answer is not the same as a good answer. When the model stops saying no, the job of saying no moves to you.

## Quick start

### What you need

| Item | Details |
|---|---|
| **GPU server** | One NVIDIA **RTX 5090 (32 GB)**, rented by the hour. Ubuntu or Debian with the NVIDIA driver installed. At least 60 GB of disk: the model is about 21 GB and the download check wants 40 GiB free. |
| **SSH** | An SSH key your provider accepts. Windows 10/11, macOS and Linux all include an SSH client. |
| **Your computer** | **Windows** with [Docker Desktop](https://www.docker.com/products/docker-desktop/) for the chat window. macOS and Linux are not tested yet (see [runtime/clients/README.md](runtime/clients/README.md)). |
| **Money** | GPU rental is billed while the server is on. Check your provider's price, and stop the server when you finish. |

The scripts refuse to start unless they find exactly one GPU that matches the profile (for the main profile, an RTX 5090 with about 32 GB). They were developed and tested on one rented RTX 5090 server from a single provider. Other providers are untested, so please report a failure instead of working around it.

### Option A: let an AI assistant do it

1. Rent an RTX 5090 server. **Log in once yourself** with `ssh <user>@<host>` and compare the host fingerprint with your provider's console.
2. Open an AI assistant that can run terminal commands, such as Claude Code or Codex. If yours cannot, it can still guide you one command at a time.
3. Paste this:

```text
I want to run a private AI model on a rented GPU using
https://github.com/gkv856/run-uncensored-ai-rtx-5090
Clone the repo, read AGENTS.md, and follow it step by step.
Ask me before anything that costs money, downloads the model,
or needs me to type something myself. Never show me the API key.
```

The assistant is told to stop and ask you before the model download, before the first SSH connection, and before anything that exposes the server to the internet.

### Option B: do it yourself

**1. On the GPU server** (after connecting with SSH):

```bash
command -v git >/dev/null || { sudo apt-get update && sudo apt-get install -y git; }
git clone https://github.com/gkv856/run-uncensored-ai-rtx-5090.git
cd run-uncensored-ai-rtx-5090
chmod +x runtime/bootstrap.ai.sh runtime/bin/*.sh
./runtime/bootstrap.ai.sh list
./runtime/bootstrap.ai.sh deploy fleetml-sglang-32k --approve-model
```

`deploy` installs system packages with `apt-get` (using `sudo` if you are not root), downloads about 21 GB, starts the model and runs a smoke test. The first run takes a while. A successful run ends with `Smoke test passed`.

<details>
<summary><strong>Prefer to read the model report before anything downloads?</strong></summary>

<br>

Run the steps one at a time instead of `deploy`:

```bash
./runtime/bootstrap.ai.sh setup fleetml-sglang-32k
./runtime/bootstrap.ai.sh inspect fleetml-sglang-32k
# read the report it prints the path of, then:
./runtime/bootstrap.ai.sh download fleetml-sglang-32k --approve-model
./runtime/bootstrap.ai.sh start fleetml-sglang-32k
./runtime/bootstrap.ai.sh smoke fleetml-sglang-32k
```

</details>

**2. On your Windows computer**, with Docker Desktop running:

```powershell
git clone https://github.com/gkv856/run-uncensored-ai-rtx-5090.git
cd run-uncensored-ai-rtx-5090
.\runtime\clients\windows\chat.ps1 -Action Start
```

It asks once for the server address, your SSH user and your key paths, opens the tunnel, and opens the chat window. The first account you create there becomes the admin. If you do not have Git on Windows, use **Code, Download ZIP** on the GitHub page instead of `git clone`.

**3. When you finish:**

```bash
./runtime/bootstrap.ai.sh stop fleetml-sglang-32k
```

Run `chat.ps1 -Action Stop` on Windows, then **stop or delete the server in your provider's dashboard** so billing stops. Stopping the model does not stop billing.

## How it works

```mermaid
flowchart TB
    subgraph PC["Your computer (Windows + Docker Desktop)"]
        UI["Open WebUI<br/>127.0.0.1:3000"]
    end
    subgraph GPU["Rented GPU server (one RTX 5090)"]
        API["SGLang API<br/>127.0.0.1:8000"]
        MODEL["Qwen 27B, NVFP4<br/>pinned revision"]
        API --> MODEL
    end
    UI -- "SSH tunnel, strict host-key checking" --> API
```

The model API never leaves the server's loopback address. Your chat window talks to it through an SSH tunnel that you open, so there is no public port to find or attack. The 4-bit NVFP4 format shrinks the 27B model to about 21 GB, which is why one 32 GB card is enough.

## Profiles

List them with `./runtime/bootstrap.ai.sh list`.

| Profile | What it is | GPU needed |
|---|---|---|
| `fleetml-sglang-32k` | **Primary.** Community uncensored Qwen 27B, NVFP4, on SGLang. This is the one in the video. | 1x RTX 5090 (32 GB) |
| `nvidia-sglang-control-32k` | Control: NVIDIA's own NVFP4 build of the base model, for side-by-side comparison. | 1x RTX 5090 |
| `preet-vllm-32k`, `tomsarihan-vllm-32k` | Fallbacks: other community uncensored NVFP4 builds, on vLLM. | 1x RTX 5090 |
| `orcarouter-sglang-bf16-32k` | Full-precision source weights. Untested here. | About 90 GB (RTX PRO 6000 or B200 class) |

The model behind each profile is a third-party Hugging Face repository, not something I trained or control. Read the model card and licence before you download, and read the inspection report the scripts produce.

## Security defaults

- **Loopback only.** The model API binds to `127.0.0.1`, and the scripts reject any other bind address.
- **Private key, never printed.** A random API key is generated on the server in `~/.config/uncensored-ai/runtime.env` (mode 600).
- **Pinned and inspected.** The model is pinned to a full 40-character Hugging Face commit SHA, remote code is off, and pickle-style weight files are skipped.
- **Strict tunnel.** The chat window reaches the server over SSH with strict host-key checking. Ports 3000 and 8000 are not open to the internet.
- **No tools for the model.** It has no shell, no file access and no cloud credentials.

Optional advanced modes exist: a chat page hosted on the server over plain HTTP, and start-on-boot. Both are off by default, and the plain-HTTP page is not safe for anything sensitive. See [runtime/README.md](runtime/README.md).

## Documentation

| Document | What is in it |
|---|---|
| [AGENTS.md](AGENTS.md) | Runbook for an AI assistant doing the setup: hard rules, phases, expected output, troubleshooting. |
| [runtime/README.md](runtime/README.md) | Commands, profile contract, process model. |
| [runtime/clients/README.md](runtime/clients/README.md) | The chat window and the SSH tunnel. |

## Contributing and support

Found a problem on another provider or another operating system? Open an issue with the exact error text. Remove any API keys, tokens or IP addresses first.

## Licence and credits

Code and documentation: [MIT](LICENSE), copyright Gaurav K Verma. The models, [SGLang](https://github.com/sgl-project/sglang), vLLM and Open WebUI have their own licences, so check them before any commercial use.

OpenAI, ChatGPT, Claude, Gemini, Qwen and their logos are trademarks of their respective owners. They appear here only to name the products I tested, with no affiliation or endorsement. Logo files come from the MIT-licensed [LobeHub icon set](https://github.com/lobehub/lobe-icons) (details in [assets/logos](assets/logos/README.md)).
