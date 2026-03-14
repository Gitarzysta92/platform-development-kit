# Proxmox VM Disk Expansion (Ubuntu LVM Guest)

This runbook fixes the common case where you increase VM disk size in Proxmox (`scsi0`), but Ubuntu guest root (`/`) does not grow.

## Symptom

You resized VM disk in Proxmox, but inside guest:

- `lsblk` shows larger disk (for example `sda = 40G`)
- LVM partition (for example `sda3`) is still old size
- `sudo lvextend -l +100%FREE ...` reports no effective size increase

Typical message:

```bash
Size of logical volume ubuntu-vg/ubuntu-lv unchanged ...
The filesystem is already ... Nothing to do!
```

## Why this happens

Disk growth in Proxmox does not automatically expand:

1. guest partition (`/dev/sda3`)
2. LVM PV (`/dev/sda3`)
3. LV/filesystem (`/dev/ubuntu-vg/ubuntu-lv`)

All layers must be expanded in order.

## 1) Verify current state

```bash
lsblk
sudo fdisk -l
sudo pvs
sudo vgs
df -h /
```

If disk is larger but partition/PV/VG are not, continue.

## 2) Ensure `growpart` is available

```bash
sudo apt-get update
sudo apt-get install -y cloud-guest-utils
```

## 3) Expand LVM partition

For standard Ubuntu layout on `sda3`:

```bash
sudo growpart /dev/sda 3
```

If your disk is `vda`, use:

```bash
sudo growpart /dev/vda 3
```

## 4) Resize LVM PV

```bash
sudo pvresize /dev/sda3
# or /dev/vda3 on virtio disks
```

## 5) Extend LV and filesystem

```bash
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv -r
```

`-r` performs online filesystem resize after LV expansion.

## 6) Validate result

```bash
lsblk
sudo pvs
sudo vgs
df -h /
```

Expected:

- partition grows to near full disk (minus boot/EFI partitions)
- LV grows accordingly
- `/` free space increases

## Notes

- GPT warning after disk resize (backup GPT not at disk end) is normal before partition table update; `growpart` fixes it when writing partition changes.
- If disk itself did not grow in guest, reboot VM or rescan:

```bash
echo 1 | sudo tee /sys/class/block/sda/device/rescan
```
