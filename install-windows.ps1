[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Write-Section([string]$Number, [string]$Title) {
    Write-Host ""
    Write-Host "[$Number] $Title" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
}

function Read-YesNo([string]$Prompt, [bool]$DefaultYes = $false) {
    $suffix = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    while ($true) {
        $answer = Read-Host "$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $DefaultYes }
        switch ($answer.ToLowerInvariant()) {
            { $_ -in @("y", "yes") } { return $true }
            { $_ -in @("n", "no") } { return $false }
            default { Write-Warning "Please enter y for yes or n for no." }
        }
    }
}

function Read-MenuChoice([string]$Prompt, [string]$Default, [string[]]$Allowed) {
    while ($true) {
        $answer = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
        $answer = $answer.ToLowerInvariant()
        if ($Allowed -contains $answer) { return $answer }
        Write-Warning "Please choose one of the listed options."
    }
}

function Read-Port([string]$Prompt, [int]$Default, [int[]]$Forbidden = @()) {
    while ($true) {
        $answer = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default.ToString() }
        [int]$parsed = 0
        if (([int]::TryParse($answer, [ref]$parsed)) -and
            ($parsed -ge 1) -and ($parsed -le 65535)) {
            if ($Forbidden -notcontains $parsed) { return $parsed }
            Write-Warning "That port is already selected. Please choose a different port."
        } else {
            Write-Warning "Please enter a port number from 1 to 65535."
        }
    }
}

function Get-EnvValue([string]$key) {
    if (-not (Test-Path -LiteralPath ".env" -PathType Leaf)) { return $null }
    $prefix = "$key="
    $line = Get-Content -LiteralPath ".env" | Where-Object { $_.StartsWith($prefix) } | Select-Object -First 1
    if ($null -eq $line) { return $null }
    return $line.Substring($prefix.Length)
}

# Odoo releases offered by the installer, oldest first, each with a pinned image.
$supportedOdooVersions = @("19.0", "20.0")
$odooImagesByVersion = @{
    "19.0" = "odoo:19.0-20260908"
    "20.0" = "odoo:20.0-20260926"
}
# PostgreSQL plus the pgvector extension that Odoo's AI apps need for RAG.
# Odoo 20 requires PostgreSQL 16 or newer (it uses any_value()).
$postgresImagesByVersion = @{
    "19.0" = "pgvector/pgvector:0.8.7-pg15-trixie"
    "20.0" = "pgvector/pgvector:0.8.7-pg17-trixie"
}
function Get-PostgresImageMajor([string]$Image) {
    if ($Image -match '-pg(\d+)') { return [int]$Matches[1] }
    if ($Image -match '^postgres:(\d+)') { return [int]$Matches[1] }
    return $null
}
$minPostgresMajorByVersion = @{ "19.0" = 13; "20.0" = 16 }

# The version an existing .env was installed with. Files written before
# ODOO_VERSION was recorded fall back to the image tag, then to 19.0.
function Get-InstalledOdooVersion {
    if (-not (Test-Path -LiteralPath ".env" -PathType Leaf)) { return "" }
    $version = Get-EnvValue "ODOO_VERSION"
    if ([string]::IsNullOrWhiteSpace($version)) {
        $savedImage = Get-EnvValue "ODOO_IMAGE"
        if ($savedImage -match ':(\d+\.0)') { $version = $Matches[1] }
    }
    if ($odooImagesByVersion.ContainsKey("$version")) { return $version }
    return "19.0"
}

# Extracts enterprise-<version>.zip into enterprise-<version>\ beside the
# installer. A staging folder keeps an interrupted extraction from looking
# like a complete source folder.
function Expand-EnterpriseArchive([string]$Archive, [string]$Version) {
    $topFolder = "enterprise-$Version"
    $target = Join-Path $PSScriptRoot $topFolder
    $staging = Join-Path $PSScriptRoot (".enterprise-extract-" + [guid]::NewGuid().ToString("N"))
    Write-Host "Extracting $(Split-Path -Leaf $Archive). This may take several minutes..."
    try {
        Expand-Archive -LiteralPath $Archive -DestinationPath $staging -Force
        if (-not (Test-Path -LiteralPath (Join-Path $staging "$topFolder\web_enterprise\__manifest__.py") -PathType Leaf)) {
            throw "$(Split-Path -Leaf $Archive) does not contain $topFolder\web_enterprise."
        }
        Move-Item -LiteralPath (Join-Path $staging $topFolder) -Destination $target
    } finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    }
    Write-Host "Extracted Enterprise addons to $target"
    return $target
}

$supportedVersionsLabel = ($supportedOdooVersions | ForEach-Object { $_.Split(".")[0] }) -join " & "

Write-Host ""
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host "            Odoo $supportedVersionsLabel Guided Installer" -ForegroundColor Cyan
Write-Host "     Community | Enterprise | PostgreSQL | pgAdmin" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host "Follow the six guided steps. Press Enter to accept a recommended default."
Write-Host "You will review the complete Odoo plan before configuration or services change."

