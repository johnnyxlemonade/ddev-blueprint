#!/usr/bin/env bash
# Compatibility matrix. Keep supported platform choices and their associated
# packages/drivers here so validators, configuration, and rendering agree.
readonly -a BP_SUPPORTED_PHP_VERSIONS=("8.0" "8.1" "8.2" "8.3" "8.4" "8.5")
readonly -a BP_SUPPORTED_WEBSERVERS=("apache-fpm" "nginx-fpm")
readonly -a BP_SUPPORTED_DATABASES=("mariadb" "mysql" "postgres" "none")
readonly -a BP_SUPPORTED_REDIS_TAGS=(
  "6.2-alpine" "7.2-alpine" "7.4-alpine" "8.0-alpine" "8.2-alpine"
  "8.4-alpine" "8.6-alpine" "8.8-alpine" "8.10-alpine"
)
readonly -a BP_SUPPORTED_MARIADB_VERSIONS=(
  "5.5" "10.0" "10.1" "10.2" "10.3" "10.4" "10.5" "10.6" "10.7" "10.8"
  "10.11" "11.4" "11.8" "12.3"
)
readonly -a BP_SUPPORTED_MYSQL_VERSIONS=("5.5" "5.6" "5.7" "8.0" "8.4" "9.7")
readonly -a BP_SUPPORTED_POSTGRES_VERSIONS=("9" "10" "11" "12" "13" "14" "15" "16" "17" "18")
readonly -a BP_SUPPORTED_OPTIONAL_EXTENSIONS=(
  "redis" "apcu" "memcached" "gd" "imagick" "imap" "intl" "soap"
  "bcmath" "gmp" "pcntl" "exif" "ldap" "xsl" "tidy" "snmp"
)

bp_capability_in_list() {
  local needle="$1"
  shift
  local value
  for value in "$@"; do
    [[ "$value" == "$needle" ]] && return 0
  done
  return 1
}

bp_capability_supports_php_version() {
  bp_capability_in_list "$1" "${BP_SUPPORTED_PHP_VERSIONS[@]}"
}

bp_capability_supports_webserver() {
  bp_capability_in_list "$1" "${BP_SUPPORTED_WEBSERVERS[@]}"
}

bp_capability_supports_database() {
  bp_capability_in_list "$1" "${BP_SUPPORTED_DATABASES[@]}"
}

bp_capability_redis_tags() { printf '%s\n' "${BP_SUPPORTED_REDIS_TAGS[@]}"; }
bp_capability_supports_redis_tag() { bp_capability_in_list "$1" "${BP_SUPPORTED_REDIS_TAGS[@]}"; }

bp_capability_database_uses_version() {
  case "$1" in
    mariadb|mysql|postgres) return 0 ;;
    *) return 1 ;;
  esac
}

bp_capability_database_versions() {
  case "$1" in
    mariadb) printf '%s\n' "${BP_SUPPORTED_MARIADB_VERSIONS[@]}" ;;
    mysql) printf '%s\n' "${BP_SUPPORTED_MYSQL_VERSIONS[@]}" ;;
    postgres) printf '%s\n' "${BP_SUPPORTED_POSTGRES_VERSIONS[@]}" ;;
    *) return 1 ;;
  esac
}

bp_capability_supports_database_version() {
  local database_type="$1" version="$2"
  case "$database_type" in
    mariadb) bp_capability_in_list "$version" "${BP_SUPPORTED_MARIADB_VERSIONS[@]}" ;;
    mysql) bp_capability_in_list "$version" "${BP_SUPPORTED_MYSQL_VERSIONS[@]}" ;;
    postgres) bp_capability_in_list "$version" "${BP_SUPPORTED_POSTGRES_VERSIONS[@]}" ;;
    *) return 1 ;;
  esac
}

bp_capability_database_extensions() {
  case "$1" in
    mariadb|mysql) printf '%s\n' mysqli pdo_mysql ;;
    postgres) printf '%s\n' pgsql pdo_pgsql ;;
    none) ;;
    *) return 1 ;;
  esac
}

bp_capability_supports_optional_extension() {
  bp_capability_in_list "$1" "${BP_SUPPORTED_OPTIONAL_EXTENSIONS[@]}"
}

bp_capability_extension_package() {
  case "$1" in
    redis|apcu|memcached|gd|imagick|imap|intl|soap|bcmath|gmp|ldap|tidy|snmp)
      printf 'php%s-%s\n' "\${DDEV_PHP_VERSION}" "$1"
      ;;
    xsl) printf 'php%s-xml\n' "\${DDEV_PHP_VERSION}" ;;
    # PCNTL and EXIF are part of DDEV's standard PHP build.
    pcntl|exif) ;;
    *) return 1 ;;
  esac
}
