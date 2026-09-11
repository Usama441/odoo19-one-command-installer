[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$mode = Read-Host "Environment [testing/production] (testing)"
if ([string]::IsNullOrWhiteSpace($mode)) { $mode = "testing" }
if ($mode -notin @("testing", "production")) { throw "Enter testing or production." }
if ($mode -eq "production") {
    Write-Warning "For a real production server, Ubuntu is recommended instead of Windows Desktop."
}

$communityPort = Read-Host "Community port (8069)"
if ([string]::IsNullOrWhiteSpace($communityPort)) { $communityPort = "8069" }
$enterprisePort = Read-Host "Enterprise port (8070)"
if ([string]::IsNullOrWhiteSpace($enterprisePort)) { $enterprisePort = "8070" }
[int]$parsedCommunityPort = 0
[int]$parsedEnterprisePort = 0
if ((-not [int]::TryParse($communityPort, [ref]$parsedCommunityPort)) -or
    (-not [int]::TryParse($enterprisePort, [ref]$parsedEnterprisePort)) -or
    ($parsedCommunityPort -lt 1) -or ($parsedCommunityPort -gt 65535) -or
    ($parsedEnterprisePort -lt 1) -or ($parsedEnterprisePort -gt 65535)) {
    throw "Ports must be numbers from 1 to 65535."
}
if ($parsedCommunityPort -eq $parsedEnterprisePort) {
    throw "Community and Enterprise must use different ports."
}
$communityPort = $parsedCommunityPort.ToString()
$enterprisePort = $parsedEnterprisePort.ToString()

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

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Docker Desktop is missing and winget is unavailable. Install Docker Desktop, restart Windows, then run this script again."
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
$existingVolumeNames = @(& docker volume ls --quiet)
if ($LASTEXITCODE -ne 0) { throw "Docker volumes could not be inspected." }
$communityDbVolumeExists = ($existingVolumeNames -contains "odoo19-dual_community-db")
$enterpriseDbVolumeExists = ($existingVolumeNames -contains "odoo19-dual_enterprise-db")
$pgAdminVolumeExists = ($existingVolumeNames -contains "odoo19-dual_pgadmin-data")
if ((-not (Test-Path -LiteralPath ".env" -PathType Leaf)) -and
    ($communityDbVolumeExists -or $enterpriseDbVolumeExists -or $pgAdminVolumeExists)) {
    throw "Existing installer data volumes were found, but .env is missing. Restore .env from backup; generated replacement credentials would not unlock the existing data."
}

@("config/community", "config/enterprise", "config/pgadmin", "addons/community", "addons/enterprise", "addons/enterprise-custom") |
    ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

$enterpriseSource = Read-Host "Path to licensed Odoo 19 Enterprise addons (blank reuses existing addons, or starts Community only)"
$startEnterprise = $false
if (-not [string]::IsNullOrWhiteSpace($enterpriseSource)) {
    if (-not (Test-Path -LiteralPath $enterpriseSource -PathType Container)) { throw "Enterprise addons directory was not found." }
    if ((Resolve-Path -LiteralPath $enterpriseSource).Path -ne (Resolve-Path -LiteralPath "addons/enterprise").Path) {
        Get-ChildItem -LiteralPath $enterpriseSource -Force | Copy-Item -Destination "addons/enterprise" -Recurse -Force
    }
    $startEnterprise = $true
} elseif (@(Get-ChildItem -LiteralPath "addons/enterprise" -Force | Where-Object { $_.Name -ne ".gitkeep" }).Count -gt 0) {
    Write-Host "Reusing the Enterprise addons already in addons/enterprise."
    $startEnterprise = $true
}

function New-RandomHex([int]$bytes = 24) {
    $buffer = New-Object byte[] $bytes
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
    return ($buffer | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Get-EnvValue([string]$key) {
    if (-not (Test-Path -LiteralPath ".env" -PathType Leaf)) { return $null }
    $prefix = "$key="
    $line = Get-Content -LiteralPath ".env" | Where-Object { $_.StartsWith($prefix) } | Select-Object -First 1
    if ($null -eq $line) { return $null }
    return $line.Substring($prefix.Length)
}

function Get-ConfigValue([string]$path, [string]$key) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $line = Get-Content -LiteralPath $path | Where-Object { $_ -match "^\s*$key\s*=" } | Select-Object -First 1
    if ($null -eq $line) { return $null }
    return (($line -split "=", 2)[1]).Trim()
}

$odooImage = "odoo:19.0-20260908"
$postgresImage = "postgres:15.19"
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
    if (-not [string]::IsNullOrWhiteSpace($savedOdooImage)) { $odooImage = $savedOdooImage }
    if (-not [string]::IsNullOrWhiteSpace($savedPostgresImage)) { $postgresImage = $savedPostgresImage }
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

if ($pgAdminEnabled) {
    $pgAdminChoice = Read-Host "Install/update and configure pgAdmin? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($pgAdminChoice)) { $pgAdminChoice = "y" }
} else {
    $pgAdminChoice = Read-Host "Install/update and configure pgAdmin? [y/N]"
    if ([string]::IsNullOrWhiteSpace($pgAdminChoice)) { $pgAdminChoice = "n" }
}
$normalizedPgAdminChoice = $pgAdminChoice.ToLowerInvariant()
if ($normalizedPgAdminChoice -in @("y", "yes")) {
    $pgAdminEnabled = $true
} elseif ($normalizedPgAdminChoice -in @("n", "no")) {
    $pgAdminEnabled = $false
} else {
    throw "Enter y or n for the pgAdmin choice."
}

if ($pgAdminEnabled) {
    if ($pgAdminCredentialsMissing) {
        throw "The existing pgAdmin data volume was found, but its saved login credentials are missing from .env. Restore .env from backup before enabling pgAdmin."
    }
    $pgAdminPortInput = Read-Host "pgAdmin port ($pgAdminPort)"
    if (-not [string]::IsNullOrWhiteSpace($pgAdminPortInput)) { $pgAdminPort = $pgAdminPortInput }
    [int]$parsedPgAdminPort = 0
    if ((-not [int]::TryParse($pgAdminPort, [ref]$parsedPgAdminPort)) -or
        ($parsedPgAdminPort -lt 1) -or ($parsedPgAdminPort -gt 65535)) {
        throw "The pgAdmin port must be a number from 1 to 65535."
    }
    if (($parsedPgAdminPort -eq $parsedCommunityPort) -or ($parsedPgAdminPort -eq $parsedEnterprisePort)) {
        throw "The pgAdmin port must be different from both Odoo ports."
    }
    $pgAdminPort = $parsedPgAdminPort.ToString()
    if ($pgAdminVolumeExists) {
        Write-Host "Reusing existing pgAdmin login email: $pgAdminEmail"
    } else {
        $pgAdminEmailInput = Read-Host "pgAdmin login email ($pgAdminEmail)"
        if (-not [string]::IsNullOrWhiteSpace($pgAdminEmailInput)) { $pgAdminEmail = $pgAdminEmailInput }
    }
    if ($pgAdminEmail -notmatch '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') {
        throw "Enter a valid pgAdmin login email address."
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

@"
ODOO_IMAGE=$odooImage
POSTGRES_IMAGE=$postgresImage
PGADMIN_IMAGE=$pgAdminImage
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
            Name = "Odoo 19 Community PostgreSQL"
            Group = "Odoo 19"
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
        Name = "Odoo 19 Enterprise PostgreSQL"
        Group = "Odoo 19"
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
Invoke-NativeChecked "docker" ($composePrefix + @("pull"))
$upArguments = $composePrefix + @("up", "-d", "--wait", "--wait-timeout", "300")
if (-not $startEnterprise) {
    $upArguments += @("db-community", "community")
    if ($pgAdminEnabled) { $upArguments += "pgadmin" }
}
Invoke-NativeChecked "docker" $upArguments
if (-not $pgAdminEnabled) {
    $pgAdminContainerId = (& docker compose --profile pgadmin ps -q pgadmin | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "The existing pgAdmin container state could not be inspected." }
    if (-not [string]::IsNullOrWhiteSpace($pgAdminContainerId)) {
        Invoke-NativeChecked "docker" @("compose", "--profile", "pgadmin", "stop", "pgadmin")
    }
}

$hostIp = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.InterfaceOperationalStatus -eq "Up" } |
    Select-Object -First 1 -ExpandProperty IPAddress)
if ([string]::IsNullOrWhiteSpace($hostIp)) { $hostIp = "127.0.0.1" }

$installationInfo = @(
    "Mode: $mode",
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
Get-Content "installation-info.txt"
Write-Host "Credentials are stored in $PSScriptRoot\installation-info.txt"
