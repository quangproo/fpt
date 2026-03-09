ssh-keygen -t ed25519 -f ssh_host_ed25519_key -N ""
scp -rO ssh_host_ed25519_key* root@esxi1:/etc/ssh/
rm -rf ssh_host_ed25519_key*

# https://network.nvidia.com/products/adapter-software/firmware-tools
# https://network.nvidia.com/products/ethernet-drivers/vmware/esxi-server

wget https://www.mellanox.com/downloads/MFT/nmst-4.34.1.10-1OEM.703.0.0.18644231.x86_64.vib \
	-O nmst.vib
wget https://www.mellanox.com/downloads/MFT/mft-4.34.1.10-1OEM.703.0.0.18644231.x86_64.vib \
	-O mft.vib
wget https://www.mellanox.com/downloads/firmware/fw-ConnectX4Lx-rel-14_32_1912-MCX4121A-ACA_Ax-UEFI-14.25.17-FlexBoot-3.6.502.bin.zip \
	-O firmware.bin.zip
scp -rO nmst.vib esxi1:/
scp -rO mft.vib esxi1:/
scp -rO firmware.bin.zip esxi1:/
rm -rf nmst.vib mft.vib firmware.bin.zip

# ----------

mkdir -p ~/.ssh
chmod -R 700 ~/.ssh

cat << 'EOF' > ~/.ssh/authorized_keys
<exsi.pub.pem>
EOF


chmod 600 /etc/ssh/ssh_host_ed25519_key
chmod 644 /etc/ssh/ssh_host_ed25519_key.pub
/usr/lib/vmware/openssh/bin/ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""

cat << 'EOF' > /etc/ssh/sshd_config
Port 22
ListenAddress 0.0.0.0
AddressFamily inet
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
PermitRootLogin yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
UsePAM yes
KexAlgorithms diffie-hellman-group14-sha256,diffie-hellman-group16-sha512,ecdh-sha2-nistp256,ecdh-sha2-nistp384
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512,hmac-sha2-256
HostKeyAlgorithms rsa-sha2-512,rsa-sha2-256,ecdsa-sha2-nistp256,ssh-ed25519
SyslogFacility auth
LogLevel INFO
PrintMotd yes
TCPKeepAlive yes
X11Forwarding yes
AllowAgentForwarding yes
UseDNS no
ClientAliveInterval 200
ClientAliveCountMax 3
MaxStartups 10:30:100
RekeyLimit 1G 1H
IPQoS lowdelay throughput
Subsystem sftp /usr/lib/vmware/openssh/bin/sftp-server -f LOCAL5 -l INFO
Banner /etc/issue
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
FipsMode no
EOF

esxcli network firewall ruleset set --enabled true --ruleset-id sshServer
vim-cmd hostsvc/enable_ssh
/etc/init.d/SSH restart

# ----------

cat << 'EOF' > /etc/profile.local
export TZ="UTC-7"
export PATH=/opt/mellanox/bin:$PATH
EOF
source /etc/profile.local

esxcli system ntp set --enabled=true --server=92.92.92.1
chkconfig ntpd on

# ----------

esxcli software vib install -v /nmst.vib --no-sig-check -f
esxcli software vib install -v /mft.vib --no-sig-check -f
rm -rf /nmst.vib /mft.vib
reboot now

mst start
mst status
unzip firmware.bin.zip

# ----------

esxcli system module set -m iser -e true
esxcli system module set -m nmlx5_rdma -e true
esxcli system module set -m nvmerdma -e true

esxcli network vswitch standard add -v san
esxcli network vswitch standard uplink add -v san -u vmnic2
esxcli network vswitch standard set -v san -m 9000
esxcli network vswitch standard portgroup add -v san -p "SAN Network"

esxcli network ip interface add -i vmk1 -p "SAN Network"
esxcli network ip interface ipv4 set -i vmk1 -I 92.92.1.2 -N 255.255.255.0 -t static
esxcli network ip interface set -i vmk1 --enabled true
esxcli network ip interface set -i vmk1 -m 9000

esxcli iscsi software set --enabled=true
esxcli iscsi networkportal add -n vmk1 -A vmhba64
esxcli iscsi adapter discovery sendtarget add -A vmhba64 -a 92.92.1.1
esxcli iscsi adapter discovery rediscover -A vmhba64
esxcli storage core adapter rescan -A vmhba64

sleep 3

export NAA=$(esxcli storage core path list \
  | grep -A3 "iqn.2025-01.local.storage:iser-target1" \
  | grep "Device:" \
  | awk '{print $2}' \
  | head -1)

partedUtil mklabel /vmfs/devices/disks/${NAA} gpt

export END=$(( $(partedUtil getptbl /vmfs/devices/disks/${NAA} | sed -n '2p' | awk '{print $4}') - 34 ))

partedUtil setptbl /vmfs/devices/disks/${NAA} gpt "1 2048 ${END} AA31E02A400F11DB9590000C2911D1B8 0"

vmkfstools -C vmfs6 -b 1m -S "SAN-iSCSI" /vmfs/devices/disks/${NAA}:1

esxcli storage core device set -d ${NAA} -s 32 -q 4 -O 64

esxcli iscsi adapter param set -A vmhba64 -k FirstBurstLength -v 262144
esxcli iscsi adapter param set -A vmhba64 -k MaxBurstLength -v 16776192
esxcli iscsi adapter param set -A vmhba64 -k MaxOutstandingR2T -v 8
esxcli iscsi adapter param set -A vmhba64 -k RecoveryTimeout -v 10
esxcli iscsi adapter param set -A vmhba64 -k LoginTimeout -v 10
esxcli iscsi adapter param set -A vmhba64 -k NoopOutInterval -v 5
esxcli iscsi adapter param set -A vmhba64 -k NoopOutTimeout -v 10

export ISID=$(esxcli iscsi session list | grep "ISID:" | awk '{print $2}' | head -1)

esxcli iscsi session remove -A vmhba64 -n "iqn.2025-01.local.storage:iser-target1" -s ${ISID}

esxcli iscsi adapter discovery rediscover -A vmhba64
esxcli storage core adapter rescan        -A vmhba64


cat << 'EOF' >> /etc/rc.local.d/local.sh
esxcli storage nfs add \
	--host 92.92.92.10 \
	--share /share/nas \
	--volume-name NAS
EOF