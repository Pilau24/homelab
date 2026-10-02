# Secrets implementation

This guide implements the design in [SECRETS-PLAN.md](./SECRETS-PLAN.md).
It stores structured secrets in SOPS files encrypted to a dedicated
`ssh-ed25519` key, decrypts them only on the Debian control VM, and delivers
only the required values to the target host or container.

This guide must never contain secret values, private keys, decrypted files,
complete tokens, passwords, or environment-file contents.

## Current implementation status

Completed and verified during the initial setup:

- `age` and SOPS installed on the Debian control VM.
- Plaintext and decrypted-file protections added to `.gitignore`.
- `secrets/proxmox/`, `secrets/podman/`, and `secrets/containers/` created.
- A dedicated SSH key path selected for SOPS identities.
- `.sops.yaml` created with the dedicated SSH public recipient.
- SOPS encryption and decryption tested successfully with a harmless value.
- Proxmox, Podman, and Traefik encrypted files are present.

Remaining operational work includes validating least privilege, logging,
rotation, and recovery.

## Architecture

```text
Git repository
└── SOPS-encrypted YAML files only

Debian control VM
├── Ansible
├── SOPS and age
├── dedicated SOPS SSH private key outside the repository
└── Proxmox API credentials

Podman VM 101
├── no SOPS private key
├── no Git checkout required
├── no Proxmox API credentials
└── receives only required Podman secrets
```

The control VM is the only initial decryption point. The Podman guest does
not receive the repository, SOPS, age, the control VM private key, or
Proxmox credentials.

## Requirements

- A Debian control VM with shell access
- An existing Git repository at `/srv/homelab`
- Ansible installed on the control VM
- A Podman guest, later identified as VM `101`
- `sudo` access on the control VM
- A separately protected backup location for the decryption key
- Provider credentials created with least privilege

Replace VM IDs, paths, hostnames, and application names when the environment
uses different values.

## 1. Establish a safe starting point

Run on the control VM:

```bash
cd /srv/homelab
pwd
git status --short
find . -maxdepth 2 -type f | sort
```

Do not paste secret values or private files. Review untracked and modified
files before continuing. Do not stage a plaintext secret file.

The repository should eventually contain files similar to:

```text
.
├── .gitignore
├── .sops.yaml
├── secrets/
│   ├── proxmox/
│   │   ├── api.yml
│   │   └── config.yml
│   ├── podman/
│   │   └── config.yml
│   └── containers/
│       └── traefik.yml
├── ansible.cfg
├── inventory/
├── playbooks/
└── roles/
```

## 2. Install and verify the tools

Install age from the approved Debian source:

```bash
sudo apt-get update
sudo apt-get install -y age curl ca-certificates
```

The configured Debian repositories may not contain SOPS. Do not add an
arbitrary or unsigned repository. If an approved repository is provided,
verify its signing-key fingerprint and package origin before installing it.
Use a keyring and `signed-by` source:

```bash
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL '<VERIFIED_SIGNING_KEY_URL>' \
  | sudo gpg --dearmor -o /etc/apt/keyrings/<vendor>.gpg
sudo chmod 0644 /etc/apt/keyrings/<vendor>.gpg
echo "deb [signed-by=/etc/apt/keyrings/<vendor>.gpg] <VERIFIED_REPOSITORY_URL> <DEBIAN_RELEASE> <COMPONENT>" \
  | sudo tee /etc/apt/sources.list.d/<vendor>.list >/dev/null
sudo apt-get update
sudo apt-get install -y sops
```

If no approved repository exists, install the official SOPS release binary.
Select the asset matching the control VM architecture:

```bash
SOPS_VERSION="$(curl -fsSL https://api.github.com/repos/getsops/sops/releases/latest \
  | sed -n 's/.*"tag_name": "v\([^"]*\)".*/\1/p' | head -n 1)"

case "$(dpkg --print-architecture)" in
  amd64) SOPS_ARCH="amd64" ;;
  arm64) SOPS_ARCH="arm64" ;;
  *)
    echo "Unsupported architecture"
    exit 1
    ;;
esac

curl -fL \
  -o /tmp/sops \
  "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${SOPS_ARCH}"
sudo install -m 0755 /tmp/sops /usr/local/bin/sops
rm -f /tmp/sops
```

Verify both tools:

```bash
age --version
sops --version
ansible --version
```

Record only version and installation results in operational notes.

## 3. Create the dedicated SOPS SSH key

SOPS supports `ssh-ed25519` and `ssh-rsa` public keys directly as age
recipients, so `ssh-to-age` is not required. This key must not be used for
normal SSH access.

Create a new Ed25519 key used only for SOPS:

