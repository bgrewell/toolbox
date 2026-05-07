#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-platform-snapshot-$(hostname)-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT_DIR"

run() {
  local name="$1"
  shift

  {
    echo "# Command: $*"
    echo "# Timestamp: $(date -Is)"
    echo
    "$@"
  } > "$OUT_DIR/$name.txt" 2>&1 || {
    {
      echo "# Command failed: $*"
      echo "# Timestamp: $(date -Is)"
      echo
      "$@"
    } > "$OUT_DIR/$name.txt" 2>&1 || true
  }
}

run_shell() {
  local name="$1"
  local cmd="$2"

  {
    echo "# Command: $cmd"
    echo "# Timestamp: $(date -Is)"
    echo
    bash -lc "$cmd"
  } > "$OUT_DIR/$name.txt" 2>&1 || true
}

copy_if_exists() {
  local src="$1"
  local dst="$2"

  if [[ -e "$src" ]]; then
    mkdir -p "$(dirname "$OUT_DIR/$dst")"
    cp -a "$src" "$OUT_DIR/$dst" 2>/dev/null || true
  fi
}

echo "Writing platform snapshot to: $OUT_DIR"

# -------------------------------------------------------------------
# Basic identity / OS / kernel
# -------------------------------------------------------------------
run hostname hostnamectl
run uname uname -a
run os-release cat /etc/os-release
run lsb-release bash -lc 'command -v lsb_release >/dev/null && lsb_release -a || true'
run uptime uptime
run date date -Is
run boot-time who -b

# -------------------------------------------------------------------
# Hardware / platform / CPU / memory
# -------------------------------------------------------------------
run lscpu lscpu
run cpuinfo bash -lc 'grep -E "model name|vendor_id|cpu cores|siblings|flags|Hypervisor" /proc/cpuinfo | sort -u'
run meminfo cat /proc/meminfo
run lsmem bash -lc 'command -v lsmem >/dev/null && lsmem || true'
run dmidecode-system bash -lc 'sudo -n dmidecode -t system || dmidecode -t system || true'
run dmidecode-baseboard bash -lc 'sudo -n dmidecode -t baseboard || dmidecode -t baseboard || true'
run dmidecode-bios bash -lc 'sudo -n dmidecode -t bios || dmidecode -t bios || true'
run chassis bash -lc 'sudo -n dmidecode -t chassis || dmidecode -t chassis || true'
run dmi-sysfs bash -lc 'for f in /sys/class/dmi/id/*; do [ -r "$f" ] && echo "## $f" && cat "$f" 2>/dev/null; done'

# -------------------------------------------------------------------
# Virtualization / bare metal detection
# -------------------------------------------------------------------
run virt-detect systemd-detect-virt
run virt-detect-full bash -lc 'systemd-detect-virt --vm || true; systemd-detect-virt --container || true'
run hypervisor-hints bash -lc 'lscpu | grep -i hypervisor || true'
run dmesg-virt bash -lc 'sudo -n dmesg | grep -iE "hypervisor|kvm|qemu|vmware|virtualbox|xen|hyper-v|virtio" || true'

# -------------------------------------------------------------------
# PCI / USB / block / network hardware
# -------------------------------------------------------------------
run lspci lspci -nnk
run lsusb lsusb
run usb-tree bash -lc 'command -v lsusb >/dev/null && lsusb -t || true'
run block lsblk -o NAME,TYPE,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
run filesystems df -hT
run mounts findmnt
run network-links ip -details link
run network-addrs ip -brief addr
run network-routes ip route show table all
run ethtool-summary bash -lc 'for i in $(ls /sys/class/net | grep -v lo); do echo "## $i"; ethtool "$i" 2>/dev/null || true; ethtool -i "$i" 2>/dev/null || true; done'

# -------------------------------------------------------------------
# Kernel modules / boot config / security
# -------------------------------------------------------------------
run lsmod lsmod
run kernel-cmdline cat /proc/cmdline
run sysctl-interesting bash -lc 'sysctl kernel.unprivileged_userns_clone kernel.apparmor_restrict_unprivileged_userns net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables 2>/dev/null || true'
run apparmor-status bash -lc 'aa-status 2>/dev/null || sudo -n aa-status 2>/dev/null || true'
run selinux-status bash -lc 'command -v sestatus >/dev/null && sestatus || true'
run ufw-status bash -lc 'command -v ufw >/dev/null && sudo -n ufw status verbose || true'
run nft-ruleset bash -lc 'sudo -n nft list ruleset || true'
run iptables-save bash -lc 'sudo -n iptables-save || true'
run ip6tables-save bash -lc 'sudo -n ip6tables-save || true'

