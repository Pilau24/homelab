# Ansible Homelab Deployment Plan

## 1. Target architecture

```text
Proxmox
├── Debian control VM
│   └── Ansible
│       ├── Proxmox API
│       └── SSH to managed VMs
├── Debian VM 9000
│   └── Clean Debian 12 Cloud-Init template
└── Podman VM
    └── Podman
        └── Docker-compatible application containers
```

The Debian control VM is the Ansible controller. It creates and configures
VMs through the Proxmox API and then connects to those VMs over SSH. The
Podman VM is a separate sibling VM created from template `9000`; containers
must not run on the control VM.

## 2. Existing template contract

VM `9000` already provides the base for all managed VMs:

- Debian 12 Bookworm generic cloud image
- Proxmox storage: `local-lvm`
- Network bridge: `vmbr0`
- Virtio network adapter
- `scsi0` boot disk
- `ide2` Cloud-Init drive
- QEMU guest agent installed and enabled
- Serial console configured
- Template-specific Cloud-Init settings removed before conversion

The SSH key created for this environment is:

```text
~/.ssh/homelab_ed25519
```

Clones will use the `ansible` Cloud-Init user and receive the corresponding
public key.

## 3. Repository layout

Create the Ansible project with this structure:

```text
.
├── ansible.cfg
├── requirements.yml
├── inventory/
│   ├── hosts.yml
│   └── group_vars/
│       ├── all.yml
│       └── podman.yml
├── playbooks/
│   ├── provision-vms.yml
│   └── configure-podman.yml
├── roles/
│   ├── proxmox_vm/
│   └── podman_host/
├── templates/
│   └── podman-containers.yml.j2
├── vars/
│   └── vms.yml
└── vault/
    └── secrets.yml
```

Secrets must be stored with Ansible Vault or supplied through environment
variables. Proxmox tokens, passwords, and private SSH keys must not be
committed to Git.

## 4. Proxmox API access

Create a dedicated Proxmox service account and API token with only the
permissions required to manage the homelab VMs. Prefer a token over a
password.

The controller will connect to the Proxmox API using:

- Proxmox API endpoint
- Proxmox node name
- API username
- API token ID
- API token secret
- TLS certificate validation setting appropriate for the local environment

The API credentials will be referenced from vaulted variables rather than
embedded in playbooks.

## 5. VM definition

Define each VM as data so additional application VMs can be added without
duplicating tasks. The initial VM will be the Podman host.

Each VM definition should include:

- VM ID
- VM name
- target Proxmox node
- clone template ID (`9000`)
- CPU and memory
- disk size or resize policy
- network bridge and model
- Cloud-Init user
- SSH public key
- static IP, gateway, and DNS settings
- desired power state
- groups to add to the Ansible inventory

Example initial values to confirm before implementation:

```yaml
podman:
  vmid: 101
  name: podman
  template_vmid: 9000
  cores: 4
  memory_mb: 4096
  ip: 192.168.1.101/24
  gateway: 192.168.1.1
```

The VM ID and network values above are examples and must be replaced with the
actual values for the environment.

## 6. VM provisioning workflow

The `proxmox_vm` role and `provision-vms.yml` playbook will:

1. Validate required variables before making changes.
2. Confirm template `9000` exists on the selected Proxmox node.
3. Clone template `9000` as a full clone using `local-lvm`.
4. Apply CPU, memory, disk, network, and Cloud-Init settings.
5. Configure the `ansible` user and SSH public key.
6. Configure static networking through Proxmox Cloud-Init settings.
7. Regenerate the Cloud-Init drive.
8. Start the VM when its desired state is `started`.
9. Wait for the guest agent and SSH to become available.
10. Verify the VM is reachable using Ansible.

Provisioning must be idempotent: rerunning the playbook should update an
existing VM where safe and must not accidentally recreate or destroy it.
Destructive actions such as deleting a VM should require an explicit variable
and a separate operation.

## 7. Podman host configuration

The `podman_host` role and `configure-podman.yml` playbook will configure the
new VM after SSH becomes available:

1. Update the Debian package cache.
2. Install Podman and required supporting packages.
3. Install the Ansible `containers.podman` collection from
   `requirements.yml`.
4. Create a dedicated application directory.
5. Create application users, groups, directories, and permissions.
6. Configure rootless Podman where practical.
7. Enable required lingering or system services for the application user.
8. Deploy container definitions from version-controlled templates.
9. Pull images and start containers.
10. Verify container health and listening ports.

Podman provides a Docker-compatible command-line interface for many workflows.
Docker Compose files should not be assumed to work unchanged; use native
Podman modules or explicitly test `podman-compose`/Compose compatibility for
each application.

## 8. Inventory and execution flow

The inventory will separate infrastructure from application hosts:

```text
proxmox
podman
apps
```

The intended execution flow is:

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook playbooks/provision-vms.yml
ansible-playbook playbooks/configure-podman.yml
```

The control VM's SSH private key remains local to the control VM. Ansible
should use an explicit `ansible_private_key_file` pointing to
`~/.ssh/homelab_ed25519`, with host-key checking enabled after the initial
host verification process.

## 9. Security requirements

- Use a dedicated, restricted Proxmox API account and token.
- Store API secrets with Ansible Vault.
- Never commit private keys, passwords, or token secrets.
- Use a non-root SSH user inside managed VMs.
- Use `become: true` only for tasks that require privilege.
- Restrict the Proxmox API token to the required node, storage, and VM
  permissions.
- Keep the Podman VM separate from the Ansible controller.
- Expose only required container ports through the VM and network firewall.
- Pin or review container image versions rather than relying on `latest`.
- Keep the Debian template clean and recreate clones when major base-image
  changes are required.

## 10. Validation checklist

### Before provisioning

- [ ] VM `9000` is stopped and marked as a Proxmox template.
- [ ] `local-lvm` exists on the target Proxmox node.
- [ ] `vmbr0` is the correct bridge.
- [ ] The Proxmox API account and token work from the control VM.
- [ ] The SSH private key exists at `~/.ssh/homelab_ed25519`.
- [ ] The selected VM ID is unused.
- [ ] The static IP is unused and the gateway/DNS values are correct.

### After provisioning

- [ ] The Podman VM is running.
- [ ] Cloud-Init created the `ansible` user.
- [ ] SSH works using the configured key.
- [ ] The QEMU guest agent reports network interfaces.
- [ ] The VM has the expected hostname and IP address.
- [ ] Podman is installed and reports its version.
- [ ] A test container starts, restarts, and can be reached.
- [ ] Re-running both playbooks produces no unintended changes.

## 11. Implementation order

1. Confirm the Proxmox node name, Podman VM ID, IP address, gateway, DNS, and
   resource sizing.
2. Create the Proxmox API account and restricted token.
3. Add the Ansible project configuration and collection requirements.
4. Implement the data-driven VM inventory and `proxmox_vm` role.
5. Provision and verify the Podman VM from template `9000`.
6. Implement the `podman_host` role.
7. Deploy a deliberately simple test container.
8. Add real applications one at a time with explicit ports, volumes,
   backups, and health checks.
9. Add maintenance, update, backup, and rollback procedures.
