# DDEV Blueprint

[![CI](https://github.com/johnnyxlemonade/ddev-blueprint/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/johnnyxlemonade/ddev-blueprint/actions/workflows/ci.yml)

An interactive generator for a safe PHP/DDEV baseline with the practical
developer tooling needed for everyday local development. It is framework
agnostic: it configures DDEV and optional project files, but never installs
application code, starts containers, or imports a database.

Created and maintained by Johnny X. Lemonade (Honza Mudrak).

## Quick start

```bash
mkdir -p ~/projects/my-app
./init-project.sh ~/projects/my-app
cd ~/projects/my-app
ddev start
make composer-install
```

Preview the same interactive flow without writing files:

```bash
./init-project.sh --dry-run ~/projects/my-app
```

Run non-interactively from a complete YAML answers file:

```bash
./init-project.sh --answers examples/answers.yaml ./my-project
./init-project.sh --dry-run --answers examples/answers.yaml ./my-project
```

Other commands:

```bash
./init-project.sh --help
./init-project.sh --version
```

## Prerequisites

The generator requires Bash 4 or newer. DDEV and Docker are required to run a
generated project. `--answers` additionally requires Python 3 with PyYAML.

Host `make` is required only when generating and using the development
Makefile. On Debian/Ubuntu:

```bash
sudo apt install make
```

Git, ripgrep, and jq are useful for development but are not required to
generate files. jq is used opportunistically to add the Makefile `npm-build`
target; without it, only that target is skipped.

## Interactive options

The generator asks for:

- Project name, document root, PHP version, web server, database, optional
  fixed host database port, and hostnames/FQDNs.
- Standard development tools in the web image: make, ripgrep, and jq. Default:
  enabled.
- Optional Redis service and image tag.
- Optional PHP extensions in one comma-separated prompt. Default: `intl,gd`.
  Enter `none` to select no optional extensions. Whitespace is ignored and
  duplicate selections are removed.
- Optional local OpenTelemetry Collector.
- Recommended PHP development settings. Default: enabled.
- Development Makefile, `.editorconfig`, and `.env.local.example`. All default
  to enabled.

Database extensions are automatic, not selectable: MariaDB/MySQL add `mysqli`
and `pdo_mysql`; PostgreSQL adds `pgsql` and `pdo_pgsql`; a project without a
database gets none.

The document root defaults to `public`. Enter `.` to serve the project root;
the generated DDEV configuration represents this as `docroot: ""`.

### Fixed host database port

For a stable connection from HeidiSQL, DBeaver, or another host-OS client, the
interactive flow offers a fixed `host_db_port` for every project with a
database. It defaults to enabled and proposes the first available port from
`43000` upwards. You can change the proposed port or decline the fixed port to
keep DDEV's dynamic mapping. Two running projects must not use the same host
port.

In an answers file, set `database.host_port: 43000` to select a fixed port, or
leave it as `null` to retain DDEV's dynamic mapping.

## Supported configuration

`Supported` means a value is part of the builder's capability matrix and is
validated through `lib/capabilities.sh`. Defaults are selections from that
matrix, not the matrix itself.

PHP values are DDEV-selectable major/minor branches, not individual patch
releases.

| Component | Supported values |
| --- | --- |
| PHP | 8.0, 8.1, 8.2, 8.3, 8.4, 8.5 |
| Web server | `apache-fpm`, `nginx-fpm` |
| Database type | `mariadb`, `mysql`, `postgres`, `none` |

### Database versions

| Database | Supported versions | Default |
| --- | --- | --- |
| MariaDB | 5.5, 10.0, 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7, 10.8, 10.11, 11.4, 11.8, 12.3 | 11.8 |
| MySQL | 5.5, 5.6, 5.7, 8.0, 8.4, 9.7 | 8.4 |
| PostgreSQL | 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 | 17 |
| none | — | — |

A database version must belong to the selected database type. Unsupported or
malformed database values fail validation before project creation.

### Optional PHP extensions

`redis`, `apcu`, `memcached`, `gd`, `imagick`, `imap`, `intl`, `soap`,
`bcmath`, `gmp`, `pcntl`, `exif`, `ldap`, `xsl`, `tidy`, `snmp`.

### Redis

The optional local Redis service is implemented as the builder's custom DDEV
Compose service and is intentionally non-persistent. Redis data does not
survive `ddev restart`.

- Default: `redis:7.4-alpine`
- Runtime-tested/supported images:
    - `redis:6.2-alpine`
    - `redis:7.2-alpine`
    - `redis:7.4-alpine`
    - `redis:8.0-alpine`
    - `redis:8.2-alpine`
    - `redis:8.4-alpine`
    - `redis:8.6-alpine`
    - `redis:8.8-alpine`
    - `redis:8.10-alpine`

Interactive mode also accepts a syntactically valid custom tag, and answers
mode accepts `redis:<tag>`. A custom tag is rendered unchanged as an advanced
override, but it is not builder-guaranteed or runtime-tested. In either mode,
`default` resolves to `redis:7.4-alpine`.

The Redis service and PHP `redis` extension are independent: either can be
selected without the other.

### Capability model

`lib/defaults.sh` contains only default values. `lib/capabilities.sh` contains
the supported values and compatibility matrix. Interactive input and
`--answers` share the same validation layer.

That distinction is intentional:

- default != supported matrix
- supported Redis tag != custom Redis override

## Runtime verified

The compatibility matrix has been verified in layers rather than as one large
Cartesian product.

### Exhaustive coverage

| Area | Coverage |
| --- | --- |
| PHP × web server | 12/12 combinations across PHP 8.0–8.5 and `apache-fpm` / `nginx-fpm`; DDEV start, PHP version, and HTTP/webserver checks |
| Core databases | 30/30 declared database type/version variants; actual type/version plus healthy DB container |
| Redis images | 9/9 supported Redis tags; image, DNS, port 6379, PING, Redis set/get, PHP 8.4 + ext-redis connect/set/get, `INFO server`, and non-persistence after restart |
| PHP × default Redis | PHP 8.0–8.5 against `redis:7.4-alpine`; actual PHP connect/set/get |

### Representative coverage

- Actual PHP database connection/query: MariaDB 11.8, MySQL 8.4, PostgreSQL 17.
- Optional extension/package mapping: PHP 8.0 and PHP 8.5.

This does not claim exhaustive PHP × every DB version or PHP × every Redis tag
coverage.

## Hostnames

Short DNS labels such as `admin` become `additional_hostnames`. Full names such
as `api.example.test` become `additional_fqdns`.

## Generated DDEV configuration

The generator always creates:

```text
.ddev/config.yaml
```

When selected, it also creates:

```text
.ddev/php/99-development.ini
.ddev/docker-compose.redis.yaml
.ddev/docker-compose.otel.yaml
.ddev/otel/collector-config.yaml
```

Standard development tools and package-backed extensions use DDEV's native
`webimage_extra_packages` setting. PCNTL and EXIF are selected and reported but
do not need an extra Debian package in DDEV's standard PHP build. Database
drivers are supplied automatically by DDEV for the selected database.

Recommended PHP settings enable OPcache with immediate timestamp validation,
disable JIT, and set a 4 MiB realpath cache with a 600-second TTL. Xdebug stays
off by default. Enable it only when debugging:

```bash
ddev xdebug on
ddev xdebug off
```

## Development files

When selected and absent, the generator creates:

```text
Makefile
.editorconfig
.env.local.example
```

The Makefile always provides `start`, `stop`, `restart`, `status`, `shell`,
`logs`, and `composer-install`, plus a `help` target that lists only generated
targets. It adds `phpstan`, `phpcs`, `test`, `console`, `artisan`,
`npm-install`, and `npm-build` only when their corresponding project files
exist.

It is a host-side DDEV wrapper: run `make help` and `make start` on the host,
not with `ddev exec make`. The `make` installed in the DDEV web image is
separate and is intended for application-native/container workflows.

The env template is local-development-only. It has no DB variables when the
database option is `none`. Existing `Makefile`, `.editorconfig`, and
`.env.local.example` files are never overwritten; they are listed as skipped.

## Safety and dry-run

The generator aborts before writing if the target already contains `.ddev`. It
never merges or overwrites an existing DDEV configuration.

Dry-run asks every question, prints the selected configuration and planned
files, and creates no directories or files.

## Non-interactive answers

`--answers FILE` disables prompts. The file must be complete and conform to the
strict schema shown in [examples/answers.yaml](examples/answers.yaml). Unknown
keys, missing required keys, invalid values, invalid hostnames, and unknown PHP
extensions fail immediately. YAML is parsed safely with PyYAML; it is not
evaluated as shell code.

The stable schema is:

```yaml
project: { name: my-app, docroot: public, php: "8.4", webserver: apache-fpm }
database: { type: mariadb, version: "11.8", host_port: null }
hostnames: { additional: [], fqdns: [] }
services:
  redis: { enabled: false, image: null }
  opentelemetry: { enabled: false }
php: { extensions: [intl, gd], development_settings: true }
development: { tools: true, makefile: true, editorconfig: true, env_example: true }
```

`database.version` may be `null` when `database.type` is `none`.
`database.host_port` may be `null`; a `null` value disables the fixed host
port. A Redis image is required when Redis is enabled and must use the
`redis:<tag>` form; `default` resolves to the generator's default Redis tag.
`project.docroot` defaults to `public`; set it to `"."` to serve the project
root.

Answers files are configuration, not secret stores: never put passwords,
tokens, or production credentials in them.

## Testing

Run the shell test suite:

```bash
./tests/run.sh
```

Lint the complete builder through its actual entrypoint and the standalone test
entrypoint:

```bash
shellcheck -x init-project.sh tests/run.sh
```

The files in `lib/` are sourced modules, not standalone commands; ShellCheck
follows them through `init-project.sh`.

The shell test suite checks optional-host-tool behavior, development tools,
PHP extensions, PHP settings, conditional Makefile targets, preservation of
existing files, env behavior without a database, dry-run safety, health-report
output, and generated YAML. It requires DDEV and Docker but does not start
containers.

## License

Released under the [MIT License](LICENSE).