# -------------------------------------------------------------------
# Cgroups / namespaces / container environment
# -------------------------------------------------------------------
run cgroup-mounts bash -lc 'mount | grep -i cgroup || true'
run cgroup-filesystems cat /proc/filesystems
run cgroup-self cat /proc/self/cgroup
run cgroup-controllers bash -lc 'cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null || true'
run cgroup-subtree-control bash -lc 'cat /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true'
run cgroup-type bash -lc 'stat -fc %T /sys/fs/cgroup'
run namespaces bash -lc 'lsns || true'
run process-tree ps auxf
run container-env-hints bash -lc 'env | grep -iE "container|docker|kubernetes|k8s|rke2|containerd|podman|lxc" || true'
run container-files bash -lc 'ls -la /.dockerenv /run/.containerenv 2>/dev/null || true'

# -------------------------------------------------------------------
# Container runtimes / orchestration
# -------------------------------------------------------------------
run docker-version bash -lc 'command -v docker >/dev/null && docker version || true'
run docker-info bash -lc 'command -v docker >/dev/null && sudo -n docker info || docker info || true'
run docker-ps bash -lc 'command -v docker >/dev/null && sudo -n docker ps -a || docker ps -a || true'
run docker-images bash -lc 'command -v docker >/dev/null && sudo -n docker images || docker images || true'

run containerd-version bash -lc 'command -v containerd >/dev/null && containerd --version || true'
run ctr-version bash -lc 'command -v ctr >/dev/null && ctr version || true'
run ctr-namespaces bash -lc 'command -v ctr >/dev/null && sudo -n ctr namespaces list || true'
run crictl-info bash -lc 'command -v crictl >/dev/null && sudo -n crictl info || true'
run crictl-ps bash -lc 'command -v crictl >/dev/null && sudo -n crictl ps -a || true'
run nerdctl-info bash -lc 'command -v nerdctl >/dev/null && sudo -n nerdctl info || true'
run podman-info bash -lc 'command -v podman >/dev/null && podman info || true'
run lxc-info bash -lc 'command -v lxc >/dev/null && lxc list || true'
run incus-info bash -lc 'command -v incus >/dev/null && incus list || true'

run kubectl-version bash -lc 'command -v kubectl >/dev/null && kubectl version --client=true --output=yaml || true'
run kubectl-nodes bash -lc 'command -v kubectl >/dev/null && kubectl get nodes -o wide || true'
run kubectl-pods bash -lc 'command -v kubectl >/dev/null && kubectl get pods -A -o wide || true'
run rke2-version bash -lc 'command -v rke2 >/dev/null && rke2 --version || true'
run k3s-version bash -lc 'command -v k3s >/dev/null && k3s --version || true'

# -------------------------------------------------------------------
# Services and installed software
# -------------------------------------------------------------------
run systemd-units systemctl list-units --type=service --all
run systemd-failed systemctl --failed
run systemd-enabled systemctl list-unit-files --state=enabled
run package-summary bash -lc 'dpkg-query -W -f="${binary:Package}\t${Version}\n" | sort'
run apt-sources bash -lc 'find /etc/apt -type f -maxdepth 4 -print -exec sed -n "1,200p" {} \;'
run snap-list bash -lc 'command -v snap >/dev/null && snap list || true'
run python-versions bash -lc 'python3 --version 2>/dev/null || true; pip3 --version 2>/dev/null || true'
run gcc-version bash -lc 'gcc --version 2>/dev/null || true; g++ --version 2>/dev/null || true'
run go-version bash -lc 'go version 2>/dev/null || true'
run node-version bash -lc 'node --version 2>/dev/null || true; npm --version 2>/dev/null || true'
run java-version bash -lc 'java -version 2>&1 || true'

