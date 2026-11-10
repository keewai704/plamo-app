#!/usr/bin/env bash
# Checks how serve.sh turns settings into llama-server flags, using a stand-in binary.
# Needs the model to be downloaded already.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

cat > "${work}/llama-server" <<'EOF'
#!/usr/bin/env bash
echo "$* KEY=${LLAMA_API_KEY:-}"
EOF
chmod +x "${work}/llama-server"
export PATH="${work}:${PATH}"
export PLAMO_CONFIG="${work}/config.env"
unset PLAMO_IDLE_SECONDS PLAMO_HOST PLAMO_PORT PLAMO_API_KEY PLAMO_GPU_LAYERS PLAMO_GPU_MEMORY PLAMO_BACKEND

serve() { "${here}/serve.sh" 2>&1; }

expect_flag() { # description, pattern
  local output
  output="$(serve)"
  if ! grep -qE -- "$2" <<<"${output}"; then
    echo "FAIL: $1: expected /$2/ in: ${output}" >&2
    exit 1
  fi
  echo "ok: $1"
}

expect_no_flag() { # description, pattern
  local output
  output="$(serve)"
  if grep -qE -- "$2" <<<"${output}"; then
    echo "FAIL: $1: unexpected /$2/ in: ${output}" >&2
    exit 1
  fi
  echo "ok: $1"
}

expect_failure() { # description, pattern
  local output status=0
  output="$(serve)" || status=$?
  if [[ "${status}" == 0 ]] || ! grep -qE -- "$2" <<<"${output}"; then
    echo "FAIL: $1: status ${status}, output: ${output}" >&2
    exit 1
  fi
  echo "ok: $1"
}

expect_flag "idle timeout defaults to 600 seconds" '--sleep-idle-seconds 600( |$)'

echo 'PLAMO_IDLE_SECONDS=0' > "${PLAMO_CONFIG}"
expect_no_flag "0 keeps the weights loaded" '--sleep-idle-seconds'

printf '# comment\n\nPLAMO_IDLE_SECONDS=42\nPLAMO_PORT=9000' > "${PLAMO_CONFIG}"
expect_flag "seconds come from the config file" '--sleep-idle-seconds 42( |$)'
expect_flag "the last line needs no newline" '--port 9000( |$)'

PLAMO_IDLE_SECONDS=7 expect_flag "the environment overrides the file" '--sleep-idle-seconds 7( |$)'

echo 'PLAMO_IDLE_SECONDS=soon' > "${PLAMO_CONFIG}"
expect_failure "rejects a non-numeric timeout" 'PLAMO_IDLE_SECONDS must be'

echo 'PLAMO_IDLE_SECOND=5' > "${PLAMO_CONFIG}"
expect_failure "rejects unknown settings" 'unknown setting PLAMO_IDLE_SECOND'

echo 'PLAMO_HOST=0.0.0.0' > "${PLAMO_CONFIG}"
expect_failure "requires a key beyond loopback" 'set PLAMO_API_KEY'

printf 'PLAMO_HOST=0.0.0.0\nPLAMO_API_KEY=a=b\n' > "${PLAMO_CONFIG}"
expect_flag "keeps = inside values and passes the key by environment" 'KEY=a=b$'
expect_no_flag "keeps the key out of the arguments" 'a=b KEY'
