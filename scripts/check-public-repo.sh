#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Public repository check failed: $1" >&2
  exit 1
}

tracked_files="$(git ls-files)"

if printf '%s\n' "$tracked_files" | grep -E '(^|/)\.env($|\.)' | grep -vE '(^|/)\.env\.example$' >/dev/null; then
  fail "a non-example environment file is tracked"
fi

if printf '%s\n' "$tracked_files" | grep -Eiq '(^|/)(google-services\.json|GoogleService-Info\.plist|firebase_options\.dart|key\.properties|.*\.(jks|keystore|p12|pem))$'; then
  fail "a credential or signing file is tracked"
fi

secret_pattern='AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----|sbp_[A-Za-z0-9_-]{20,}|sk_(live|test)_[A-Za-z0-9]{16,}|eyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}'
if git grep -IEn "$secret_pattern" -- . ':!scripts/check-public-repo.sh' >/dev/null; then
  git grep -IEn "$secret_pattern" -- . ':!scripts/check-public-repo.sh' >&2
  fail "a value matching a secret pattern is tracked"
fi

if git grep -IEn '(/Users/[^/]+/|[A-Za-z]:\\Users\\[^\\]+\\)' -- . ':!scripts/check-public-repo.sh' >/dev/null; then
  git grep -IEn '(/Users/[^/]+/|[A-Za-z]:\\Users\\[^\\]+\\)' -- . ':!scripts/check-public-repo.sh' >&2
  fail "a local absolute home path is tracked"
fi

echo "Public repository check passed."
