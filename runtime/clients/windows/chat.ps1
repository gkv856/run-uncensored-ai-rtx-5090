[CmdletBinding()]
param(
  [ValidateSet("Start", "Stop", "Status")]
  [string]$Action = "Start",
  [switch]$NoBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeDirectory = (Resolve-Path (Join-Path $scriptDirectory "..\\..")).Path
$composeFile = Join-Path $runtimeDirectory "clients\\openwebui\\compose.yaml"
$tunnelScript = Join-Path $scriptDirectory "run.tunnel.ps1"
$configDirectory = Join-Path $env:LOCALAPPDATA "uncensoredAI\\openwebui"
$configPath = Join-Path $configDirectory "connection.json"
$privateEnvironmentPath = Join-Path $configDirectory "openwebui.private.env"
$tunnelStatePath = Join-Path $configDirectory "tunnel.state.json"

# Input: a prompt and optional default. Output: a non-empty operator-selected value.
function Read-RequiredValue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,
    [string]$DefaultValue = ""
  )

  $suffix = if ([string]::IsNullOrWhiteSpace($DefaultValue)) { "" } else { " [$DefaultValue]" }
  $value = Read-Host "$Prompt$suffix"
  if ([string]::IsNullOrWhiteSpace($value)) {
    $value = $DefaultValue
  }

  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "$Prompt is required."
  }

  return $value.Trim()
}

# Input: a generated secret byte count. Output: a lower-case hexadecimal secret without console output.
function New-HexSecret {
  param(
    [int]$ByteCount = 32
  )

  $bytes = New-Object byte[] $ByteCount
  $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $random.GetBytes($bytes)
  }
  finally {
    $random.Dispose()
  }

  return (($bytes | ForEach-Object { $_.ToString("x2") }) -join "")
}

# Input: a local path. Output: a user-only ACL that prevents inherited access rules.
function Set-UserOnlyAcl {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
  $item = Get-Item -LiteralPath $Path
  $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::None
  if ($item.PSIsContainer) {
    $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
  }
  $acl = Get-Acl -LiteralPath $Path
  $acl.SetAccessRuleProtection($true, $false)
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $identity,
    [System.Security.AccessControl.FileSystemRights]::FullControl,
    $inheritanceFlags,
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow
  )
  $acl.SetAccessRule($rule)
  Set-Acl -LiteralPath $Path -AclObject $acl
}

# Input: no arguments. Output: Windows OpenSSH path, preferring the operating-system binary.
function Get-SshPath {
  $systemSshPath = Join-Path $env:WINDIR "System32\\OpenSSH\\ssh.exe"
  if (Test-Path -LiteralPath $systemSshPath) {
    return $systemSshPath
  }

  $sshCommand = Get-Command ssh.exe -ErrorAction Stop
  return $sshCommand.Source
}

# Input: no arguments. Output: Docker CLI path when Docker Desktop's command line is available.
function Get-DockerPath {
  $dockerCommand = Get-Command docker.exe -ErrorAction Stop
  return $dockerCommand.Source
}

# Input: no arguments. Output: a newly created, non-secret GPU server connection configuration.
function Initialize-Configuration {
  $defaultKeyPath = Join-Path $env:USERPROFILE ".ssh\\uncensored_ai_ed25519"
  $defaultKnownHostsPath = Join-Path $env:USERPROFILE ".ssh\\known_hosts_uncensored_ai"
  if (-not (Test-Path -LiteralPath $defaultKeyPath)) {
    $defaultKeyPath = Join-Path $env:USERPROFILE ".ssh\\id_ed25519"
  }
  if (-not (Test-Path -LiteralPath $defaultKnownHostsPath)) {
    $defaultKnownHostsPath = Join-Path $env:USERPROFILE ".ssh\\known_hosts"
  }

  Write-Host "[PrivateChat] First-run setup stores connection details under $configDirectory."
  $sshHost = Read-RequiredValue -Prompt "GPU server host or IP address"
  $sshUser = Read-RequiredValue -Prompt "SSH username" -DefaultValue "ubuntu"
  $identityFile = Read-RequiredValue -Prompt "SSH private-key path" -DefaultValue $defaultKeyPath
  $knownHostsFile = Read-RequiredValue -Prompt "Verified known-hosts path" -DefaultValue $defaultKnownHostsPath

  if (-not (Test-Path -LiteralPath $identityFile)) {
    throw "SSH private key was not found: $identityFile"
  }
  if (-not (Test-Path -LiteralPath $knownHostsFile)) {
    throw "Verified known-hosts file was not found: $knownHostsFile"
  }

  $config = [ordered]@{
    sshHost = $sshHost
    sshPort = 22
    sshUser = $sshUser
    identityFile = (Resolve-Path -LiteralPath $identityFile).Path
    knownHostsFile = (Resolve-Path -LiteralPath $knownHostsFile).Path
    localTunnelPort = 18000
    openWebUiPort = 3000
  }
  $config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8
  Set-UserOnlyAcl -Path $configDirectory
  return [pscustomobject]$config
}

