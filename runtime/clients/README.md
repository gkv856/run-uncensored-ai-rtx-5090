# Chat clients

The Windows launcher is the supported single-user Open WebUI path. It starts a visible native SSH tunnel, then starts a localhost-only Open WebUI Docker service. The model itself is deliberately manual: start or stop it with the Linux runtime so GPU billing is always an intentional action.

From the repo root on Windows, after starting Docker Desktop and the model profile on the server:

```powershell
.\runtime\clients\windows\chat.ps1 -Action Start
```

The first run asks for the server host, SSH user, and already-verified key paths. "Verified" means you have connected to the server over SSH once yourself, checked the host fingerprint against your provider's console, and saved it to a known-hosts file; the tunnel refuses unknown hosts. The script stores these details and the API configuration it needs under `%LOCALAPPDATA%\uncensoredAI\openwebui`, outside this source folder. It then opens `http://127.0.0.1:3000`; create the first Open WebUI administrator there.

Stop the local UI and SSH tunnel without changing the model process on the server:

```powershell
.\runtime\clients\windows\chat.ps1 -Action Stop
```

Check state at any time with `-Action Status`.

## macOS and Linux

There is no launcher script for these yet, and this path is **not tested**. The same design applies: open an SSH tunnel that maps a local loopback port to the server's `127.0.0.1:8000`, then run `runtime/clients/openwebui/compose.yaml` locally with `OPEN_WEBUI_PORT`, `LOCAL_TUNNEL_PORT`, `WEBUI_SECRET_KEY` and `MODEL_API_KEY` set. Docker Desktop on macOS should behave like Windows. Native Docker on Linux cannot reach a host loopback listener through `host.docker.internal`, so adapt the compose file (for example with host networking) and review it before use. [AGENTS.md](../../AGENTS.md) describes the steps for an AI assistant.

## Optional server-hosted browser UI

The Linux runtime can also host the chat page directly on the server. This is intentionally separate from the local-client workflow: it publishes only the Open WebUI login page at `http://<SERVER_PUBLIC_IP>:3000`, never the model API at port 8000.

From the server after connecting through verified SSH:

```bash
./runtime/bootstrap.ai.sh serve fleetml-sglang-32k --publish-ui
```

The direct raw-IP page is HTTP, so use it only for low-sensitivity testing. Retrieve the first-login credentials with `./runtime/bootstrap.ai.sh ui-credentials` and stop it with `./runtime/bootstrap.ai.sh ui-stop`.