```bash
install -d -m 700 ~/.config/sops/ssh
ssh-keygen -t ed25519 \
  -f ~/.config/sops/ssh/sops_ed25519 \
  -C "sops-control-key"
chmod 600 ~/.config/sops/ssh/sops_ed25519
chmod 644 ~/.config/sops/ssh/sops_ed25519.pub
cat ~/.config/sops/ssh/sops_ed25519.pub
```

Use a unique strong passphrase. Record only the public key. Configure SOPS
to find the private key on the control VM:

```bash
export SOPS_AGE_SSH_PRIVATE_KEY_FILE="$HOME/.config/sops/ssh/sops_ed25519"
```

Persist this variable only in a protected control-VM environment file if the
Ansible workflow requires it. Never commit that file. The private-key path
method is preferred over `SOPS_AGE_SSH_PRIVATE_KEY_CMD` because command
output must not expose a passphrase-protected key.

Before using it in production, complete the test in section 6. Keep the
key backup until SSH-backed recovery is proven. This implementation uses
SSH-backed SOPS identities only; do not create or retain a native age-key
fallback.

## 4. Back up the private key

Back up the dedicated private key before creating production secrets:

- `~/.config/sops/ssh/sops_ed25519`
- The unique passphrase protecting that key

Use at least two encrypted backups on separate media or encrypted storage.
Keep one backup offline and separate from the Git repository. Protect the
private key and its passphrase independently. Do not store either in Git,
chat, an issue, an unencrypted email, or the Podman guest.

Test restoration later in a separate environment. Do not print the key while
testing.

## 5. Add repository protections

Create or update `.gitignore`:

```gitignore
secrets/*.plain.yml
secrets/**/*.plain.yml
*.decrypted
.env
*.key
```

Create the directory structure:

```bash
mkdir -p secrets/proxmox secrets/podman secrets/containers
```

Before staging changes, inspect the diff:

```bash
git diff -- .gitignore .sops.yaml secrets/
git status --short
```

## 6. Configure SOPS and test encryption

Create `.sops.yaml` using the complete public-key line from
`~/.config/sops/ssh/sops_ed25519.pub`:

```yaml
creation_rules:
  - path_regex: secrets/proxmox/.*\.ya?ml$
    age: ssh-ed25519 AAAA_REPLACE_WITH_PUBLIC_KEY

  - path_regex: secrets/podman/.*\.ya?ml$
    age: ssh-ed25519 AAAA_REPLACE_WITH_PUBLIC_KEY

  - path_regex: secrets/containers/.*\.ya?ml$
    age: ssh-ed25519 AAAA_REPLACE_WITH_PUBLIC_KEY
```

Set the SSH identity before testing:

```bash
export SOPS_AGE_SSH_PRIVATE_KEY_FILE="$HOME/.config/sops/ssh/sops_ed25519"
```

Do not commit the private key or an environment file containing this path if
the path reveals sensitive host details.

Create a temporary test file under a matching repository path with a harmless
value. The fail-fast setting prevents a failed encryption from being reported
as a successful test:

```bash
cd /srv/homelab
umask 077
(
  set -euo pipefail
  test_file="secrets/containers/.sops-test.plain.yml"
  decrypted_file="/tmp/sops-test.decrypted.yml"

  cat > "$test_file" <<'EOF'
test_value: not-a-secret
EOF
  sops --encrypt --in-place "$test_file"
  grep -q 'ENC\[' "$test_file"
  sops --decrypt "$test_file" > "$decrypted_file"
  grep -q 'test_value: not-a-secret' "$decrypted_file"
  rm -f "$test_file" "$decrypted_file"
  echo "SOPS encryption and decryption passed"
)
```

Do not use production credentials for this test. If it fails, stop and
resolve key or identity configuration before creating real secret files.

## 7. Create encrypted secret files

Create plaintext input only on the control VM, encrypt it immediately, and
remove the plaintext file after verification. Example Proxmox schema:

```yaml
proxmox_api_user: REPLACE_LOCALLY
proxmox_api_token_id: REPLACE_LOCALLY
proxmox_api_token_secret: REPLACE_LOCALLY
```

Encrypt it:

```bash
sops secrets/proxmox/api.yml
```

Use the editor opened by SOPS to enter values. Save and exit; SOPS writes an
encrypted YAML file. Create the encrypted site configuration files with the fields needed by
provisioning:

```yaml
# secrets/proxmox/config.yml
proxmox_api_host: REPLACE_LOCALLY
proxmox_node: REPLACE_LOCALLY
proxmox_storage: local-lvm
proxmox_bridge: vmbr0
proxmox_vlan_tag: 70
proxmox_template_vmid: 9000
proxmox_validate_certs: false
```