# Input: no arguments. Output: validated user-only configuration, creating it only for Start.
function Get-Configuration {
  if (-not (Test-Path -LiteralPath $configPath)) {
    if ($Action -ne "Start") {
      throw "Local configuration is missing. Run chat.ps1 -Action Start once to create it."
    }
    return Initialize-Configuration
  }

  $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  $requiredProperties = @(
    "sshHost", "sshPort", "sshUser", "identityFile", "knownHostsFile", "localTunnelPort", "openWebUiPort"
  )
  foreach ($property in $requiredProperties) {
    if ([string]::IsNullOrWhiteSpace([string]$config.$property)) {
      throw "Local configuration is missing '$property': $configPath"
    }
  }
  if (-not (Test-Path -LiteralPath $config.identityFile)) {
    throw "SSH private key was not found: $($config.identityFile)"
  }
  if (-not (Test-Path -LiteralPath $config.knownHostsFile)) {
    throw "Verified known-hosts file was not found: $($config.knownHostsFile)"
  }

  return $config
}

# Input: connection configuration. Output: strict public-key SSH arguments without secrets.
function Get-SshArguments {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Config
  )

  return @(
    "-i", $Config.identityFile,
    "-o", "BatchMode=yes",
    "-o", "IdentitiesOnly=yes",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "UserKnownHostsFile=$($Config.knownHostsFile)",
    "-o", "ConnectTimeout=10",
    "-p", "$($Config.sshPort)",
    "$($Config.sshUser)@$($Config.sshHost)"
  )
}

# Input: a harmless remote command. Output: its text result or a safe connection failure.
function Invoke-RemoteCommand {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Config,
    [Parameter(Mandatory = $true)]
    [string]$Command
  )

  $sshArguments = Get-SshArguments -Config $Config
  $output = & $script:sshPath @sshArguments $Command 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Could not reach the GPU server with the verified SSH key. Start the instance in your provider's dashboard and wait until it is running."
  }
  return ($output -join "`n").Trim()
}

# Input: a localhost URL. Output: its HTTP status, or null when no listener is reachable.
function Get-HttpStatus {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Url
  )

  try {
    $request = [System.Net.WebRequest]::Create($Url)
    $request.Method = "GET"
    $request.Timeout = 5000
    $response = $request.GetResponse()
    try {
      return [int]$response.StatusCode
    }
    finally {
      $response.Close()
    }
  }
  catch [System.Net.WebException] {
    if ($null -ne $_.Exception.Response) {
      try {
        return [int]$_.Exception.Response.StatusCode
      }
      finally {
        $_.Exception.Response.Close()
      }
    }
    return $null
  }
}

# Input: port number. Output: true only when Windows has no local TCP listener on the port.
function Test-PortAvailable {
  param(
    [Parameter(Mandatory = $true)]
    [int]$Port
  )

  $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
  return -not ($listeners | Where-Object { $_.Port -eq $Port })
}

