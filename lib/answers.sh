#!/usr/bin/env bash

bp_load_answers() {
  [[ -f "$ANSWERS_FILE" ]] || bp_die "Answers file not found: $ANSWERS_FILE"
  command -v python3 >/dev/null 2>&1 || bp_die "Answers mode requires Python 3 with PyYAML."
  local output key value
  if ! output="$(python3 - "$ANSWERS_FILE" <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("ERROR: Answers mode requires Python 3 with PyYAML.", file=sys.stderr); raise SystemExit(1)
try:
    with open(sys.argv[1], encoding="utf-8") as stream: data = yaml.safe_load(stream)
except (OSError, yaml.YAMLError) as error:
    print(f"ERROR: Cannot read answers file: {error}", file=sys.stderr); raise SystemExit(1)
schema = {"project":{"name":None,"docroot":None,"php":None,"webserver":None}, "database":{"type":None,"version":None,"host_port":None}, "hostnames":{"additional":None,"fqdns":None}, "services":{"redis":{"enabled":None,"image":None},"opentelemetry":{"enabled":None}}, "php":{"extensions":None,"development_settings":None}, "development":{"tools":None,"makefile":None,"editorconfig":None,"env_example":None}}
if not isinstance(data, dict): print("ERROR: Answers file must contain a YAML mapping.", file=sys.stderr); raise SystemExit(1)
def check_keys(value, allowed, prefix=""):
    if not isinstance(value, dict): print(f"ERROR: Invalid answer value: {prefix[:-1] or 'root'} must be a mapping.", file=sys.stderr); raise SystemExit(1)
    for key in value:
        if key not in allowed: print(f"ERROR: Unknown answer key: {prefix}{key}", file=sys.stderr); raise SystemExit(1)
    for key, child in allowed.items():
        full=f"{prefix}{key}"
        if key not in value: print(f"ERROR: Missing required answer: {full}", file=sys.stderr); raise SystemExit(1)
        if isinstance(child, dict): check_keys(value[key], child, full+".")
check_keys(data, schema)
def get(path):
    value=data
    for part in path.split("."): value=value[part]
    return value
def scalar(path):
    value=get(path)
    if value is None: return ""
    if not isinstance(value,(str,int)) or isinstance(value,bool): print(f"ERROR: Invalid answer value: {path} must be a string, number, or null.",file=sys.stderr); raise SystemExit(1)
    value=str(value)
    if any(c in value for c in "\t\r\n"): print(f"ERROR: Invalid answer value: {path} contains an unsupported character.",file=sys.stderr); raise SystemExit(1)
    return value
def boolean(path):
    value=get(path)
    if not isinstance(value,bool): print(f"ERROR: Invalid answer value: {path} must be true or false.",file=sys.stderr); raise SystemExit(1)
    return "y" if value else "n"
def string_list(path):
    value=get(path)
    if not isinstance(value,list) or not all(isinstance(item,str) for item in value): print(f"ERROR: Invalid answer value: {path} must be a list of strings.",file=sys.stderr); raise SystemExit(1)
    if any(any(c in item for c in "\t\r\n") for item in value): print(f"ERROR: Invalid answer value: {path} contains an unsupported character.",file=sys.stderr); raise SystemExit(1)
    return ",".join(value)
for path in ("project.name","project.docroot","project.php","project.webserver","database.type","database.version","database.host_port","services.redis.image"): print(f"{path}\t{scalar(path)}")
for path in ("services.redis.enabled","services.opentelemetry.enabled","php.development_settings","development.tools","development.makefile","development.editorconfig","development.env_example"): print(f"{path}\t{boolean(path)}")
for path in ("hostnames.additional","hostnames.fqdns","php.extensions"): print(f"{path}\t{string_list(path)}")
PY
)"; then bp_die "Unable to parse answers file. Python 3 with PyYAML is required."; fi
  while IFS=$'\t' read -r key value; do ANSWERS["$key"]="$value"; done <<< "$output"
}
