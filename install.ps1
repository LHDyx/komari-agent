# Windows PowerShell installation script for Komari Agent

# Logging functions with colors
function Log-Info { param([string]$Message) Write-Host "$Message"    -ForegroundColor Cyan }
function Log-Success { param([string]$Message) Write-Host "$Message"    -ForegroundColor Green }
function Log-Warning { param([string]$Message) Write-Host "[WARNING] $Message"    -ForegroundColor Yellow }
function Log-Error { param([string]$Message) Write-Host "[ERROR] $Message"    -ForegroundColor Red }
function Log-Step { param([string]$Message) Write-Host "$Message"    -ForegroundColor Magenta }
function Log-Config { param([string]$Message) Write-Host "- $Message"    -ForegroundColor White }

# Default parameters
$SystemDriveLetter = if ($Env:SystemDrive) { $Env:SystemDrive } else { "C:" }
$InstallDir = Join-Path $SystemDriveLetter "kmr\lh"
$ServiceName = "kmr-ag"
$GitHubProxy = ""
$KomariArgs = @()
$InstallVersion = ""
$AgentRepo = "LHDyx/komari-agent"  # 发布产物来源仓库（owner/name）
$VerifyChecksum = $true
$InstallKeepLegacy = $false      # 不自动清理旧版本安装
$NoHide = $false                 # 安装后不隐藏安装目录
$NoScFallback = $false           # sm.exe 不可用时禁止回退 sc.exe

# Parse script arguments
for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        "--install-dir" { $InstallDir = $args[$i + 1]; $i++; continue }
        "--install-service-name" { $ServiceName = $args[$i + 1]; $i++; continue }
        "--install-ghproxy" { $GitHubProxy = $args[$i + 1]; $i++; continue }
        "--install-version" { $InstallVersion = $args[$i + 1]; $i++; continue }
        "--install-repo" { $AgentRepo = $args[$i + 1]; $i++; continue }
        "--install-no-verify" { $VerifyChecksum = $false; continue }
        "--install-keep-legacy" { $InstallKeepLegacy = $true; continue }
        "--install-no-hide" { $NoHide = $true; continue }
        "--install-no-sc-fallback" { $NoScFallback = $true; continue }
        Default { $KomariArgs += $args[$i] }
    }
}

# Quote a value the way the Windows C runtime command-line parser expects,
# so arguments survive command-line re-quoting boundaries (Start-Process
# -ArgumentList, powershell -File, cmd /c, ...) even when they contain
# spaces such as C:\Users\John Doe\... (komari-monitor/komari#655).
function ConvertTo-CommandLineArg {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    $escaped = $Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

# Ensure running as Administrator. Instead of failing, re-launch this script
# elevated and re-quote its own arguments: wrappers that elevate externally
# (Start-Process and friends) regularly split arguments of paths containing
# spaces, which breaks installs for user names with spaces (komari#655).
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        Log-Error "Cannot elevate a script that was not run from a file. Save it as install.ps1 and run it again as Administrator."
        exit 1
    }
    Log-Warning "Administrator privileges are required. Requesting elevation, please accept the UAC prompt..."
    $hostExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $relaunchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (ConvertTo-CommandLineArg $PSCommandPath))
    foreach ($a in $args) {
        $relaunchArgs += ConvertTo-CommandLineArg ([string]$a)
    }
    try {
        $elevated = Start-Process -FilePath $hostExe -Verb RunAs -Wait -PassThru -ArgumentList ($relaunchArgs -join ' ')
        exit $elevated.ExitCode
    }
    catch {
        Log-Error "Elevation failed or was cancelled: $_"
        Log-Error "Please run this script as Administrator."
        exit 1
    }
}

# Prepare GitHub proxy display
if ($GitHubProxy -ne '') { $ProxyDisplay = $GitHubProxy } else { $ProxyDisplay = '(direct)' }

# Detect architecture early for constructing binary name
switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { $arch = 'amd64' }
    'ARM64' { $arch = 'arm64' }
    'x86' { $arch = '386' }
    Default { Log-Error "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE"; exit 1 }
}

