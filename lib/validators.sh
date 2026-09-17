#!/usr/bin/env bash

bp_valid_project_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; }
bp_valid_php_version() { bp_capability_supports_php_version "$1"; }
bp_valid_webserver() { bp_capability_supports_webserver "$1"; }
bp_valid_docroot() { [[ "$1" == . || "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*([/][A-Za-z0-9][A-Za-z0-9._-]*)*$ ]]; }
bp_valid_db_type() { bp_capability_supports_database "$1"; }
bp_valid_db_version() { bp_capability_supports_database_version "$DB_TYPE" "$1"; }
bp_valid_version() { [[ "$1" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; }
bp_valid_port() { [[ "$1" =~ ^[1-9][0-9]{0,4}$ ]] && (( 10#$1 <= 65535 )); }
bp_valid_redis_tag() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; }
bp_normalize_redis_tag() { local tag="$1"; [[ -z "$tag" || "$tag" == default ]] && tag="$DEFAULT_REDIS_TAG"; bp_valid_redis_tag "$tag" || return 1; printf '%s' "$tag"; }
bp_redis_tag_classification() { bp_capability_supports_redis_tag "$1" && printf supported || printf 'custom override'; }
bp_valid_hostname() { local value="$1" label; [[ ${#value} -le 253 && "$value" != *..* && "$value" != .* && "$value" != *. ]] || return 1; IFS='.' read -r -a labels <<< "$value"; for label in "${labels[@]}"; do [[ "$label" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || return 1; done; }
bp_trim() { local value="$1"; value="${value#"${value%%[![:space:]]*}"}"; printf '%s' "${value%"${value##*[![:space:]]}"}"; }
bp_set_hostnames() { local value="$1" raw host; HOSTNAMES=(); FQDNS=(); [[ -z "$value" ]] && return 0; local -a entries=(); IFS=',' read -r -a entries <<< "$value"; for raw in "${entries[@]}"; do host="$(bp_trim "$raw")"; bp_valid_hostname "$host" || return 1; if [[ "$host" == *.* ]]; then FQDNS+=("$host"); else HOSTNAMES+=("$host"); fi; done; }