# Input: tunnel state path. Output: terminates only the recorded visible tunnel processes.
function Stop-Tunnel {
  if (-not (Test-Path -LiteralPath $tunnelStatePath)) {
    return
  }

  $state = Get-Content -LiteralPath $tunnelStatePath -Raw | ConvertFrom-Json
  foreach ($property in @("sshPid", "shellPid")) {
    $processId = $state.$property
    if ($null -ne $processId) {
      $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
      if ($null -ne $process) {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
      }
    }
  }
  Remove-Item -LiteralPath $tunnelStatePath -Force -ErrorAction SilentlyContinue
}

# Input: configuration. Output: starts a visible SSH tunnel window with a recorded process state.
function Start-Tunnel {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Config
  )

  if (Test-Path -LiteralPath $tunnelStatePath) {
    $existingStatus = Get-HttpStatus -Url "http://127.0.0.1:$($Config.localTunnelPort)/v1/models"
    if ($existingStatus -in @(401, 403)) {
      return $false
    }
    throw "A recorded SSH tunnel is not usable. Run chat.ps1 -Action Stop, then retry."
  }
  if (-not (Test-PortAvailable -Port $Config.localTunnelPort)) {
    throw "Local tunnel port $($Config.localTunnelPort) is already in use."
  }

  $powerShellPath = Join-Path $PSHOME "powershell.exe"
  if (-not (Test-Path -LiteralPath $powerShellPath)) {
    $powerShellPath = Join-Path $PSHOME "pwsh.exe"
  }
  if (-not (Test-Path -LiteralPath $powerShellPath)) {
    $powerShellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
  }
  $arguments = @(
    "-NoLogo",
    "-NoExit",
    "-File", $tunnelScript,
    "-ConfigPath", $configPath,
    "-StatePath", $tunnelStatePath
  )
  Start-Process -FilePath $powerShellPath -ArgumentList $arguments | Out-Null

  $deadline = (Get-Date).AddSeconds(20)
  do {
    Start-Sleep -Milliseconds 500
    $status = Get-HttpStatus -Url "http://127.0.0.1:$($Config.localTunnelPort)/v1/models"
    if ($status -in @(401, 403)) {
      return $true
    }
  } while ((Get-Date) -lt $deadline)

  throw "The SSH tunnel opened but the model API is unavailable. Start the profile on the server, then retry."
}

# Input: connection configuration. Output: model API key captured over verified SSH and never printed.
function Get-RemoteApiKey {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Config
  )

  $command = @'
env_file="$HOME/.config/uncensored-ai/runtime.env"
test -r "$env_file"
awk -F= '$1 == "API_KEY" { print substr($0, index($0, "=") + 1); exit }' "$env_file"
'@
  $apiKey = Invoke-RemoteCommand -Config $Config -Command $command
  if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey.Length -lt 32) {
    throw "The server did not return a valid model API key."
  }
  return $apiKey
}

# Input: a simple KEY=VALUE environment file. Output: dictionary of non-empty values.
function Get-EnvironmentValues {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $values = @{}
  if (-not (Test-Path -LiteralPath $Path)) {
    return $values
  }
  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match "^([^=]+)=(.*)$") {
      $values[$matches[1]] = $matches[2]
    }
  }
  return $values
}

# Input: remote model key and connection settings. Output: private Docker environment file with user-only ACL.
function Write-PrivateEnvironment {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ModelApiKey,
    [Parameter(Mandatory = $true)]
    [object]$Config
  )

  $existingValues = Get-EnvironmentValues -Path $privateEnvironmentPath
  $webUiSecret = $existingValues["WEBUI_SECRET_KEY"]
  if ([string]::IsNullOrWhiteSpace($webUiSecret)) {
    $webUiSecret = New-HexSecret
  }

  $lines = @(
    "MODEL_API_KEY=$ModelApiKey",
    "WEBUI_SECRET_KEY=$webUiSecret",
    "LOCAL_TUNNEL_PORT=$($Config.localTunnelPort)",
    "OPEN_WEBUI_PORT=$($Config.openWebUiPort)"
  )
  Set-Content -LiteralPath $privateEnvironmentPath -Value $lines -Encoding ascii
  Set-UserOnlyAcl -Path $privateEnvironmentPath
}

