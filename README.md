# Dagychu Community

**Self-hosted execution control for production jobs and pipelines.**

Dagychu helps engineering and data teams define repeatable workflows, run them on their own infrastructure, and operate executions from one place — without moving workload code into a hosted orchestration service.

> Dagychu Community is the open-source edition of Dagychu, developed and maintained by Raideria LLC. Licensed under [Apache License 2.0](LICENSE.md).

## Why Dagychu

Production automation often starts simply: Python scripts, Bash commands, cron jobs, containers, and internal services. As the number of workflows grows, teams also need to know:

- what is running now;
- what succeeded or failed;
- which job failed inside a pipeline;
- what was scheduled and why it ran;
- how to rerun or stop an execution;
- where logs and execution state live;
- how external systems can trigger work.

Dagychu provides a self-hosted control plane for those operations.

## What you can do

- **YAML-defined pipelines** with jobs and execution metadata.
- **Tracked task and job lifecycle** with `PENDING`, `RUNNING`, `SUCCESS`, `FAILED`, and `CANCELLED` states.
- **Manual execution and control** including rerun, job rerun, cancellation, pipeline termination, and status reconciliation.
- **Scheduling** including scheduled jobs, pause/resume, and manual trigger.
- **Local and Docker-based job execution** through pluggable job executors.
- **Multiple pipeline groups/projects** with project runtime configuration.
- **Web UI** for pipeline and task operations.
- **Execution logs, dashboard summaries, trends, and operational monitoring**.
- **HTTP APIs** for tasks, pipelines, administration, and automation.
- **Realtime task updates** through WebSockets.

Dagychu is designed for self-hosted and private-cloud environments. Execution metadata stays in your PostgreSQL instance, while job logs remain on worker storage.

## Architecture

```text
Browser
   |
   v
Frontend / UI backend
   |
   v
Dagychu API -------- PostgreSQL
   |
   +---------------- RabbitMQ
                        |
                        v
                     Worker(s)
                        |
                        v
                 Local / Docker jobs

Scheduler ----------> Dagychu API
```

The API stores execution state and publishes work. Workers consume queued jobs and execute them. The scheduler creates and triggers scheduled work. The UI provides the operational control plane.

## Quick start (recommended)

Community production installs use a **client pack** (GitHub Release asset `client-community-<version>`): pinned GHCR image, Compose file, `.env.example`, and `install.sh`.

Requirements: Docker Engine and Docker Compose v2.

1. Download and unpack the Community client pack for the version you want (see GitHub Releases).
2. From the unpacked directory:

```bash
./install.sh
```

3. Open the UI printed by the installer. Default: **http://localhost:3000** (or `FRONTEND_HOST_PORT` in `.env`).
4. Sign in with the UI admin token printed by `install.sh`.

The pack pulls the Community image from GHCR:

```bash
docker pull ghcr.io/raideria-software/dagychu:3.4.1
```

Demo pipelines are seeded under `runtime/demo/` on first install. Operator details are in `CLIENT_SETUP.md` inside the pack.

Use explicit version tags in production rather than `latest`. Current product line: **3.4.1**.

## Run from this repository (development)

```bash
./update-dev.sh
```

UI: http://localhost:3000 · API: http://localhost:8000

Do not treat `docker-compose.prod.yml` as the Community distribution. Production Community compose is `docker-compose.community.prod.yml`, rendered into the client pack as `docker-compose.yml`.

## Community and Enterprise

Dagychu Community is the Apache-licensed self-hosted distribution.

Raideria also develops commercial Dagychu capabilities (Enterprise) for organizations with additional operational, security, governance, or support requirements.

The edition boundary is version-specific. Community is not intentionally crippled with artificial task or run quotas.

## Security

Dagychu executes code and can optionally interact with the Docker daemon. Treat deployment security as part of the infrastructure boundary.

Before exposing Dagychu outside a trusted network:

- configure authentication and service tokens;
- use strong PostgreSQL and RabbitMQ credentials;
- restrict network access between services;
- protect any Docker socket mount;
- review runtime variables and secrets;
- deploy behind TLS;
- keep Dagychu and its dependencies updated.

Do not disclose vulnerabilities in public GitHub issues. See [SECURITY.md](SECURITY.md).

## Documentation

- This README and [CLIENT_SETUP.md](CLIENT_SETUP.md) (install pack)
- In a running instance: **Settings → Documentation** and **Settings → Legal**
- [CONTRIBUTING.md](CONTRIBUTING.md)

## License

Dagychu Community is licensed under the [Apache License 2.0](LICENSE.md).

The software license covers the source code and other materials distributed under that license. It does **not** grant rights to use Raideria or Dagychu trademarks except as permitted by applicable law or the project's trademark policy.

See [TRADEMARKS.md](TRADEMARKS.md) and [NOTICE.md](NOTICE.md).

## Project ownership

Dagychu is developed and maintained by **Raideria LLC (Armenia)**.

The public GitHub organization and repository are distribution and collaboration channels. They do not change ownership of Dagychu intellectual property.

## Links

- **Website:** https://raideria.com/dagychu
- **Raideria:** https://raideria.com
- **GitHub organization:** https://github.com/Raideria-Software

---

If Dagychu is already running critical workflows in your organization and you need commercial support or Enterprise capabilities, contact Raideria through the official website.
