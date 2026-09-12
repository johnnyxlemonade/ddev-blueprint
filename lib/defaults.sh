#!/usr/bin/env bash

BP_VERSION="0.1.0"
[[ -r "$SCRIPT_DIR/VERSION" ]] && IFS= read -r BP_VERSION < "$SCRIPT_DIR/VERSION"
readonly BP_VERSION
readonly DEFAULT_PHP_VERSION="8.4" DEFAULT_WEBSERVER="apache-fpm"
readonly DEFAULT_DB_TYPE="mariadb"
readonly -A BP_DEFAULT_DATABASE_VERSIONS=(
  [mariadb]="11.8"
  [mysql]="8.4"
  [postgres]="17"
)
readonly DEFAULT_REDIS_TAG="7.4-alpine" DEFAULT_OTEL_VERSION="0.160.0"
readonly DEFAULT_DOCROOT="public"
readonly -a DEFAULT_OPTIONAL_EXTENSIONS=("intl" "gd")