```yaml
# secrets/podman/config.yml
podman_vm_id: 101
podman_vm_name: podman
podman_vm_address: REPLACE_LOCALLY
podman_vm_cidr: REPLACE_LOCALLY
podman_vm_gateway: REPLACE_LOCALLY
podman_vm_nameserver: REPLACE_LOCALLY
podman_vm_cores: 4
podman_vm_memory: 4096
```

Verify structure without printing decrypted values:

```bash
grep -q 'ENC\[' secrets/proxmox/api.yml
grep -q 'ENC\[' secrets/proxmox/config.yml
grep -q 'ENC\[' secrets/podman/config.yml
grep -q 'ENC\[' secrets/containers/traefik.yml
sops --decrypt --extract '["proxmox_api_user"]' secrets/proxmox/api.yml >/dev/null
```

Every secret file must be encrypted before it is staged. Split files by
trust boundary; never place Proxmox credentials in a guest or application
file.

## 8. Wire Ansible to decrypt on the control VM

Use the repository's supported SOPS/Ansible integration. The private key
must remain on the control VM and must not be copied to managed guests.

Load only the field required by a task. Secret-bearing tasks must include:

```yaml
no_log: true
```

Do not pass secrets in command-line arguments, labels, debug output,
persistent plaintext files, or ordinary environment variables when a file
secret is supported.

Disable persistent fact caching for decrypted values. Run the smallest
available checks:

```bash
ansible-playbook --syntax-check playbooks/site.yml
ansible-playbook --syntax-check playbooks/configure-podman.yml
ansible-playbook --syntax-check playbooks/configure-traefik.yml
ansible-playbook --syntax-check playbooks/configure-helloworld.yml
```

Use check mode or a targeted deployment before applying changes where the
playbooks support it. Review output for accidental secret exposure.

## 9. Deliver secrets to Podman

The control VM should send only the application-specific value required by
the Podman host. On the guest, create a named Podman secret and attach it to
the intended container:

```text
/run/secrets/<secret-name>
```

Prefer file-based secret consumption over environment variables. Make the
Ansible task idempotent, use `no_log: true`, and restart only the affected
container after a credential change.

The Podman VM must not receive:

- The control VM age or SSH private key
- The SOPS repository checkout
- Proxmox API credentials
- Credentials for unrelated applications

## 10. Validate the deployment

Perform these checks without printing secret contents:

- Confirm every committed file under `secrets/` contains SOPS encryption
  metadata and `ENC[` values.
- Confirm `git diff --cached` contains no plaintext credential.
- Confirm Ansible output redacts secret-bearing tasks.
- Confirm the Podman guest has no control VM private key.
- Confirm the Podman guest has no Proxmox API credential.
- Confirm each container can read only its intended
  `/run/secrets/<secret-name>` file.
- Confirm the application works after deployment.

Review before committing:

```bash
git diff --check
git status --short
git diff -- .gitignore .sops.yaml secrets/
```

## 11. Rotate a credential

When a credential expires, staff access changes, or exposure is suspected:

1. Create a replacement with equal or narrower permissions.
2. Update only the relevant encrypted SOPS file.
3. Run the targeted Ansible deployment.
4. Restart or recreate the affected container.
5. Test the application.
6. Revoke the old credential at the provider.
7. Record the date and credential name, never its value.

To rotate the age or dedicated SSH recipient, add the new recipient, re-encrypt
all required files, test decryption and deployment, then remove the old
recipient only after recovery is confirmed.

## 12. Test recovery

Use a separate machine or temporary environment:

1. Clone the repository.
2. Restore the protected private-key backup.
3. Configure the supported SOPS identity path.
4. Decrypt a non-production test secret.
5. Confirm the value without printing it.
6. Run a targeted deployment.
7. Remove the temporary environment and any decrypted files.

If the private key is lost and no backup works, encrypted SOPS files cannot
be recovered. If the private key is exposed, generate a replacement, update
the recipient, re-encrypt all files for the new recipient, deploy, and revoke
the exposed key.

## Completion record

Record only dates, versions, filenames, recipient fingerprints or public
recipients, and test outcomes:

| Step | Date | Result |
|------|------|--------|
| Tools installed | 2026-10-02 | age and sops installed |
| Dedicated SSH key generated | | |
| SSH key backup tested | | |
| SOPS test passed | 2026-10-02 | Passed; VS Code prompt warnings were unrelated to SOPS |
| Encrypted files created | | |
| Ansible deployment tested | | |
| Podman secret delivery tested | | |
| Recovery tested | | |
