#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.1.0"
[[ -r "$SCRIPT_DIR/VERSION" ]] && IFS= read -r VERSION < "$SCRIPT_DIR/VERSION"

# Maintain defaults and supported PHP versions here.
SUPPORTED_PHP_VERSIONS=("8.0" "8.1" "8.2" "8.3" "8.4" "8.5")
DEFAULT_PHP_VERSION="8.4"
DEFAULT_WEBSERVER="apache-fpm"
DEFAULT_DB_TYPE="mariadb"
DEFAULT_MARIADB_VERSION="11.8"
DEFAULT_MYSQL_VERSION="8.4"
DEFAULT_POSTGRES_VERSION="17"
DEFAULT_REDIS_TAG="7.4-alpine"
DEFAULT_OTEL_VERSION="0.160.0"
DEFAULT_DOCROOT="public"
DEFAULT_OPTIONAL_EXTENSIONS=("intl" "gd")
SUPPORTED_OPTIONAL_EXTENSIONS=(
  "redis" "apcu" "memcached" "gd" "imagick" "imap" "intl" "soap"
  "bcmath" "gmp" "pcntl" "exif" "ldap" "xsl" "tidy" "snmp"
)

DRY_RUN=false
ANSWERS_MODE=false
ANSWERS_FILE=""
GENERATED=()
SKIPPED=()
declare -A ANSWERS=()

