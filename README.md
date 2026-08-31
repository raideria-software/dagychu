# Dagychu Community

**Self-hosted execution control for production jobs and pipelines.**

Dagychu helps engineering and data teams define repeatable workflows, run them on their own infrastructure, and operate executions from one place — without moving workload code into a hosted orchestration service.

Dagychu Community is the **free self-hosted edition of Dagychu**, developed and maintained by Raideria LLC. It is distributed as versioned container images together with a public install/distribution repository.

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

This tree is the **Community install distribution** (same layout as the GitHub Release asset `client-community-<version>`). Application code runs from the pinned GHCR image; there is no local app build in this pack.

Requirements: Docker Engine and Docker Compose v2. Pulling from GHCR needs a GitHub PAT with `read:packages` if the package is not public (`install.sh` logs in).

1. Download and unpack the Community client pack (or clone this repository).
2. From this directory:

```bash
./install.sh
```

3. Open the UI printed by the installer. Default: **http://localhost:3000** (or `FRONTEND_HOST_PORT` in `.env`).
4. Sign in with the UI admin token printed by `install.sh`.

The stack uses `docker-compose.yml` (pinned `ghcr.io/raideria-software/dagychu:<version>`). Optional overlay when jobs run via the host Docker engine: `docker-compose.docker-sock.yml` (`JOB_EXECUTOR=docker`).

```bash
docker pull ghcr.io/raideria-software/dagychu:3.4.2
```

Demo pipelines are seeded under `runtime/demo/` on first install. Runs require a **connected** project: open **Administration → Projects**, validate and connect the group before the first run (`execution.project_execution_gate_enabled` in `dagychu-instance.yaml`). Operator steps: [CLIENT_SETUP.md](CLIENT_SETUP.md).

After install, use `./update.sh` for a newer pack/image tag. Do **not** run `./install.sh` again on an existing deployment (it regenerates secrets).

Use explicit version tags in production rather than `latest`. Current product line: **3.4.2**.

## What this repository contains

- `install.sh` / `update.sh` / `reload-projects.sh`
- `docker-compose.yml`, `.env.example`, `dagychu-instance.yaml`
- `examples/`, `skills/`
- `LICENSE.md`, `NOTICE.md`, `TRADEMARKS.md`, `SECURITY.md`, `CONTRIBUTING.md`

This pack does not include a local development compose or an application source tree. You run Dagychu from the GHCR image via `docker-compose.yml`.

## Community and Enterprise

Dagychu Community is the free self-hosted edition of Dagychu. The application runs from versioned Dagychu runtime images; the application source code is maintained by Raideria and is not published in this repository.

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

## Product telemetry

Dagychu includes optional product telemetry that helps Raideria understand product adoption and usage.

Community installations have product telemetry enabled by default. Enterprise installations have it disabled by default. An administrator can review and change the current setting under **Administration → Product Telemetry**.

When enabled, Dagychu sends approximately once every 24 hours:

- a randomly generated installation identifier;
- Dagychu version and edition;
- the aggregate number of runs during the previous 24 hours;
- the aggregate number of active pipelines during the previous 24 hours.

Raideria may derive an approximate country from the network address used to deliver the request. The source IP address is not stored as part of the product telemetry dataset.

Dagychu does **not** send workflow code, pipeline or job names, logs, execution parameters, secrets, usernames, organization names, hostnames, database metadata, or infrastructure identifiers.

Telemetry is sent to `https://telemetry.raideria.com` and can be disabled at any time.

See **Administration → Product Telemetry** in Dagychu for the current telemetry status and the exact values that may be sent by the installation.

## Documentation

- This README and [CLIENT_SETUP.md](CLIENT_SETUP.md)
- In a running instance: **Settings → Documentation** and **Settings → Legal**
- [CONTRIBUTING.md](CONTRIBUTING.md)

## Licensing and distribution

This public repository contains installation assets, documentation, examples, skills, configuration templates, and related release materials. Materials identified as Apache-licensed are provided under the [Apache License 2.0](LICENSE.md).

The Dagychu application source code is not published in this repository. The presence of the Apache license in this repository does not by itself license unpublished Dagychu application source code. Runtime images and other separately distributed components are governed by the terms applicable to those release artifacts.

The licenses for repository materials do **not** grant rights to use Raideria or Dagychu trademarks except as permitted by applicable law or the project trademark policy.

See [TRADEMARKS.md](TRADEMARKS.md) and [NOTICE.md](NOTICE.md).

## Project ownership

Dagychu is developed and maintained by **Raideria LLC (Armenia)**.

The public GitHub organization and repository are distribution and collaboration channels. They do not change ownership of Dagychu intellectual property.

## Links

- **Website:** https://software.raideria.com/dagychu
- **Raideria:** https://raideria.com
- **GitHub organization:** https://github.com/Raideria-Software

---

If Dagychu is already running critical workflows in your organization and you need commercial support or Enterprise capabilities, contact Raideria through the official website.
