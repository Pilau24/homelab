# Remaining secrets work

The initial SOPS setup and real Proxmox and Traefik encrypted files are
complete. The remaining work is to connect encrypted values to Ansible and
Podman, then test operations and recovery.

## 1. Wire SOPS into Ansible

- [ ] Identify the repository's inventory, playbooks, and roles that need
  Proxmox or application credentials.
- [ ] Configure the control VM to load the dedicated SOPS SSH private key
  through `SOPS_AGE_SSH_PRIVATE_KEY_FILE`.
- [ ] Use the repository-supported SOPS/Ansible lookup or decryption method.
- [ ] Load only the fields required by each task.
- [ ] Add `no_log: true` to every task that reads, transforms, transfers, or
  creates a secret.
- [ ] Do not pass secret values as command-line arguments, labels, or debug
  output.
- [ ] Disable persistent fact caching for decrypted values.
- [ ] Run playbook syntax checks and a safe targeted check-mode run.

The private SSH key remains only on the control VM. It must not be copied to
the Podman guest.

## 2. Deliver Podman secrets

- [ ] Pass only the required application value from Ansible to the Podman VM.
- [ ] Create an idempotent named Podman secret.
- [ ] Attach the secret only to its intended container.
- [ ] Mount it at `/run/secrets/<secret-name>`.
- [ ] Prefer file-based consumption over environment variables.
- [ ] Use `no_log: true` for every secret-bearing task.
- [ ] Restart only the affected container after a secret changes.

The Podman VM must not receive the SOPS repository, the SOPS SSH private key,
or Proxmox API credentials.

## 3. Validate the trust boundaries

- [ ] Confirm no Proxmox credentials are present on the Podman VM.
- [ ] Confirm no SOPS private key is present on the Podman VM.
- [ ] Confirm each container can access only its intended secret.
- [ ] Confirm Ansible output does not reveal secret values.
- [ ] Confirm `git diff --cached` contains encrypted values only.
- [ ] Confirm the application works after deployment.
- [ ] Confirm a container restart preserves the intended secret behavior.

## 4. Test rotation

- [ ] Create a replacement application credential with equal or narrower
  permissions.
- [ ] Update only the relevant encrypted SOPS file.
- [ ] Run the targeted Ansible deployment.
- [ ] Restart or recreate the affected container.
- [ ] Test the application.
- [ ] Revoke the old credential at the provider.
- [ ] Record only the credential name and rotation date.

If the dedicated SSH key is ever exposed, create a replacement key, update
the SOPS recipient, re-encrypt all affected files, deploy, and revoke the
exposed key.

## 5. Test recovery

- [ ] Maintain at least two independent encrypted backups of the dedicated
  SOPS SSH private key and its passphrase.
- [ ] Clone the repository in a separate test environment.
- [ ] Restore the private-key backup without committing or displaying it.
- [ ] Configure `SOPS_AGE_SSH_PRIVATE_KEY_FILE`.
- [ ] Decrypt a non-production test secret.
- [ ] Run a targeted deployment.
- [ ] Remove the temporary environment and decrypted files.
- [ ] Record the recovery date and result without recording secret values.

## Completion criteria

This plan is complete when all checkboxes above pass and the following are
true:

- Encrypted secret files are the only secret files tracked by Git.
- Ansible decrypts only on the control VM and redacts secret tasks.
- Podman receives only application-specific secrets.
- Rotation has been tested.
- Recovery from the protected SSH-key backup has been tested.