function Invoke-NativeChecked([string]$FilePath, [string[]]$ArgumentList) {
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

function Get-DockerDesktopExecutable {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidates += (Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates += (Join-Path $env:LOCALAPPDATA "Docker\Docker Desktop.exe")
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Enable-DockerDesktopAutoStart([string]$DockerDesktopPath) {
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    New-Item -Path $runKey -Force | Out-Null
    $quotedPath = '"' + $DockerDesktopPath + '"'
    New-ItemProperty -Path $runKey -Name "Docker Desktop" -Value $quotedPath -PropertyType String -Force | Out-Null
    Write-Host "Docker Desktop is configured to start automatically when this user signs in."
}

function Start-DockerDesktopAndWait([string]$DockerDesktopPath, [int]$TimeoutSeconds = 180) {
    Write-Host "Starting Docker Desktop and waiting for its engine..."
    Start-Process -FilePath $DockerDesktopPath | Out-Null
    for ($elapsed = 0; $elapsed -lt $TimeoutSeconds; $elapsed += 3) {
        Start-Sleep -Seconds 3
        & docker info *> $null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    return $false
}

Write-Section "1/6" "Check Docker Desktop"
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "Docker Desktop is required but is not installed."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Docker Desktop is missing and winget is unavailable. Install Docker Desktop, restart Windows, then run this script again."
    }
    if (-not (Read-YesNo "Install Docker Desktop now using winget?" $true)) {
        Write-Host "Installation cancelled. Install Docker Desktop before running this installer again."
        exit 0
    }
    Write-Host "Installing Docker Desktop..."
    Invoke-NativeChecked "winget" @("install", "--id", "Docker.DockerDesktop", "--exact", "--accept-package-agreements", "--accept-source-agreements")
    $installedDockerDesktop = Get-DockerDesktopExecutable
    if (-not [string]::IsNullOrWhiteSpace($installedDockerDesktop)) {
        Enable-DockerDesktopAutoStart $installedDockerDesktop
    }
    Write-Host "Docker Desktop was installed. Restart Windows, sign in, accept Docker's terms if prompted, then run this same command again."
    exit 0
}

$dockerDesktop = Get-DockerDesktopExecutable
if (-not [string]::IsNullOrWhiteSpace($dockerDesktop)) {
    Enable-DockerDesktopAutoStart $dockerDesktop
}
& docker info *> $null
if ($LASTEXITCODE -ne 0) {
    if ([string]::IsNullOrWhiteSpace($dockerDesktop) -or
        (-not (Start-DockerDesktopAndWait $dockerDesktop))) {
        throw "Docker Desktop could not be started. Restart Windows, open Docker Desktop, accept its terms if prompted, and rerun this installer."
    }
}
& docker compose version *> $null
if ($LASTEXITCODE -ne 0) {
    throw "The Docker Compose plugin is unavailable. Update or reinstall Docker Desktop, then rerun this installer."
}
$composeUpHelp = (& docker compose up --help 2>&1 | Out-String)
if (($LASTEXITCODE -ne 0) -or ($composeUpHelp -notmatch '--wait-timeout')) {
    throw "This installer requires a newer Docker Compose plugin with --wait support. Update Docker Desktop, then rerun it."
}
Write-Host "Docker Desktop and Docker Compose are ready." -ForegroundColor Green
$existingVolumeNames = @(& docker volume ls --quiet)
if ($LASTEXITCODE -ne 0) { throw "Docker volumes could not be inspected." }
$communityDbVolumeExists = ($existingVolumeNames -contains "odoo19-dual_community-db")
$enterpriseDbVolumeExists = ($existingVolumeNames -contains "odoo19-dual_enterprise-db")
$pgAdminVolumeExists = ($existingVolumeNames -contains "odoo19-dual_pgadmin-data")
if ((-not (Test-Path -LiteralPath ".env" -PathType Leaf)) -and
    ($communityDbVolumeExists -or $enterpriseDbVolumeExists -or $pgAdminVolumeExists)) {
    throw "Existing installer data volumes were found, but .env is missing. Restore .env from backup; generated replacement credentials would not unlock the existing data."
}

Write-Section "2/6" "Choose how Odoo should run"
$installedOdooVersion = Get-InstalledOdooVersion
$defaultOdooVersion = if ($installedOdooVersion) { $installedOdooVersion } else { $supportedOdooVersions[-1] }
Write-Host "Which Odoo version do you want to install?"
$versionChoices = @()
for ($index = 0; $index -lt $supportedOdooVersions.Count; $index++) {
    $version = $supportedOdooVersions[$index]
    $label = "Odoo $version"
    if ($version -eq $installedOdooVersion) { $label += " (installed)" }
    elseif ((-not $installedOdooVersion) -and ($version -eq $supportedOdooVersions[-1])) { $label += " (recommended)" }
    Write-Host "  $($index + 1)) $label"
    if ($version -eq $defaultOdooVersion) { $defaultVersionIndex = "$($index + 1)" }
    $versionChoices += @("$($index + 1)", $version, $version.Split(".")[0])
}
$versionChoice = Read-MenuChoice "Choose an Odoo version [$defaultVersionIndex]" $defaultVersionIndex $versionChoices
if ($versionChoice -match '^\d+$' -and [int]$versionChoice -le $supportedOdooVersions.Count) {
    $odooVersion = $supportedOdooVersions[[int]$versionChoice - 1]
} else {
    $odooVersion = "$($versionChoice.Split('.')[0]).0"
}
$odooMajorVersion = $odooVersion.Split(".")[0]
Write-Host "Odoo $odooVersion selected (image $($odooImagesByVersion[$odooVersion]))."

# Databases created by one major version cannot be opened by another, so a
# version switch is only allowed once the old databases are gone.
$odooVersionChanged = $installedOdooVersion -and ($installedOdooVersion -ne $odooVersion)
if ($odooVersionChanged) {
    if ($communityDbVolumeExists -or $enterpriseDbVolumeExists) {
        Write-Warning "This system already has Odoo $installedOdooVersion databases."
        Write-Host "Odoo $odooVersion cannot open them; a major-version upgrade needs Odoo's database migration."
        Write-Host "Back up the databases, remove the odoo19-dual database volumes,"
        Write-Host "then run the installer again and choose Odoo $odooVersion."
        exit 1
    }
    Write-Host "Switching the existing configuration from Odoo $installedOdooVersion to Odoo $odooVersion (no databases exist yet)."
}

Write-Host ""
Write-Host "Select a setup profile:"
Write-Host "  1) Testing (recommended for evaluation and development)"
Write-Host "  2) Production (enables two Odoo workers and memory limits)"
$modeChoice = Read-MenuChoice "Choose a profile [1]" "1" @("1", "2", "testing", "production")
switch ($modeChoice.ToLowerInvariant()) {
    { $_ -in @("1", "testing") } { $mode = "testing" }
    { $_ -in @("2", "production") } { $mode = "production" }
    default { throw "Choose 1 for testing or 2 for production." }
}
if ($mode -eq "production") {
    Write-Warning "For a real production server, Ubuntu is recommended instead of Windows Desktop."
}

# Host address the Odoo and pgAdmin web ports publish on: localhost only, or an
# address the user enters (0.0.0.0 for all interfaces). A saved choice is the
# default on reruns.
function Test-IPv4([string]$Address) {
    if ($Address -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $false }
    foreach ($octet in $Address.Split(".")) { if ([int]$octet -gt 255) { return $false } }
    return $true
}
$hostIpAddresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty IPAddress)
$defaultBindAddress = if ($mode -eq "testing") { "127.0.0.1" } else { "0.0.0.0" }
$savedBindAddress = Get-EnvValue "BIND_ADDRESS"
if ((-not [string]::IsNullOrWhiteSpace($savedBindAddress)) -and (Test-IPv4 $savedBindAddress)) {
    $defaultBindAddress = $savedBindAddress
}
$defaultBindChoice = if ($defaultBindAddress -eq "127.0.0.1") { "1" } else { "2" }
Write-Host ""
Write-Host "Network bind address:"
Write-Host "  1) localhost only (127.0.0.1) - reachable only from this computer"
Write-Host "  2) Enter an IP address - a computer IP, or 0.0.0.0 for all interfaces"
$bindChoice = Read-MenuChoice "Choose a bind address option [$defaultBindChoice]" $defaultBindChoice @("1", "2")
if ($bindChoice -eq "1") {
    $bindAddress = "127.0.0.1"
} else {
    if ($defaultBindAddress -eq "127.0.0.1") { $defaultBindAddress = "0.0.0.0" }
    Write-Host "IPv4 addresses on this computer: $($hostIpAddresses -join ', ')"
    while ($true) {
        $enteredAddress = Read-Host "Bind IP address [$defaultBindAddress]"
        if ([string]::IsNullOrWhiteSpace($enteredAddress)) { $enteredAddress = $defaultBindAddress }
        $enteredAddress = $enteredAddress.Trim()
        if (-not (Test-IPv4 $enteredAddress)) {
            Write-Warning "Please enter an IPv4 address such as 192.168.1.10 or 0.0.0.0."
            continue
        }
        # Docker can only publish on an address assigned to this computer.
        if (($enteredAddress -notin @("0.0.0.0", "127.0.0.1")) -and ($hostIpAddresses -notcontains $enteredAddress)) {
            Write-Warning "$enteredAddress is not assigned to this computer, so Docker could not publish on it."
            continue
        }
        $bindAddress = $enteredAddress
        break
    }
}
$bindAddressLabel = switch ($bindAddress) {
    "127.0.0.1" { "localhost only (127.0.0.1)" }
    "0.0.0.0" { "all host interfaces (0.0.0.0)" }
    default { "$bindAddress only" }
}

Write-Host ""
Write-Host "The Community web port is used in the browser URL."
[int]$parsedCommunityPort = Read-Port "Community web port" 8069
$communityPort = $parsedCommunityPort.ToString()
$enterprisePort = "8070"
[int]$parsedEnterprisePort = 8070

@("config/community", "config/enterprise", "config/pgadmin", "addons/community", "addons/enterprise", "addons/enterprise-custom") |
    ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

function Test-EnterpriseAddons([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or
        (-not (Test-Path -LiteralPath $Path -PathType Container))) { return $false }
    $manifest = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "__manifest__.py") -PathType Leaf } |
        Select-Object -First 1
    return ($null -ne $manifest)
}

