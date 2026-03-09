#!/bin/bash
set -e

mkdir -p ~/.ssh
chmod -R 700 ~/.ssh

cat << EOF | tee ~/.ssh/authorized_keys
<home.pub.pem>
EOF

rm -rf ~/.ssh/github.pri.pem
nano ~/.ssh/github.pri.pem
<github.pri.pem>
chmod 600 ~/.ssh/github.pri.pem

# ssh-keygen -t rsa -b 4096 -N "" -C "" -f id_rsa
cat << EOF | tee ~/.ssh/esxi1.pri.pem
<esxi1.pri.pem>
EOF
chmod 600 ~/.ssh/esxi1.pri.pem


cat << EOF | tee ~/.ssh/monitor.pri.pem
<monitor.pri.pem>
EOF
chmod 600 ~/.ssh/monitor.pri.pem

cat << EOF | tee ~/.ssh/config
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  ForwardAgent yes

Host github.com
  HostName ssh.github.com
  Port 443
  IdentityFile ~/.ssh/github.pri.pem
  User git

Host esxi1
  IdentityFile ~/.ssh/esxi1.pri.pem
  User root
  Port 22

Host monitor
  IdentityFile ~/.ssh/monitor.pri.pem
  User vt_admin
  Port 22
EOF

sudo rm /etc/ssh/ssh_host_*
sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
sudo chmod 600 /etc/ssh/ssh_host_*_key
sudo chmod 644 /etc/ssh/ssh_host_*_key.pub
sudo chown root:root /etc/ssh/ssh_host_*

cat << EOF | sudo tee /etc/ssh/sshd_config
Port 22
ListenAddress 0.0.0.0
PermitRootLogin no
AddressFamily inet
UseDNS no
PrintMotd yes
X11Forwarding yes
AllowAgentForwarding yes
Protocol 2
PubkeyAuthentication yes
PasswordAuthentication no
AuthorizedKeysFile .ssh/authorized_keys
KerberosAuthentication no
GSSAPIAuthentication no
KbdInteractiveAuthentication no
UsePAM no
Subsystem sftp /usr/lib/openssh/sftp-server
AcceptEnv LANG LC_*
ChallengeResponseAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com
HostKey /etc/ssh/ssh_host_ed25519_key
EOF
sudo rm -rf /etc/ssh/sshd_config.d
sudo systemctl daemon-reload
sudo systemctl restart ssh


# ----------

sudo mount /dev/nvme0n1p1 /boot/efi
sudo mkdir -p /boot/grub

source /etc/os-release
export MIRROR="https://ubuntu.vpsttt.com/${ID}"
cat << EOF | sudo tee /etc/apt/sources.list.d/ubuntu.sources
Types: deb
URIs: ${MIRROR}
Suites: ${VERSION_CODENAME} ${VERSION_CODENAME}-updates ${VERSION_CODENAME}-backports ${VERSION_CODENAME}-security
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/${ID}-archive-keyring.gpg
EOF
sudo rm -rf /etc/apt/sources.list
sudo apt update


sudo rm -rf /etc/localtime
sudo ln -s /usr/share/zoneinfo/Asia/Ho_Chi_Minh /etc/localtime
sudo mkdir -p /var/log/chrony
sudo apt install -y chrony
cat << EOF | sudo tee /etc/chrony/chrony.conf
server 92.92.92.1 iburst prefer

sourcedir /run/chrony-dhcp
sourcedir /etc/chrony/sources.d
keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
ntsdumpdir /var/lib/chrony
logdir /var/log/chrony
maxupdateskew 100.0
rtcsync
makestep 1 3
leapsectz right/UTC
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now chrony
sudo systemctl disable --now systemd-timesyncd

sudo apt install -y locales
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8

sudo rm -rf /etc/netplan
sudo mkdir -p /etc/netplan
sudo chmod 755 /etc/netplan

