# Changelog

All notable changes to this project are documented in this file.

## Unreleased

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
