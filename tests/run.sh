#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATOR="$ROOT/init-project.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ddev-blueprint-tests.XXXXXX")"
FAKE_BIN="$WORK/bin"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$FAKE_BIN"
printf '%s\n' '#!/usr/bin/env sh' 'last=""' 'for arg in "$@"; do last="$arg"; done' 'grep -q ""build"" "$last"' > "$FAKE_BIN/jq"
chmod +x "$FAKE_BIN/jq"
printf '%s\n' '#!/usr/bin/env sh' 'exit 0' > "$FAKE_BIN/make"
chmod +x "$FAKE_BIN/make"

pass=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { pass=$((pass + 1)); printf 'ok %d - %s\n' "$pass" "$1"; }
assert_file() { [[ -f "$1" ]] || fail "missing file: $1"; }
assert_absent() { [[ ! -e "$1" ]] || fail "unexpected path: $1"; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "expected $2 in $1"; }
assert_not_contains() { ! grep -Fq -- "$2" "$1" || fail "did not expect $2 in $1"; }
run_generator() { local target="$1" output="$2"; env PATH="$FAKE_BIN:$PATH" "$GENERATOR" "$target" >"$output"; }
NO_MAKE_ENV="$WORK/no-host-make.bash"
printf '%s\n' 'command() {' '  if [[ "$1" == -v && "$2" == make ]]; then return 1; fi' '  builtin command "$@"' '}' > "$NO_MAKE_ENV"
run_generator_without_make() { local target="$1" output="$2"; env BASH_ENV="$NO_MAKE_ENV" PATH="$FAKE_BIN:$PATH" "$GENERATOR" "$target" >"$output"; }
validate_yaml() {
  local target="$1"
  (cd "$target" && ddev debug configyaml >/dev/null)
  for compose in "$target"/.ddev/docker-compose.*.yaml; do
    [[ -e "$compose" ]] || continue
    env DDEV_SITENAME=test docker compose -f "$compose" config -q
  done
}
answers_default() {
  printf '%s\n' "$1" public 8.4 apache-fpm mariadb 11.8 "" "" y n "" n y y y y
}
answers_none() {
  printf '%s\n' "$1" public 8.4 apache-fpm none "" y n "" n y y y y
}

# The generator has no mandatory host-tool preflight dependency.
preflight_target="$WORK/preflight"
printf '%s\n' preflight-app public 8.4 apache-fpm mariadb 11.8 '' '' y n '' n y y n y y | env PATH="/usr/bin:/bin" "$GENERATOR" --dry-run "$preflight_target" >"$WORK/preflight.out"
assert_contains "$WORK/preflight.out" 'DDEV Blueprint dry run completed'
assert_contains "$WORK/preflight.out" 'No files were written.'
ok 'generation works without optional host tools'

default_target="$WORK/default"; answers_default default-app | run_generator "$default_target" "$WORK/default.out"
assert_contains "$default_target/.ddev/config.yaml" '  - make'
assert_contains "$default_target/.ddev/config.yaml" '  - ripgrep'
assert_contains "$default_target/.ddev/config.yaml" '  - jq'
assert_file "$default_target/.ddev/php/99-development.ini"
assert_contains "$default_target/.ddev/php/99-development.ini" 'opcache.jit = 0'
assert_file "$default_target/Makefile"; assert_file "$default_target/.editorconfig"; assert_file "$default_target/.env.local.example"
assert_contains "$default_target/Makefile" 'composer-install:'
for target in help start stop restart status shell logs composer-install; do assert_contains "$default_target/Makefile" "$target:"; done
assert_contains "$default_target/Makefile" 'Available targets:'
assert_not_contains "$default_target/Makefile" 'phpstan:'
assert_contains "$WORK/default.out" 'DDEV Blueprint completed successfully'
assert_contains "$WORK/default.out" 'OPcache ............ enabled'
assert_contains "$WORK/default.out" 'PHP extensions:'
assert_contains "$WORK/default.out" 'intl, gd, mysqli, pdo_mysql'
assert_not_contains "$WORK/default.out" 'Skipped:'
assert_contains "$default_target/.ddev/config.yaml" 'php${DDEV_PHP_VERSION}-intl'
assert_contains "$default_target/.ddev/config.yaml" 'php${DDEV_PHP_VERSION}-gd'
validate_yaml "$default_target"
ok 'default developer tooling, PHP settings, generated files, summary and YAML'