# Input: no arguments. Output: fails unless the user has manually started Docker Desktop.
function Assert-DockerReady {
  $null = & $script:dockerPath version --format "{{.Server.Version}}" 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Docker Desktop is not running. Start it manually, wait for its engine to be ready, then retry."
  }
}

# Input: Compose arguments. Output: Docker Compose result or a clear failure.
function Invoke-Compose {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  & $script:dockerPath compose --env-file $privateEnvironmentPath -f $composeFile @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Open WebUI Docker Compose command failed."
  }
}

# Input: connection configuration. Output: private local web chat after model and tunnel checks pass.
function Start-Chat {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Config
  )

  $remoteResult = Invoke-RemoteCommand -Config $Config -Command "printf remote-ok"
  if ($remoteResult -ne "remote-ok") {
    throw "SSH verification returned an unexpected result."
  }

  $tunnelStarted = Start-Tunnel -Config $Config
  try {
    $apiKey = Get-RemoteApiKey -Config $Config
    Write-PrivateEnvironment -ModelApiKey $apiKey -Config $Config
    Assert-DockerReady

    if (-not (Test-PortAvailable -Port $Config.openWebUiPort)) {
      $existingUiStatus = Get-HttpStatus -Url "http://127.0.0.1:$($Config.openWebUiPort)"
      if ($existingUiStatus -eq $null) {
        throw "Local Open WebUI port $($Config.openWebUiPort) is already in use."
      }
    }

    Invoke-Compose -Arguments @("up", "-d")
    $deadline = (Get-Date).AddMinutes(2)
    do {
      Start-Sleep -Seconds 2
      $webUiStatus = Get-HttpStatus -Url "http://127.0.0.1:$($Config.openWebUiPort)"
      if ($webUiStatus -in @(200, 302, 307)) {
        $url = "http://127.0.0.1:$($Config.openWebUiPort)"
        Write-Host "[PrivateChat] Ready at $url"
        if (-not $NoBrowser) {
          Start-Process $url
        }
        return
      }
    } while ((Get-Date) -lt $deadline)

    throw "Open WebUI did not become ready within two minutes. Run Docker Compose logs for details."
  }
  catch {
    if ($tunnelStarted -or (Test-Path -LiteralPath $tunnelStatePath)) {
      Stop-Tunnel
    }
    throw
  }
}

# Input: no arguments. Output: local UI and tracked tunnel stopped; remote inference is unchanged.
function Stop-Chat {
  if (Test-Path -LiteralPath $privateEnvironmentPath) {
    try {
      $script:dockerPath = Get-DockerPath
      Assert-DockerReady
      Invoke-Compose -Arguments @("down")
    }
    catch {
      Write-Warning "[PrivateChat] Local Open WebUI was not stopped through Docker: $($_.Exception.Message)"
    }
  }
  Stop-Tunnel
  Write-Host "[PrivateChat] Local UI and SSH tunnel stopped. Server inference was not changed."
}

# Input: connection configuration. Output: non-mutating local and tunnel state summary.
function Show-Status {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Config
  )

  $tunnelStatus = Get-HttpStatus -Url "http://127.0.0.1:$($Config.localTunnelPort)/v1/models"
  $uiStatus = Get-HttpStatus -Url "http://127.0.0.1:$($Config.openWebUiPort)"
  Write-Host "[PrivateChat] Tunnel HTTP status: $tunnelStatus"
  Write-Host "[PrivateChat] Open WebUI HTTP status: $uiStatus"
}

try {
  if (-not (Test-Path -LiteralPath $configDirectory)) {
    New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
    Set-UserOnlyAcl -Path $configDirectory
  }
  if ($Action -ne "Stop") {
    $script:sshPath = Get-SshPath
    $script:dockerPath = Get-DockerPath
    $config = Get-Configuration
  }

  switch ($Action) {
    "Start" { Start-Chat -Config $config }
    "Stop" { Stop-Chat }
    "Status" { Show-Status -Config $config }
  }
}
catch {
  Write-Error "[PrivateChat] $($_.Exception.Message)"
  exit 1
}
