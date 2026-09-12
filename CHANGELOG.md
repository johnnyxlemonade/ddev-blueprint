# Changelog

All notable changes to this project are documented in this file.

## Unreleased

## 0.2.0 - 2026-09-12

- Modularized `init-project.sh` into focused `lib/` modules while preserving the public CLI and answers schema.
- Centralized supported PHP, webserver, database, and Redis capabilities separately from defaults.
- Added shared capability-based validation for interactive and `--answers` configuration, including PHP 8.0–8.5, `apache-fpm`/`nginx-fpm`, and explicit MariaDB, MySQL, and PostgreSQL versions.
- Added a runtime-verified Redis image matrix while retaining valid custom Redis tags as non-guaranteed overrides.
- Updated README support documentation for the runtime-verified capability matrix.
- Made CI ShellCheck source-aware for the modular Bash entrypoint.

## 0.1.1 - 2026-09-11

- Added a strict non-interactive YAML answers mode.
- Added generated Makefile help and a clearer final generation report.
- Redis image tag `default` is now resolved to the configured default Redis tag.
- The same normalization works in interactive and `--answers` modes.

## 0.1.0 - 2026-09-11

- Initial public release.
- Safe interactive DDEV PHP-project generator with dry-run support.
- Input validation, hostname/FQDN separation, optional Redis and OpenTelemetry.
- Shell-based test suite and GitHub Actions validation.