no_tools_target="$WORK/no-tools"
{
  printf '%s\n' no-tools public 8.4 apache-fpm none "" n n none n n n n n
} | run_generator "$no_tools_target" "$WORK/no-tools.out"
assert_absent "$no_tools_target/.ddev/php/99-development.ini"
if grep -Fq 'ripgrep' "$no_tools_target/.ddev/config.yaml"; then fail 'tools=no must not add tool packages'; fi
assert_absent "$no_tools_target/Makefile"; assert_absent "$no_tools_target/.editorconfig"; assert_absent "$no_tools_target/.env.local.example"
assert_contains "$WORK/no-tools.out" 'OPcache ............ disabled'
ok 'developer tools and optional generated files can be disabled'

no_host_make_target="$WORK/no-host-make"
printf '%s\n' no-host-make public 8.4 apache-fpm none '' y n none n y y n y y | env BASH_ENV="$NO_MAKE_ENV" PATH="$FAKE_BIN:$PATH" "$GENERATOR" "$no_host_make_target" >"$WORK/no-host-make.out" 2>&1
assert_absent "$no_host_make_target/Makefile"
assert_contains "$WORK/no-host-make.out" 'Host `make` is not installed.'
assert_contains "$WORK/no-host-make.out" 'Makefile ............ host `make` not available'
assert_contains "$WORK/no-host-make.out" 'Makefile ........... skipped'
ok 'interactive mode skips Makefile when host make is unavailable and declined'

no_host_make_dry_target="$WORK/no-host-make-dry"
printf '%s\n' no-host-make-dry public 8.4 apache-fpm none '' y n none n y y n y y | env BASH_ENV="$NO_MAKE_ENV" PATH="$FAKE_BIN:$PATH" "$GENERATOR" --dry-run "$no_host_make_dry_target" >"$WORK/no-host-make-dry.out" 2>&1
assert_absent "$no_host_make_dry_target"
assert_contains "$WORK/no-host-make-dry.out" 'Host `make` is not installed.'
assert_contains "$WORK/no-host-make-dry.out" 'No files were written.'
ok 'interactive dry-run applies the host make decision'

extensions_target="$WORK/extensions"
printf '%s\n' extensions public 8.5 nginx-fpm none "" n n 'redis, apcu, memcached, gd, imagick, imap, intl, soap, bcmath, gmp, pcntl, exif, ldap, xsl, tidy, snmp' n y n n n | run_generator "$extensions_target" "$WORK/extensions.out"
for extension in redis apcu memcached gd imagick imap intl soap bcmath gmp ldap tidy snmp; do assert_contains "$extensions_target/.ddev/config.yaml" "php\${DDEV_PHP_VERSION}-$extension"; done
assert_contains "$extensions_target/.ddev/config.yaml" 'php${DDEV_PHP_VERSION}-xml'
assert_contains "$WORK/extensions.out" 'PHP ................ 8.5'
assert_contains "$WORK/extensions.out" 'redis, apcu, memcached, gd, imagick, imap, intl, soap, bcmath, gmp, pcntl, exif, ldap, xsl, tidy, snmp'
validate_yaml "$extensions_target"
ok 'all supported optional PHP extensions are selected'

custom_extensions_target="$WORK/custom-extensions"
printf '%s\n' custom-extensions public 8.4 apache-fpm none "" n n ' redis, apcu , gd, redis, exif ' n n n n n | run_generator "$custom_extensions_target" "$WORK/custom-extensions.out"
assert_contains "$WORK/custom-extensions.out" 'redis, apcu, gd, exif'
for extension in redis apcu gd; do assert_contains "$custom_extensions_target/.ddev/config.yaml" "php\${DDEV_PHP_VERSION}-$extension"; done
ok 'custom extensions trim whitespace and remove duplicates'

