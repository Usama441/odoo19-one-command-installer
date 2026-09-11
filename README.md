# Odoo 19 dual-edition one-command installer

Guided installers for Ubuntu and Windows that run Odoo 19 Community, optional
Odoo 19 Enterprise, and optional pgAdmin as isolated Docker services.

![Odoo 19 installer flow](docs/images/installer-flow.svg)

## What gets installed

| Component | When it starts | Default address |
|---|---|---|
| Odoo 19 Community + PostgreSQL | Always | `http://SERVER-IP:8069` |
| Odoo 19 Enterprise + PostgreSQL | When licensed Enterprise addons are supplied or already present | `http://SERVER-IP:8070` |
| pgAdmin 4 web application | When the user answers `y` | `http://SERVER-IP:5050` |

Community and Enterprise use separate databases, passwords, filestores, ports,
configuration files, and custom-addon folders. pgAdmin can manage both databases
without exposing PostgreSQL ports to the host network.

## Requirements

- Ubuntu 22.04 or 24.04 with a normal sudo-enabled user; or Windows 10/11 with
  PowerShell.
- An internet connection for installing Docker when needed and pulling images.
- A valid Odoo Enterprise subscription and a local copy of the Odoo 19
  Enterprise addons if Enterprise will be used.
- Enough free disk space for Docker images, databases, filestores, and backups.

Do not run the Ubuntu installer as `root`. Run it as your normal user and enter
your sudo password when Ubuntu requests it.

## Run the installer

### Ubuntu 22.04 / 24.04

```bash
chmod +x install-ubuntu.sh
./install-ubuntu.sh
```

If Docker is missing, the script installs Docker Engine and the Compose plugin
from Docker's official Ubuntu repository after receiving user approval. Before
the Odoo questions, it can update the APT package lists and upgrade currently
installed Ubuntu packages, then displays which prerequisites are installed or
missing. Missing items can be installed in bulk, approved one by one, or left
unchanged by cancelling. This package upgrade does not perform a major Ubuntu
release upgrade such as 22.04 to 24.04.

After Docker is available, the script explicitly enables and starts
`docker.service`, so Docker starts automatically during future system boots. It
may use `sudo docker` for the current run; log out and back in later if you want
the new Docker group membership to take effect.

### Windows 10 / 11

Open PowerShell in this repository folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-windows.ps1
```

If Docker Desktop is missing, the script asks permission, installs it through
`winget`, and then stops. It also configures Docker Desktop to launch whenever
the current Windows user signs in. Restart Windows, sign in, accept Docker's
terms if prompted, and run the same installer command again. On later runs, the
installer starts Docker Desktop itself and waits up to three minutes when its
engine is not already ready.

## Questions the installer asks

Press Enter to accept the value shown in square brackets.
If a user mistypes a choice, port, Enterprise folder, email, or yes/no answer,
the installer explains the expected value and asks the same question again.

On Windows, `Install Docker Desktop now using winget? [Y/n]` appears first only
when Docker is missing. Answering `n` cancels cleanly; answering `y` installs
Docker Desktop and explains the required restart before Odoo setup continues.

### Ubuntu preparation questions

These appear before the Odoo configuration questions:

| Order | Prompt | Effect |
|---:|---|---|
| 1 | `Refresh package lists and upgrade installed Ubuntu packages now? [y/N]` | `y` runs `apt-get update` followed by a non-interactive `apt-get upgrade`. It does not change the Ubuntu release. |
| 2 | `Continue this installation before rebooting? [y/N]` | Shown only when Ubuntu reports that upgraded packages require a reboot. The safe default stops so the user can reboot and rerun. |
| 3 | `Choose an option [1]` | Shown only when prerequisites are missing. `1` installs everything missing, `2` asks permission for each item, and `3` cancels. |
| 4 | Individual package questions | Shown only in one-by-one mode for CA certificates, curl, OpenSSL, Docker Engine, and Docker Compose when each item is missing. |

Before prompt 3, the installer prints a status report similar to:

```text
Ubuntu prerequisite status
  CA certificates              INSTALLED
  curl                         INSTALLED
  OpenSSL                      INSTALLED
  Docker Engine / CLI          MISSING
  Docker Compose plugin        MISSING
  Docker system service        NOT INSTALLED
