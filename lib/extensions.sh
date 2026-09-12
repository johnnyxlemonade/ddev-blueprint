#!/usr/bin/env bash

bp_extension_package() { bp_capability_extension_package "$1"; }
bp_is_supported_optional_extension() { bp_capability_supports_optional_extension "$1"; }
bp_add_package() { local package="$1" current; for current in "${PACKAGES[@]}"; do [[ "$current" == "$package" ]] && return; done; PACKAGES+=("$package"); }
bp_set_extensions() { local value="$1" raw extension package; local -a entries=(); EXTENSIONS=(); value="$(bp_trim "$value")"; [[ "$value" == none ]] && return 0; IFS=',' read -r -a entries <<< "$value"; for raw in "${entries[@]}"; do extension="$(bp_trim "$raw")"; if ! bp_is_supported_optional_extension "$extension"; then printf 'Unknown PHP extension: %s. Supported values: %s, none.\n' "$extension" "${BP_SUPPORTED_OPTIONAL_EXTENSIONS[*]}" >&2; EXTENSIONS=(); return 1; fi; if [[ " ${EXTENSIONS[*]} " != *" $extension "* ]]; then EXTENSIONS+=("$extension"); fi; done; for extension in "${EXTENSIONS[@]}"; do package="$(bp_extension_package "$extension")" || true; [[ -z "$package" ]] || bp_add_package "$package"; done; }
bp_set_db_extensions() { mapfile -t DB_EXTENSIONS < <(bp_capability_database_extensions "$DB_TYPE"); }