none_extensions_target="$WORK/none-extensions"
printf '%s\n' none-extensions public 8.4 apache-fpm none "" n n none n n n n n | run_generator "$none_extensions_target" "$WORK/none-extensions.out"
if grep -Fq 'PHP extensions:' "$WORK/none-extensions.out"; then fail 'none must not report an extension section'; fi
if grep -Fq 'php${DDEV_PHP_VERSION}-' "$none_extensions_target/.ddev/config.yaml"; then fail 'none must not add optional PHP packages'; fi
ok 'none disables optional PHP extensions'

invalid_extensions_target="$WORK/invalid-extensions"
if printf '%s\n' invalid-extensions public 8.4 apache-fpm none "" n n does-not-exist | env PATH="$FAKE_BIN:$PATH" "$GENERATOR" "$invalid_extensions_target" >"$WORK/invalid-extensions.out" 2>&1; then
  fail 'unknown extension must fail'
fi
assert_contains "$WORK/invalid-extensions.out" 'Unknown PHP extension: does-not-exist'
assert_absent "$invalid_extensions_target"
ok 'unknown PHP extension is rejected'

mysql_extensions_target="$WORK/mysql-extensions"
printf '%s\n' mysql-extensions public 8.4 apache-fpm mysql 8.4 "" "" n n none n n n n n | run_generator "$mysql_extensions_target" "$WORK/mysql-extensions.out"
assert_contains "$WORK/mysql-extensions.out" 'mysqli, pdo_mysql'
if grep -Fq 'php${DDEV_PHP_VERSION}-mysqli' "$mysql_extensions_target/.ddev/config.yaml"; then fail 'MySQL drivers must not be manually packaged'; fi
ok 'MySQL database extensions are automatic'

postgres_extensions_target="$WORK/postgres-extensions"
printf '%s\n' postgres-extensions public 8.4 apache-fpm postgres 17 "" "" n n none n n n n n | run_generator "$postgres_extensions_target" "$WORK/postgres-extensions.out"
assert_contains "$WORK/postgres-extensions.out" 'pgsql, pdo_pgsql'
if grep -Fq 'php${DDEV_PHP_VERSION}-pgsql' "$postgres_extensions_target/.ddev/config.yaml"; then fail 'PostgreSQL drivers must not be manually packaged'; fi
ok 'PostgreSQL database extensions are automatic'

conditional_target="$WORK/conditional"; mkdir -p "$conditional_target/vendor/bin" "$conditional_target/bin"
touch "$conditional_target/vendor/bin/phpstan" "$conditional_target/vendor/bin/phpcs" "$conditional_target/phpunit.xml" "$conditional_target/bin/console" "$conditional_target/artisan"
printf '%s\n' '{"scripts":{"build":"vite build"}}' > "$conditional_target/package.json"
answers_none conditional-app | run_generator "$conditional_target" "$WORK/conditional.out"
for target in phpstan phpcs test console artisan npm-install npm-build; do assert_contains "$conditional_target/Makefile" "$target:"; done
assert_contains "$conditional_target/Makefile" 'help:'
assert_contains "$conditional_target/Makefile" 'Available targets:'
ok 'conditional Makefile targets'

preserve_target="$WORK/preserve"; mkdir -p "$preserve_target"
printf 'keep-make\n' > "$preserve_target/Makefile"; printf 'keep-editor\n' > "$preserve_target/.editorconfig"; printf 'keep-env\n' > "$preserve_target/.env.local.example"
answers_none preserve-app | run_generator "$preserve_target" "$WORK/preserve.out"
assert_contains "$preserve_target/Makefile" 'keep-make'
assert_contains "$preserve_target/.editorconfig" 'keep-editor'
assert_contains "$preserve_target/.env.local.example" 'keep-env'
assert_contains "$WORK/preserve.out" 'Makefile (existing)'
assert_contains "$WORK/preserve.out" '.editorconfig (existing)'
assert_contains "$WORK/preserve.out" '.env.local.example (existing)'
ok 'existing Makefile, editorconfig and env template are preserved'