function Read-EnterpriseSource([string]$SuggestedPath = "") {
    if ([string]::IsNullOrWhiteSpace($SuggestedPath)) {
        $SuggestedPath = Join-Path $PSScriptRoot "enterprise-$odooVersion"
    }
    while ($true) {
        Write-Host "Enterprise path detected from the current installer location:"
        Write-Host "  $SuggestedPath" -ForegroundColor Green
        $enteredPath = Read-Host "Enterprise addons folder [$SuggestedPath]"
        if ([string]::IsNullOrWhiteSpace($enteredPath)) { $enteredPath = $SuggestedPath }
        $enteredPath = $enteredPath.Trim().Trim('"')
        if (-not (Test-EnterpriseAddons $enteredPath)) {
            Write-Warning "That folder does not contain Odoo addon manifests. Please select the folder whose direct subfolders are Enterprise modules."
            continue
        }
        if (-not (Test-Path -LiteralPath (Join-Path $enteredPath "web_enterprise\__manifest__.py") -PathType Leaf)) {
            Write-Warning "The web_enterprise module was not found. Please select a complete Odoo $odooVersion Enterprise addon folder."
            continue
        }
        return (Resolve-Path -LiteralPath $enteredPath).Path
    }
}

Write-Section "3/6" "Choose Community or Enterprise"
$startEnterprise = $false
$enterpriseSource = ""
$installedEnterprisePath = Join-Path $PSScriptRoot "addons\enterprise"
$bundledEnterpriseSource = ""
$bundledEnterpriseArchive = ""
# The unversioned legacy folder only ever held Odoo 19 addons.
$enterpriseCandidateNames = @("enterprise-$odooVersion")
if ($odooVersion -eq "19.0") { $enterpriseCandidateNames += "enterprise" }
foreach ($candidateName in $enterpriseCandidateNames) {
    $candidatePath = Join-Path $PSScriptRoot $candidateName
    if (Test-EnterpriseAddons $candidatePath) {
        $bundledEnterpriseSource = $candidatePath
        break
    }
}
$enterpriseArchivePath = Join-Path $PSScriptRoot "enterprise-$odooVersion.zip"
if ([string]::IsNullOrWhiteSpace($bundledEnterpriseSource) -and
    (Test-Path -LiteralPath $enterpriseArchivePath -PathType Leaf) -and
    (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "enterprise-$odooVersion")))) {
    $bundledEnterpriseArchive = $enterpriseArchivePath
    $bundledEnterpriseSource = $enterpriseArchivePath
}
# The installed copy belongs to the version recorded in .env; legacy installs
# without .env only ever held Odoo 19 addons.
$installedEnterpriseVersion = if ($installedOdooVersion) { $installedOdooVersion } else { "19.0" }
$installedEnterpriseMatches = (Test-EnterpriseAddons $installedEnterprisePath) -and
    ($installedEnterpriseVersion -eq $odooVersion)

