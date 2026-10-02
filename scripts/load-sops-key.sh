#!/usr/bin/env bash
set -euo pipefail

key_file="${SOPS_AGE_SSH_PRIVATE_KEY_FILE:-${HOME}/.config/sops/ssh/sops_ed25519}"

if [[ ! -f "$key_file" ]]; then
    printf 'SOPS key not found: %s\n' "$key_file" >&2
    printf 'Create it outside the repository or set SOPS_AGE_SSH_PRIVATE_KEY_FILE.\n' >&2
    exit 1
fi

if [[ -z "${SSH_AUTH_SOCK:-}" || ! -S "$SSH_AUTH_SOCK" ]]; then
    printf '%s\n' 'No usable ssh-agent is available.' >&2
    printf '%s\n' 'Start one in the current shell, then run this script again:'
    printf '%s\n' '  eval "$(ssh-agent -s)"'
    exit 1
fi

chmod 600 "$key_file"
ssh-add "$key_file"

printf 'Loaded SOPS key into ssh-agent: %s\n' "$key_file"
printf '%s\n' 'The passphrase was prompted by ssh-add and was not stored.'