```

OpenSSL, Docker Engine, and Docker Compose are required to continue. If any of
them remain missing after the user's choices, the installer stops and explains
how to rerun it.

### Odoo service questions

| Order | Prompt | What it controls |
|---:|---|---|
| 1 | `Choose a profile [1]` | `1` selects testing. `2` selects production with two workers and basic memory limits. |
| 2 | `Community web port [8069]` | Browser port for Odoo Community. |
| 3 | `Choose an edition option [1]` | Selects Community only, detected/existing Enterprise addons, or another Enterprise folder. The recommended choice adapts to what the installer detects. |
| 4 | `Enterprise addons folder` | Asked only when Enterprise was selected but no detected folder is being used. The folder is validated before it is copied. |
| 5 | `Enterprise web port [8070]` | Asked only when Enterprise will start. It must differ from the Community port. |
| 6 | `Add pgAdmin to this installation? [y/N]` | Enables the optional pgAdmin web application. A rerun with pgAdmin enabled instead asks whether to keep it enabled. |
| 7 | `pgAdmin web port [5050]` | Asked only when pgAdmin is enabled. It must differ from the enabled Odoo ports. |
| 8 | `pgAdmin login email [admin@example.com]` | Asked only on the first pgAdmin setup. Existing pgAdmin data reuses the saved email. |
| 9 | `Start this installation now? [Y/n]` | Shows after a complete plan summary and provides a final chance to cancel before configuration or Enterprise addons are changed. |

The PostgreSQL passwords, Odoo master passwords, and pgAdmin login password are
never requested. The installer generates strong random values automatically.

Example Community + pgAdmin installation when no Enterprise folder is detected:

```text
Refresh package lists and upgrade installed Ubuntu packages now? [y/N]: n
Choose an option [1]:
Choose a profile [1]:
Community web port [8069]:
Choose an edition option [1]: 1
Add pgAdmin to this installation? [y/N]: y
pgAdmin web port [5050]:
pgAdmin login email [admin@example.com]: admin@example.com
Start this installation now? [Y/n]:
```

When `enterprise-19.0/` is beside the installer, both scripts detect it and show
its full path. The user normally presses Enter to accept it instead of typing a
folder path. On a rerun, selecting Community only stops previously running
Enterprise containers, and disabling pgAdmin stops its existing container.

## Complete execution flow

1. **Validate the platform.** Ubuntu checks for Ubuntu 22.04/24.04 and refuses
   to run as root. Windows starts through PowerShell from the project folder.
2. **Offer Ubuntu maintenance.** The Ubuntu script asks whether to refresh APT
   metadata and upgrade installed packages. If a reboot becomes necessary, the
   user can stop safely and continue after restarting the machine.
3. **Audit and prepare prerequisites.** Ubuntu displays CA certificates, curl,
   OpenSSL, Docker Engine, Compose, and Docker service status. Missing items are
   installed only after bulk or per-item approval. Windows checks Docker Desktop,
   can install it through `winget`, and configures it to start at user sign-in.
4. **Guide the user through choices.** Numbered menus select testing/production,
   Community/Enterprise, optional pgAdmin, and only the ports that are relevant.
   A recent Compose version with `--wait` support is required.
5. **Protect existing data.** The script detects installer-created Docker
   volumes. If data volumes exist but `.env` is missing, it stops instead of
   creating new passwords that cannot access the existing data.
6. **Prepare Enterprise.** The installer first detects existing copied addons or
   `enterprise-19.0/` beside the script. Manual path entry is requested only when
   the user selects another folder. The folder must contain addon manifests and
   `web_enterprise` before it is copied into `addons/enterprise`.
7. **Configure pgAdmin.** If selected, the script prepares pgAdmin login data,
   a server-definition file, and a protected PostgreSQL password file. It
   registers Community automatically and also registers Enterprise when that
   stack will start.
8. **Generate or reuse configuration.** On the first run, random passwords are
   generated. On reruns, database, Odoo master, and pgAdmin credentials are
   preserved. `.env` and the Odoo configuration files are then updated with the
   current ports and environment mode.
9. **Review and confirm.** A summary shows the selected profile, editions, ports,
   pgAdmin choice, and automatic restart state before Odoo configuration or
   Enterprise addons are changed.
10. **Pull and start containers.** The pinned images are downloaded. Community
   always starts; Enterprise and pgAdmin start only when selected by the earlier
   choices. Every created service has the `restart: unless-stopped` policy.
11. **Wait for health.** Docker Compose waits up to 300 seconds for all requested
   services. On Ubuntu, an already-active UFW firewall receives allow rules for
   the selected public web ports.
12. **Show next steps.** The terminal prints URLs, credentials, and browser setup
   guidance. The access information is also saved to `installation-info.txt`.

## Runtime architecture

![Odoo 19 Docker service architecture](docs/images/service-architecture.svg)

| Web service | Internal database | Persistent storage | Start condition |
|---|---|---|---|
| `community` | `db-community` | `community-data`, `community-db` | Always |
| `enterprise` | `db-enterprise` | `enterprise-data`, `enterprise-db` | Enterprise addons exist |
| `pgadmin` | Connects to the selected internal databases | `pgadmin-data` | User enables pgAdmin |

The two PostgreSQL services listen only on Docker's internal network. Only the
Odoo and pgAdmin web ports are published on the host.

## Automatic startup after a restart

No installer rerun is normally required after restarting the machine:

- **Ubuntu:** `docker.service` is enabled at boot. When the Docker daemon becomes
  ready, it starts the previously running Odoo, PostgreSQL, and optional pgAdmin
  containers automatically.
- **Windows:** Docker Desktop launches after the user who ran the installer signs
  in. When its engine becomes ready, the previously running containers start
  automatically. Docker Desktop does not provide this desktop workflow before a
  user signs in.
- **Containers:** Compose uses `restart: unless-stopped`. A normal reboot restarts
  them, but a service deliberately stopped with `docker compose stop` remains
  stopped. `docker compose down` removes the containers, so run the installer or
  `docker compose up -d` before expecting automatic restarts again.

Only services that were actually created will restart. For example, Enterprise
will not appear after reboot unless Enterprise addons were supplied, and pgAdmin
will not appear unless it was enabled during installation.

## Files created or updated

```text
odoo19-one-command-installer/
├── .env                              # Image versions, ports, and credentials
├── installation-info.txt             # URLs and user-facing login details
├── config/
│   ├── community/odoo.conf           # Community database and runtime settings
│   ├── enterprise/odoo.conf          # Enterprise database and runtime settings
│   └── pgadmin/
│       ├── servers.json              # Automatically registered DB servers
│       └── pgpass                    # Automatic DB authentication for pgAdmin
└── addons/
    ├── community/                    # Community custom addons
    ├── enterprise/                   # Licensed Odoo Enterprise addons
    └── enterprise-custom/            # Enterprise custom addons
