#!/usr/bin/env bash
set -euo pipefail

flutter_version="3.47.9"
flutter_sha256="25ed8c3c29d51a7353f2a944310b478af8214920639524b19c50a19e6c044c5a"
cache_root="${NETLIFY_CACHE_DIR:-${HOME}/.cache}"
flutter_root="${cache_root}/flutter-sdk-${flutter_version}"
temp_dir=""
created_env=0

cleanup() {
  if [[ "$created_env" -eq 1 ]]; then
    rm -f .env
  fi
  if [[ -n "$temp_dir" ]]; then
    rm -rf "$temp_dir"
  fi
}
trap cleanup EXIT

if [[ -e .env ]]; then
  echo "Refusing to build with a checked-out .env file; use Netlify environment variables instead." >&2
  exit 1
fi

: > .env
created_env=1

write_public_env() {
  local key="$1"
  local value="${!key:-}"

  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo "Netlify variable ${key} must not contain newlines." >&2
    exit 1
  fi

  if [[ -n "$value" ]]; then
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
}

write_public_env SUPABASE_URL
write_public_env SUPABASE_ANON_KEY
write_public_env AGORA_APP_ID

if [[ ! -x "$flutter_root/bin/flutter" ]]; then
  if [[ -e "$flutter_root" ]]; then
    echo "Cached Flutter SDK is incomplete at ${flutter_root}; clear the Netlify build cache and retry." >&2
    exit 1
  fi

  mkdir -p "$cache_root"
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/flutter-sdk.XXXXXX")"
  archive="${temp_dir}/flutter.tar.xz"
  url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${flutter_version}-stable.tar.xz"

  curl --fail --location --silent --show-error --retry 3 "$url" --output "$archive"
  printf '%s  %s\n' "$flutter_sha256" "$archive" | sha256sum --check
  tar -xJf "$archive" -C "$temp_dir"
  mv "${temp_dir}/flutter" "$flutter_root"
fi

"${flutter_root}/bin/flutter" config --no-analytics
"${flutter_root}/bin/flutter" pub get
"${flutter_root}/bin/flutter" build web --release