none_target="$WORK/none"; answers_none none-app | run_generator "$none_target" "$WORK/none.out"
if grep -Fq 'DB_HOST=' "$none_target/.env.local.example"; then fail 'database=none must not generate DB variables'; fi
ok 'env template excludes DB variables without database'

dry_target="$WORK/dry"
answers_default dry-app | env PATH="$FAKE_BIN:$PATH" "$GENERATOR" --dry-run "$dry_target" >"$WORK/dry.out"
assert_absent "$dry_target"
assert_contains "$WORK/dry.out" 'No files were written.'
assert_contains "$WORK/dry.out" 'Makefile'
assert_contains "$WORK/dry.out" '.editorconfig'
ok 'dry-run writes nothing and reports the plan'

[[ "$("$GENERATOR" --version)" == "0.1.1" ]] || fail 'version output is incorrect'
"$GENERATOR" --help >"$WORK/help.out"
assert_contains "$WORK/help.out" 'Supported PHP: 8.0, 8.1, 8.2, 8.3, 8.4, 8.5 (default: 8.4).'
assert_contains "$WORK/help.out" '--answers FILE'
assert_contains "$WORK/help.out" 'Default extensions: intl,gd.'
ok 'version and help output'

answers_file="$WORK/answers.yaml"
cp "$ROOT/examples/answers.yaml" "$answers_file"
answers_target="$WORK/answers"
env PATH="$FAKE_BIN:$PATH" "$GENERATOR" --answers "$answers_file" "$answers_target" >"$WORK/answers.out"
assert_not_contains "$WORK/answers.out" 'DDEV project name'
assert_contains "$WORK/answers.out" 'Name ............... my-app'
assert_contains "$WORK/answers.out" 'Hostnames .......... docs'
assert_contains "$WORK/answers.out" 'FQDNs .............. api.example.test'
assert_file "$answers_target/.ddev/docker-compose.redis.yaml"
assert_absent "$answers_target/.ddev/docker-compose.otel.yaml"
validate_yaml "$answers_target"
ok 'complete answers file is non-interactive and generates selected services'

if env BASH_ENV="$NO_MAKE_ENV" PATH="$FAKE_BIN:$PATH" "$GENERATOR" --answers "$answers_file" "$WORK/answers-no-host-make" >"$WORK/answers-no-host-make.out" 2>&1; then fail 'answers makefile=true must fail without host make'; fi
assert_contains "$WORK/answers-no-host-make.out" 'development.makefile=true requires host command `make`'
ok 'answers makefile=true fails without host make'

answers_no_make_file="$WORK/answers-no-make.yaml"
sed 's/makefile: true/makefile: false/' "$answers_file" > "$answers_no_make_file"
env BASH_ENV="$NO_MAKE_ENV" PATH="$FAKE_BIN:$PATH" "$GENERATOR" --answers "$answers_no_make_file" "$WORK/answers-no-make" >"$WORK/answers-no-make.out"
assert_absent "$WORK/answers-no-make/Makefile"
assert_contains "$WORK/answers-no-make.out" 'Makefile ........... disabled'
ok 'answers makefile=false does not require host make'

if env BASH_ENV="$NO_MAKE_ENV" PATH="$FAKE_BIN:$PATH" "$GENERATOR" --dry-run --answers "$answers_file" "$WORK/answers-no-host-make-dry" >"$WORK/answers-no-host-make-dry.out" 2>&1; then fail 'answers dry-run makefile=true must fail without host make'; fi
assert_contains "$WORK/answers-no-host-make-dry.out" 'development.makefile=true requires host command `make`'
assert_absent "$WORK/answers-no-host-make-dry"
ok 'answers dry-run consistently requires host make'