```

`.env`, `installation-info.txt`, generated configuration files, and copied
Enterprise addons are excluded by `.gitignore`. On Ubuntu, secret files are made
owner-readable only where container compatibility permits.

## First browser setup

### Odoo Community

1. Open the Community URL printed by the installer.
2. On Odoo's database creation screen, use the **Community Odoo master
   password** from `installation-info.txt`.
3. Choose a database name, administrator email, and administrator login
   password. You can also choose the language, country, and demo data.

### Odoo Enterprise

If Enterprise started, open its URL and repeat the database setup using the
separate **Enterprise Odoo master password**.

An Odoo master password controls database creation, restoration, duplication,
and deletion. It is not the administrator login password that you choose in the
browser.

### pgAdmin

pgAdmin is installed as a browser-based Docker service, not as the native
desktop application.

1. Open the pgAdmin URL from `installation-info.txt`.
2. Sign in with its saved **pgAdmin login email** and **pgAdmin login password**.
3. Expand the `Odoo 19` group in the left panel.
4. Open `Odoo 19 Community PostgreSQL`, or the Enterprise server when present.

The installer-generated `pgpass` file allows those registered servers to
connect without requesting the PostgreSQL password. Because
`PGADMIN_REPLACE_SERVERS_ON_STARTUP=True`, the installer-managed server list is
refreshed when pgAdmin starts; manually added server definitions may be replaced.

## First run compared with a rerun

| Item | First run | Rerun |
|---|---|---|
| Database passwords | Generated | Reused from `.env` |
| Odoo master passwords | Generated | Reused from `.env` or existing Odoo config |
| pgAdmin password | Generated | Reused from `.env` |
| Odoo ports and mode | Selected through guided menus | Asked again and configuration updated |
| pgAdmin choice and port | Asked; disabled by default | Asked again; previous enabled state and port become defaults |
| Enterprise addons | Nearby folder is auto-detected or another folder is selected | Existing addons are recommended automatically, with an option to update or disable Enterprise |
| Persistent databases and filestores | Created | Kept and reused |

If an existing database or pgAdmin volume is present but its required saved
credentials are missing, restore `.env` from backup before rerunning.

## Enterprise requirement

There is no separate official Odoo Enterprise Docker image. This installer uses
the official Odoo 19 image together with your licensed Enterprise addon files.
You must have a valid Odoo Enterprise subscription and a legal local copy of
those addons.

To add Enterprise after a Community-only installation, place the licensed folder
beside the installer and name it `enterprise-19.0`, or choose its location from
the edition menu. Existing modules under `addons/enterprise` are detected and
offered as the recommended choice on later runs.

## Useful commands

Run these commands from the repository folder:

```bash
# Show current service state
docker compose --profile pgadmin ps

