# Import parameters from an official Komari Agent install command and install
# this fork instead. Mirrors import-command.sh for Windows.
#
# Usage:
#   .\import-command.ps1
#   .\import-command.ps1 -AgentCommand '<official command>'
#   Get-Clipboard | .\import-command.ps1
#
# Options:
#   -DryRun              print the parsed result without installing
#   -Yes                 skip the confirmation prompt
#   -InstallUrl <url>    override the install.ps1 URL

param(
    [string]$AgentCommand = "",
    [switch]$DryRun,
    [switch]$Yes,
    [string]$InstallUrl = "https://raw.githubusercontent.com/LHDyx/komari-agent/refs/heads/main/install.ps1"
)

$ErrorActionPreference = "Stop"

if (-not $AgentCommand) {
    if ($MyInvocation.ExpectingInput) {
        $AgentCommand = (@($input) -join ' ')
    }
    elseif (-not [Console]::IsInputRedirected) {
        Write-Host "Paste the official install command and press Enter:"
        $AgentCommand = Read-Host ">"
    }
    else {
        $AgentCommand = (@($input) -join ' ')
    }
}

$AgentCommand = ($AgentCommand -replace "\r?\n", " ").Trim()
if (-not $AgentCommand) {
    Write-Host "No command received." -ForegroundColor Red
    exit 2
}

# powershell ... -Command "iwr ...; & '.\install.ps1' '-e' ..."
# Strip the -Command wrapper so its inner tokens can be parsed.
if ($AgentCommand -match '(?s)-Command\s+"(.*)"\s*$') {
    $AgentCommand = $Matches[1]
}
elseif ($AgentCommand -match "(?s)-Command\s+'(.*)'\s*$") {
    $AgentCommand = $Matches[1]
}

function Split-CommandLine {
    param([string]$Text)
    $tokens = @()
    $current = ""
    $quote = $null
    foreach ($ch in $Text.ToCharArray()) {
        if ($null -ne $quote) {
            if ($ch -eq $quote) { $quote = $null } else { $current += $ch }
        }
        elseif ($ch -eq "'" -or $ch -eq '"') {
            $quote = $ch
        }
        elseif ($ch -eq ' ' -or $ch -eq "`t") {
            if ($current -ne "") { $tokens += $current; $current = "" }
        }
        else {
            $current += $ch
        }
    }
    if ($current -ne "") { $tokens += $current }
    return , $tokens
}

$tokens = Split-CommandLine $AgentCommand

$valueFlags = @(
    '-e', '--endpoint', '-t', '--token', '-i', '--interval', '-r', '--max-retries',
    '-c', '--reconnect-interval', '--auto-discovery', '--info-report-interval',
    '--include-nics', '--exclude-nics', '--include-mountpoint', '--month-rotate',
    '--custom-dns', '--custom-ipv4', '--custom-ipv6', '--prefer-ip-version',
    '--config', '--update-repo', '--install-dir', '--install-service-name',
    '--install-ghproxy', '--install-version', '--install-repo'
)
$boolFlags = @(
    '--disable-auto-update', '--disable-web-ssh', '--ignore-unsafe-cert', '-u',
    '--gpu', '--memory-include-cache', '--memory-exclude-bcf', '--get-ip-addr-from-nic',
    '--disable-compression', '--enable-security-warning', '--install-no-mirror',
    '--install-no-verify', '--install-keep-legacy', '--install-no-hide', '--install-use-sc'
)

$newArgs = @()
for ($i = 0; $i -lt $tokens.Count; $i++) {
    $t = [string]$tokens[$i]
    if ($t -match '^(--[^=]+)=(.+)$') {
        if ($valueFlags -contains $Matches[1]) { $newArgs += $t }
        continue
    }
    if ($valueFlags -contains $t) {
        if ($i + 1 -lt $tokens.Count) {
            $newArgs += $t
            $newArgs += [string]$tokens[$i + 1]
            $i++
        }
        continue
    }
    if ($boolFlags -contains $t) { $newArgs += $t }
}

$endpoint = ""
$identityKind = ""
$identityValue = ""
for ($j = 0; $j -lt $newArgs.Count; $j++) {
    $a = [string]$newArgs[$j]
    $next = ""
    if ($j + 1 -lt $newArgs.Count) { $next = [string]$newArgs[$j + 1] }

    if ($a -eq '-e' -or $a -eq '--endpoint') {
        $endpoint = $next
    }
    elseif ($a -match '^--endpoint=(.+)$') {
        $endpoint = $Matches[1]
    }
    elseif ($a -eq '-t' -or $a -eq '--token') {
        $identityKind = 'token'
        $identityValue = $next
    }
    elseif ($a -match '^--token=(.+)$') {
        $identityKind = 'token'
        $identityValue = $Matches[1]
    }
    elseif ($a -eq '--auto-discovery') {
        $identityKind = 'auto-discovery'
        $identityValue = $next
    }
    elseif ($a -match '^--auto-discovery=(.+)$') {
        $identityKind = 'auto-discovery'
        $identityValue = $Matches[1]
    }
}

if (-not $endpoint) {
    Write-Host "Could not parse the endpoint (-e/--endpoint)." -ForegroundColor Red
    Write-Host ("Parsed args: " + ($newArgs -join ' '))
    exit 2
}
if (-not $identityValue) {
    Write-Host "Could not parse a token (-t/--token) or auto-discovery key." -ForegroundColor Red
    Write-Host ("Parsed args: " + ($newArgs -join ' '))
    exit 2
}

function Get-Masked([string]$Value) {
    if ($Value.Length -le 2) { return $Value.Substring(0, 1) + "****" }
    if ($Value.Length -le 8) { return $Value.Substring(0, 2) + "****" }
    return $Value.Substring(0, 4) + "****" + $Value.Substring($Value.Length - 2)
}

Write-Host "Parsed result:"
Write-Host "  Endpoint: $endpoint"
Write-Host "  Identity: $identityKind $(Get-Masked $identityValue)"
Write-Host ("  Args: " + ($newArgs -join ' '))
Write-Host "  Install script: $InstallUrl"

if ($DryRun) {
    Write-Host ""
    Write-Host "(dry run, nothing installed)"
    exit 0
}

if (-not $Yes) {
    $answer = Read-Host "Continue installation? [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host "Cancelled."
        exit 1
    }
}

$tempScript = Join-Path $env:TEMP ("komari-import-" + [guid]::NewGuid().ToString("N") + ".ps1")
try {
    Write-Host "Fetching install script ..."
    Invoke-WebRequest -Uri $InstallUrl -OutFile $tempScript -UseBasicParsing
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tempScript @newArgs
    exit $LASTEXITCODE
}
finally {
    Remove-Item -Path $tempScript -Force -ErrorAction SilentlyContinue
}
