[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ConfigPath,
  [Parameter(Mandatory = $true)]
  [string]$StatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Input: a user-only JSON connection configuration. Output: a visible SSH tunnel window.
function Get-SshPath {
  $systemSshPath = Join-Path $env:WINDIR "System32\\OpenSSH\\ssh.exe"
  if (Test-Path -LiteralPath $systemSshPath) {
    return $systemSshPath
  }

  $sshCommand = Get-Command ssh.exe -ErrorAction Stop
  return $sshCommand.Source
}

# Input: a configuration object. Output: OpenSSH arguments that bind only Windows loopback.
function Get-SshArguments {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Config
  )

  return @(
    "-NT",
    "-i", $Config.identityFile,
    "-o", "BatchMode=yes",
    "-o", "IdentitiesOnly=yes",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "UserKnownHostsFile=$($Config.knownHostsFile)",
    "-o", "ExitOnForwardFailure=yes",
    "-o", "ServerAliveInterval=30",
    "-o", "ServerAliveCountMax=3",
    "-L", "127.0.0.1:$($Config.localTunnelPort):127.0.0.1:8000",
    "-p", "$($Config.sshPort)",
    "$($Config.sshUser)@$($Config.sshHost)"
  )
}

try {
  $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
  $sshPath = Get-SshPath
  $sshArguments = Get-SshArguments -Config $config

  # Start SSH in this visible terminal and record both process identifiers for safe cleanup.
  $sshProcess = Start-Process -FilePath $sshPath -ArgumentList $sshArguments -NoNewWindow -PassThru
  $state = [ordered]@{
    shellPid = $PID
    sshPid = $sshProcess.Id
  }
  $state | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding utf8

  Write-Host "[PrivateTunnel] Connected window is active. Closing this window ends model access."
  Wait-Process -Id $sshProcess.Id
}
catch {
  Write-Error "[PrivateTunnel] $($_.Exception.Message)"
}
finally {
  if (Test-Path -LiteralPath $StatePath) {
    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
  }
}
