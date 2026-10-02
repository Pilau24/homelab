# Proxmox Cloud-Init Setup

This guide creates a Debian Cloud-Init template in Proxmox and tests one
cloned virtual machine.

This guide does not configure Ansible, Proxmox API access, Podman, or
application deployment.

## Requirements

- Shell access to a Proxmox VE host
- Proxmox storage named `local-lvm`
- Proxmox bridge named `vmbr0`
- A Debian VM that will run Ansible
- A free VM ID for the template, such as `9000`
- A free VM ID for the test VM, such as `101`

Replace `local-lvm`, `vmbr0`, VM IDs, and IP addresses when your environment
uses different values.

## 1. Create an SSH Key

Run this on the Debian Ansible VM:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/homelab_ed25519
```

Keep the private key on the Ansible VM. Copy only the public key to the
Proxmox host:

```bash
scp ~/.ssh/homelab_ed25519.pub root@PVE_HOST:/root/
```

## 2. Download the Debian Cloud Image

Run these commands on the Proxmox host:

```bash
mkdir -p /var/lib/vz/template/iso
cd /var/lib/vz/template/iso
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
```

## 3. Create the Debian Template VM

Create VM `9000`:

```bash
qm create 9000 \
  --name debian-12-cloudinit \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0
```

Import the Debian disk:

```bash
qm importdisk 9000 \
  /var/lib/vz/template/iso/debian-12-generic-amd64.qcow2 \
  local-lvm
```

Attach the imported disk:

```bash
qm set 9000 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:vm-9000-disk-0
```

Add the Cloud-Init drive:

```bash
qm set 9000 --ide2 local-lvm:cloudinit
```

Configure boot and serial console:

```bash
qm set 9000 \
  --boot order=scsi0 \
  --serial0 socket \
  --vga serial0
```

Enable the QEMU guest-agent device:

```bash
qm set 9000 --agent enabled=1
```

Check the configuration:

```bash
qm config 9000
```

The configuration must include `scsi0`, `ide2`, `boot: order=scsi0`,
`serial0: socket`, and `vga: serial0`.

## 4. Install QEMU Guest Agent

Temporarily configure Cloud-Init access to VM `9000`:

```bash
qm set 9000 \
  --ciuser debian \
  --cipassword 'TEMPORARY_PASSWORD' \
  --sshkeys /root/homelab_ed25519.pub \
  --ipconfig0 ip=dhcp
```

Set `--ciuser` and `--cipassword` before first boot. Cloud-Init applies
initial user and password settings during first boot.

Start the VM:

```bash
qm start 9000
```

Debian Cloud images have no default password. Cloud-Init creates user
`debian` and installs the SSH public key from `--sshkeys`.

Find the DHCP address from the router or DHCP server. Connect from the
Debian Ansible VM:

```bash
ssh -i ~/.ssh/homelab_ed25519 debian@VM_IP_ADDRESS
```

For serial access, open VM `9000` in the Proxmox web interface and select
**Console**. You can also connect from the Proxmox host:

```bash
qm terminal 9000
```

Log in as `debian` with the temporary password.

Install and start the guest agent inside Debian:

```bash
sudo apt update
sudo apt install -y qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
```

Shut down the VM:

```bash
sudo poweroff
```

Wait until Proxmox reports that VM `9000` is stopped. Remove temporary
Cloud-Init settings:

```bash
qm set 9000 --delete ciuser
qm set 9000 --delete cipassword
qm set 9000 --delete sshkeys
qm set 9000 --delete ipconfig0
```

## 5. Convert VM to a Template

Convert VM `9000`:

```bash
qm template 9000
```

Verify template status:

```bash
qm config 9000
```

The output must include:

```text
ide2: local-lvm:vm-9000-cloudinit,media=cdrom
scsi0: local-lvm:base-9000-disk-0
template: 1
serial0: socket
vga: serial0
```

The exact disk size and Cloud-Init volume details can differ.

## 6. Clone and Configure a Test VM

Clone VM `9000` to VM `101`:

```bash
qm clone 9000 101 \
  --name cloudinit-test \
  --full true \
  --storage local-lvm
```

Wait for the clone task to finish with status `OK`. Do not configure or
start VM `101` while the clone task is running.

Configure the Cloud-Init user, SSH key, and DHCP:

```bash
qm set 101 \
  --ciuser ansible \
  --sshkeys /root/homelab_ed25519.pub \
  --ipconfig0 ip=dhcp
```

Start the test VM:

```bash
qm start 101
```

Open VM `101` in Proxmox **Console** using the serial terminal.

## 7. Find the Test VM IP Address

The guest agent should now be available:

```bash
qm guest cmd 101 network-get-interfaces
```

If Proxmox reports `QEMU guest agent is not running`, log in through the
serial terminal and check the agent:

```bash
sudo systemctl status qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
```

You can also find the address inside Debian:

```bash
ip -br address
```

Test SSH from the Debian Ansible VM:

```bash
ssh -i ~/.ssh/homelab_ed25519 ansible@VM_IP_ADDRESS
```

Successful SSH access confirms that Cloud-Init configured the user, SSH key,
and network.

## 8. Optional Cloud-Init Settings

Set a static IPv4 address:

```bash
qm set 101 \
  --ipconfig0 ip=192.168.1.101/24,gw=192.168.1.1
```

Set DNS:

```bash
qm set 101 --nameserver 192.168.1.1
```

Regenerate the Cloud-Init drive after changing settings:

```bash
qm cloudinit update 101
```

Cloud-Init applies most initial settings during first boot. For major
changes, create a fresh clone from template `9000`.

## Template Rule

Keep VM `9000` as the clean Debian template. Apply machine-specific
settings only to cloned VMs.
