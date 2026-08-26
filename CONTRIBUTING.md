# Contributing to Dagychu Community

Thank you for your interest in Dagychu Community.

This public repository is the **Dagychu Community install and distribution repository**. It contains deployment assets, documentation, examples, skills, and release-related materials. The Dagychu application source code is not published in this repository.

## Before contributing

Please use GitHub Issues to discuss significant changes before investing substantial work. This helps avoid duplicate effort and proposals that do not fit the current product or distribution architecture.

For security vulnerabilities, do **not** open a public issue. Follow [SECURITY.md](SECURITY.md).

## Contributions accepted in this repository

Useful contributions may include:

- documentation improvements;
- deployment and installation improvements;
- examples and sample pipelines/jobs;
- pipeline-author skills and guidance;
- compatibility fixes for public install/distribution assets;
- corrections to configuration templates;
- reproducible bug reports;
- focused improvements to public repository tooling and scripts.

A contribution should:

- have a clear purpose;
- avoid unrelated refactoring;
- preserve backward compatibility where practical;
- update documentation when public behavior or setup changes;
- avoid including secrets, customer material, private infrastructure details, or proprietary Raideria code.

## Product-code changes

The Dagychu application source code is maintained by Raideria outside this public repository.

If you want to propose a change to Dagychu product behavior, runtime functionality, UI, API, scheduler, worker, or other application components, open a GitHub Issue describing:

- the problem or use case;
- the affected Dagychu version;
- expected behavior;
- reproduction steps when applicable;
- why the change would be useful.

A product proposal may be implemented by Raideria in a future Community release, but the corresponding application-source change is not submitted through this repository.

## License of repository contributions

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the Apache-licensed materials of this repository is submitted under the terms of the Apache License 2.0, as described in Section 5 of that license.

By submitting a contribution, you represent that you have the right to submit it under those terms.

This contribution rule applies to materials contributed to this public repository. It does not grant access to, ownership of, or rights in Dagychu application source code that is not published here.

## Pull requests

Before opening a pull request:

1. make sure the change is within the scope of this public repository;
2. describe the problem being solved;
3. explain notable implementation decisions where relevant;
4. identify breaking setup or migration behavior;
5. link the relevant issue when one exists.

Maintainers may request changes or decline contributions that do not fit the current product or distribution direction.

## Enterprise and proprietary material

Do not submit proprietary Raideria code, customer code, credentials, private infrastructure configuration, Enterprise-only source material, or material copied from private Dagychu repositories.

If you are unsure whether material is appropriate for the public repository, do not publish it until a maintainer has reviewed it.