# Follow logs
docker compose logs -f community
docker compose logs -f enterprise
docker compose --profile pgadmin logs -f pgadmin

# Stop or start pgAdmin only
docker compose --profile pgadmin stop pgadmin
docker compose --profile pgadmin start pgadmin

# Stop all containers but keep persistent data
docker compose --profile pgadmin down
```

Do not run `docker compose down -v` unless you deliberately want to delete all
Odoo databases, filestores, and pgAdmin data.

## Versions and upgrades

The default images are pinned so a future installation does not silently use
different software:

- Odoo: `odoo:19.0-20260908`
- PostgreSQL: `postgres:15.19`
- pgAdmin: `dpage/pgadmin4:9.17`

Before upgrading, back up both PostgreSQL databases and both Odoo filestores,
verify that the Enterprise addons match the target Odoo 19 build, and then
deliberately change `ODOO_IMAGE`, `POSTGRES_IMAGE`, or `PGADMIN_IMAGE` in `.env`.
Rerun the installer to pull and start the chosen images.

## Security and production note

Protect `.env` and `installation-info.txt`, and keep encrypted off-machine
backups. They contain credentials needed to administer or recover the services.

The `production` choice enables two Odoo workers and basic memory limits. It does
not configure a domain, TLS/HTTPS, reverse proxy, mail delivery, monitoring, or
automated backups. Before exposing the system to the internet, add those controls,
restrict Odoo and pgAdmin access with firewall rules, and test database and
filestore restoration.

## Troubleshooting

- **Docker engine is not ready:** Start Docker/Docker Desktop, wait until it is
  running, and rerun the installer.
- **A service does not become healthy within five minutes:** Run
  `docker compose --profile pgadmin ps` and inspect the relevant log command
  shown above.
- **A selected port is already in use:** Rerun the installer and choose a free,
  unique port.
- **`.env` is missing but Docker volumes remain:** Restore `.env` from the same
  installation backup. Do not invent replacement database passwords.
- **Enterprise does not start:** Confirm `addons/enterprise` contains the licensed
  Odoo 19 Enterprise modules, then rerun the installer.
