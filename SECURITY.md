# Security Policy

Dagychu executes production workloads and may interact with sensitive infrastructure. Security reports are taken seriously.

## Reporting a vulnerability

**Do not report security vulnerabilities through public GitHub Issues, Discussions, pull requests, or other public channels.**

Use **GitHub Private Vulnerability Reporting** for this repository:

1. Open the Dagychu Community repository on GitHub.
2. Select **Security**.
3. Select **Advisories**.
4. Select **Report a vulnerability**.
5. Provide the information requested below.

If private vulnerability reporting is temporarily unavailable, contact Raideria through the official website and request a private security contact channel without including exploit details in the initial public message:

https://raideria.com

## What to include

A useful security report should include:

- affected Dagychu version or commit;
- affected component;
- deployment assumptions required to reproduce the issue;
- clear reproduction steps;
- expected and actual behavior;
- security impact;
- proof of concept, if appropriate;
- suggested mitigation, if known.

Please minimize access to real customer or third-party data while reproducing an issue.

## Sensitive areas

Security-sensitive Dagychu components include, among others:

- authentication and session handling;
- API and service tokens;
- external task submission;
- scheduler webhooks;
- runtime variables and secrets;
- PostgreSQL and RabbitMQ credentials;
- job execution;
- Docker-based execution;
- Docker socket access;
- log access;
- pipeline definitions;
- filesystem boundaries;
- permission and access-control logic.

## Supported versions

| Version | Supported |
| --- | --- |
| 3.4.x (current stable) | Yes |
| Older 3.x releases | See GitHub Releases |
| Unversioned `latest` images | Not recommended for production |

Users should keep Dagychu and its dependencies updated.

## Disclosure process

Raideria aims to:

1. acknowledge receipt of a valid private report;
2. reproduce and assess the issue;
3. determine affected versions;
4. prepare a fix or mitigation;
5. coordinate disclosure when appropriate;
6. publish a security advisory for issues that materially affect users.

No fixed response or remediation deadline is promised by the Community edition unless separately agreed under a commercial support agreement.

## Deployment security

Dagychu is self-hosted. Operators remain responsible for securing their deployment environment.

At minimum:

- do not expose PostgreSQL or RabbitMQ directly to untrusted networks;
- use strong unique credentials and service tokens;
- protect API and UI endpoints with appropriate authentication;
- deploy behind TLS where traffic leaves a trusted host/network;
- tightly control any Docker socket mount;
- review worker permissions and filesystem mounts;
- protect runtime variables and secrets;
- restrict access to job logs, which may contain sensitive output;
- keep host, containers, Dagychu, and dependencies patched.

## Scope

This policy applies to security issues in Dagychu Community code and official Community release artifacts maintained by Raideria LLC.

Issues in third-party applications, infrastructure, operating systems, or independently modified Dagychu distributions should normally be reported to their respective maintainers unless the issue is caused by Dagychu itself.
