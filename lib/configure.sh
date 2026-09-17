#!/usr/bin/env bash
# Collect answers in the established public question order and turn them into
# normalized project state. Prompt functions transparently consume ANSWERS in
# non-interactive mode, so both paths use the same validators.
bp_configure_project_identity() {
  bp_answer_or_prompt_value project.name 'DDEV project name' "$DEFAULT_NAME" bp_valid_project_name
  PROJECT_NAME="$ANSWER"
  bp_answer_or_prompt_value project.docroot 'Document root' "$DEFAULT_DOCROOT" bp_valid_docroot
  DOCROOT="$ANSWER"
  [[ "$DOCROOT" == . ]] && DOCROOT=""
  bp_answer_or_prompt_value project.php 'PHP version' "$DEFAULT_PHP_VERSION" bp_valid_php_version
  PHP_VERSION="$ANSWER"
  bp_answer_or_prompt_value project.webserver 'Webserver (apache-fpm/nginx-fpm)' "$DEFAULT_WEBSERVER" bp_valid_webserver
  WEBSERVER="$ANSWER"
}

bp_configure_database() {
  bp_answer_or_prompt_value database.type 'Database (mariadb/mysql/postgres/none)' "$DEFAULT_DB_TYPE" bp_valid_db_type
  DB_TYPE="$ANSWER"
  DB_VERSION=""
  HOST_DB_PORT=""

  [[ "$DB_TYPE" != none ]] || return 0

  local default_version="${BP_DEFAULT_DATABASE_VERSIONS[$DB_TYPE]}"
  bp_answer_or_prompt_value database.version 'Database version' "$default_version" bp_valid_db_version
  DB_VERSION="$ANSWER"

  if "$ANSWERS_MODE"; then
    HOST_DB_PORT="${ANSWERS[database.host_port]}"
    [[ -z "$HOST_DB_PORT" ]] || bp_valid_port "$HOST_DB_PORT" || bp_die 'Invalid answer value: database.host_port'
  else
    bp_prompt_port
    HOST_DB_PORT="$ANSWER"
  fi
}

bp_configure_hostnames() {
  local hostname_input
  if "$ANSWERS_MODE"; then
    hostname_input="${ANSWERS[hostnames.additional]}"
    if [[ -n "${ANSWERS[hostnames.fqdns]}" ]]; then
      [[ -z "$hostname_input" ]] || hostname_input+=','
      hostname_input+="${ANSWERS[hostnames.fqdns]}"
    fi
    bp_set_hostnames "$hostname_input" || bp_die 'Invalid answer value: hostnames'
  else
    bp_prompt_hostnames
  fi
}

bp_configure_redis() {
  bp_answer_or_prompt_yes_no services.redis.enabled 'Add Redis service?' N
  ENABLE_REDIS_SERVICE="$ANSWER"
  REDIS_TAG=""
  [[ "$ENABLE_REDIS_SERVICE" == y ]] || return 0

  if "$ANSWERS_MODE"; then
    local redis_image="${ANSWERS[services.redis.image]}"
    if [[ "$redis_image" == default ]]; then
      REDIS_TAG=default
    elif [[ "$redis_image" == redis:* ]]; then
      REDIS_TAG="${redis_image#redis:}"
    else
      bp_die 'Invalid answer value: services.redis.image'
    fi
  else
    bp_prompt_value 'Redis image tag' "$DEFAULT_REDIS_TAG" bp_valid_redis_tag
    REDIS_TAG="$ANSWER"
  fi
  REDIS_TAG="$(bp_normalize_redis_tag "$REDIS_TAG")" || bp_die 'Invalid answer value: services.redis.image'
}

bp_configure_extensions_and_tools() {
  PACKAGES=()
  EXTENSIONS=()
  if [[ "$ENABLE_DEV_TOOLS" == y ]]; then
    bp_add_package make
    bp_add_package ripgrep
    bp_add_package jq
  fi
  if "$ANSWERS_MODE"; then
    bp_set_extensions "${ANSWERS[php.extensions]}" || bp_die 'Invalid answer value: php.extensions'
  else
    bp_prompt_extensions
  fi
  bp_set_db_extensions
}

bp_configure_makefile() {
  bp_answer_or_prompt_yes_no development.makefile 'Generate development Makefile?' Y
  ENABLE_MAKEFILE="$ANSWER"
  MAKEFILE_SKIP_REASON=""
  [[ "$ENABLE_MAKEFILE" == y ]] || return 0
  command -v make >/dev/null 2>&1 && return 0

  if "$ANSWERS_MODE"; then
    bp_die 'development.makefile=true requires host command `make`. Install it first or set development.makefile=false.'
  fi
  printf '\nHost `make` is not installed.\nThe generated Makefile runs DDEV commands on the host.\n\nSuggested installation on Debian/Ubuntu:\n  sudo apt install make\n\n' >&2
  bp_prompt_yes_no 'Generate the Makefile anyway?' N
  if [[ "$ANSWER" == n ]]; then
    ENABLE_MAKEFILE=n
    MAKEFILE_SKIP_REASON='host `make` not available'
  fi
}

bp_configure_project() {
  bp_configure_project_identity
  bp_configure_database
  bp_configure_hostnames
  bp_answer_or_prompt_yes_no development.tools 'Include standard development tools?' Y
  ENABLE_DEV_TOOLS="$ANSWER"
  bp_configure_redis
  bp_configure_extensions_and_tools
  bp_answer_or_prompt_yes_no services.opentelemetry.enabled 'Add local OpenTelemetry Collector?' N
  ENABLE_OTEL="$ANSWER"
  bp_answer_or_prompt_yes_no php.development_settings 'Configure recommended PHP development settings?' Y
  ENABLE_PHP_SETTINGS="$ANSWER"
  bp_configure_makefile
  bp_answer_or_prompt_yes_no development.editorconfig 'Generate .editorconfig?' Y
  ENABLE_EDITORCONFIG="$ANSWER"
  bp_answer_or_prompt_yes_no development.env_example 'Generate .env.local.example?' Y
  ENABLE_ENV_TEMPLATE="$ANSWER"
}