cat << EOF | sudo tee /etc/netplan/iser.yaml
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ${NCCL_SOCKET_IFNAME}:
      mtu: 9000
      addresses: [92.92.1.1/24]
      dhcp4: false
      dhcp6: false
      optional: true
EOF
sudo chmod 600 /etc/netplan/iser.yaml

cat << EOF | sudo tee /etc/netplan/manage.yaml
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    enp1s0:
      addresses: [92.92.92.10/24]
      dhcp4: false
      dhcp6: true
      wakeonlan: true
      routes:
        - to: default
          via: 92.92.92.1
      nameservers:
        addresses: [92.92.92.1]
EOF
sudo chmod 600 /etc/netplan/manage.yaml

cat << EOF | sudo tee /etc/netplan/routeros.yaml
network:
  version: 2
  ethernets:
    enp2s0:
      addresses: [192.168.88.100/24]
      routes:
        - to: 0.0.0.0/0
          via: 192.168.88.1
EOF
sudo chmod 600 /etc/netplan/manage.yaml

sudo netplan generate
sudo netplan apply

sudo rm /etc/resolv.conf
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
cat << EOF | sudo tee /etc/systemd/resolved.conf
[Resolve]
DNS=92.92.92.1
FallbackDNS=1.1.1.1
Domains=~.
EOF
sudo systemctl restart systemd-resolved


sudo apt install -y \
  wget ca-certificates software-properties-common dnsutils \
  iputils-ping net-tools htop python3-launchpadlib unzip iptables \
  apt-transport-https pkg-config gnupg2 debian-archive-keyring tzdata \
  git tree xz-utils telnet ethtool rsync zip traceroute \
  openssh-server zstd nano

git config --global http.postBuffer 524288000
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999

sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
sudo apt install -y gcc-15 g++-15
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-15 200
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-15 200

sudo apt -y install \
  make pkg-config autoconf automake git-core wget \
  dpkg-dev libtool ninja-build \
  python3-pip python3-dev python3-setuptools \
  ccache

sudo apt upgrade -y systemd udev

source /etc/os-release
wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | \
  sudo gpg --dearmor -o /usr/share/keyrings/apt-llvm-keyring.gpg
cat << EOF | sudo tee /etc/apt/sources.list.d/llvm.sources
Types: deb
URIs: https://apt.llvm.org/${VERSION_CODENAME}/
Suites: llvm-toolchain-${VERSION_CODENAME}-18
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/apt-llvm-keyring.gpg
EOF
sudo apt update
sudo apt -y install \
  llvm-18 llvm-18-dev clang-18 libclang-18-dev
sudo ln -sf /usr/bin/llvm-config-18 /usr/bin/llvm-config
sudo ln -sf /usr/bin/clang-18 /usr/bin/clang

export VER="4.2.3"
sudo apt remove -y cmake cmake-data 2>/dev/null || true
cd /tmp
wget https://github.com/Kitware/CMake/releases/download/v${VER}/cmake-${VER}-linux-x86_64.tar.gz
tar -xzf cmake-${VER}-linux-x86_64.tar.gz
sudo mv cmake-${VER}-linux-x86_64 /opt/cmake
sudo mkdir -p /usr/local/bin
sudo ln -sf /opt/cmake/bin/cmake /usr/local/bin/cmake
sudo ln -sf /opt/cmake/bin/ctest /usr/local/bin/ctest
sudo ln -sf /opt/cmake/bin/cpack /usr/local/bin/cpack
cmake --version
rm -rf cmake-${VER}-linux-x86_64.tar.gz

sudo apt -y install \
  libass-dev libfreetype6-dev libgnutls28-dev libmp3lame-dev \
  libsdl2-dev libva-dev libvdpau-dev libvorbis-dev \
  libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev \
  meson texinfo yasm zlib1g-dev \
  libfdk-aac-dev libopus-dev libssl-dev \
  libunistring-dev libc6-dev

sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:bamboo-engine/ibus-bamboo
sudo apt update
sudo apt install -y ibus ibus-bamboo --install-recommends
ibus restart


echo "source ~/env.sh" >> ~/.bashrc