interactive_equivalent="$WORK/interactive-equivalent"
printf '%s\n' my-app public 8.4 apache-fpm mariadb 11.8 '' 'docs,api.example.test' y y 7.4-alpine 'intl,gd,redis' n y y y y | run_generator "$interactive_equivalent" "$WORK/interactive-equivalent.out"
cmp "$answers_target/.ddev/config.yaml" "$interactive_equivalent/.ddev/config.yaml" >/dev/null || fail 'answers config must match equivalent interactive input'
ok 'answers and interactive modes share generated configuration'

redis_empty_target="$WORK/redis-empty"
printf '%s\n' redis-empty public 8.4 apache-fpm none '' y y '' 'intl,gd' n y y y y | run_generator "$redis_empty_target" "$WORK/redis-empty.out"
assert_contains "$redis_empty_target/.ddev/docker-compose.redis.yaml" 'image: "redis:7.4-alpine"'
assert_contains "$WORK/redis-empty.out" 'Redis .............. redis:7.4-alpine'
ok 'empty Redis tag resolves to the default tag'

redis_default_target="$WORK/redis-default"
printf '%s\n' redis-default public 8.4 apache-fpm none '' y y default 'intl,gd' n y y y y | run_generator "$redis_default_target" "$WORK/redis-default.out"
assert_contains "$redis_default_target/.ddev/docker-compose.redis.yaml" 'image: "redis:7.4-alpine"'
assert_contains "$WORK/redis-default.out" 'Redis .............. redis:7.4-alpine'
ok 'literal default Redis tag resolves to the default tag'

redis_custom_target="$WORK/redis-custom"
printf '%s\n' redis-custom public 8.4 apache-fpm none '' y y 7.2-alpine 'intl,gd' n y y y y | run_generator "$redis_custom_target" "$WORK/redis-custom.out"
assert_contains "$redis_custom_target/.ddev/docker-compose.redis.yaml" 'image: "redis:7.2-alpine"'
assert_contains "$WORK/redis-custom.out" 'Redis .............. redis:7.2-alpine'
ok 'custom Redis tag is preserved'

answers_redis_default="$WORK/answers-redis-default.yaml"
sed 's/image: redis:7.4-alpine/image: default/' "$answers_file" > "$answers_redis_default"
env PATH="$FAKE_BIN:$PATH" "$GENERATOR" --answers "$answers_redis_default" "$WORK/answers-redis-default" >"$WORK/answers-redis-default.out"
assert_contains "$WORK/answers-redis-default/.ddev/docker-compose.redis.yaml" 'image: "redis:7.4-alpine"'
assert_contains "$WORK/answers-redis-default.out" 'Redis .............. redis:7.4-alpine'
ok 'answers default Redis image resolves to the default tag'

missing_answers="$WORK/missing.yaml"
sed '/  php: "8.4"/d' "$answers_file" > "$missing_answers"
if env PATH="$FAKE_BIN:$PATH" "$GENERATOR" --answers "$missing_answers" "$WORK/missing" >"$WORK/missing.out" 2>&1; then fail 'missing answer must fail'; fi
assert_contains "$WORK/missing.out" 'ERROR: Missing required answer: project.php'
ok 'missing required answers fail without prompts'

invalid_answers="$WORK/invalid.yaml"
sed 's/php: "8.4"/php: "8.6"/' "$answers_file" > "$invalid_answers"
if env PATH="$FAKE_BIN:$PATH" "$GENERATOR" --answers "$invalid_answers" "$WORK/invalid" >"$WORK/invalid.out" 2>&1; then fail 'invalid answer must fail'; fi
assert_contains "$WORK/invalid.out" 'ERROR: Invalid answer value: project.php'
ok 'invalid answers use interactive validators'

