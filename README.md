# DDEV Blueprint

An interactive generator for a safe PHP/DDEV baseline with the practical
developer tooling needed for everyday local development. It is framework
agnostic: it configures DDEV and optional project files, but never installs
application code, starts containers, or imports a database.

Created and maintained by Johnny X. Lemonade (Honza Mudrak).

## Prerequisites

The generator needs Bash 4 or newer. DDEV and Docker are required to run a
generated project. `--answers` additionally requires Python 3 with PyYAML.
Host `make` is required only when generating and using the development
Makefile. On Debian/Ubuntu install it with:

    sudo apt install make

Git, ripgrep, and jq are useful for development but are not required to
generate files. jq is used opportunistically to add the Makefile `npm-build`
target; without it, only that target is skipped.

## Quick start

    mkdir -p ~/projects/my-app
    ./init-project.sh ~/projects/my-app
    cd ~/projects/my-app
    ddev start
    make composer-install

Preview the same interactive flow without writing files:

    ./init-project.sh --dry-run ~/projects/my-app

Other commands:

    ./init-project.sh --help
    ./init-project.sh --version

Run non-interactively from a complete YAML answers file:

    ./init-project.sh --answers examples/answers.yaml ./my-project
    ./init-project.sh --dry-run --answers examples/answers.yaml ./my-project

## Interactive options

The generator asks for:

- Project name, document root, PHP version, web server, database, optional
  database port, and hostnames/FQDNs.
- Standard development tools in the web image: make, ripgrep, and jq. Default:
  enabled.
- Optional Redis service and its image tag.
- PHP extensions are selected in one comma-separated prompt. Supported optional
  values are redis, apcu, memcached, gd, imagick, imap, intl, soap, bcmath,
  gmp, pcntl, exif, ldap, xsl, tidy, and snmp. The default is `intl,gd`; enter
  `none` to select no optional extensions. Whitespace is ignored and duplicate
  selections are removed.
- Database extensions are automatic, not selectable: MariaDB/MySQL add
  `mysqli` and `pdo_mysql`; PostgreSQL adds `pgsql` and `pdo_pgsql`; a project
  without a database gets none.
- Optional local OpenTelemetry Collector.
- Recommended PHP development settings. Default: enabled.
- Development Makefile, .editorconfig, and .env.local.example. All default to
  enabled.

Supported PHP versions are 8.0, 8.1, 8.2, 8.3, 8.4, and 8.5. Defaults are
centralized near the top of init-project.sh.

Short DNS labels such as admin become additional_hostnames. Full names such as
api.example.test become additional_fqdns.

## Generated DDEV configuration

The generator always creates:

    .ddev/config.yaml

When selected, it also creates:

    .ddev/php/99-development.ini
    .ddev/docker-compose.redis.yaml
    .ddev/docker-compose.otel.yaml
    .ddev/otel/collector-config.yaml

Standard development tools and package-backed extensions use DDEV's native
webimage_extra_packages setting. PCNTL and EXIF are selected and reported but
do not need an extra Debian package in DDEV's standard PHP build. Database
drivers are supplied automatically by DDEV for the selected database.

Recommended PHP settings enable OPcache with immediate timestamp validation,
disable JIT, and set a 4 MiB realpath cache with a 600-second TTL. Xdebug stays
off by default. Enable it only when debugging:

    ddev xdebug on
    ddev xdebug off

## Development files

When selected and absent, the generator creates:

    Makefile
    .editorconfig
    .env.local.example

The Makefile always provides start, stop, restart, status, shell, logs, and
composer-install, plus a `help` target that lists only the generated targets.
It adds phpstan, phpcs, test, console, artisan, npm-install, and npm-build only
when their corresponding project files exist. It is a host-side DDEV wrapper:
run `make help` and `make start` on the host, not with `ddev exec make`.
The `make` installed in the DDEV web image is separate and is for
application-native/container workflows.

The env template is local-development-only. It has no DB variables when the
database option is none. Existing Makefile, .editorconfig, and
.env.local.example files are never overwritten; they are listed as skipped.

## Safety and dry-run

The generator aborts before writing if the target contains .ddev. It never
merges or overwrites DDEV configuration.

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

`database.version` and `database.host_port` may be `null` when `database.type`
is `none`. A Redis image is required when Redis is enabled and must use the
`redis:<tag>` form; `default` resolves to the generator's default Redis tag.
Answers files are configuration, not secret stores: never
put passwords, tokens, or production credentials in them.

## Testing

    ./tests/run.sh

The shell test suite checks optional-host-tool behavior, development tools,
PHP extensions, PHP settings, conditional Makefile targets, preservation of
existing files, env behavior without a database, dry-run safety, health-report
output, and generated YAML. It requires DDEV and Docker but does not start
containers.

## License

Released under the [MIT License](LICENSE).
