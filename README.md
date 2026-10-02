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
├── bootstrap-podman-host.yml
│   ├── configure-podman.yml
│   ├── configure-traefik.yml
│   └── configure-helloworld.yml
└── roles/
    ├── podman/tasks/main.yml
    ├── traefik/
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── templates/traefik.container
    └── helloworld/
        ├── tasks/main.yml
        ├── handlers/main.yml
        └── templates/hello-world.container
```

## Site configuration

Edit the encrypted site configuration in:

- [secrets/proxmox/config.yml](/srv/homelab/secrets/proxmox/config.yml)
- [secrets/podman/config.yml](/srv/homelab/secrets/podman/config.yml)

`secrets/proxmox/config.yml` contains the Proxmox host, node, storage, bridge,
VLAN tag, and template settings. `secrets/podman/config.yml` contains the
Podman VM ID, static IP, gateway, DNS, and resource sizing. Both files must be
SOPS-encrypted before deployment or commit.

The playbooks automatically use
`~/.config/sops/ssh/sops_ed25519` for the SOPS private key. Set
`SOPS_AGE_SSH_PRIVATE_KEY_FILE` only if the key is stored elsewhere. The SSH
key defaults to `~/.ssh/homelab_ed25519`; set `HOMELAB_SSH_KEY` only if that
key is elsewhere. Do not put private keys or decrypted secret files in Git.

If the SOPS key has a passphrase, load it into an existing SSH agent:

```bash
eval "$(ssh-agent -s)"
./scripts/load-sops-key.sh
```

The script prompts through `ssh-add`; it does not store the passphrase or
copy the private key into the repository.

## Install collections

```bash
sudo apt-get update
sudo apt-get install -y python3-proxmoxer
ansible-galaxy collection install -r requirements.yml
```

`python3-proxmoxer` is required by the `community.proxmox` collection on the
control VM.

## Provision and configure

```bash
ansible-playbook playbooks/provision-podman-vm.yml
ansible-playbook playbooks/configure-podman.yml
```

The first playbook clones template `9000` as the Podman VM. The second
installs the Podman base. `configure-traefik.yml` and
`configure-helloworld.yml` independently deploy Traefik and the
`crccheck/hello-world` application using systemd Quadlet. Traefik discovers
the hello-world container through its labels and the Podman API socket.
ACME/DNS challenge configuration is deferred until a DNS provider token and
domain are configured.

Run both stages with:

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
with its own Quadlet template and Traefik labels. Traefik will automatically
discover the new container when the application playbook starts it; no manual
Traefik route file is required.

Run syntax checks before applying changes:

```bash
ansible-playbook --syntax-check playbooks/provision-podman-vm.yml
ansible-playbook --syntax-check playbooks/configure-podman.yml
ansible-playbook --syntax-check playbooks/configure-traefik.yml
ansible-playbook --syntax-check playbooks/configure-helloworld.yml
```
