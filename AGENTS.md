# AGENTS.md: runbook for an AI assistant

You are helping a person, who may not be technical, set up a private AI model on a rented GPU server and chat with it from their own computer. Follow this file step by step. The human decides; you operate. Read [README.md](README.md) first if you have not.

## Hard rules

These apply for the whole session. If a step seems to need breaking one, stop and ask the human.

1. **Never print, echo, log, commit or paste the API key.** It lives in `~/.config/uncensored-ai/runtime.env` on the server. Do not `cat` that file. Do not put it in a command line, a URL, a chat message or a file in this repository. The smoke test and the Windows launcher read it themselves.
2. **Never open port 8000, and never expose the model API to the internet.** The scripts bind to `127.0.0.1` on purpose. Do not edit `BIND_HOST`, add firewall rules that open ports, or change the SSH tunnel to listen on anything but loopback.
3. **Do not run `serve ... --publish-ui` or `autostart` unless the human explicitly asks for it by name.** `--publish-ui` serves a login page over plain HTTP on the server's public IP. `autostart` keeps the GPU billing after every reboot. The default way to chat is the SSH tunnel.
4. **Get a clear yes from the human before `--approve-model`.** That flag downloads about 21 GB onto the server from a third-party Hugging Face repository. Tell them the model name, the size and the profile first, and prefer the step-by-step path (see Phase 3) so they can read the inspection report.
5. **Ask before anything that costs money or changes their accounts.** Renting or starting a server, resizing a disk, or paying for anything is the human's action, in their provider's dashboard. Do not try to log in to their accounts or handle their payment details.
6. **The human does the first SSH login and checks the host fingerprint.** Do not disable host-key checking (`StrictHostKeyChecking=no`, `-o UserKnownHostsFile=/dev/null`) anywhere to make a connection work.
7. **Do not edit the profiles under `runtime/profiles/`, the scripts under `runtime/bin/`, or the security defaults** to work around an error. Read the error, use the troubleshooting section, and ask the human. If a script has a real bug, say so and propose a patch; do not apply it silently.
8. **Stay inside this repository and the setup task.** Do not read the human's unrelated files, browser data or other SSH keys. Do not send their data anywhere.
9. **At the end, remind the human to stop or delete the server in the provider's dashboard**, and to check the billing page. Stopping the model process does not stop billing.
10. **Be honest about results.** If a step fails, show the human the error text (with any secrets removed) and say what you will try next. Do not claim it works until the smoke test in Phase 4 has passed.

If you cannot run commands yourself (for example you are a chat window), give the human **one command at a time**, say where to run it (their laptop or the GPU server), and ask them to paste the output back. Never ask them to paste the API key.

## About this model (tell the human)

The model is a community-modified, "uncensored" Qwen model. It refuses less than hosted assistants and can state wrong things confidently. The human is responsible for what they ask and what they do with the answers, and must follow local law and the GPU provider's acceptable-use policy. Do not use this setup yourself to produce content that helps cause harm, and do not help the human bypass their provider's rules.

## Phase 0: what the human needs

Confirm each item before you start. Ask for anything missing.

