# Homelab Ansible Deployment

This repository provisions a Podman VM from Proxmox template `9000` and
deploys Traefik and `crccheck/hello-world` to it. Secrets are stored as
SOPS-encrypted YAML and are decrypted only on the Ansible control VM.

## Layout

```text
homelab/
├── ansible.cfg
├── inventory/
│   └── hosts.yml
├── playbooks/
│   ├── site.yml
│   ├── provision-podman-vm.yml
│   ├── bootstrap-podman-host.yml
│   ├── configure-podman.yml
│   ├── configure-traefik.yml
│   └── configure-helloworld.yml
└── roles/
    ├── podman/tasks/main.yml
    ├── traefik/
    │   ├── tasks/main.yml
    │   └── handlers/main.yml
    └── helloworld/
        ├── tasks/main.yml
        └── handlers/main.yml
```

## Site configuration

Edit the encrypted site configuration in:

- [secrets/proxmox/config.yml](/srv/homelab/secrets/proxmox/config.yml)
- [secrets/podman/config.yml](/srv/homelab/secrets/podman/config.yml)

Field templates with non-production example values are available beside each
encrypted file as `*.example.yml`. Copy the relevant template to a local
plaintext file, replace every example value, encrypt it with SOPS, and remove
the plaintext copy before deployment. Do not use the example values in a
live environment.

`secrets/proxmox/config.yml` contains the Proxmox host, node, storage, bridge,
VLAN tag, and template settings. `secrets/podman/config.yml` contains the
Podman VM ID, static IP, gateway, DNS, and resource sizing. Both files must be
SOPS-encrypted before deployment or commit.

The playbooks automatically use
`~/.config/sops/ssh/sops_ed25519` for the SOPS private key. Set
`SOPS_AGE_SSH_PRIVATE_KEY_FILE` only if the key is stored elsewhere. The SSH
key defaults to `~/.ssh/homelab_ed25519`; set `HOMELAB_SSH_KEY` only if that
key is elsewhere. Do not put private keys or decrypted secret files in Git.

The current SOPS key has no passphrase for unattended decryption; no SSH
agent or key-loader script is required. Restrict the private key to mode
`0600` and keep encrypted backups outside the repository.

The keys are separate: `~/.ssh/homelab_ed25519` authenticates controller-to-VM
SSH, while `~/.config/sops/ssh/sops_ed25519` decrypts SOPS files only. Only the
communication key's public key is installed in the guest by Cloud-Init.

## Install collections

```bash
sudo apt-get update
sudo apt-get install -y python3-proxmoxer
ansible-galaxy collection install -r requirements.yml
```

`python3-proxmoxer` is required by the `community.proxmox` collection on the
control VM.

## Proxmox API token permissions

The token name alone is not the ACL identity. Proxmox ACLs must reference the
token as:

```text
USER@REALM!TOKEN_NAME
```

For example, if the token `homelab-ansible` belongs to `ansible@pam`, use:

```text
ansible@pam!homelab-ansible
```

Create the restricted roles once on the Proxmox node, replacing the privilege
lists if the deployment scope changes:

```bash
pveum role add HomelabTemplateClone \
  --privs "VM.Audit VM.Clone"

pveum role add HomelabVMProvisioner \
  --privs "VM.Audit VM.Allocate VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.Memory VM.Config.Network VM.Config.Options VM.PowerMgmt Sys.Audit"

pveum role add HomelabStorage \
  --privs "Datastore.AllocateSpace"
```

Assign the roles to the token. Run these commands on the Proxmox node as an
administrator, replacing `ansible@pam` with the actual token owner and realm:

```bash
pveum acl modify /vms/9000 \
  --tokens 'ansible@pam!homelab-ansible' \
  --roles HomelabTemplateClone

pveum acl modify / \
  --tokens 'ansible@pam!homelab-ansible' \
  --roles HomelabVMProvisioner

pveum acl modify /storage/local-lvm \
  --tokens 'ansible@pam!homelab-ansible' \
  --roles HomelabStorage
```

If token privilege separation is enabled, effective permissions are the
intersection of the owner's ACLs and the token's ACLs. The owner must have
the same or broader permissions on these paths; token-only grants cannot
exceed the owner's permissions. For a dedicated `ansible@pam` account,
assign the same roles to the owner:

```bash
pveum acl modify /vms/9000 --users ansible@pam --roles HomelabTemplateClone
pveum acl modify / --users ansible@pam --roles HomelabVMProvisioner
pveum acl modify /storage/local-lvm --users ansible@pam --roles HomelabStorage
```

The `/` provisioning grant covers all VMs, not just VM `101`. Review that
scope before using these example ACLs outside this homelab.

Verify the ACL entries and effective token permissions before deploying:

```bash
pveum acl list
pveum user token list ansible@pam
pveum user token permissions ansible@pam homelab-ansible
```

The token secret is not used in these ACL commands and must not be printed or
committed. The provisioning playbook requires access to template `9000`,
target VM allocation, `local-lvm`, node `pve`, and the target VM's CPU, disk,
memory, network, options, and power state.

## Provision and configure

```bash
ansible-playbook playbooks/provision-podman-vm.yml
ansible-playbook playbooks/configure-podman.yml
```

The first playbook clones template `9000` as the Podman VM. The second
installs the Podman base. Cloning and configuration are separate operations:
the existing VM is explicitly updated with `update: true`. The NIC update
preserves its MAC address and other options; no disk settings are updated.
Provisioning reads back the Cloud-Init settings, regenerates the Cloud-Init
drive while stopped, and checks the generated NIC, static IP, gateway, login
user, and SSH key before startup.
Configuration changes require the VM to be stopped; a correctly configured
running VM is not stopped on subsequent runs.

To configure and verify a stopped VM without booting it:

```bash
ansible-playbook playbooks/provision-podman-vm.yml -e podman_vm_start=false
```

The first SSH connection to a new or recreated VM requires host-key trust.
Verify the VM's SSH host-key fingerprint through the Proxmox console or
guest agent before accepting it from the controller. If replacing a VM,
remove only its stale entry with `ssh-keygen -R 10.10.70.4`, then connect
with `ssh -i ~/.ssh/homelab_ed25519 ansible@10.10.70.4` and confirm the
fingerprint. Host-key checking remains enabled for Ansible.

If a VM has already booted with incomplete Cloud-Init settings, updating the
Proxmox configuration does not prove the guest has reapplied them. Verify
the guest's address and Cloud-Init state after boot; do not assume that an
open SSH port belongs to this VM. Guest recovery or recreation may be needed
if first-boot state was cached. Do not delete the VM without checking for data
and obtaining approval.

`configure-traefik.yml` and
`configure-helloworld.yml` independently deploy Traefik and the
`crccheck/hello-world` application using native systemd units generated by
Podman. Debian 12 ships Podman 4.3.1, which does not include Quadlet, so the
roles use `containers.podman.podman_container` with `generate_systemd`
instead. The units recreate containers on startup and are enabled for boot.
Application settings live in `inventory/group_vars/podman_hosts.yml`, matching
the runtime inventory group. Traefik discovers the hello-world container
through its labels and the Podman API socket.
ACME/DNS challenge configuration is deferred until a DNS provider token and
domain are configured.

Run the complete deployment with:

```bash
ansible-playbook playbooks/site.yml
```

## Deploying the components separately

Run only the base:

```bash
ansible-playbook playbooks/configure-podman.yml
```

Run Traefik:

```bash
ansible-playbook playbooks/configure-traefik.yml
```

Run hello-world:

```bash
ansible-playbook playbooks/configure-helloworld.yml
```

To add another application, create a separate role and configuration playbook
using `podman_container`, `generate_systemd`, and Traefik labels. Traefik will
automatically discover the new container when the application playbook starts it; no manual
Traefik route file is required.

## Verify deployment

The hello-world role checks both container state and an HTTP 200 response
containing `Hello World` through Traefik, requested from the control node.
For a manual check:

```bash
curl --fail http://10.10.70.4/
ssh -i ~/.ssh/homelab_ed25519 ansible@10.10.70.4 \
  'sudo cloud-init status --long; ip -br addr; sudo systemctl is-active traefik hello-world; sudo systemctl is-enabled traefik hello-world'
```

Re-running `playbooks/site.yml` should make no persistent VM or container
changes. The controller's `add_host` task may still report a change because
it populates runtime inventory for each execution.

Run syntax checks before applying changes:

```bash
ansible-playbook --syntax-check playbooks/provision-podman-vm.yml
ansible-playbook --syntax-check playbooks/configure-podman.yml
ansible-playbook --syntax-check playbooks/configure-traefik.yml
ansible-playbook --syntax-check playbooks/configure-helloworld.yml
```