# export NCCL_SOCKET_IFNAME=$(ibdev2netdev | grep \${NCCL_IB_HCA} | awk '{print \$(NF-1)}')

cat << EOF | tee ~/env.sh
source /etc/os-release
export DEBIAN_FRONTEND=noninteractive
export CCACHE_DIR=\${HOME}/.ccache
export CC="/usr/lib/ccache/gcc-15"
export CXX="/usr/lib/ccache/g++-15"
export TRITON_CC="/usr/bin/gcc-15"
export TRITON_CXX="/usr/bin/g++-15"

export CUDA_HOME=/usr/local/cuda
export CUDA_PATH=\${CUDA_HOME}
export CUDA_DEVICE_ORDER=PCI_BUS_ID
export CUDACXX=\${CUDA_HOME}/bin/nvcc
export NVIDIA_VISIBLE_DEVICES=0,1
export NVIDIA_DRIVER_CAPABILITIES=compute,utility,video
export TRT_LIBPATH=/usr/lib/x86_64-linux-gnu
export LD_LIBRARY_PATH=\${CUDA_HOME}/lib64:/usr/lib/x86_64-linux-gnu:\${LD_LIBRARY_PATH}
export PATH="\${CUDA_HOME}/bin:/usr/lib/ccache:\${PATH}"

export NCCL_DEBUG=WARN
export NCCL_IB_DISABLE=0
export NCCL_IB_HCA=mlx5_0
export NCCL_SOCKET_IFNAME=enp59s0f0np0
export NCCL_IB_GID_INDEX=3
export NCCL_ALGO=Ring
export NCCL_PROTO=Simple
export NCCL_P2P_LEVEL=NVL
export NCCL_P2P_DISABLE=0
export NCCL_SHM_DISABLE=0
export NCCL_NET_GDR_LEVEL=5
export NCCL_NVLS_ENABLE=1
EOF
sudo chmod 644 ~/env.sh
source ~/env.sh
sudo ldconfig

ccache -M 5G
ccache --set-config=max_size=5G
ccache --set-config=compression=true
ccache --set-config=compression_level=6
ccache -z

sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt install -y \
	python3.14 python3.14-venv python3.14-dev



# ----------

wget -qO - https://linux.mellanox.com/public/repo/doca/GPG-KEY-Mellanox.pub | \
  sudo gpg --dearmor -o /usr/share/keyrings/GPG-KEY-Mellanox.pub
sudo tee /etc/apt/sources.list.d/doca.sources << EOF
Types: deb
URIs: https://linux.mellanox.com/public/repo/doca/latest/${ID}${VERSION_ID}/x86_64
Suites: /
Signed-By: /usr/share/keyrings/GPG-KEY-Mellanox.pub
EOF
sudo apt update
sudo apt install -y doca-ofed

cat << EOF | sudo tee /etc/modules-load.d/iser.conf
mlx5_core
mlx5_ib
ib_cm
rdma_cm
rdma_ucm
ib_iser
ib_isert
EOF

sudo reboot now

# ----------


sudo add-apt-repository -y ppa:weiers/openzfs-latest

cat << EOF | sudo tee /etc/sysctl.d/storage.conf
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 33554432
net.core.wmem_default = 33554432
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 87380 134217728
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_mtu_probing = 1
net.core.netdev_max_backlog = 250000
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_low_latency = 1
vm.swappiness = 1
EOF
sudo sysctl --system

sudo mkdir -p /hdd /share/iser /share/nas/iso /share/nas/model

cat << EOF | sudo tee /etc/fstab
# <file system>  <mount point>  <type>  <options>  <dump>  <pass>
/dev/disk/by-uuid/d6efd589-2b42-417b-ac7d-3e6b1a6a268e  none  swap  sw  0  0
/dev/disk/by-uuid/2C40-F7C1  /boot/efi  vfat  defaults,nofail,x-systemd.device-timeout=1  0  1
UUID=d883a5e5-2167-4b70-a8f9-f3684d9c1825  /hdd  ext4  defaults,nofail,x-systemd.device-timeout=10  0  2
UUID=6c035831-9415-434e-95c4-a3f9c64c704a  /share  ext4  defaults,nofail,x-systemd.device-timeout=10  0  2
EOF
sudo systemctl daemon-reload
cd ~
sudo mount -a

