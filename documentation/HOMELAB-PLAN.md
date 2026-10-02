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
- VLAN tag: `70`
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
│   ├── site.yml
│   ├── provision-podman-vm.yml
│   ├── bootstrap-podman-host.yml
│   ├── configure-podman.yml
│   ├── configure-traefik.yml
│   └── configure-helloworld.yml
├── roles/
│   ├── podman/
│   ├── traefik/
│   └── helloworld/
└── secrets/
    ├── proxmox/
    │   ├── api.yml
    │   └── config.yml
    ├── podman/
    │   └── config.yml
    └── containers/
        └── traefik.yml
```

All files under `secrets/` are SOPS-encrypted before they are committed.
The age private key and SSH private key remain outside Git.

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

The API credentials and site configuration are decrypted from SOPS files on
the control VM rather than embedded in playbooks.

The control VM also requires the Debian `python3-proxmoxer` package for the
`community.proxmox` collection:

```bash
sudo apt-get update
sudo apt-get install -y python3-proxmoxer
```

The API token must be able to audit and clone template VM `9000`, allocate
space on `local-lvm`, configure and start the target VM, and access node
`pve`. At minimum, review `VM.Audit`, `VM.Clone`, `VM.Config.CPU`,
`VM.Config.Disk`, `VM.Config.Memory`, `VM.Config.Network`,
`VM.Config.Options`, `VM.PowerMgmt`, `Datastore.AllocateSpace`, and
`Sys.Audit` for the token's ACL scope.

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
- VLAN tag, static IP, gateway, and DNS settings
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
  ip: 10.10.70.4/24
  gateway: 10.10.70.1
  vlan_tag: 70
```

The VM ID and network values above are examples and must be replaced with the
actual values for the environment.

## 6. VM provisioning workflow

The `provision-podman-vm.yml` playbook will:

1. Validate required variables before making changes.
2. Confirm template `9000` exists on the selected Proxmox node.
3. Clone template `9000` as a full clone using `local-lvm`.
4. Apply CPU, memory, disk, network, and Cloud-Init settings.
5. Configure the `ansible` user and SSH public key.
6. Configure static networking through Proxmox Cloud-Init settings.
7. Regenerate the Cloud-Init drive.
8. Start the VM when its desired state is `started`.
9. Wait for SSH to become available.
10. Verify the VM is reachable using Ansible.

Provisioning must be idempotent: rerunning the playbook should update an
existing VM where safe and must not accidentally recreate or destroy it.
Destructive actions such as deleting a VM should require an explicit variable
and a separate operation.

## 7. Podman host configuration

The `podman` role and `configure-podman.yml` playbook configure the new VM
after SSH becomes available. Separate playbooks deploy the applications:

- `configure-traefik.yml` deploys the Traefik reverse proxy.
- `configure-helloworld.yml` deploys `crccheck/hello-world`.

The Podman API socket allows Traefik to discover application containers from
their labels.

The Podman role will:

1. Update the Debian package cache.
2. Install Podman and required supporting packages.
3. Install the Ansible `containers.podman` collection from
   `requirements.yml`.
4. Create a dedicated application directory.
5. Create application users, groups, directories, and permissions.
6. Configure rootless Podman where practical.
7. Enable the Podman API socket.
8. Verify the base host.

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
ansible-playbook playbooks/site.yml
```

The control VM's SSH private key remains local to the control VM. Ansible
should use an explicit `ansible_private_key_file` pointing to
`~/.ssh/homelab_ed25519`, with host-key checking enabled after the initial
host verification process.

## 9. Security requirements

- Use a dedicated, restricted Proxmox API account and token.
- Store API credentials and site configuration with SOPS and age.
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
- [ ] `vmbr0` and VLAN tag `70` are correct.
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

1. Edit and encrypt `secrets/proxmox/config.yml` and
   `secrets/podman/config.yml`.
2. Create the Proxmox API account and restricted token.
3. Add the Ansible project configuration and collection requirements.
4. Implement the data-driven VM provisioning playbook.
5. Provision and verify the Podman VM from template `9000`.
6. Implement the Podman, Traefik, and hello-world roles.
7. Deploy and verify the HTTP test container.
8. Add real applications one at a time with explicit ports, volumes,
   backups, and health checks.
9. Add maintenance, update, backup, and rollback procedures.
