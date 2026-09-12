#!/usr/bin/env bash

bp_die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
bp_usage() { cat <<'EOF'
Usage: init-project.sh [--dry-run] [--answers FILE] [TARGET_DIR]

Creates a safe DDEV and developer-tooling baseline in TARGET_DIR (the current
directory by default). Without --answers it is interactive. It never merges
with or overwrites an existing .ddev directory.

Arguments:
  TARGET_DIR       New or existing application directory without .ddev.

Options:
  --dry-run        Ask all questions and show the plan without writing files.
  --answers FILE    Read complete non-interactive answers from a YAML file.
  -h, --help       Show this help text.
  --version        Print the blueprint version.

Supported PHP: 8.0, 8.1, 8.2, 8.3, 8.4, 8.5 (default: 8.4).
Web servers: apache-fpm, nginx-fpm (default: apache-fpm).
Databases: mariadb (default: 11.8), mysql (default: 8.4), postgres
(default: 17), or none. The default database is mariadb.

Optional PHP extensions: redis, apcu, memcached, gd, imagick, imap, intl,
soap, bcmath, gmp, pcntl, exif, ldap, xsl, tidy, snmp.
Default extensions: intl,gd.

Standard development tools, recommended PHP development settings, Makefile,
.editorconfig, and .env.local.example are enabled by default.

Answers mode requires Python 3 with PyYAML. Answers files are configuration,
not secret stores; do not put passwords or production credentials in them.
The generated Makefile runs DDEV commands on the host and requires host `make`.
EOF
}
bp_parse_cli() { DRY_RUN=false; ANSWERS_MODE=false; ANSWERS_FILE=""; local target_arg=""; while (( $# > 0 )); do case "$1" in --dry-run) DRY_RUN=true ;; --answers) shift; (( $# > 0 )) || bp_die "--answers requires a YAML file path."; [[ -z "$ANSWERS_FILE" ]] || bp_die "--answers may only be specified once."; ANSWERS_FILE="$1"; ANSWERS_MODE=true ;; -h|--help) bp_usage; exit 0 ;; --version) printf '%s\n' "$BP_VERSION"; exit 0 ;; --*) bp_die "Unknown option: $1" ;; *) [[ -z "$target_arg" ]] || bp_die "Only one target directory may be provided."; target_arg="$1" ;; esac; shift; done; TARGET_ARG="${target_arg:-$(pwd)}"; }
bp_prepare_target() { if [[ "$TARGET_ARG" = /* ]]; then TARGET_DIR="${TARGET_ARG%/}"; else TARGET_DIR="$(pwd)/${TARGET_ARG%/}"; fi; [[ -n "$TARGET_DIR" && "$TARGET_DIR" != "/" ]] || bp_die "Target directory must not be the filesystem root."; [[ ! -e "$TARGET_DIR/.ddev" ]] || bp_die "Target already contains $TARGET_DIR/.ddev. Aborting without changes."; DEFAULT_NAME="$(basename "$TARGET_DIR")"; }
