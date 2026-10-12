# Runtime toolkit

This directory is the executable part of the deployment: reviewed model profiles, and the scripts that install an inference engine, download and pin a model, start it privately, and open a chat window to it. The repo root [README](../README.md) explains what this is for; [AGENTS.md](../AGENTS.md) is the step-by-step runbook for an AI assistant.

## Quick path

On the Linux GPU server, from the repo root:

```bash
chmod +x runtime/bootstrap.ai.sh runtime/bin/*.sh
./runtime/bootstrap.ai.sh list
./runtime/bootstrap.ai.sh deploy fleetml-sglang-32k --approve-model
```

After the server is warm, run the provider-neutral three-case benchmark:

```bash
./runtime/bootstrap.ai.sh benchmark fleetml-sglang-32k
```

Stop it with:

```bash
./runtime/bootstrap.ai.sh stop fleetml-sglang-32k
```

`deploy` is deliberately explicit: it installs the Linux and Python prerequisites, creates a private API key file, records repository metadata, pins the model to a full commit SHA, downloads the snapshot, validates the GPU and disk, launches it, and runs authenticated checks. `--approve-model` is required because downloading writes tens of gigabytes to the server disk. If you want to read the repository-inspection report before anything is downloaded, run the steps one at a time instead (`setup`, `inspect`, then `download --approve-model`, `start`, `smoke`).

## Chat window: private by default

The model API only ever listens on `127.0.0.1:8000` on the server. The default way to chat is a private SSH tunnel from your own computer, which keeps the server's web ports closed.

On Windows, with Docker Desktop running and the model profile started on the server:

```powershell
.\runtime\clients\windows\chat.ps1 -Action Start
```

It opens Open WebUI only at `http://127.0.0.1:3000` and creates a visible SSH tunnel to the server's loopback API. The first-run settings and API key stay outside this repository (under `%LOCALAPPDATA%\uncensoredAI\openwebui`). See [clients/README.md](clients/README.md).

## Advanced: chat UI hosted on the server

One command starts the selected profile if needed, installs Docker, and starts a password-protected Open WebUI page:

```bash
./runtime/bootstrap.ai.sh serve fleetml-sglang-32k --publish-ui
```

The model API remains `127.0.0.1:8000`; only Open WebUI is published, at `http://<SERVER_PUBLIC_IP>:3000`. Its default title is **AI UnChained**, the initial administrator is named **Admin**, and the selected FleetML profile appears as **Qwen UnCensored**. Retrieve the one-time administrator credentials in the same SSH session with `./runtime/bootstrap.ai.sh ui-credentials`.

**This route is plain HTTP on a public IP, not HTTPS.** Do not use it for anything sensitive, and prefer the SSH tunnel above. Stop it with `./runtime/bootstrap.ai.sh serve-stop fleetml-sglang-32k`.

## Advanced: keep the model and UI ready after the server restarts

The default server session is deliberate and manual. When you explicitly want a server to restore the selected model and hosted chat UI after every boot, enable the guarded system service once:

```bash
./runtime/bootstrap.ai.sh autostart fleetml-sglang-32k --publish-ui
```

The command installs a system service, enables it for future boots, and waits until the authenticated loopback model API, the Open WebUI container, and the UI HTTP endpoint are all healthy. After that, the guardian checks the stack every 30 seconds and reconciles a failed model or UI layer. The inference API remains loopback-only; the only public listener is the authenticated UI on port 3000.

Check the current state without exposing credentials:

```bash
./runtime/bootstrap.ai.sh status fleetml-sglang-32k
```

Disable automatic startup without deleting model files, UI data, or credentials:

```bash
./runtime/bootstrap.ai.sh autostart-disable
```

Automatic startup consumes your GPU provider's hourly rate whenever the server boots. Enable it only for a server you intend to keep serving.

## Profile contract

Tracked profiles contain public, reproducible settings only:

```text
PROFILE_NAME, PROFILE_ROLE
ENGINE, ENGINE_VERSION
MODEL_ID, MODEL_REVISION
SERVED_MODEL_NAME
BIND_HOST, PORT
MAX_MODEL_LEN
TRUST_REMOTE_CODE, SPECULATIVE_DECODING
hardware and disk minimums
engine-specific cache, parser, and batching fields
```

`MODEL_REVISION` remains a visible placeholder until the operator inspects the repository. `pin-revision.sh` writes the resolved 40-character SHA to an untracked `<profile>.revision.env` override under `~/.config/uncensored-ai/profiles`. Optional reviewed exceptions belong in a separate `<profile>.local.env` file.

## Security properties

- Launch adapters reject any bind address except `127.0.0.1`.
- They reject a missing or placeholder API key.
- They reject an unpinned model revision.
- Model loading uses a local directory downloaded at that exact revision.
- Remote code needs two independent local opt-ins; every tracked profile disables it.
- No adapter gives the model a shell, a filesystem, or cloud credentials.
- Logs are created with a restrictive umask and are stored outside the repository.

The API key is necessarily supplied to the engine process as an engine argument. On a single-user disposable server this is defence in depth behind SSH. Do not add untrusted shell users to that server, and never include the command line in public screenshots.

## Process model

`start-profile.sh` performs preflight, launches a bounded supervisor in a new process group, starts GPU power logging, writes PID files, and waits for the authenticated model endpoint. The supervisor restarts an unexpected server exit only a small configured number of times. `stop-profile.sh` sends a clean termination signal to the whole server process group and stops its power logger. The bootstrap entry point invokes these adapters; use an adapter directly only for a reviewed troubleshooting step.

The default remains intentional session supervision. The optional boot guardian is a separately enabled, named service for one reviewed profile; it continuously verifies both the model API and Open WebUI, and does not broaden the model API's network exposure. Its billing implication is explicit at installation time.