usage() {
  cat <<'EOF'
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
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while (( $# > 0 )); do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --answers)
      shift
      (( $# > 0 )) || die "--answers requires a YAML file path."
      [[ -z "$ANSWERS_FILE" ]] || die "--answers may only be specified once."
      ANSWERS_FILE="$1"; ANSWERS_MODE=true
      ;;
    -h|--help) usage; exit 0 ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    --*) die "Unknown option: $1" ;;
    *) [[ -z "${TARGET_ARG:-}" ]] || die "Only one target directory may be provided."; TARGET_ARG="$1" ;;
  esac
  shift
done
TARGET_ARG="${TARGET_ARG:-$(pwd)}"
if [[ "$TARGET_ARG" = /* ]]; then TARGET_DIR="${TARGET_ARG%/}"; else TARGET_DIR="$(pwd)/${TARGET_ARG%/}"; fi
[[ -n "$TARGET_DIR" && "$TARGET_DIR" != "/" ]] || die "Target directory must not be the filesystem root."
[[ ! -e "$TARGET_DIR/.ddev" ]] || die "Target already contains $TARGET_DIR/.ddev. Aborting without changes."
DEFAULT_NAME="$(basename "$TARGET_DIR")"

valid_project_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; }
valid_php_version() { local v; for v in "${SUPPORTED_PHP_VERSIONS[@]}"; do [[ "$1" == "$v" ]] && return 0; done; return 1; }
valid_webserver() { [[ "$1" == apache-fpm || "$1" == nginx-fpm ]]; }
valid_docroot() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*([/][A-Za-z0-9][A-Za-z0-9._-]*)*$ ]]; }
valid_db_type() { [[ "$1" =~ ^(mariadb|mysql|postgres|none)$ ]]; }
valid_version() { [[ "$1" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; }
valid_port() { [[ "$1" =~ ^[1-9][0-9]{0,4}$ ]] && (( 10#$1 <= 65535 )); }
valid_redis_tag() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; }
normalize_redis_tag() {
  local tag="$1"
  [[ -z "$tag" || "$tag" == default ]] && tag="$DEFAULT_REDIS_TAG"
  valid_redis_tag "$tag" || return 1
  printf '%s' "$tag"
}
load_answers() {
  [[ -f "$ANSWERS_FILE" ]] || die "Answers file not found: $ANSWERS_FILE"
  command -v python3 >/dev/null 2>&1 || die "Answers mode requires Python 3 with PyYAML."
  local output key value
  if ! output="$(python3 - "$ANSWERS_FILE" <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("ERROR: Answers mode requires Python 3 with PyYAML.", file=sys.stderr)
    raise SystemExit(1)

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as stream:
        data = yaml.safe_load(stream)
except (OSError, yaml.YAMLError) as error:
    print(f"ERROR: Cannot read answers file: {error}", file=sys.stderr)
    raise SystemExit(1)

schema = {
    "project": {"name": None, "docroot": None, "php": None, "webserver": None},
    "database": {"type": None, "version": None, "host_port": None},
    "hostnames": {"additional": None, "fqdns": None},
    "services": {"redis": {"enabled": None, "image": None}, "opentelemetry": {"enabled": None}},
    "php": {"extensions": None, "development_settings": None},
    "development": {"tools": None, "makefile": None, "editorconfig": None, "env_example": None},
}
if not isinstance(data, dict):
    print("ERROR: Answers file must contain a YAML mapping.", file=sys.stderr)
    raise SystemExit(1)

def check_keys(value, allowed, prefix=""):
    if not isinstance(value, dict):
        label = prefix[:-1] or "root"
        print(f"ERROR: Invalid answer value: {label} must be a mapping.", file=sys.stderr)
        raise SystemExit(1)
    for key in value:
        if key not in allowed:
            print(f"ERROR: Unknown answer key: {prefix}{key}", file=sys.stderr)
            raise SystemExit(1)
    for key, child in allowed.items():
        full = f"{prefix}{key}"
        if key not in value:
            print(f"ERROR: Missing required answer: {full}", file=sys.stderr)
            raise SystemExit(1)
        if isinstance(child, dict):
            check_keys(value[key], child, full + ".")

check_keys(data, schema)

def scalar(path):
    value = data
    for part in path.split("."):
        value = value[part]
    if value is None:
        return ""
    if not isinstance(value, (str, int)) or isinstance(value, bool):
        print(f"ERROR: Invalid answer value: {path} must be a string, number, or null.", file=sys.stderr)
        raise SystemExit(1)
    value = str(value)
    if any(char in value for char in "\t\r\n"):
        print(f"ERROR: Invalid answer value: {path} contains an unsupported character.", file=sys.stderr)
        raise SystemExit(1)
    return value

def boolean(path):
    value = data
    for part in path.split("."):
        value = value[part]
    if not isinstance(value, bool):
        print(f"ERROR: Invalid answer value: {path} must be true or false.", file=sys.stderr)
        raise SystemExit(1)
    return "y" if value else "n"

def string_list(path):
    value = data
    for part in path.split("."):
        value = value[part]
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        print(f"ERROR: Invalid answer value: {path} must be a list of strings.", file=sys.stderr)
        raise SystemExit(1)
    if any(any(char in item for char in "\t\r\n") for item in value):
        print(f"ERROR: Invalid answer value: {path} contains an unsupported character.", file=sys.stderr)
        raise SystemExit(1)
    return ",".join(value)

for path in ("project.name", "project.docroot", "project.php", "project.webserver", "database.type", "database.version", "database.host_port", "services.redis.image"):
    print(f"{path}\t{scalar(path)}")
for path in ("services.redis.enabled", "services.opentelemetry.enabled", "php.development_settings", "development.tools", "development.makefile", "development.editorconfig", "development.env_example"):
    print(f"{path}\t{boolean(path)}")
for path in ("hostnames.additional", "hostnames.fqdns", "php.extensions"):
    print(f"{path}\t{string_list(path)}")
PY
)"; then
    die "Unable to parse answers file. Python 3 with PyYAML is required."
  fi
  while IFS=$'\t' read -r key value; do ANSWERS["$key"]="$value"; done <<< "$output"
}
valid_hostname() {
  local value="$1" label
  [[ ${#value} -le 253 && "$value" != *..* && "$value" != .* && "$value" != *. ]] || return 1
  IFS='.' read -r -a labels <<< "$value"
  for label in "${labels[@]}"; do [[ "$label" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || return 1; done
}
prompt_value() {
  local prompt="$1" default="$2" validator="$3" value
  while true; do
    printf '%s [%s]: ' "$prompt" "$default"; IFS= read -r value || die "Input ended unexpectedly."
    value="${value:-$default}"
    if "$validator" "$value"; then ANSWER="$value"; return; fi
    printf 'Invalid value. Please try again.\n' >&2
  done
}
answer_or_prompt_value() {
  local key="$1" prompt="$2" default="$3" validator="$4" value
  if "$ANSWERS_MODE"; then
    value="${ANSWERS[$key]}"
    "$validator" "$value" || die "Invalid answer value: $key"
    ANSWER="$value"
  else
    prompt_value "$prompt" "$default" "$validator"
  fi
}
prompt_yes_no() {
  local prompt="$1" default="$2" value
  while true; do
    printf '%s [%s]: ' "$prompt" "$default"; IFS= read -r value || die "Input ended unexpectedly."
    value="${value:-$default}"
    case "$value" in y|Y) ANSWER=y; return ;; n|N) ANSWER=n; return ;; *) printf 'Invalid value. Enter y or n.\n' >&2 ;; esac
  done
}
answer_or_prompt_yes_no() {
  local key="$1" prompt="$2" default="$3" value
  if "$ANSWERS_MODE"; then
    value="${ANSWERS[$key]}"
    [[ "$value" == y || "$value" == n ]] || die "Invalid answer value: $key"
    ANSWER="$value"
  else
    prompt_yes_no "$prompt" "$default"
  fi
}
prompt_port() {
  local value
  while true; do
    printf 'Fixed host DB port for HeidiSQL/DBeaver [empty = automatic]: '; IFS= read -r value || die "Input ended unexpectedly."
    if [[ -z "$value" ]] || valid_port "$value"; then ANSWER="$value"; return; fi
    printf 'Invalid port. Enter 1-65535 or leave it empty.\n' >&2
  done
}
set_hostnames() {
  local value="$1" raw host
  HOSTNAMES=(); FQDNS=()
  [[ -z "$value" ]] && return 0
  local -a entries=(); IFS=',' read -r -a entries <<< "$value"
  for raw in "${entries[@]}"; do
    host="${raw#"${raw%%[![:space:]]*}"}"; host="${host%"${host##*[![:space:]]}"}"
    valid_hostname "$host" || return 1
    if [[ "$host" == *.* ]]; then FQDNS+=("$host"); else HOSTNAMES+=("$host"); fi
  done
}
prompt_hostnames() {
  local value
  while true; do
    printf 'Hostnames/FQDNs separated by commas [empty = none]: '; IFS= read -r value || die "Input ended unexpectedly."
    set_hostnames "$value" && return
    printf 'Invalid hostname/FQDN. Please try again.\n' >&2
  done
}
extension_package() {
  case "$1" in
    redis|apcu|memcached|gd|imagick|imap|intl|soap|bcmath|gmp|ldap|tidy|snmp)
      printf 'php${DDEV_PHP_VERSION}-%s\n' "$1"
      ;;
    xsl) printf 'php${DDEV_PHP_VERSION}-xml\n' ;;
    # PCNTL and EXIF are part of DDEV's standard PHP build.
    pcntl|exif) return 0 ;;
  esac
}
is_supported_optional_extension() {
  local extension
  for extension in "${SUPPORTED_OPTIONAL_EXTENSIONS[@]}"; do
    [[ "$extension" == "$1" ]] && return 0
  done
  return 1
}
set_extensions() {
  local value="$1" raw extension package
  local -a entries=()
  EXTENSIONS=()
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  [[ "$value" == none ]] && return 0
  IFS=',' read -r -a entries <<< "$value"
  for raw in "${entries[@]}"; do
    extension="${raw#"${raw%%[![:space:]]*}"}"
    extension="${extension%"${extension##*[![:space:]]}"}"
    if ! is_supported_optional_extension "$extension"; then
      printf 'Unknown PHP extension: %s. Supported values: %s, none.\n' "$extension" "${SUPPORTED_OPTIONAL_EXTENSIONS[*]}" >&2
      EXTENSIONS=()
      return 1
    fi
    if [[ " ${EXTENSIONS[*]} " != *" $extension "* ]]; then EXTENSIONS+=("$extension"); fi
  done
  for extension in "${EXTENSIONS[@]}"; do
    package="$(extension_package "$extension")" || true
    if [[ -n "$package" ]]; then add_package "$package"; fi
  done
}
prompt_extensions() {
  local value default_list
  default_list="$(IFS=,; printf '%s' "${DEFAULT_OPTIONAL_EXTENSIONS[*]}")"
  while true; do
    printf 'PHP extensions [intl,gd]: '; IFS= read -r value || die "Input ended unexpectedly."
    [[ -z "$value" ]] && value="$default_list"
    set_extensions "$value" && return
  done
}
add_package() {
  local package="$1" current
  for current in "${PACKAGES[@]}"; do [[ "$current" == "$package" ]] && return; done
  PACKAGES+=("$package")
}
add_generated() { GENERATED+=("$1"); }
add_skipped() { SKIPPED+=("$1"); }
join_by() {
  local separator="$1" item result=""
  shift
  for item in "$@"; do
    [[ -z "$result" ]] || result+="$separator"
    result+="$item"
  done
  printf '%s' "$result"
}

if "$ANSWERS_MODE"; then load_answers; fi
answer_or_prompt_value project.name 'DDEV project name' "$DEFAULT_NAME" valid_project_name; PROJECT_NAME="$ANSWER"
answer_or_prompt_value project.docroot 'Document root' "$DEFAULT_DOCROOT" valid_docroot; DOCROOT="$ANSWER"
answer_or_prompt_value project.php 'PHP version' "$DEFAULT_PHP_VERSION" valid_php_version; PHP_VERSION="$ANSWER"
answer_or_prompt_value project.webserver 'Webserver (apache-fpm/nginx-fpm)' "$DEFAULT_WEBSERVER" valid_webserver; WEBSERVER="$ANSWER"
answer_or_prompt_value database.type 'Database (mariadb/mysql/postgres/none)' "$DEFAULT_DB_TYPE" valid_db_type; DB_TYPE="$ANSWER"
DB_VERSION=""; HOST_DB_PORT=""
if [[ "$DB_TYPE" != none ]]; then
  case "$DB_TYPE" in mariadb) DB_DEFAULT="$DEFAULT_MARIADB_VERSION" ;; mysql) DB_DEFAULT="$DEFAULT_MYSQL_VERSION" ;; postgres) DB_DEFAULT="$DEFAULT_POSTGRES_VERSION" ;; esac
  answer_or_prompt_value database.version 'Database version' "$DB_DEFAULT" valid_version; DB_VERSION="$ANSWER"
  if "$ANSWERS_MODE"; then
    HOST_DB_PORT="${ANSWERS[database.host_port]}"
    [[ -z "$HOST_DB_PORT" ]] || valid_port "$HOST_DB_PORT" || die 'Invalid answer value: database.host_port'
  else
    prompt_port; HOST_DB_PORT="$ANSWER"
  fi
fi
if "$ANSWERS_MODE"; then
  HOSTNAME_INPUT="${ANSWERS[hostnames.additional]}"
  if [[ -n "${ANSWERS[hostnames.fqdns]}" ]]; then
    [[ -z "$HOSTNAME_INPUT" ]] || HOSTNAME_INPUT+=","
    HOSTNAME_INPUT+="${ANSWERS[hostnames.fqdns]}"
  fi
  set_hostnames "$HOSTNAME_INPUT" || die 'Invalid answer value: hostnames'
else
  prompt_hostnames
fi
answer_or_prompt_yes_no development.tools 'Include standard development tools?' Y; ENABLE_DEV_TOOLS="$ANSWER"
answer_or_prompt_yes_no services.redis.enabled 'Add Redis service?' N; ENABLE_REDIS_SERVICE="$ANSWER"; REDIS_TAG=""
if [[ "$ENABLE_REDIS_SERVICE" == y ]]; then
  if "$ANSWERS_MODE"; then
    REDIS_IMAGE="${ANSWERS[services.redis.image]}"
    if [[ "$REDIS_IMAGE" == default ]]; then
      REDIS_TAG=default
    elif [[ "$REDIS_IMAGE" == redis:* ]]; then
      REDIS_TAG="${REDIS_IMAGE#redis:}"
    else
      die 'Invalid answer value: services.redis.image'
    fi
  else
    prompt_value 'Redis image tag' "$DEFAULT_REDIS_TAG" valid_redis_tag; REDIS_TAG="$ANSWER"
  fi
  REDIS_TAG="$(normalize_redis_tag "$REDIS_TAG")" || die 'Invalid answer value: services.redis.image'
fi

PACKAGES=(); EXTENSIONS=()
if [[ "$ENABLE_DEV_TOOLS" == y ]]; then add_package make; add_package ripgrep; add_package jq; fi
if "$ANSWERS_MODE"; then set_extensions "${ANSWERS[php.extensions]}" || die 'Invalid answer value: php.extensions'; else prompt_extensions; fi
case "$DB_TYPE" in
  mariadb|mysql) DB_EXTENSIONS=("mysqli" "pdo_mysql") ;;
  postgres) DB_EXTENSIONS=("pgsql" "pdo_pgsql") ;;
  none) DB_EXTENSIONS=() ;;
esac
answer_or_prompt_yes_no services.opentelemetry.enabled 'Add local OpenTelemetry Collector?' N; ENABLE_OTEL="$ANSWER"
answer_or_prompt_yes_no php.development_settings 'Configure recommended PHP development settings?' Y; ENABLE_PHP_SETTINGS="$ANSWER"
answer_or_prompt_yes_no development.makefile 'Generate development Makefile?' Y; ENABLE_MAKEFILE="$ANSWER"
MAKEFILE_SKIP_REASON=""
if [[ "$ENABLE_MAKEFILE" == y ]] && ! command -v make >/dev/null 2>&1; then
  if "$ANSWERS_MODE"; then
    die 'development.makefile=true requires host command `make`. Install it first or set development.makefile=false.'
  fi
  printf '\nHost `make` is not installed.\nThe generated Makefile runs DDEV commands on the host.\n\nSuggested installation on Debian/Ubuntu:\n  sudo apt install make\n\n' >&2
  prompt_yes_no 'Generate the Makefile anyway?' N
  if [[ "$ANSWER" == n ]]; then
    ENABLE_MAKEFILE=n
    MAKEFILE_SKIP_REASON='host `make` not available'
  fi
fi
answer_or_prompt_yes_no development.editorconfig 'Generate .editorconfig?' Y; ENABLE_EDITORCONFIG="$ANSWER"
answer_or_prompt_yes_no development.env_example 'Generate .env.local.example?' Y; ENABLE_ENV_TEMPLATE="$ANSWER"

add_generated ".ddev/config.yaml"
[[ "$ENABLE_PHP_SETTINGS" == y ]] && add_generated ".ddev/php/99-development.ini"
[[ "$ENABLE_REDIS_SERVICE" == y ]] && add_generated ".ddev/docker-compose.redis.yaml"
if [[ "$ENABLE_OTEL" == y ]]; then add_generated ".ddev/docker-compose.otel.yaml"; add_generated ".ddev/otel/collector-config.yaml"; fi
if [[ "$ENABLE_MAKEFILE" == y ]]; then
  [[ -e "$TARGET_DIR/Makefile" ]] && add_skipped "Makefile (existing)" || add_generated Makefile
elif [[ -n "$MAKEFILE_SKIP_REASON" ]]; then
  add_skipped "Makefile ............ $MAKEFILE_SKIP_REASON"
fi
if [[ "$ENABLE_EDITORCONFIG" == y ]]; then [[ -e "$TARGET_DIR/.editorconfig" ]] && add_skipped ".editorconfig (existing)" || add_generated .editorconfig; fi
if [[ "$ENABLE_ENV_TEMPLATE" == y ]]; then [[ -e "$TARGET_DIR/.env.local.example" ]] && add_skipped ".env.local.example (existing)" || add_generated .env.local.example; fi

if ! "$DRY_RUN"; then
  mkdir -p "$TARGET_DIR/.ddev"
  cat > "$TARGET_DIR/.ddev/config.yaml" <<EOF
# Generated by ddev-blueprint. Review before committing.
name: $PROJECT_NAME
type: php
docroot: $DOCROOT
php_version: "$PHP_VERSION"
webserver_type: $WEBSERVER
EOF
  if [[ "$DB_TYPE" == none ]]; then printf '\nomit_containers:\n  - db\n' >> "$TARGET_DIR/.ddev/config.yaml"; else
    printf '\ndatabase:\n  type: %s\n  version: "%s"\n' "$DB_TYPE" "$DB_VERSION" >> "$TARGET_DIR/.ddev/config.yaml"
    [[ -n "$HOST_DB_PORT" ]] && printf '\nhost_db_port: "%s"\n' "$HOST_DB_PORT" >> "$TARGET_DIR/.ddev/config.yaml"
  fi
  if (( ${#HOSTNAMES[@]} )); then printf '\nadditional_hostnames:\n' >> "$TARGET_DIR/.ddev/config.yaml"; printf '  - "%s"\n' "${HOSTNAMES[@]}" >> "$TARGET_DIR/.ddev/config.yaml"; fi
  if (( ${#FQDNS[@]} )); then printf '\nadditional_fqdns:\n' >> "$TARGET_DIR/.ddev/config.yaml"; printf '  - "%s"\n' "${FQDNS[@]}" >> "$TARGET_DIR/.ddev/config.yaml"; fi
  if (( ${#PACKAGES[@]} )); then printf '\nwebimage_extra_packages:\n' >> "$TARGET_DIR/.ddev/config.yaml"; printf '  - %s\n' "${PACKAGES[@]}" >> "$TARGET_DIR/.ddev/config.yaml"; fi
  printf '\nweb_environment:\n  - APP_ENV=development\n' >> "$TARGET_DIR/.ddev/config.yaml"
  if [[ "$ENABLE_PHP_SETTINGS" == y ]]; then
    mkdir -p "$TARGET_DIR/.ddev/php"
    cat > "$TARGET_DIR/.ddev/php/99-development.ini" <<'EOF'
; Recommended local PHP development settings.
[opcache]
opcache.enable = 1
opcache.validate_timestamps = 1
opcache.revalidate_freq = 0
opcache.jit = 0
realpath_cache_size = 4096K
realpath_cache_ttl = 600
EOF
  fi
  if [[ "$ENABLE_REDIS_SERVICE" == y ]]; then
    cat > "$TARGET_DIR/.ddev/docker-compose.redis.yaml" <<EOF
services:
  redis:
    container_name: "ddev-\${DDEV_SITENAME}-redis"
    image: "redis:$REDIS_TAG"
    restart: "no"
    expose: ["6379"]
EOF
  fi
  if [[ "$ENABLE_OTEL" == y ]]; then
    mkdir -p "$TARGET_DIR/.ddev/otel"
    cat > "$TARGET_DIR/.ddev/docker-compose.otel.yaml" <<EOF
services:
  otel-collector:
    container_name: "ddev-\${DDEV_SITENAME}-otel-collector"
    image: "otel/opentelemetry-collector-contrib:$DEFAULT_OTEL_VERSION"
    restart: "no"
    command: ["--config=/etc/otelcol-contrib/config.yaml"]
    expose: ["4317", "4318"]
    volumes: ["./otel/collector-config.yaml:/etc/otelcol-contrib/config.yaml:ro"]
EOF
    cat > "$TARGET_DIR/.ddev/otel/collector-config.yaml" <<'EOF'
receivers:
  otlp:
    protocols:
      grpc: { endpoint: 0.0.0.0:4317 }
      http: { endpoint: 0.0.0.0:4318 }
processors:
  batch: {}
exporters:
  debug:
    verbosity: basic
service:
  pipelines:
    traces: { receivers: [otlp], processors: [batch], exporters: [debug] }
    metrics: { receivers: [otlp], processors: [batch], exporters: [debug] }
    logs: { receivers: [otlp], processors: [batch], exporters: [debug] }
EOF
  fi
  if [[ "$ENABLE_MAKEFILE" == y && ! -e "$TARGET_DIR/Makefile" ]]; then
    MAKE_TARGETS=(help start stop restart status shell logs composer-install)
    MAKE_DESCRIPTIONS=(
      'Show available targets'
      'Start the DDEV project'
      'Stop the DDEV project'
      'Restart the DDEV project'
      'Show DDEV project status'
      'Open a shell in the web container'
      'Follow DDEV logs'
      'Install Composer dependencies'
    )
    [[ -e "$TARGET_DIR/vendor/bin/phpstan" ]] && { MAKE_TARGETS+=(phpstan); MAKE_DESCRIPTIONS+=('Run PHPStan'); }
    [[ -e "$TARGET_DIR/vendor/bin/phpcs" ]] && { MAKE_TARGETS+=(phpcs); MAKE_DESCRIPTIONS+=('Run PHP_CodeSniffer'); }
    [[ -e "$TARGET_DIR/phpunit.xml" || -e "$TARGET_DIR/phpunit.xml.dist" ]] && { MAKE_TARGETS+=(test); MAKE_DESCRIPTIONS+=('Run PHPUnit'); }
    [[ -e "$TARGET_DIR/bin/console" ]] && { MAKE_TARGETS+=(console); MAKE_DESCRIPTIONS+=('Run the Symfony console'); }
    [[ -e "$TARGET_DIR/artisan" ]] && { MAKE_TARGETS+=(artisan); MAKE_DESCRIPTIONS+=('Run Laravel Artisan'); }
    if [[ -e "$TARGET_DIR/package.json" ]]; then
      MAKE_TARGETS+=(npm-install); MAKE_DESCRIPTIONS+=('Install npm dependencies')
      if command -v jq >/dev/null 2>&1 && jq -e '.scripts.build? != null' "$TARGET_DIR/package.json" >/dev/null 2>&1; then
        MAKE_TARGETS+=(npm-build); MAKE_DESCRIPTIONS+=('Build frontend assets')
      elif ! command -v jq >/dev/null 2>&1; then
        add_skipped 'npm-build (jq unavailable)'
      fi
    fi
    {
      printf '.PHONY: %s\n\n' "${MAKE_TARGETS[*]}"
      printf 'help:\n\t@printf '\''Available targets:\\n'\''\n'
      for index in "${!MAKE_TARGETS[@]}"; do
        printf "\t@printf '  %%-18s %%s\\\\n' '%s' '%s'\n" "${MAKE_TARGETS[$index]}" "${MAKE_DESCRIPTIONS[$index]}"
      done
      printf '\nstart:\n\tddev start\n\nstop:\n\tddev stop\n\nrestart:\n\tddev restart\n\nstatus:\n\tddev describe\n\nshell:\n\tddev ssh\n\nlogs:\n\tddev logs -f\n\ncomposer-install:\n\tddev composer install\n'
      [[ -e "$TARGET_DIR/vendor/bin/phpstan" ]] && printf '\nphpstan:\n\tddev exec -- vendor/bin/phpstan\n'
      [[ -e "$TARGET_DIR/vendor/bin/phpcs" ]] && printf '\nphpcs:\n\tddev exec -- vendor/bin/phpcs\n'
      [[ -e "$TARGET_DIR/phpunit.xml" || -e "$TARGET_DIR/phpunit.xml.dist" ]] && printf '\ntest:\n\tddev exec -- vendor/bin/phpunit\n'
      [[ -e "$TARGET_DIR/bin/console" ]] && printf '\nconsole:\n\tddev exec -- bin/console\n'
      [[ -e "$TARGET_DIR/artisan" ]] && printf '\nartisan:\n\tddev exec -- php artisan\n'
      if [[ -e "$TARGET_DIR/package.json" ]]; then
        printf '\nnpm-install:\n\tddev exec -- npm install\n'
        [[ " ${MAKE_TARGETS[*]} " == *' npm-build '* ]] && printf '\nnpm-build:\n\tddev exec -- npm run build\n'
      fi
    } > "$TARGET_DIR/Makefile"
  fi
  if [[ "$ENABLE_EDITORCONFIG" == y && ! -e "$TARGET_DIR/.editorconfig" ]]; then
    cat > "$TARGET_DIR/.editorconfig" <<'EOF'
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
indent_style = space
indent_size = 4

[*.{yml,yaml}]
indent_size = 2
EOF
  fi
  if [[ "$ENABLE_ENV_TEMPLATE" == y && ! -e "$TARGET_DIR/.env.local.example" ]]; then
    printf '# Example local environment values.\nAPP_ENV=development\n' > "$TARGET_DIR/.env.local.example"
    if [[ "$DB_TYPE" != none ]]; then
      printf '\nDB_HOST=db\nDB_PORT=%s\nDB_NAME=db\nDB_USER=db\nDB_PASSWORD=db\n' "$([[ "$DB_TYPE" == postgres ]] && printf 5432 || printf 3306)" >> "$TARGET_DIR/.env.local.example"
    fi
    [[ "$ENABLE_REDIS_SERVICE" == y ]] && printf '\nREDIS_HOST=redis\nREDIS_PORT=6379\n' >> "$TARGET_DIR/.env.local.example"
    [[ "$ENABLE_OTEL" == y ]] && printf '\nOTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318\n' >> "$TARGET_DIR/.env.local.example"
  fi
fi

if "$DRY_RUN"; then
  printf '\nDDEV Blueprint dry run completed\nNo files were written.\n'
else
  printf '\nDDEV Blueprint completed successfully\n'
fi
printf '\nProject:\n  Name ............... %s\n  Target ............. %s\n' "$PROJECT_NAME" "$TARGET_DIR"
printf '\nDDEV:\n  PHP ................ %s\n  Web server ......... %s\n  Document root ...... %s\n' "$PHP_VERSION" "$WEBSERVER" "$DOCROOT"
if [[ "$DB_TYPE" == none ]]; then printf '  Database ........... disabled\n'; else printf '  Database ........... %s %s\n' "$DB_TYPE" "$DB_VERSION"; fi
if (( ${#HOSTNAMES[@]} )); then printf '  Hostnames .......... %s\n' "$(join_by ', ' "${HOSTNAMES[@]}")"; fi
if (( ${#FQDNS[@]} )); then printf '  FQDNs .............. %s\n' "$(join_by ', ' "${FQDNS[@]}")"; fi
ALL_EXTENSIONS=("${EXTENSIONS[@]}" "${DB_EXTENSIONS[@]}")
if (( ${#ALL_EXTENSIONS[@]} )); then
  printf '\nPHP extensions:\n  %s\n' "$(join_by ', ' "${ALL_EXTENSIONS[@]}")"
fi
if [[ "$ENABLE_MAKEFILE" == y && -e "$TARGET_DIR/Makefile" && ! "$DRY_RUN" ]]; then MAKEFILE_STATUS='skipped (existing)'; elif [[ "$ENABLE_MAKEFILE" == y ]]; then MAKEFILE_STATUS="$([[ "$DRY_RUN" == true ]] && printf 'planned (host make)' || printf 'generated (host make)')"; elif [[ -n "$MAKEFILE_SKIP_REASON" ]]; then MAKEFILE_STATUS=skipped; else MAKEFILE_STATUS=disabled; fi
if [[ "$ENABLE_EDITORCONFIG" == y && -e "$TARGET_DIR/.editorconfig" && ! "$DRY_RUN" ]]; then EDITORCONFIG_STATUS='skipped (existing)'; elif [[ "$ENABLE_EDITORCONFIG" == y ]]; then EDITORCONFIG_STATUS="$([[ "$DRY_RUN" == true ]] && printf planned || printf generated)"; else EDITORCONFIG_STATUS=disabled; fi
if [[ "$ENABLE_ENV_TEMPLATE" == y && -e "$TARGET_DIR/.env.local.example" && ! "$DRY_RUN" ]]; then ENV_STATUS='skipped (existing)'; elif [[ "$ENABLE_ENV_TEMPLATE" == y ]]; then ENV_STATUS="$([[ "$DRY_RUN" == true ]] && printf planned || printf generated)"; else ENV_STATUS=disabled; fi
printf '\nDevelopment:\n  Standard tools ..... %s\n  OPcache ............ %s\n  Xdebug ............. disabled\n  Makefile ........... %s\n  .editorconfig ...... %s\n  Env example ........ %s\n' "$([[ "$ENABLE_DEV_TOOLS" == y ]] && printf enabled || printf disabled)" "$([[ "$ENABLE_PHP_SETTINGS" == y ]] && printf enabled || printf disabled)" "$MAKEFILE_STATUS" "$EDITORCONFIG_STATUS" "$ENV_STATUS"
if [[ "$ENABLE_REDIS_SERVICE" == y || "$ENABLE_OTEL" == y ]]; then
  printf '\nServices:\n'
  if [[ "$ENABLE_REDIS_SERVICE" == y ]]; then printf '  Redis .............. redis:%s\n' "$REDIS_TAG"; fi
  if [[ "$ENABLE_OTEL" == y ]]; then printf '  OpenTelemetry ...... enabled\n'; fi
fi
if (( ${#GENERATED[@]} )); then printf '\nGenerated:\n'; printf '  %s\n' "${GENERATED[@]}"; fi
if (( ${#SKIPPED[@]} )); then printf '\nSkipped:\n'; printf '  %s\n' "${SKIPPED[@]}"; fi
printf '\nNext steps:\n  cd %s\n  ddev start\n' "$TARGET_DIR"
if [[ "$ENABLE_MAKEFILE" == y ]] && { "$DRY_RUN" || [[ ! -e "$TARGET_DIR/Makefile" ]]; }; then printf '  make composer-install\n'; fi
