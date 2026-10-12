# Run an uncensored AI model on a rented RTX 5090

A set of scripts that runs an open-weights, community-modified ("uncensored") Qwen model on a rented RTX 5090 GPU server, with a private chat window on your own computer. It is the setup behind my video *AI Without Guardrails*.

You do not need to write code. You can follow the steps yourself, or hand this repository to an AI assistant and let it drive. A step-by-step runbook for the assistant is in [AGENTS.md](AGENTS.md).

> **Read this first.** An uncensored model will answer things a hosted AI refuses, and it can be confidently wrong. What you ask and what you do with the answer is your responsibility. Follow your local laws and your GPU provider's acceptable-use rules. This repository is published for research, education and personal experimentation, and comes with no warranty (see [LICENSE](LICENSE)). I do not endorse using it to cause harm.

## What you get

- One command on the GPU server (`deploy`) that installs the engine, downloads the model at a pinned revision, starts it, and checks it works.
- A model API that only listens on the server's own loopback address (`127.0.0.1:8000`) and needs a private key. No web port is opened by default.
- A Windows launcher that opens an SSH tunnel and a local chat window (Open WebUI) at `http://127.0.0.1:3000`.
- Reviewed profiles so you are not choosing engine flags by hand.

## What you need

| Item | Details |
|---|---|
| A GPU server | One NVIDIA **RTX 5090** (32 GB), rented by the hour. Ubuntu or Debian with the NVIDIA driver installed. At least 60 GB of disk (the model is about 21 GB and the download check wants 40 GiB free). |
| SSH | An SSH key registered with the provider. Windows 10/11, macOS and Linux all include an SSH client. |
| Your computer | **Windows** with [Docker Desktop](https://www.docker.com/products/docker-desktop/) for the chat window. macOS and Linux are not tested yet (see [runtime/clients/README.md](runtime/clients/README.md)). |
| Money | GPU rental is billed while the server is on. Check your provider's price and stop the server when you finish. |

The scripts refuse to start unless they find exactly one GPU matching the profile (for the main profile: an RTX 5090 with about 32 GB). They were developed and tested on a single rented RTX 5090 server from one provider. Other providers are untested, so treat a failure there as something to report, not a mystery.

## Easiest route: let an AI do the setup

1. Rent an RTX 5090 server and make sure you can open a terminal session to it over SSH. Do the first SSH login yourself and compare the host fingerprint with your provider's console.
2. Start an AI assistant that can run terminal commands (Claude Code, Codex, or similar). If yours cannot run commands, it can still guide you one command at a time.
3. Paste this:

```text
I want to run a private AI model on a rented GPU using
https://github.com/gkv856/run-uncensored-ai-rtx-5090
Clone the repo, read AGENTS.md, and follow it step by step.
Ask me before anything that costs money, downloads the model,
or needs me to type something myself. Never show me the API key.
```

The assistant is told to stop and ask you at the points that matter: before the model download, before the first SSH connection, and before anything that exposes the server to the internet.

## Do it yourself

On the GPU server (after connecting with SSH):

```bash
command -v git >/dev/null || { sudo apt-get update && sudo apt-get install -y git; }
git clone https://github.com/gkv856/run-uncensored-ai-rtx-5090.git
cd run-uncensored-ai-rtx-5090
chmod +x runtime/bootstrap.ai.sh runtime/bin/*.sh
./runtime/bootstrap.ai.sh list
./runtime/bootstrap.ai.sh deploy fleetml-sglang-32k --approve-model
```

`deploy` installs system packages with `apt-get` (it uses `sudo` if you are not root), downloads about 21 GB, starts the model and runs a smoke test. The first run takes a while.

If you want to read the model repository inspection report before anything is downloaded, run the steps one at a time instead:

```bash
./runtime/bootstrap.ai.sh setup fleetml-sglang-32k
./runtime/bootstrap.ai.sh inspect fleetml-sglang-32k
# read the report it prints the path of, then:
./runtime/bootstrap.ai.sh download fleetml-sglang-32k --approve-model
./runtime/bootstrap.ai.sh start fleetml-sglang-32k
./runtime/bootstrap.ai.sh smoke fleetml-sglang-32k
```

Then, on your Windows computer, with Docker Desktop running:

```powershell
git clone https://github.com/gkv856/run-uncensored-ai-rtx-5090.git
cd run-uncensored-ai-rtx-5090
.\runtime\clients\windows\chat.ps1 -Action Start
```

It asks for the server address, your SSH user and your key paths once, opens the tunnel, and opens the chat window. The first account you create there becomes the admin. If you do not have Git on Windows, use **Code, Download ZIP** on the GitHub page instead of `git clone`.

When you finish, stop the model with `./runtime/bootstrap.ai.sh stop fleetml-sglang-32k`, `chat.ps1 -Action Stop` on Windows, and **stop or delete the server in your provider's dashboard** so billing stops.

## Profiles

List them with `./runtime/bootstrap.ai.sh list`.

| Profile | What it is | GPU needed |
|---|---|---|
| `fleetml-sglang-32k` | **Primary.** Community uncensored Qwen 27B, NVFP4, on SGLang. This is the one in the video. | 1x RTX 5090 (32 GB) |
| `nvidia-sglang-control-32k` | Control: NVIDIA's own NVFP4 build of the base model, for side-by-side comparison. | 1x RTX 5090 |
| `preet-vllm-32k`, `tomsarihan-vllm-32k` | Fallbacks: other community uncensored NVFP4 builds, on vLLM. | 1x RTX 5090 |
| `orcarouter-sglang-bf16-32k` | Full-precision source weights. | About 90 GB GPU (RTX PRO 6000 or B200 class) |

The model on each profile is a third-party Hugging Face repository, not something I trained or control. Read the model card and licence before you download, and check the inspection report the scripts produce.

## Security defaults

- The model API binds to `127.0.0.1` only. The scripts reject any other bind address.
- A random API key is generated on the server in `~/.config/uncensored-ai/runtime.env` (mode 600) and is never printed.
- The model is pinned to a full 40-character Hugging Face commit SHA, and remote code execution is off.
- The chat window reaches the server through an SSH tunnel with strict host-key checking. No port 3000 or 8000 is open to the internet.
- The model has no shell, no file access and no cloud credentials.

Optional "advanced" modes (a chat page hosted on the server over plain HTTP, and start-on-boot) exist in [runtime/README.md](runtime/README.md). They are off by default, and the plain-HTTP page is not safe for anything sensitive.

## Documentation

- [AGENTS.md](AGENTS.md): runbook for an AI assistant doing the setup.
- [runtime/README.md](runtime/README.md): commands, profile contract, process model.
- [runtime/clients/README.md](runtime/clients/README.md): the chat window and SSH tunnel.

## Licence

[MIT](LICENSE). The models, the engines (SGLang, vLLM) and Open WebUI have their own licences. Check them before any commercial use.