- [ ] A rented GPU server with **exactly one NVIDIA RTX 5090 (32 GB)**, running **Ubuntu or Debian** with the NVIDIA driver already installed, and **at least 60 GB of disk**. (`orcarouter-sglang-bf16-32k` instead needs a GPU of about 90 GB; do not pick it unless they have one.)
- [ ] The server's IP address (or host name), the SSH user (often `ubuntu` or `root`) and an SSH private key the provider accepts.
- [ ] They have logged in to the server once themselves with `ssh <user>@<host>` and checked the host fingerprint against the provider's console. This also saves the host key to their `known_hosts` file, which the Windows launcher needs.
- [ ] For the chat window on their own computer: Windows 10/11 with [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running. macOS and Linux are untested (see Phase 5).
- [ ] They understand the server bills by the hour until they stop it.

If the key has a passphrase, the Windows launcher cannot prompt for it (it runs SSH in batch mode), so the key must be loaded into `ssh-agent` first, or they should create a separate key for this server.

## Phase 1: check the server

Run on the **GPU server** (over SSH).

```bash
nvidia-smi -L
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
df -h ~
cat /etc/os-release | head -3
```

Expected: exactly one line from `nvidia-smi -L`, a name containing `RTX 5090`, memory of about 32000 MiB, at least 60 GB free, and Ubuntu or Debian.

Stop and ask the human if any of these is off:

| Symptom | Likely cause |
|---|---|
| `nvidia-smi: command not found` or "couldn't communicate with the NVIDIA driver" | The image has no driver. Ask the human to pick a newer Ubuntu image from the provider that includes the NVIDIA driver. The RTX 50 series needs a recent driver. |
| More than one GPU listed | The single-user profiles require exactly one. Pick a one-GPU instance. |
| A different GPU name | Not supported by the primary profile. Do not edit `EXPECTED_GPU_NAME_REGEX` to force it. |
| Less than 40 GiB free | The download check will fail. Ask for a bigger disk. |

## Phase 2: get the code onto the server

On the **GPU server**:

```bash
command -v git >/dev/null || { sudo apt-get update && sudo apt-get install -y git; }
git clone https://github.com/gkv856/run-uncensored-ai-rtx-5090.git
cd run-uncensored-ai-rtx-5090
chmod +x runtime/bootstrap.ai.sh runtime/bin/*.sh
./runtime/bootstrap.ai.sh list
```

Expected: a table of five profiles. The primary one is `fleetml-sglang-32k`. Use it unless the human asks for another and you have checked its GPU requirement in the README.

If `sudo` asks for a password, ask the human; do not guess. If the user is `root`, `sudo` is not needed.

## Phase 3: install, inspect, download

The step-by-step path lets the human read the inspection report before the download. Use it unless the human has already reviewed the model and asked for the one-shot `deploy`.

```bash
./runtime/bootstrap.ai.sh setup fleetml-sglang-32k
```

This installs system packages with `apt-get`, creates `~/.config/uncensored-ai/runtime.env` with a generated API key (the output says it was not printed), and installs the inference engine. It can take a while. A good finish prints `cuda_available=True`, a `gpu=` line naming the RTX 5090, and `Installed sglang 0.5.19.` If `cuda_available=False`, the NVIDIA driver or image is wrong; go back to Phase 1. If it prints "Automatic setup currently supports Ubuntu/Debian with apt-get", the OS is unsupported; tell the human.

```bash
./runtime/bootstrap.ai.sh inspect fleetml-sglang-32k
```

It prints `Repository inspection completed: <path>`. Read that file and give the human a short summary: the repository and resolved revision, and the risk scan. A clean result contains `repository_file_risk_scan=no Python or pickle-style weight files found`. Any line starting with `ACTION:` (for example a repository that ships Python files, or pickle-style weights) is a warning you must show them in plain words; the download script skips pickle-style weight files, and remote code stays off. Then say:

> The next step downloads about 21 GB of model files from `fleetml/Qwen3.8-27B-Uncensored-NVFP4-RTX5090` on Hugging Face to this server. Do you want me to go ahead?

Only after a clear yes:

```bash
./runtime/bootstrap.ai.sh download fleetml-sglang-32k --approve-model
```

This pins the model to a full commit SHA and downloads that exact snapshot. It checks free disk first (at least 40 GiB for this profile).

Shortcut, only if the human asks for it or has already reviewed the model: `./runtime/bootstrap.ai.sh deploy fleetml-sglang-32k --approve-model` runs setup, inspect, pin, download, start and smoke in one go.

## Phase 4: start and verify

```bash
./runtime/bootstrap.ai.sh start fleetml-sglang-32k
./runtime/bootstrap.ai.sh smoke fleetml-sglang-32k
```

`start` runs a preflight (GPU, disk, port, key, revision pin) and waits until the model answers; success prints `Profile is ready at http://127.0.0.1:8000/v1`. Loading a 27B model takes minutes; do not kill it early. `smoke` must end with `Smoke test passed`. It proves four things: anonymous requests are rejected, a wrong key is rejected, the right key works, and a chat and tool-call request both return.

Where to look when something fails (on the server):

```bash
ls ~/.local/share/uncensored-ai/logs/fleetml-sglang-32k/
tail -n 60 ~/.local/share/uncensored-ai/logs/fleetml-sglang-32k/<latest log file>
./runtime/bootstrap.ai.sh status fleetml-sglang-32k
```

`status` also checks the optional server-hosted chat page, so in the default tunnel-only setup it prints `open_webui=missing` and exits with an error even when everything is fine. Only the `model_api=200` line matters here. Before showing log excerpts to anyone, check they contain no API key (the key is passed to the engine process, so never paste a process listing such as `ps aux` output).

| Error | Meaning and next step |
|---|---|
| `Port 8000 is already listening` | A previous run is still up. Run `./runtime/bootstrap.ai.sh stop fleetml-sglang-32k`, then start again. |
| `GPU '...' does not match ...` or `GPU reports N MiB` | Wrong GPU or not enough memory. See Phase 1. |
| `Only N GiB is free` | Not enough disk. The human must resize the disk or pick a bigger instance. |
| Out-of-memory in the engine log | Something else is using the GPU. Check `nvidia-smi`. Do not raise the memory settings in the profile. |
| `Unauthenticated /v1/models returned HTTP 200` | The endpoint is not private. Do not continue. Stop the profile and tell the human. |
| `Model download is intentionally gated` | You forgot `--approve-model`. Get the human's yes first. |
| Download fails or stalls | Re-run `download`; files already downloaded are skipped. If Hugging Face rate-limits, the human can create a read-only Hugging Face token and put it in `HF_TOKEN=` in `~/.config/uncensored-ai/runtime.env` themselves. Do not ask them to paste it to you. |

Optional: `./runtime/bootstrap.ai.sh benchmark fleetml-sglang-32k` runs a short three-case timing test.

## Phase 5: the private chat window

The model is now running on the server, reachable only on the server's loopback. The human chats from their own computer through an SSH tunnel.

**Windows** (the tested path). On the human's computer, with Docker Desktop running:

```powershell
git clone https://github.com/gkv856/run-uncensored-ai-rtx-5090.git
cd run-uncensored-ai-rtx-5090
.\runtime\clients\windows\chat.ps1 -Action Start
```

(If they do not have Git, they can download the ZIP from the GitHub page.) The first run asks four things: the server host or IP, the SSH username, the SSH private-key path, and the verified known-hosts path. The defaults fall back to `~\.ssh\id_ed25519` and `~\.ssh\known_hosts`. Have the human type them; they are not secrets, but the key file's contents are. It then fetches the API key over SSH, starts a localhost-only Open WebUI container, and opens `http://127.0.0.1:3000`. The first account they create there becomes the admin.

- Check it: `.\runtime\clients\windows\chat.ps1 -Action Status`
- Stop the local window and the tunnel: `.\runtime\clients\windows\chat.ps1 -Action Stop` (this does not stop the model on the server).
- "Could not reach the GPU server with the verified SSH key": the server is stopped, the IP changed, the key needs a passphrase (see Phase 0), or the host key is not in the known-hosts file. Have the human SSH in manually once more.
- "The SSH tunnel opened but the model API is unavailable": the model is not running. Run `start` on the server.

**macOS and Linux:** there is no launcher and this path is **untested**. Say so to the human. The design is the same: an SSH tunnel from a local loopback port to the server's `127.0.0.1:8000`, then `runtime/clients/openwebui/compose.yaml` run locally. Read [runtime/clients/README.md](runtime/clients/README.md) and tell the human what you will do before doing it. Do not use `--publish-ui` as a shortcut.

**If the human only wants an API:** the same tunnel works for scripts. Map `-L 127.0.0.1:18000:127.0.0.1:8000` over SSH and call `http://127.0.0.1:18000/v1` with the key as a Bearer token. Do not write the key into any file you create.

## Phase 6: wrap up

Tell the human, in plain words:

1. How to chat again: start the server in the dashboard, `ssh` in, `./runtime/bootstrap.ai.sh start fleetml-sglang-32k`, then `chat.ps1 -Action Start`. (Model files and the API key survive a normal stop of the instance only if the disk persists; some providers wipe the disk when an instance is deleted.)
2. How to stop the model: `./runtime/bootstrap.ai.sh stop fleetml-sglang-32k`.
3. **How to stop paying: stop or delete the server in the provider's dashboard, then check the billing page.** Stopping the model does not stop billing, and some providers keep billing for the disk after the server stops.
4. A reminder that the model can be confidently wrong and that what they do with its answers is on them.

## Reference

| What | Where |
|---|---|
| Entry point | `./runtime/bootstrap.ai.sh <command> <profile>` (run with no arguments for usage) |
| Private config and API key | `~/.config/uncensored-ai/runtime.env` (server, mode 600) |
| Model files, engine, logs | `~/.local/share/uncensored-ai/` (server) |
| Profile settings | `runtime/profiles/*.env` |
| Pinned revision override | `~/.config/uncensored-ai/profiles/<profile>.revision.env` |
| Windows chat settings | `%LOCALAPPDATA%\uncensoredAI\openwebui` (laptop) |
| Details | [runtime/README.md](runtime/README.md), [runtime/clients/README.md](runtime/clients/README.md) |