sudo apt install nfs-kernel-server -y
sudo systemctl enable --now nfs-kernel-server

sudo chown nobody:nogroup -R /share/nas
sudo chmod 777 -R /share/nas
cat << EOF | sudo tee /etc/exports
/share/nas *(rw,sync,no_subtree_check,no_root_squash,fsid=0)
/share/xxx 92.92.92.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF
sudo exportfs -ra
sudo systemctl daemon-reload
sudo systemctl restart nfs-kernel-server

sudo apt install -y targetcli-fb
sudo systemctl enable --now rtslib-fb-targetctl

# ----------


sudo mlnx_qos \
	-i ${NCCL_SOCKET_IFNAME} \
	--trust dscp \
	--pfc 0,0,0,0,0,0,0,0

sudo mst start
sudo mlxconfig \
	-d /dev/mst/mt4117_pciconf0 \
	set \
	ROCE_NEXT_PROTOCOL=1 \
	ROCE_CC_PRIO_MASK_P1=8 \
	ROCE_RTT_RESP_DSCP_P1=26
sudo mlxconfig \
	-d /dev/mst/mt4117_pciconf0.1 \
	set \
	ROCE_NEXT_PROTOCOL=1


cat << EOF | sudo tee /etc/modprobe.d/mlx5.conf
options mlx5_core log_level=1
EOF

cat << EOF | sudo tee /etc/systemd/system/roce.service
[Unit]
Description=Set RoCEv2 mode - mlx5_0
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/bash -c '\
  for i in \$(seq 1 60); do \
    [ -d /sys/class/infiniband/mlx5_0/ports/1 ] && \
    [ "\$(cat /sys/class/infiniband/mlx5_0/ports/1/state)" = "4: ACTIVE" ] && \
    exit 0; \
    sleep 1; \
  done; exit 1'
ExecStart=/usr/sbin/cma_roce_mode -d mlx5_0 -p 1 -m 2
ExecStart=/bin/bash -c 'mlnx_qos -i ${NCCL_SOCKET_IFNAME} --trust dscp --pfc 0,0,0,0,0,0,0,0'

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now roce


cat << EOF | sudo tee /etc/systemd/system/dcqcn.service
[Unit]
Description=DCQCN ECN CC params for mlx5_0
After=roce.service
Requires=roce.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/bash -c '\
	mount | grep -q debugfs || mount -t debugfs debugfs /sys/kernel/debug'
ExecStartPre=/bin/bash -c '\
	for i in \$(seq 1 20); do \
		[ -d /sys/kernel/debug/mlx5/0000:3b:00.0/cc_params ] && exit 0; \
		sleep 1; \
	done; exit 1'
ExecStart=/bin/sh -c '\
	CC=/sys/kernel/debug/mlx5/0000:3b:00.0/cc_params; \
	echo 1     > \$CC/rp_clamp_tgt_rate; \
	echo 6     > \$CC/np_cnp_prio; \
	echo 1     > \$CC/np_cnp_prio_mode; \
	echo 48    > \$CC/np_cnp_dscp; \
	echo 4     > \$CC/np_min_time_between_cnps; \
	echo 11    > \$CC/rp_gd; \
	echo 1023  > \$CC/rp_initial_alpha_value; \
	echo 4     > \$CC/rp_rate_reduce_monitor_period; \
	echo 1     > \$CC/rp_dce_tcp_rtt; \
	echo 1019  > \$CC/rp_dce_tcp_g; \
	echo 0     > \$CC/rp_rate_to_set_on_first_cnp; \
	echo 1     > \$CC/rp_min_rate; \
	echo 50    > \$CC/rp_min_dec_fac; \
	echo 50    > \$CC/rp_hai_rate; \
	echo 0     > \$CC/rp_max_rate; \
	echo 5     > \$CC/rp_ai_rate; \
	echo 1     > \$CC/rp_threshold; \
	echo 32767 > \$CC/rp_byte_reset; \
	echo 300   > \$CC/rp_time_reset; \
	echo 1     > \$CC/rp_clamp_tgt_rate_ati'

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now dcqcn

