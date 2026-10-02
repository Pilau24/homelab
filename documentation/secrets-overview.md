# Homelab secrets overview

This document summarizes the secrets design. Follow
[sops-age-setup.md](./sops-age-setup.md) for the complete setup procedure.

## Purpose

The secrets system protects Proxmox, host, and container credentials while
allowing encrypted configuration to be stored in Git. Secrets are decrypted
only on the Debian control VM and delivered to the specific host or container
that needs them.

## Trust boundaries

```text
Git repository
└── encrypted SOPS YAML files only

Debian control VM
├── Ansible
├── SOPS
├── dedicated SOPS SSH private key
└── Proxmox API credentials

Podman VM
├── no SOPS private key
├── no repository checkout required
├── no Proxmox credentials
└── receives only required application secrets
```

The control VM is the trusted decryption point. The Podman VM is not given
the private key or unrelated credentials.

## Encryption model

SOPS encrypts YAML values to a dedicated `ssh-ed25519` public key. The
corresponding private key remains outside the repository and is loaded on
the control VM through:

```bash
SOPS_AGE_SSH_PRIVATE_KEY_FILE
```

The dedicated key must not be reused for normal SSH access. `ssh-to-age` is
not required because SOPS supports SSH public keys directly as recipients.

## Repository layout

```text
.
├── .gitignore
├── .sops.yaml
└── secrets/
    ├── proxmox/
    │   ├── api.plain.yml        # temporary, ignored, local only
    │   └── api.yml              # encrypted, safe to commit
    ├── hosts/
    │   └── podman.yml           # encrypted host-only values
    └── containers/
        ├── traefik.plain.yml    # temporary, ignored, local only
        └── traefik.yml          # encrypted application values
```

Plaintext templates must be removed immediately after successful encryption.
Only encrypted files belong in Git.

## Secret separation

- Proxmox API credentials are control-node-only.
- Podman host credentials contain only values required by the Podman host.
- Each application has its own encrypted file.
- A DNS provider token is restricted to the required zone and operations.
- Credentials are not shared between unrelated applications.

## Operational rules

- Never commit or paste private keys, passwords, tokens, or decrypted files.
- Use `no_log: true` on Ansible tasks that handle secrets.
- Do not pass secrets as command-line arguments or container labels.
- Prefer Podman secret files at `/run/secrets/<secret-name>` over environment
  variables.
- Review staged changes before every commit.
- Rotate credentials after expiry, access changes, or suspected exposure.
- Maintain independent encrypted backups of the SOPS private key and
  passphrase.
- Test recovery on a separate machine or temporary environment.

## Implementation state

The tools, repository protections, SSH-backed SOPS configuration, and
encrypted Proxmox and Traefik files are present. The Ansible playbooks now
wire Proxmox credentials into VM provisioning and deploy Traefik plus
`crccheck/hello-world` with Podman Quadlet. Rotation and recovery testing
remain operational follow-up work.