# Important packages likely relevant to air-gapped/container/K8s behavior
run important-packages bash -lc '
for p in \
  docker.io docker-ce docker-ce-cli containerd containerd.io runc \
  kubectl kubelet kubeadm rke2-server rke2-agent k3s \
  apparmor apparmor-utils udev systemd libseccomp2 seccomp \
  nftables iptables bridge-utils ethtool pciutils usbutils \
  uhd-host libuhd-dev libuhd4.6.0 libuhd4.5.0 \
  linux-generic linux-image-generic linux-modules-extra-$(uname -r)
do
  dpkg-query -W -f="${binary:Package}\t${Version}\n" "$p" 2>/dev/null || true
done | sort
'

# -------------------------------------------------------------------
# UHD / USRP specific
# -------------------------------------------------------------------
run uhd-version bash -lc 'command -v uhd_config_info >/dev/null && uhd_config_info --version || true'
run uhd-config bash -lc 'command -v uhd_config_info >/dev/null && uhd_config_info --print-all || true'
run uhd-find-devices bash -lc 'command -v uhd_find_devices >/dev/null && uhd_find_devices || true'
run uhd-usrp-probe bash -lc 'command -v uhd_usrp_probe >/dev/null && timeout 20s uhd_usrp_probe || true'
run udev-usrp-rules bash -lc 'ls -la /etc/udev/rules.d /usr/lib/udev/rules.d 2>/dev/null; grep -R "2500\\|3923\\|fffe\\|USRP\\|uhd" /etc/udev/rules.d /usr/lib/udev/rules.d 2>/dev/null || true'
run udevadm-usrp bash -lc '
for dev in /dev/bus/usb/*/*; do
  if udevadm info -q property -n "$dev" 2>/dev/null | grep -qE "ID_VENDOR_ID=(2500|3923|fffe)"; then
    echo "## $dev"
    ls -l "$dev"
    udevadm info -q property -n "$dev"
  fi
done
'

# -------------------------------------------------------------------
# Config directories worth capturing
# -------------------------------------------------------------------
copy_if_exists /etc/docker etc/docker
copy_if_exists /etc/containerd etc/containerd
copy_if_exists /etc/rancher etc/rancher
copy_if_exists /etc/rke2 etc/rke2
copy_if_exists /etc/cni etc/cni
copy_if_exists /etc/crictl.yaml etc/crictl.yaml
copy_if_exists /etc/modules-load.d etc/modules-load.d
copy_if_exists /etc/modprobe.d etc/modprobe.d
copy_if_exists /etc/sysctl.d etc/sysctl.d
copy_if_exists /etc/udev/rules.d etc/udev/rules.d
copy_if_exists /etc/apparmor.d etc/apparmor.d

# -------------------------------------------------------------------
# Recent logs
# -------------------------------------------------------------------
run journal-boot-errors bash -lc 'sudo -n journalctl -b -p warning..alert --no-pager || true'
run journal-docker bash -lc 'sudo -n journalctl -u docker --since "24 hours ago" --no-pager || true'
run journal-containerd bash -lc 'sudo -n journalctl -u containerd --since "24 hours ago" --no-pager || true'
run journal-rke2-server bash -lc 'sudo -n journalctl -u rke2-server --since "24 hours ago" --no-pager || true'
run journal-rke2-agent bash -lc 'sudo -n journalctl -u rke2-agent --since "24 hours ago" --no-pager || true'
run journal-udev bash -lc 'sudo -n journalctl -u systemd-udevd --since "24 hours ago" --no-pager || true'

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
cat > "$OUT_DIR/README.txt" <<EOF
Platform snapshot collected on: $(date -Is)
Host: $(hostname)
Directory: $OUT_DIR

Useful starting files:
- hostname.txt
- os-release.txt
- uname.txt
- lscpu.txt
- dmidecode-system.txt
- virt-detect.txt
- docker-info.txt
- containerd-version.txt
- cgroup-type.txt
- cgroup-self.txt
- important-packages.txt
- udev-usrp-rules.txt
- uhd-find-devices.txt
- uhd-usrp-probe.txt
- journal-boot-errors.txt

Notes:
- Some files may be empty or contain failures if the related tool/package is not installed.
- Run with sudo for the most complete output.
EOF

tar -czf "$OUT_DIR.tar.gz" "$OUT_DIR"

echo
echo "Done."
echo "Snapshot directory: $OUT_DIR"
echo "Archive: $OUT_DIR.tar.gz"