Write-Host "Odoo version: $odooVersion"
if ($installedEnterpriseMatches) {
    Write-Host "Existing Enterprise addons are already installed."
    Write-Host "  1) Reuse the installed Enterprise addons (recommended)"
    Write-Host "  2) Import or update Enterprise addons from another folder"
    Write-Host "  3) Start Community only"
    $editionChoice = Read-MenuChoice "Choose an edition option [1]" "1" @("1", "2", "3")
    switch ($editionChoice) {
        "1" { $startEnterprise = $true }
        "2" {
            $suggestedSource = if ($bundledEnterpriseArchive) { "" } else { $bundledEnterpriseSource }
            $enterpriseSource = Read-EnterpriseSource $suggestedSource
            $startEnterprise = $true
        }
        "3" { $startEnterprise = $false }
        default { throw "Choose 1, 2, or 3." }
    }
} elseif (-not [string]::IsNullOrWhiteSpace($bundledEnterpriseSource)) {
    Write-Host "Enterprise addons were detected automatically:"
    Write-Host "  $bundledEnterpriseSource" -ForegroundColor Green
    Write-Host "  1) Install Community + Enterprise using this folder (recommended)"
    Write-Host "  2) Select a different Enterprise folder"
    Write-Host "  3) Install Community only"
    $editionChoice = Read-MenuChoice "Choose an edition option [1]" "1" @("1", "2", "3")
    switch ($editionChoice) {
        "1" {
            if ($bundledEnterpriseArchive) {
                $bundledEnterpriseSource = Expand-EnterpriseArchive $bundledEnterpriseArchive $odooVersion
            }
            $enterpriseSource = $bundledEnterpriseSource
            $startEnterprise = $true
        }
        "2" { $enterpriseSource = Read-EnterpriseSource; $startEnterprise = $true }
        "3" { $startEnterprise = $false }
        default { throw "Choose 1, 2, or 3." }
    }
} else {
    Write-Host "Community is free and requires no additional files."
    Write-Host "Enterprise requires your licensed Odoo $odooVersion Enterprise addon folder."
    Write-Host "  1) Install Community only (recommended)"
    Write-Host "  2) Install Community + Enterprise"
    $editionChoice = Read-MenuChoice "Choose an edition option [1]" "1" @("1", "2")
    switch ($editionChoice) {
        "1" { $startEnterprise = $false }
        "2" { $enterpriseSource = Read-EnterpriseSource; $startEnterprise = $true }
        default { throw "Choose 1 or 2." }
    }
}