invalid_hostname_answers="$WORK/invalid-hostname.yaml"
sed 's/    - docs/    - invalid_host/' "$answers_file" > "$invalid_hostname_answers"
if env PATH="$FAKE_BIN:$PATH" "$GENERATOR" --answers "$invalid_hostname_answers" "$WORK/invalid-hostname" >"$WORK/invalid-hostname.out" 2>&1; then fail 'invalid hostname must fail'; fi
assert_contains "$WORK/invalid-hostname.out" 'ERROR: Invalid answer value: hostnames'
ok 'answers validate hostnames and FQDNs'

unknown_answers="$WORK/unknown.yaml"
cp "$answers_file" "$unknown_answers"; printf '\nunknown: true\n' >> "$unknown_answers"
if env PATH="$FAKE_BIN:$PATH" "$GENERATOR" --answers "$unknown_answers" "$WORK/unknown" >"$WORK/unknown.out" 2>&1; then fail 'unknown key must fail'; fi
assert_contains "$WORK/unknown.out" 'ERROR: Unknown answer key: unknown'
ok 'unknown answer keys fail'

duplicate_answers="$WORK/duplicate.yaml"
sed 's/    - redis/    - redis\n    - intl/' "$answers_file" > "$duplicate_answers"
env PATH="$FAKE_BIN:$PATH" "$GENERATOR" --answers "$duplicate_answers" "$WORK/duplicate" >"$WORK/duplicate.out"
assert_contains "$WORK/duplicate.out" 'intl, gd, redis, mysqli, pdo_mysql'
ok 'answers normalize duplicate PHP extensions'

none_answers="$WORK/none.yaml"
sed -e 's/type: mariadb/type: none/' -e 's/version: "11.8"/version: null/' -e 's/enabled: true/enabled: false/' "$answers_file" > "$none_answers"
env PATH="$FAKE_BIN:$PATH" "$GENERATOR" --answers "$none_answers" "$WORK/answers-none" >"$WORK/answers-none.out"
assert_contains "$WORK/answers-none/.ddev/config.yaml" 'omit_containers:'
assert_absent "$WORK/answers-none/.ddev/docker-compose.redis.yaml"
assert_absent "$WORK/answers-none/.ddev/docker-compose.otel.yaml"
if grep -Fq 'DB_HOST=' "$WORK/answers-none/.env.local.example"; then fail 'answers database=none must omit DB variables'; fi
ok 'answers support database none and disabled services'

otel_answers="$WORK/otel.yaml"
sed '0,/enabled: false/s//enabled: true/' "$answers_file" > "$otel_answers"
env PATH="$FAKE_BIN:$PATH" "$GENERATOR" --answers "$otel_answers" "$WORK/answers-otel" >"$WORK/answers-otel.out"
assert_file "$WORK/answers-otel/.ddev/docker-compose.otel.yaml"
assert_contains "$WORK/answers-otel.out" 'OpenTelemetry ...... enabled'
ok 'answers support enabled OpenTelemetry'

no_python_bin="$WORK/no-python-bin"; mkdir -p "$no_python_bin"
printf '%s\n' '#!/usr/bin/env sh' 'exit 127' > "$no_python_bin/python3"; chmod +x "$no_python_bin/python3"
if env PATH="$no_python_bin:$FAKE_BIN:$PATH" "$GENERATOR" --answers "$answers_file" "$WORK/no-python" >"$WORK/no-python.out" 2>&1; then fail 'missing PyYAML dependency must fail'; fi
assert_contains "$WORK/no-python.out" 'Python 3 with PyYAML is required'
ok 'answers mode reports an unavailable YAML dependency'

answers_dry_target="$WORK/answers-dry"
env PATH="$FAKE_BIN:$PATH" "$GENERATOR" --dry-run --answers "$answers_file" "$answers_dry_target" >"$WORK/answers-dry.out"
assert_absent "$answers_dry_target"
assert_contains "$WORK/answers-dry.out" 'DDEV Blueprint dry run completed'
assert_contains "$WORK/answers-dry.out" 'No files were written.'
ok 'answers dry-run writes nothing'

printf 'All %d tests passed.\n' "$pass"