# Ensure installation directory exists for the service manager and agent
Log-Step "Ensuring installation directory exists: $InstallDir"
New-Item -ItemType Directory -Path $InstallDir -Force -ErrorAction SilentlyContinue | Out-Null

# Service manager: nssm, stored locally as sm.exe and invoked by full path.
$SmExe = Join-Path $InstallDir "sm.exe"
if (-not (Test-Path $SmExe)) {
    $NssmCmd = Get-Command nssm -ErrorAction SilentlyContinue
    if ($NssmCmd) {
        Log-Info "nssm found in PATH at $($NssmCmd.Source); copying it to $SmExe"
        Copy-Item -Path $NssmCmd.Source -Destination $SmExe -Force
    }
    else {
        Log-Info "nssm not found. Downloading to $SmExe ..."
        $NssmVersion = "2.24"
        $NssmZipUrl = "https://nssm.cc/release/nssm-$NssmVersion.zip"
        $TempNssmZipPath = Join-Path $env:TEMP "nssm-$NssmVersion.zip"
        $TempExtractDir = Join-Path $env:TEMP "nssm_extract_temp"

        try {
            Log-Info "Downloading nssm from $NssmZipUrl..."
            Invoke-WebRequest -Uri $NssmZipUrl -OutFile $TempNssmZipPath -UseBasicParsing

            if (Test-Path $TempExtractDir) { Remove-Item -Recurse -Force $TempExtractDir }
            New-Item -ItemType Directory -Path $TempExtractDir -Force | Out-Null
            Expand-Archive -Path $TempNssmZipPath -DestinationPath $TempExtractDir -Force

            # 'win32' nssm works for both amd64 and arm64 PowerShell hosts.
            $NssmArchSubDir = Join-Path "nssm-$NssmVersion" "win32"
            $NssmSourceExePath = Join-Path (Join-Path $TempExtractDir $NssmArchSubDir) "nssm.exe"
            if (-not (Test-Path $NssmSourceExePath)) {
                $foundNssmFallback = Get-ChildItem -Path $TempExtractDir -Recurse -Filter "nssm.exe" |
                    Where-Object { $_.FullName -like "*$NssmArchSubDir\nssm.exe" } |
                    Select-Object -First 1
                if ($foundNssmFallback) {
                    Log-Warning "Found nssm.exe at $($foundNssmFallback.FullName) using fallback search."
                    $NssmSourceExePath = $foundNssmFallback.FullName
                }
                else {
                    Log-Error "nssm.exe not found in $TempExtractDir. Install nssm manually from https://nssm.cc and put it in PATH."
                    exit 1
                }
            }

            Copy-Item -Path $NssmSourceExePath -Destination $SmExe -Force
        }
        catch {
            Log-Error "Failed to download or prepare the service manager: $_"
            Log-Error "Install nssm manually from https://nssm.cc and ensure nssm.exe is in PATH."
            exit 1
        }
        finally {
            if (Test-Path $TempNssmZipPath) { Remove-Item $TempNssmZipPath -Force -ErrorAction SilentlyContinue }
            if (Test-Path $TempExtractDir) { Remove-Item $TempExtractDir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

# Downloaded executables carry Mark-of-the-Web and may be blocked from running.
# Unblock, clear attributes, retry once, then try a copy in %TEMP%; finally
# fall back to sc.exe service management.
$UseSc = $false
$SmVersionOutput = $null

function Reset-SmForExecution {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    try { Unblock-File -Path $Path -ErrorAction SilentlyContinue } catch { }
    try { (Get-Item -Path $Path -Force).Attributes = 'Normal' } catch { }
}

Reset-SmForExecution $SmExe
for ($attempt = 1; $attempt -le 2; $attempt++) {
    try {
        $SmVersionOutput = & $SmExe version 2>&1
        if ($SmVersionOutput) { break }
    }
    catch {
        if ($attempt -eq 1) { Start-Sleep -Milliseconds 500; Reset-SmForExecution $SmExe }
    }
}

if (-not $SmVersionOutput) {
    $SmTemp = Join-Path $env:TEMP "sm.exe"
    try {
        Copy-Item -Path $SmExe -Destination $SmTemp -Force
        Reset-SmForExecution $SmTemp
        $SmVersionOutput = & $SmTemp version 2>&1
        if ($SmVersionOutput) {
            $SmExe = $SmTemp
            Log-Info "Using service manager from $SmTemp"
        }
    }
    catch { }
}

if (-not $SmVersionOutput) {
    if ($NoScFallback) {
        Log-Error "sm.exe cannot be executed and --install-no-sc-fallback is set."
        Log-Error "Run: Unblock-File $SmExe"
        Log-Error "or install nssm manually (https://nssm.cc) and put nssm.exe in PATH, then retry."
        exit 1
    }
    Log-Warning "sm.exe cannot be executed (access denied or blocked). Falling back to sc.exe."
    $UseSc = $true
}
else {
    Log-Info "Service manager: $SmExe ($SmVersionOutput)"
}

# Legacy installation from older defaults (service "komari-agent").
# Only removed when endpoint + identity (token or auto-discovery key) match,
# so agents reporting to other panels on the same host are preserved.
function Get-TextIdentity {
    param([string]$Text)
    $Endpoint = [regex]::Match($Text, '(--endpoint|-e)[ =]"?([^"\s]+)"?').Groups[2].Value
    if (-not $Endpoint) { $Endpoint = [regex]::Match($Text, 'AGENT_ENDPOINT="?([^"\s]+)"?').Groups[1].Value }
    $Token = [regex]::Match($Text, '(--token|-t)[ =]"?([^"\s]+)"?').Groups[2].Value
    if (-not $Token) { $Token = [regex]::Match($Text, 'AGENT_TOKEN="?([^"\s]+)"?').Groups[1].Value }
    $AutoDiscovery = [regex]::Match($Text, '--auto-discovery[ =]"?([^"\s]+)"?').Groups[1].Value
    if (-not $AutoDiscovery) { $AutoDiscovery = [regex]::Match($Text, 'AGENT_AUTO_DISCOVERY_KEY="?([^"\s]+)"?').Groups[1].Value }
    [pscustomobject]@{ Endpoint = $Endpoint; Token = $Token; AutoDiscovery = $AutoDiscovery }
}

function Invoke-LegacyCleanup {
    param([string[]]$NewArgs)
    if ($InstallKeepLegacy) {
        Log-Info "Keeping legacy installations (--install-keep-legacy)."
        return
    }

    $LegacyService = "komari-agent"
    if (-not (Get-Service -Name $LegacyService -ErrorAction SilentlyContinue)) { return }

    $newText = (@($NewArgs) -join ' ')
    foreach ($name in @('AGENT_ENDPOINT', 'AGENT_TOKEN', 'AGENT_AUTO_DISCOVERY_KEY')) {
        $value = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ($value) { $newText = "$newText $name=$value" }
    }
    $newId = Get-TextIdentity $newText

    $legacyText = ""
    $legacyApp = ""
    $params = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$LegacyService\Parameters" -ErrorAction SilentlyContinue
    if ($params) {
        if ($params.AppParameters) { $legacyText = [string]$params.AppParameters }
        if ($params.Application) {
            $legacyApp = [string]$params.Application
            $legacyText = "$legacyText $legacyApp"
        }
        if ($params.AppEnvironmentExtra) { $legacyText = "$legacyText $([string]$params.AppEnvironmentExtra)" }
    }
    $legacyId = Get-TextIdentity $legacyText

    $verdict = "unknown"
    if ($newId.Endpoint -and $legacyId.Endpoint) {
        if ($newId.Endpoint.TrimEnd('/') -ne $legacyId.Endpoint.TrimEnd('/')) {
            $verdict = "mismatch"
        }
        elseif ($newId.Token -and $legacyId.Token) {
            if ($newId.Token -eq $legacyId.Token) { $verdict = "match" } else { $verdict = "mismatch" }
        }
        elseif ($newId.AutoDiscovery -and $legacyId.AutoDiscovery) {
            if ($newId.AutoDiscovery -eq $legacyId.AutoDiscovery) { $verdict = "match" } else { $verdict = "mismatch" }
        }
    }

    if ($verdict -ne "match") {
        if ($verdict -eq "mismatch") {
            Log-Warning "Legacy agent service '$LegacyService' found but it reports to $($legacyId.Endpoint); leaving it untouched."
        }
        else {
            Log-Warning "Legacy agent service '$LegacyService' found but its endpoint/token cannot be verified; leaving it untouched."
            Log-Info "Remove it manually if it is the old Komari Agent."
        }
        return
    }

    Log-Info "Removing legacy agent service '$LegacyService' ($($legacyId.Endpoint))..."
    if ($UseSc) {
        & sc.exe stop $LegacyService 2>&1 | Out-Null
        & sc.exe delete $LegacyService 2>&1 | Out-Null
    }
    else {
        & $SmExe stop $LegacyService 2>&1 | Out-Null
        & $SmExe remove $LegacyService confirm 2>&1 | Out-Null
    }
    if (-not (Get-Service -Name $LegacyService -ErrorAction SilentlyContinue)) {
        Log-Info "Legacy service removed."
    }
    if ($legacyApp -and $legacyApp -ne $AgentPath -and (Test-Path $legacyApp)) {
        Remove-Item -Path $legacyApp -Force -ErrorAction SilentlyContinue
        Log-Info "Removed legacy binary $legacyApp"
    }
}

Log-Step "Installation configuration:"
Log-Config "Service name: $ServiceName"
Log-Config "Install directory: $InstallDir"
Log-Config "GitHub proxy: $ProxyDisplay"
Log-Config "Agent arguments: $($KomariArgs -join ' ')"
if ($InstallVersion -ne "") {
    Log-Config "Specified agent version: $InstallVersion"
} else {
    Log-Config "Agent version: Latest"
}

# Paths
$BinaryName = "komari-agent-windows-$arch.exe"
$AgentPath = Join-Path $InstallDir "lh_kmr_ag.exe"

# Uninstall previous service and binary
function Uninstall-Previous {
    Log-Step "Checking for existing service..."
    if ($UseSc) {
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($svc) {
            Log-Info "Stopping and removing service $ServiceName (sc.exe)..."
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            & sc.exe delete $ServiceName 2>&1 | Out-Null
        }
    }
    else {
        # Check if service exists using nssm status, as Get-Service might not work for nssm services if not properly registered
        $serviceStatus = & $SmExe status $ServiceName 2>&1
        if ($serviceStatus -notmatch "SERVICE_STOPPED" -and $serviceStatus -notmatch "does not exist") {
            Log-Info "Stopping service $ServiceName..."
            & $SmExe stop $ServiceName 2>&1 | Out-Null
        }
        # Attempt to remove the service using nssm
        # We check if it exists first by trying to get its status.
        # nssm remove will succeed if the service exists, and fail otherwise.
        # We add confirm to avoid interactive prompts.
        $removeOutput = & $SmExe remove $ServiceName confirm 2>&1
        if ($LASTEXITCODE -eq 0) {
        }
        elseif ($removeOutput -match "Can't open service! (The specified service does not exist as an installed service.)" -or $removeOutput -match "No such service" -or $removeOutput -match "does not exist") {
            Log-Info "Service $ServiceName does not exist or was already removed."
        }
        else {
            # If nssm remove fails for other reasons, try sc.exe delete as a fallback for older installations
            $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if ($svc) {
                Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue
                sc.exe delete $ServiceName | Out-Null
            }
        }
    }

    if (Test-Path $AgentPath) {
        Log-Warning "Removing old binary..."
        Remove-Item $AgentPath -Force
    }
}
Invoke-LegacyCleanup -NewArgs $KomariArgs
Uninstall-Previous

function Get-LatestCustomVersion {
    param([Parameter(Mandatory = $true)][string]$AssetName)

    # 只认 <x.y.z>-custom.<i> 的正式构建；预览版 -custom-pre.<i> 不会被选中。
    $ApiUrl = "https://api.github.com/repos/$AgentRepo/releases?per_page=100"
    $ApiUrls = @($ApiUrl)
    if ($GitHubProxy -ne "") {
        $ApiUrls = @("$GitHubProxy/$ApiUrl", $ApiUrl)
    }

    for ($i = 0; $i -lt $ApiUrls.Count; $i++) {
        try {
            Log-Info "Fetching releases from GitHub API..."
            $releases = Invoke-RestMethod -Uri $ApiUrls[$i] -UseBasicParsing
        }
        catch {
            $releases = $null
        }

        if ($releases) {
            $candidates = foreach ($release in $releases) {
                if ($release.draft -or $release.prerelease) { continue }
                $m = [regex]::Match([string]$release.tag_name, '^(\d+)\.(\d+)\.(\d+)-custom\.(\d+)$')
                if (-not $m.Success) { continue }
                if (@($release.assets.name) -notcontains $AssetName) { continue }
                [pscustomobject]@{
                    Tag   = $release.tag_name
                    Major = [int]$m.Groups[1].Value
                    Minor = [int]$m.Groups[2].Value
                    Patch = [int]$m.Groups[3].Value
                    Index = [int]$m.Groups[4].Value
                }
            }
            if ($candidates) {
                return ($candidates | Sort-Object Major, Minor, Patch, Index | Select-Object -Last 1).Tag
            }
        }

        if ($i -lt ($ApiUrls.Count - 1)) {
            Log-Warning "Failed to resolve releases through GitHub proxy, retrying directly."
        }
    }

    # 回退：仓库没有 <x.y.z>-custom.<i> 形式时使用 GitHub 的 latest release
    # （例如 --install-repo komari-monitor/komari-agent 安装官方版本）。
    $LatestUrl = "https://api.github.com/repos/$AgentRepo/releases/latest"
    $LatestUrls = @($LatestUrl)
    if ($GitHubProxy -ne "") {
        $LatestUrls = @("$GitHubProxy/$LatestUrl", $LatestUrl)
    }
    foreach ($url in $LatestUrls) {
        try {
            $latest = Invoke-RestMethod -Uri $url -UseBasicParsing
            if ($latest.tag_name) { return [string]$latest.tag_name }
        }
        catch {
            continue
        }
    }

    throw "No release matching <x.y.z>-custom.<i> contains asset $AssetName."
}

function Get-LatestSnapshotVersion {
    param([Parameter(Mandatory = $true)][string]$AssetName)

    $ApiUrl = "https://api.github.com/repos/$AgentRepo/releases?per_page=100"
    $ApiUrls = @($ApiUrl)
    if ($GitHubProxy -ne "") {
        $ApiUrls = @("$GitHubProxy/$ApiUrl", $ApiUrl)
    }

    for ($i = 0; $i -lt $ApiUrls.Count; $i++) {
        try {
            Log-Info "Fetching snapshot releases from GitHub API..."
            $releases = Invoke-RestMethod -Uri $ApiUrls[$i] -UseBasicParsing
        }
        catch {
            $releases = $null
        }

        if ($releases) {
            $latestSnapshot = $releases |
            Where-Object {
                $_.draft -eq $false -and
                $_.prerelease -eq $true -and
                $_.tag_name -like "Snapshot-*" -and
                (@($_.assets.name) -contains $AssetName)
            } |
            Sort-Object -Property @{ Expression = { [datetime]$_.published_at }; Descending = $true }, @{ Expression = { $_.tag_name }; Descending = $true } |
            Select-Object -First 1

            if ($latestSnapshot) {
                return $latestSnapshot.tag_name
            }
        }

        if ($i -lt ($ApiUrls.Count - 1)) {
            Log-Warning "Failed to resolve snapshot releases through GitHub proxy, retrying directly."
        }
    }

    throw "No snapshot release contains asset $AssetName."
}

$versionToInstall = ""
if ($InstallVersion -ne "") {
    Log-Info "Attempting to install specified version: $InstallVersion"
    if ($InstallVersion -ieq "snapshot") {
        Log-Info "Resolving the latest snapshot version..."
        try {
            $versionToInstall = Get-LatestSnapshotVersion -AssetName $BinaryName
            Log-Success "Latest snapshot version fetched: $versionToInstall"
        }
        catch {
            Log-Error "Failed to resolve the latest snapshot version: $_"
            exit 1
        }
    }
    else {
        $versionToInstall = $InstallVersion
    }
}
else {
    Log-Step "Resolving the latest release from $AgentRepo ..."
    try {
        $versionToInstall = Get-LatestCustomVersion -AssetName $BinaryName
        Log-Success "Latest release fetched: $versionToInstall"
    }
    catch {
        Log-Error "Failed to resolve the latest release: $_"
        exit 1
    }
}
Log-Success "Installing Komari Agent version: $versionToInstall"

# Construct download URL
$BinaryName = "komari-agent-windows-$arch.exe"
$DownloadUrl = if ($GitHubProxy) { "$GitHubProxy/https://github.com/$AgentRepo/releases/download/$versionToInstall/$BinaryName" } else { "https://github.com/$AgentRepo/releases/download/$versionToInstall/$BinaryName" }

# Download and install
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Log-Info "URL: $DownloadUrl"
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $AgentPath -UseBasicParsing
}
catch {
    Log-Error "Download failed: $_"
    exit 1
}
Log-Success "Downloaded and saved to $AgentPath"

# Verify SHA-256 when the release provides it
if ($VerifyChecksum) {
    $ShaPath = "${AgentPath}.sha256"
    try {
        Invoke-WebRequest -Uri "${DownloadUrl}.sha256" -OutFile $ShaPath -UseBasicParsing
        $expected = ((Get-Content -Path $ShaPath -Raw) -split '\s+')[0].Trim().ToLowerInvariant()
        $actual = (Get-FileHash -Path $AgentPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expected -ne $actual) {
            Remove-Item -Path $AgentPath, $ShaPath -Force -ErrorAction SilentlyContinue
            Log-Error "Checksum mismatch: got $actual, want $expected"
            exit 1
        }
        Log-Success "Checksum OK"
    }
    catch {
        Log-Warning "Checksum file not available; verification skipped ($_)"
    }
    finally {
        Remove-Item -Path $ShaPath -Force -ErrorAction SilentlyContinue
    }
}
else {
    Log-Warning "Checksum verification disabled by --install-no-verify"
}

# Register and start service
$argString = $KomariArgs -join ' '
if ($UseSc) {
    Log-Step "Configuring Windows service with sc.exe..."
    $binPath = '"' + $AgentPath + '"'
    if ($argString) { $binPath = $binPath + ' ' + $argString }
    New-Service -Name $ServiceName -BinaryPathName $binPath -DisplayName "Komari Agent Service" -StartupType Automatic | Out-Null
    # Exit code 42 (self-update restart) is treated as a failure, so restart it.
    & sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/5000/restart/5000 2>&1 | Out-Null
    Start-Service -Name $ServiceName
    Log-Success "Service $ServiceName installed and started using sc.exe."
}
else {
    Log-Step "Configuring Windows service with nssm..."
    # The application path is passed WITHOUT literal quotes: PowerShell already
    # quotes native arguments containing spaces on the command line, while
    # embedded quotes made nssm store a broken Application path (komari-agent#118).
    & $SmExe install $ServiceName $AgentPath $argString
    # Set display name and startup type using nssm
    & $SmExe set $ServiceName DisplayName "Komari Agent Service"
    & $SmExe set $ServiceName Start SERVICE_AUTO_START
    & $SmExe set $ServiceName AppExit Default Restart
    & $SmExe set $ServiceName AppRestartDelay 5000
    # Start the service using nssm
    & $SmExe start $ServiceName
    Log-Success "Service $ServiceName installed and started using nssm."
}

# Hide the install directory (system + hidden) unless disabled.
if (-not $NoHide) {
    try {
        & attrib.exe +s +h $InstallDir | Out-Null
        Log-Success "Marked $InstallDir as a hidden system folder (attrib +s +h)."
    }
    catch {
        Log-Warning "Could not mark $InstallDir hidden: $_"
    }
}

Log-Success "Komari Agent installation completed!"
Log-Config "Service name: $ServiceName"
Log-Config "Arguments: $argString"