if ($startEnterprise) {
    $parsedEnterprisePort = Read-Port "Enterprise web port" 8070 @($parsedCommunityPort)
    $enterprisePort = $parsedEnterprisePort.ToString()
}

function New-RandomHex([int]$bytes = 24) {
    $buffer = New-Object byte[] $bytes
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
    return ($buffer | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Get-ConfigValue([string]$path, [string]$key) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $line = Get-Content -LiteralPath $path | Where-Object { $_ -match "^\s*$key\s*=" } | Select-Object -First 1
    if ($null -eq $line) { return $null }
    return (($line -split "=", 2)[1]).Trim()
}

$odooImage = $odooImagesByVersion[$odooVersion]
$postgresImage = $postgresImagesByVersion[$odooVersion]
$pgAdminImage = "dpage/pgadmin4:9.17"
$pgAdminEnabled = $false
$pgAdminPort = "5050"
$pgAdminEmail = "admin@example.com"
$pgAdminCredentialsMissing = $false
if (Test-Path -LiteralPath ".env" -PathType Leaf) {
    $communityDbPassword = Get-EnvValue "COMMUNITY_DB_PASSWORD"
    $enterpriseDbPassword = Get-EnvValue "ENTERPRISE_DB_PASSWORD"
    if ([string]::IsNullOrWhiteSpace($communityDbPassword) -or [string]::IsNullOrWhiteSpace($enterpriseDbPassword)) {
        throw "The existing .env file is missing a database password. It was not overwritten because existing Docker volumes may still depend on it."
    }
    $communityAdminPassword = Get-EnvValue "COMMUNITY_ADMIN_PASSWORD"
    $enterpriseAdminPassword = Get-EnvValue "ENTERPRISE_ADMIN_PASSWORD"
    if ([string]::IsNullOrWhiteSpace($communityAdminPassword)) { $communityAdminPassword = Get-ConfigValue "config/community/odoo.conf" "admin_passwd" }
    if ([string]::IsNullOrWhiteSpace($enterpriseAdminPassword)) { $enterpriseAdminPassword = Get-ConfigValue "config/enterprise/odoo.conf" "admin_passwd" }
    if ([string]::IsNullOrWhiteSpace($communityAdminPassword)) { $communityAdminPassword = New-RandomHex }
    if ([string]::IsNullOrWhiteSpace($enterpriseAdminPassword)) { $enterpriseAdminPassword = New-RandomHex }
    $savedOdooImage = Get-EnvValue "ODOO_IMAGE"
    $savedPostgresImage = Get-EnvValue "POSTGRES_IMAGE"
    # A saved image only applies to the version it was installed with.
    if ((-not [string]::IsNullOrWhiteSpace($savedOdooImage)) -and (-not $odooVersionChanged)) { $odooImage = $savedOdooImage }
    # A saved PostgreSQL image is kept only when it is new enough for the
    # selected Odoo version; existing volumes cannot move to a newer major.
    if (-not [string]::IsNullOrWhiteSpace($savedPostgresImage)) {
        $savedPostgresMajor = Get-PostgresImageMajor $savedPostgresImage
        if (($null -ne $savedPostgresMajor) -and ($savedPostgresMajor -eq (Get-PostgresImageMajor $postgresImage))) {
            # Same major version: the pinned image reads the existing data
            # unchanged and adds pgvector.
            if ($savedPostgresImage -ne $postgresImage) {
                Write-Host "Switching PostgreSQL from $savedPostgresImage to $postgresImage (same PostgreSQL $savedPostgresMajor data, adds the pgvector extension)."
            }
        } elseif (($null -ne $savedPostgresMajor) -and ($savedPostgresMajor -lt $minPostgresMajorByVersion[$odooVersion])) {
            if ($communityDbVolumeExists -or $enterpriseDbVolumeExists) {
                Write-Warning "Odoo $odooVersion needs PostgreSQL $($minPostgresMajorByVersion[$odooVersion]) or newer, but this installation uses $savedPostgresImage."
                Write-Host "The existing database volumes were created by PostgreSQL $savedPostgresMajor and cannot be opened by a newer major version."
                Write-Host "Back up any databases you need, remove the odoo19-dual database volumes, then run the installer again."
                exit 1
            }
            Write-Host "Upgrading PostgreSQL from $savedPostgresImage to $postgresImage for Odoo $odooVersion (no databases exist yet)."
        } else {
            $postgresImage = $savedPostgresImage
        }
    }
    $savedPgAdminImage = Get-EnvValue "PGADMIN_IMAGE"
    $savedPgAdminEnabled = Get-EnvValue "PGADMIN_ENABLED"
    $savedPgAdminPort = Get-EnvValue "PGADMIN_PORT"
    $savedPgAdminEmail = Get-EnvValue "PGADMIN_EMAIL"
    $savedPgAdminPassword = Get-EnvValue "PGADMIN_PASSWORD"
    if (-not [string]::IsNullOrWhiteSpace($savedPgAdminImage)) { $pgAdminImage = $savedPgAdminImage }
    if ($savedPgAdminEnabled -eq "true") { $pgAdminEnabled = $true }
    if (-not [string]::IsNullOrWhiteSpace($savedPgAdminPort)) { $pgAdminPort = $savedPgAdminPort }
    if (-not [string]::IsNullOrWhiteSpace($savedPgAdminEmail)) { $pgAdminEmail = $savedPgAdminEmail }
    if ($pgAdminVolumeExists -and
        ([string]::IsNullOrWhiteSpace($savedPgAdminEmail) -or [string]::IsNullOrWhiteSpace($savedPgAdminPassword))) {
        $pgAdminCredentialsMissing = $true
    }
    if ([string]::IsNullOrWhiteSpace($savedPgAdminPassword)) { $pgAdminPassword = New-RandomHex } else { $pgAdminPassword = $savedPgAdminPassword }
    Write-Host "Existing installation detected; database and Odoo master passwords will be reused."
} else {
    $communityDbPassword = New-RandomHex
    $enterpriseDbPassword = New-RandomHex
    $communityAdminPassword = New-RandomHex
    $enterpriseAdminPassword = New-RandomHex
    $pgAdminPassword = New-RandomHex
}

Write-Section "4/6" "Choose optional pgAdmin"
Write-Host "pgAdmin is an optional browser-based database manager."
Write-Host "Odoo works normally without it."
if ($pgAdminEnabled) {
    $pgAdminEnabled = Read-YesNo "Keep pgAdmin enabled?" $true
} else {
    $pgAdminEnabled = Read-YesNo "Add pgAdmin to this installation?" $false
}

if ($pgAdminEnabled) {
    if ($pgAdminCredentialsMissing) {
        throw "The existing pgAdmin data volume was found, but its saved login credentials are missing from .env. Restore .env from backup before enabling pgAdmin."
    }
    $forbiddenPorts = @($parsedCommunityPort)
    if ($startEnterprise) { $forbiddenPorts += $parsedEnterprisePort }
    [int]$pgAdminDefaultPort = 5050
    if ((-not [int]::TryParse($pgAdminPort, [ref]$pgAdminDefaultPort)) -or
        ($pgAdminDefaultPort -lt 1) -or ($pgAdminDefaultPort -gt 65535)) {
        $pgAdminDefaultPort = 5050
    }
    [int]$parsedPgAdminPort = Read-Port "pgAdmin web port" $pgAdminDefaultPort $forbiddenPorts
    $pgAdminPort = $parsedPgAdminPort.ToString()
    if ($pgAdminVolumeExists) {
        Write-Host "Reusing existing pgAdmin login email: $pgAdminEmail"
    } else {
        Write-Host "This email is used only to sign in to the local pgAdmin web page."
        while ($true) {
            $pgAdminEmailInput = Read-Host "pgAdmin login email [$pgAdminEmail]"
            if (-not [string]::IsNullOrWhiteSpace($pgAdminEmailInput)) { $pgAdminEmail = $pgAdminEmailInput }
            if ($pgAdminEmail -match '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') { break }
            Write-Warning "Please enter a valid email address, for example admin@example.com."
        }
    }
    if ($pgAdminEmail -notmatch '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') {
        throw "The saved pgAdmin login email is invalid. Correct PGADMIN_EMAIL in .env, then rerun the installer."
    }
}
[int]$unusedPgAdminPort = 0
if ((-not [int]::TryParse($pgAdminPort, [ref]$unusedPgAdminPort)) -or
    ($unusedPgAdminPort -lt 1) -or ($unusedPgAdminPort -gt 65535)) { $pgAdminPort = "5050" }
if ($pgAdminEmail -notmatch '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') { $pgAdminEmail = "admin@example.com" }
if (($odooImage -notmatch '^[A-Za-z0-9][A-Za-z0-9._/@:-]+$') -or
    ($postgresImage -notmatch '^[A-Za-z0-9][A-Za-z0-9._/@:-]+$') -or
    ($pgAdminImage -notmatch '^[A-Za-z0-9][A-Za-z0-9._/@:-]+$')) {
    throw "An image reference in .env is invalid."
}

Write-Section "5/6" "Review the installation plan"
Write-Host ("  {0,-24} {1}" -f "Odoo version", "$odooVersion ($odooImage)")
Write-Host ("  {0,-24} {1}" -f "Profile", $mode)
Write-Host ("  {0,-24} {1}" -f "Network exposure", $bindAddressLabel)
Write-Host ("  {0,-24} {1}" -f "Community", "enabled on port $communityPort")
if ($startEnterprise) {
    Write-Host ("  {0,-24} {1}" -f "Enterprise", "enabled on port $enterprisePort")
    if ([string]::IsNullOrWhiteSpace($enterpriseSource)) {
        Write-Host ("  {0,-24} {1}" -f "Enterprise addons", "reuse installed addons")
    } else {
        Write-Host ("  {0,-24} {1}" -f "Enterprise addons", "import from $enterpriseSource")
    }
} else {
    Write-Host ("  {0,-24} {1}" -f "Enterprise", "not selected")
}
if ($pgAdminEnabled) {
    Write-Host ("  {0,-24} {1}" -f "pgAdmin", "enabled on port $pgAdminPort")
    Write-Host ("  {0,-24} {1}" -f "pgAdmin login", $pgAdminEmail)
} else {
    Write-Host ("  {0,-24} {1}" -f "pgAdmin", "not selected")
}
Write-Host ("  {0,-24} {1}" -f "Automatic restart", "enabled after Windows sign-in")
Write-Host ""
if (-not (Read-YesNo "Start this installation now?" $true)) {
    Write-Host "Installation cancelled. No Odoo configuration or Enterprise addons were changed."
    exit 0
}

if (-not [string]::IsNullOrWhiteSpace($enterpriseSource) -and
    ((Resolve-Path -LiteralPath $enterpriseSource).Path -ne (Resolve-Path -LiteralPath $installedEnterprisePath).Path)) {
    # Addons left from a different Odoo version must not mix with the new ones.
    if ((-not $installedEnterpriseMatches) -and (Test-EnterpriseAddons $installedEnterprisePath)) {
        Write-Host "Removing the installed Odoo $installedEnterpriseVersion Enterprise addons copy..."
        Get-ChildItem -LiteralPath $installedEnterprisePath -Force |
            Where-Object { $_.Name -ne ".gitkeep" } |
            Remove-Item -Recurse -Force
    }
    Write-Host "Copying Enterprise addons into this installation. This may take a moment..."
    Get-ChildItem -LiteralPath $enterpriseSource -Force |
        Copy-Item -Destination $installedEnterprisePath -Recurse -Force
}

Write-Host "Generating private configuration and credentials..."

@"
ODOO_VERSION=$odooVersion
ODOO_IMAGE=$odooImage
POSTGRES_IMAGE=$postgresImage
PGADMIN_IMAGE=$pgAdminImage
BIND_ADDRESS=$bindAddress
COMMUNITY_PORT=$communityPort
ENTERPRISE_PORT=$enterprisePort
COMMUNITY_DB_PASSWORD=$communityDbPassword
ENTERPRISE_DB_PASSWORD=$enterpriseDbPassword
COMMUNITY_ADMIN_PASSWORD=$communityAdminPassword
ENTERPRISE_ADMIN_PASSWORD=$enterpriseAdminPassword
PGADMIN_ENABLED=$($pgAdminEnabled.ToString().ToLowerInvariant())
PGADMIN_PORT=$pgAdminPort
PGADMIN_EMAIL=$pgAdminEmail
PGADMIN_PASSWORD=$pgAdminPassword
"@ | Set-Content -Encoding ascii ".env"

$workers = 0
$hard = 0
$soft = 0
if ($mode -eq "production") { $workers = 2; $hard = 2684354560; $soft = 2147483648 }

function Write-OdooConfig($path, $dbHost, $dbPassword, $adminPassword, $addonsPath) {
@"
[options]
admin_passwd = $adminPassword
db_host = $dbHost
db_port = 5432
db_user = odoo
db_password = $dbPassword
addons_path = $addonsPath
data_dir = /var/lib/odoo
http_interface = 0.0.0.0
list_db = True
proxy_mode = False
workers = $workers
max_cron_threads = 1
limit_memory_hard = $hard
limit_memory_soft = $soft
"@ | Set-Content -Encoding ascii $path
}
Write-OdooConfig "config/community/odoo.conf" "db-community" $communityDbPassword $communityAdminPassword "/usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons"
Write-OdooConfig "config/enterprise/odoo.conf" "db-enterprise" $enterpriseDbPassword $enterpriseAdminPassword "/mnt/enterprise-addons,/usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons"

$servers = [ordered]@{
    Servers = [ordered]@{
        "1" = [ordered]@{
            Name = "Odoo $odooMajorVersion Community PostgreSQL"
            Group = "Odoo $odooMajorVersion"
            Host = "db-community"
            Port = 5432
            MaintenanceDB = "postgres"
            Username = "odoo"
            SSLMode = "prefer"
        }
    }
}
if ($startEnterprise) {
    $servers.Servers["2"] = [ordered]@{
        Name = "Odoo $odooMajorVersion Enterprise PostgreSQL"
        Group = "Odoo $odooMajorVersion"
        Host = "db-enterprise"
        Port = 5432
        MaintenanceDB = "postgres"
        Username = "odoo"
        SSLMode = "prefer"
    }
}
$servers | ConvertTo-Json -Depth 5 | Set-Content -Encoding ascii "config/pgadmin/servers.json"
$pgpassContent = "db-community:5432:*:odoo:$communityDbPassword`n" +
    "db-enterprise:5432:*:odoo:$enterpriseDbPassword`n"
[IO.File]::WriteAllText(
    (Join-Path $PSScriptRoot "config/pgadmin/pgpass"),
    $pgpassContent,
    [Text.Encoding]::ASCII
)

$composePrefix = @("compose")
if ($pgAdminEnabled) { $composePrefix += @("--profile", "pgadmin") }
Write-Host "Downloading the required Docker images..."
Invoke-NativeChecked "docker" ($composePrefix + @("pull"))
if (-not $startEnterprise) {
    $enterpriseContainerId = (& docker compose ps -q enterprise | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "The existing Enterprise application state could not be inspected." }
    $enterpriseDbContainerId = (& docker compose ps -q db-enterprise | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "The existing Enterprise database state could not be inspected." }
    if ((-not [string]::IsNullOrWhiteSpace($enterpriseContainerId)) -or
        (-not [string]::IsNullOrWhiteSpace($enterpriseDbContainerId))) {
        Write-Host "Stopping the previously running Enterprise services because Community-only was selected..."
        Invoke-NativeChecked "docker" @("compose", "stop", "enterprise", "db-enterprise")
    }
}
if (-not $pgAdminEnabled) {
    $pgAdminContainerId = (& docker compose --profile pgadmin ps -q pgadmin | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "The existing pgAdmin container state could not be inspected." }
    if (-not [string]::IsNullOrWhiteSpace($pgAdminContainerId)) {
        Write-Host "Stopping pgAdmin because it was not selected..."
        Invoke-NativeChecked "docker" @("compose", "--profile", "pgadmin", "stop", "pgadmin")
    }
}
$upArguments = $composePrefix + @("up", "-d", "--wait", "--wait-timeout", "300")
if (-not $startEnterprise) {
    $upArguments += @("db-community", "community")
    if ($pgAdminEnabled) { $upArguments += "pgadmin" }
}
Invoke-NativeChecked "docker" $upArguments

$hostIp = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.InterfaceOperationalStatus -eq "Up" } |
    Select-Object -First 1 -ExpandProperty IPAddress)
