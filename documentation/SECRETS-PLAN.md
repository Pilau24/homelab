# Remaining secrets work

Controller-side SOPS decryption, encrypted Proxmox/Podman configuration,
and the complete homelab deployment are implemented and tested. Remaining
work is to validate least privilege, deliver application secrets when needed,
and test rotation and recovery.

## 1. Wire SOPS into Ansible

- [x] Identify the repository's inventory, playbooks, and roles that need
  Proxmox or application credentials.
- [x] Configure the control VM to load the dedicated SOPS SSH private key
  through `SOPS_AGE_SSH_PRIVATE_KEY_FILE`.
- [x] Use the repository-supported SOPS/Ansible lookup or decryption method.
- [ ] Load only the fields required by each task.
- [ ] Add `no_log: true` to every task that reads, transforms, transfers, or
  creates a secret.
- [x] Do not pass secret values as command-line arguments, labels, or debug
  output.
- [x] Disable persistent fact caching for decrypted values.
- [x] Run playbook syntax checks and a targeted deployment.

The dedicated SOPS private key remains only on the control VM. It is
separate from the controller-to-guest SSH key. The current SOPS key has no
passphrase for unattended operation; it requires no SSH agent. Neither
private key is copied to the Podman guest.

## 2. Deliver Podman secrets

Deferred: the initial HTTP-only Traefik and hello-world containers need no
application secrets. The encrypted Traefik file is reserved for future use.

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
- [x] Confirm the application works after deployment.
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
  SOPS SSH private key and any passphrase, if one is used.
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