cat << EOF | sudo tee /etc/systemd/system/ethtool-tune.service
[Unit]
Description=ethtool NIC tuning
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/ethtool -G enp59s0f0np0 rx 8192 tx 8192
ExecStart=/usr/sbin/ethtool -C enp59s0f0np0 rx-usecs 16 tx-usecs 16 adaptive-rx on adaptive-tx on

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now ethtool-tune




sudo targetcli << TCLI
cd /iscsi
create iqn.2025-01.local.storage:iser-target1

cd /iscsi/iqn.2025-01.local.storage:iser-target1/tpg1/portals
delete 0.0.0.0 3260
create ip_address=92.92.1.1 ip_port=3260

cd /iscsi/iqn.2025-01.local.storage:iser-target1/tpg1
set attribute authentication=0
set attribute demo_mode_write_protect=0
set attribute generate_node_acls=1
set attribute cache_dynamic_acls=1
set parameter HeaderDigest=None
set parameter DataDigest=None

exit
TCLI

export ISER_IMG="block1"
sudo targetcli \
  /backstores/fileio \
  create name=iser_${ISER_IMG} \
  file_or_dev=/share/iser/${ISER_IMG}.img \
  size=1T \
  write_back=false \
  sparse=true

sudo targetcli \
  /iscsi/iqn.2025-01.local.storage:iser-target1/tpg1/luns \
  create /backstores/fileio/iser_${ISER_IMG}

sudo targetcli saveconfig

sudo apt install -y open-iscsi

# ----------

source /etc/os-release

wget https://repo.zabbix.com/zabbix/8.0/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_8.0%2B${ID}${VERSION_ID}_all.deb \
  -O /tmp/zabbix.deb
sudo dpkg -i /tmp/zabbix.deb
rm -rf /tmp/zabbix.deb

sudo apt update
sudo apt install -y zabbix-agent

sudo usermod -aG zabbix zabbix
sudo chown -R zabbix:zabbix /var/log/zabbix