if ([string]::IsNullOrWhiteSpace($hostIp)) { $hostIp = "127.0.0.1" }
if ($bindAddress -eq "127.0.0.1") { $hostIp = "localhost" }
elseif ($bindAddress -ne "0.0.0.0") { $hostIp = $bindAddress }

$installationInfo = @(
    "Odoo version: $odooVersion",
    "Mode: $mode",
    "Network binding: $bindAddress",
    "Automatic startup: enabled after Windows sign-in (containers restart unless manually stopped)",
    "Community: http://${hostIp}:$communityPort",
    "Community Odoo master password: $communityAdminPassword"
)
if ($startEnterprise) {
    $installationInfo += @(
        "Enterprise: http://${hostIp}:$enterprisePort",
        "Enterprise Odoo master password: $enterpriseAdminPassword"
    )
} else {
    $installationInfo += "Enterprise: not started"
}
if ($pgAdminEnabled) {
    $installationInfo += @(
        "pgAdmin: http://${hostIp}:$pgAdminPort",
        "pgAdmin login email: $pgAdminEmail",
        "pgAdmin login password: $pgAdminPassword"
    )
} else {
    $installationInfo += "pgAdmin: not started"
}
$installationInfo += @(
    "Odoo image: $odooImage",
    "PostgreSQL image: $postgresImage"
)
if ($pgAdminEnabled) { $installationInfo += "pgAdmin image: $pgAdminImage" }
$installationInfo | Set-Content -Encoding utf8 "installation-info.txt"
Write-Section "6/6" "Installation complete"
Get-Content "installation-info.txt"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1) Open the Community URL above in your browser."
Write-Host "  2) Use its Odoo master password on the database creation page."
if ($startEnterprise) {
    Write-Host "  3) Open the Enterprise URL and use its separate master password."
}
if ($pgAdminEnabled) {
    Write-Host "  - Sign in to pgAdmin with the email and password shown above."
}
Write-Host "Credentials are stored in $PSScriptRoot\installation-info.txt"
