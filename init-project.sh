#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/defaults.sh
source "$SCRIPT_DIR/lib/defaults.sh"
# shellcheck source=lib/capabilities.sh
source "$SCRIPT_DIR/lib/capabilities.sh"
# shellcheck source=lib/validators.sh
source "$SCRIPT_DIR/lib/validators.sh"
# shellcheck source=lib/cli.sh
source "$SCRIPT_DIR/lib/cli.sh"
# shellcheck source=lib/input.sh
source "$SCRIPT_DIR/lib/input.sh"
# shellcheck source=lib/answers.sh
source "$SCRIPT_DIR/lib/answers.sh"
# shellcheck source=lib/extensions.sh
source "$SCRIPT_DIR/lib/extensions.sh"
# shellcheck source=lib/configure.sh
source "$SCRIPT_DIR/lib/configure.sh"
# shellcheck source=lib/render.sh
source "$SCRIPT_DIR/lib/render.sh"
# shellcheck source=lib/report.sh
source "$SCRIPT_DIR/lib/report.sh"

declare -A ANSWERS=()
GENERATED=()
SKIPPED=()
HOSTNAMES=()
FQDNS=()
PACKAGES=()
EXTENSIONS=()
DB_EXTENSIONS=()

bp_parse_cli "$@"
bp_prepare_target

if "$ANSWERS_MODE"; then
  bp_load_answers
fi

bp_configure_project
bp_plan_project

if ! "$DRY_RUN"; then
  bp_render_project
fi

bp_print_report