cat << 'EOF' | sudo tee /etc/zabbix/zabbix_agentd.conf > /dev/null
PidFile=/run/zabbix/zabbix_agentd.pid
LogFile=/var/log/zabbix/zabbix_agentd.log
LogFileSize=10
Server=92.92.92.13
ServerActive=92.92.92.13
Hostname=san-target
LogRemoteCommands=1
Include=/etc/zabbix/zabbix_agentd.d/*.conf
EOF
sudo chmod 640 /etc/zabbix/zabbix_agentd.conf
sudo chown root:zabbix /etc/zabbix/zabbix_agentd.conf

sudo systemctl enable --now zabbix-agent

# ----------

sudo usermod -aG zabbix vt_admin
sudo rm -rf /etc/zabbix/scripts
sudo mkdir -p /etc/zabbix/scripts

sudo chown vt_admin:zabbix /etc/zabbix/scripts
sudo chmod 750 /etc/zabbix/scripts

sudo install -m 640 -o root -g zabbix env.json /etc/zabbix/scripts/env.json
sudo install -m 640 -o root -g zabbix requirements.txt /etc/zabbix/scripts/requirements.txt
sudo install -m 750 -o root -g zabbix iser_monitor.py  /etc/zabbix/scripts/iser_monitor.py

sudo python3.14 -m venv /etc/zabbix/scripts/env
sudo chown -R root:zabbix /etc/zabbix/scripts/env
sudo chmod -R 750         /etc/zabbix/scripts/env
sudo UV_LINK_MODE=copy /etc/zabbix/scripts/env/bin/python3 -m pip install uv
sudo UV_LINK_MODE=copy /etc/zabbix/scripts/env/bin/python3 -m uv pip install -r /etc/zabbix/scripts/requirements.txt
sudo -u zabbix /etc/zabbix/scripts/env/bin/python3 -c "import uvloop, orjson, click; print('venv OK')"


cat << 'EOF' | sudo tee /etc/sudoers.d/zabbix-ethtool > /dev/null
zabbix   ALL=(root) NOPASSWD: /usr/sbin/ethtool
vt_admin ALL=(root) NOPASSWD: /usr/sbin/ethtool
EOF
sudo chown root:root /etc/sudoers.d/zabbix-ethtool
sudo chmod 440 /etc/sudoers.d/zabbix-ethtool
sudo visudo -c -f /etc/sudoers.d/zabbix-ethtool
sudo -u zabbix sudo /usr/sbin/ethtool -S enp59s0f0np0 | head -3

cat << 'EOF' | sudo tee /etc/logrotate.d/iser-monitor > /dev/null
/var/log/zabbix/iser_monitor.log {
	daily
	rotate 30
	compress
	delaycompress
	missingok
	notifempty
	create 0640 zabbix zabbix
}
EOF

cat << 'EOF' | sudo tee /etc/systemd/system/iser-monitor.service > /dev/null
[Unit]
Description=iSER/RoCEv2 monitoring daemon
After=network-online.target rtslib-fb-targetctl.service
Wants=network-online.target

[Service]
Type=simple
User=zabbix
Group=zabbix
ExecStart=/etc/zabbix/scripts/env/bin/python3 /etc/zabbix/scripts/iser_monitor.py
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=iser-monitor

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now iser-monitor

sudo rm -f /etc/zabbix/zabbix_agentd.d/iser.conf
sudo systemctl restart zabbix-agent

# ----------

sudo mount /dev/nvme0n1p1 /boot/efi

export DRIVER=590
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
rm -f cuda-keyring_1.1-1_all.deb
sudo apt update
sudo apt install -y \
	nvidia-driver-$DRIVER
sudo apt install -y \
	nvtop cuda-toolkit cudnn9-cuda-13 \
	tensorrt libnccl2 libnccl-dev
sudo apt install -y \
	nvidia-fabricmanager-${DRIVER}
nvidia-smi
nvcc --version

# ----------

sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public \
  | sudo gpg --dearmor -o /etc/apt/keyrings/salt-archive-keyring.gpg
source /etc/os-release
cat << EOF | sudo tee /etc/apt/sources.list.d/salt.sources
Types: deb
URIs: https://packages.broadcom.com/artifactory/saltproject-deb
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/salt-archive-keyring.gpg
EOF
sudo apt update
sudo apt install -y salt-master

sudo mkdir -p /etc/salt/master.d /var/log/salt /opt/salt /opt/pillar
cat << 'EOF' | sudo tee /etc/salt/master.d/local.conf
interface: 92.92.92.10
auto_accept: False
log_level: warning
log_file: /var/log/salt/master.log
timeout: 10
file_roots:
  base:
  - /opt/salt
pillar_roots:
  base:
  - /opt/pillar
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now salt-master

# ----------
sudo mount /dev/nvme0n1p1 /boot/efi

sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y

sudo mount /dev/nvme0n1p1 /boot/efi
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 iommu=pt intel_iommu=on"/' /etc/default/grub
sudo grub-mkconfig -o /boot/efi/EFI/ubuntu/grub.cfg

sudo reboot now

# ----------

rm -rf env
python3.14 -m venv env
env/bin/python3 -m pip install uv
env/bin/python3 -m uv pip install --upgrade uv pip
env/bin/python3 -m uv pip install torch torchvision torchaudio \
	--index-url https://download.pytorch.org/whl/nightly/cu130
env/bin/python3 -m uv pip install -r requirements.txt

sudo apt -y install ninja-build

rm -rf exllamav2
git clone https://github.com/turboderp/exllamav2
cd exllamav2
../env/bin/python3 -m pip install -r requirements.txt
../env/bin/python3 -m pip install .
cd ..
mv exllamav2/convert.py .
mv exllamav2/exllamav2 env/lib64/python3.14/site-packages
rm -rf exllamav2


# ----------------------------------------------------------------------
# Zabbix UI
# ----------------------------------------------------------------------

Data Collection / Hosts / Create host
	Host name: san-target
	Host groups: Network
	Interface / Agent:
		IP: 92.92.92.10
		Port: 10050

Data Collection / Hosts / san-target / Items / Create item

  Name: iSER events — errors
  Type: Zabbix agent
  Key: log[/var/log/zabbix/iser_monitor.log,RDMA_ERROR|NIC_DROP,UTF-8,20,skip]
  Type of information: Log
  Update interval: 10s

  Name: iSER events — warnings
  Key: log[/var/log/zabbix/iser_monitor.log,RDMA_RATE_HIGH|NIC_RATE_HIGH|NO_SESSIONS|COUNTER_RESET,UTF-8,20,skip]
  Type of information: Log
  Update interval: 10s

  Name: iSER throughput
  Key: log[/var/log/zabbix/iser_monitor.log,THROUGHPUT,UTF-8,5,skip]
  Type of information: Log
  Update interval: 30s

  Name: iSER health summary
  Key: log[/var/log/zabbix/iser_monitor.log,HEALTH,UTF-8,5,skip]
  Type of information: Log
  Update interval: 60s


Data Collection / Hosts / san-target / Triggers / Create trigger

  Name: RDMA error / NIC drop
  Severity: Disaster
  Problem:
    find(/san-target/log[/var/log/zabbix/iser_monitor.log,RDMA_ERROR|NIC_DROP,UTF-8,20,skip],60s,"regexp",".")=1
  Recovery:
    find(/san-target/log[/var/log/zabbix/iser_monitor.log,RDMA_ERROR|NIC_DROP,UTF-8,20,skip],180s,"regexp",".")=0

  Name: RDMA/NIC rate high or no sessions
  Severity: High
  Problem:
    find(/san-target/log[/var/log/zabbix/iser_monitor.log,RDMA_RATE_HIGH|NIC_RATE_HIGH|NO_SESSIONS|COUNTER_RESET,UTF-8,20,skip],60s,"regexp",".")=1
  Recovery:
    find(/san-target/log[/var/log/zabbix/iser_monitor.log,RDMA_RATE_HIGH|NIC_RATE_HIGH|NO_SESSIONS|COUNTER_RESET,UTF-8,20,skip],180s,"regexp",".")=0


  Name: iSER fabric — CRITICAL
  Severity: Disaster
  Problem:
    find(/san-target/log[/var/log/zabbix/iser_monitor.log,HEALTH,UTF-8,5,skip],120s,"regexp","status=CRITICAL")=1
  Recovery:
    find(/san-target/log[/var/log/zabbix/iser_monitor.log,HEALTH,UTF-8,5,skip],300s,"regexp","status=CRITICAL")=0

  Name: iSER fabric — DEGRADED
  Severity: High
  Problem:
    find(/san-target/log[/var/log/zabbix/iser_monitor.log,HEALTH,UTF-8,5,skip],120s,"regexp","status=DEGRADED")=1
  Recovery:
    find(/san-target/log[/var/log/zabbix/iser_monitor.log,HEALTH,UTF-8,5,skip],300s,"regexp","status=DEGRADED")=0


Data Collection / Hosts / san-target / Triggers
  "iSER fabric — CRITICAL" / Dependencies / Add
    san-target / "RDMA error / NIC drop"

Data Collection / Hosts / san-target / Triggers
  "iSER fabric — DEGRADED" / Dependencies / Add
    san-target / "RDMA/NIC rate high or no sessions"

# ----------------------------------------------------------------------

sudo apt install -y ipmitool


# LSI MegaRAID SAS 9361-8i
