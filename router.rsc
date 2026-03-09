/interface pppoe-client
add name=pppoe-out1 \
	interface=ether1 \
	user=Hnfdl-260225-3396 \
	password=<fpt_pass> \
	add-default-route=yes \
	use-peer-dns=yes \
	disabled=no

/ip address set [find interface="ether3"] address=92.92.92.1/24

/user set [find name=admin] password=<router_pass>

/ip dhcp-server remove [find]
/ip pool remove [find]
/ip dhcp-server network remove [find]

/ip pool
add name=pool-LAN ranges=92.92.92.100-92.92.92.254

/ip dhcp-server
add name=dhcp-LAN interface=bridge-LAN address-pool=pool-LAN lease-time=10m disabled=no

/ip dhcp-server network
add address=92.92.92.0/24 gateway=92.92.92.1 dns-server=92.92.92.1 ntp-server=92.92.92.1

/ip service
set telnet disabled=yes
set ftp disabled=yes
set www port=8080
set ssh port=2222

/ip firewall filter
remove [find]
add chain=input action=accept connection-state=established,related comment="INPUT: established/related"
add chain=input action=drop connection-state=invalid comment="INPUT: drop invalid"
add chain=input action=accept protocol=icmp in-interface=bridge-LAN comment="INPUT: ICMP from LAN"
add chain=input action=accept protocol=tcp dst-port=2222 in-interface=bridge-LAN connection-state=new comment="INPUT: SSH :2222 from LAN"
add chain=input action=accept protocol=udp dst-port=53 in-interface=bridge-LAN comment="INPUT: DNS UDP from LAN"
add chain=input action=accept protocol=tcp dst-port=53 in-interface=bridge-LAN connection-state=new comment="INPUT: DNS TCP from LAN"
add chain=input action=accept protocol=udp dst-port=123 in-interface=bridge-LAN comment="INPUT: NTP from LAN"
add chain=input action=accept protocol=udp dst-port=67 in-interface=bridge-LAN comment="INPUT: DHCP from LAN"
add chain=input action=accept protocol=tcp dst-port=8080 in-interface=bridge-LAN connection-state=new comment="INPUT: Webfig HTTP from LAN"
add chain=input action=accept protocol=tcp dst-port=8291 in-interface=bridge-LAN connection-state=new comment="INPUT: Winbox from LAN"
add chain=input action=accept protocol=tcp dst-port=8080 in-interface=pppoe-out1 connection-nat-state=dstnat connection-state=new comment="INPUT: Webfig via WAN dst-nat port 1000"
add chain=input action=log log-prefix="FW-DROP-IN: " log=yes comment="INPUT: log before drop"
add chain=input action=drop comment="INPUT: drop all"

add chain=forward action=accept connection-state=established,related comment="FORWARD: established/related"
add chain=forward action=drop connection-state=invalid comment="FORWARD: drop invalid"
add chain=forward action=accept src-address=92.92.92.0/24 out-interface=pppoe-out1 connection-state=new comment="FORWARD: LAN to WAN"
add chain=forward action=accept src-address=92.92.92.0/24 dst-address=92.92.92.0/24 comment="FORWARD: LAN inter-host"
add chain=forward action=accept protocol=tcp dst-port=22  in-interface=pppoe-out1 connection-nat-state=dstnat connection-state=new dst-address=92.92.92.10 comment="FORWARD: WAN :22   → san :22"
add chain=forward action=accept protocol=tcp dst-port=80  in-interface=pppoe-out1 connection-nat-state=dstnat connection-state=new dst-address=92.92.92.10 comment="FORWARD: WAN :80   → san HTTP"
add chain=forward action=accept protocol=tcp dst-port=443 in-interface=pppoe-out1 connection-nat-state=dstnat connection-state=new dst-address=92.92.92.10 comment="FORWARD: WAN :443  → san HTTPS"
add chain=forward action=accept protocol=udp dst-port=443 in-interface=pppoe-out1 connection-nat-state=dstnat dst-address=92.92.92.10 comment="FORWARD: WAN :443  → san HTTP/3"
add chain=forward action=accept protocol=tcp dst-port=80  in-interface=pppoe-out1 connection-nat-state=dstnat connection-state=new dst-address=92.92.92.2  comment="FORWARD: WAN :1001 → switch Webfig :80"
add chain=forward action=accept protocol=tcp dst-port=443 in-interface=pppoe-out1 connection-nat-state=dstnat connection-state=new dst-address=92.92.92.12 comment="FORWARD: WAN :1002 → ESXi :443"
add chain=forward action=accept protocol=udp dst-port=443 in-interface=pppoe-out1 connection-nat-state=dstnat dst-address=92.92.92.12 comment="FORWARD: WAN :1002 UDP → ESXi :443 HTTP/3"
add chain=forward action=accept protocol=udp dst-port=443 in-interface=pppoe-out1 connection-nat-state=dstnat dst-address=92.92.92.13 comment="FORWARD: WAN :1003 UDP → Zabbix :443 HTTP/3"
add chain=forward action=accept protocol=udp dst-port=443 in-interface=pppoe-out1 connection-nat-state=dstnat dst-address=92.92.92.14 comment="FORWARD: WAN :1004 UDP → pxoay :443 HTTP/3"
add chain=forward action=accept protocol=tcp dst-port=80  in-interface=pppoe-out1 connection-nat-state=dstnat connection-state=new dst-address=92.92.92.13 comment="FORWARD: WAN :1003 → Zabbix :80"
add chain=forward action=accept protocol=tcp dst-port=80  in-interface=pppoe-out1 connection-nat-state=dstnat connection-state=new dst-address=92.92.92.14 comment="FORWARD: WAN :1004 → pxoay :80"
add chain=forward action=log log-prefix="FW-DROP-FWD: " log=yes comment="FORWARD: log before drop"
add chain=forward action=drop comment="FORWARD: drop all"

add chain=output action=accept connection-state=established,related comment="OUTPUT: established/related"
add chain=output action=drop connection-state=invalid comment="OUTPUT: drop invalid"
add chain=output action=accept protocol=icmp comment="OUTPUT: ICMP"
add chain=output action=accept protocol=udp dst-port=53 comment="OUTPUT: DNS UDP upstream"
add chain=output action=accept protocol=tcp dst-port=53 comment="OUTPUT: DNS TCP upstream"
add chain=output action=accept protocol=udp dst-port=123 comment="OUTPUT: NTP upstream"
add chain=output action=accept protocol=tcp dst-port=80 comment="OUTPUT: HTTP package update"
add chain=output action=accept protocol=tcp dst-port=443 comment="OUTPUT: HTTPS package update"
add chain=output action=accept protocol=udp dst-port=443 comment="OUTPUT: HTTP/3 QUIC upstream"
add chain=output action=log log-prefix="FW-DROP-OUT: " log=yes comment="OUTPUT: log before drop"
add chain=output action=drop comment="OUTPUT: drop all"

/ip firewall nat
remove [find]
add chain=srcnat out-interface=ether1 action=masquerade
add chain=srcnat src-address=92.92.92.0/24 out-interface-list=WAN action=masquerade
add comment="HTTP" dst-port=80 to-addresses=92.92.92.10 to-ports=80 chain=dstnat protocol=tcp action=dst-nat
add comment="HTTPS" dst-port=443 to-addresses=92.92.92.10 to-ports=80 chain=dstnat protocol=tcp action=dst-nat
add comment="HTTP3" dst-port=443 to-addresses=92.92.92.10 to-ports=80 chain=dstnat protocol=udp action=dst-nat
add comment="router" dst-port=1000 to-addresses=92.92.92.1 to-ports=8080 chain=dstnat protocol=tcp action=dst-nat
add comment="switch" dst-port=1001 to-addresses=92.92.92.2 to-ports=80 chain=dstnat protocol=tcp action=dst-nat
add comment="ssh" dst-port=22 to-addresses=92.92.92.10 to-ports=22 chain=dstnat protocol=tcp action=dst-nat
add comment="esxi1" dst-port=1002 to-addresses=92.92.92.12 to-ports=443 chain=dstnat protocol=tcp action=dst-nat
add comment="esxi HTTP/3" dst-port=1002 protocol=udp to-addresses=92.92.92.12 to-ports=443 chain=dstnat action=dst-nat
add comment="zabbix HTTP/3" dst-port=1003 protocol=udp to-addresses=92.92.92.13 to-ports=443 chain=dstnat action=dst-nat
add comment="pxoay HTTP/3" dst-port=1004 protocol=udp to-addresses=92.92.92.14 to-ports=443 chain=dstnat action=dst-nat
add comment="zabbix" dst-port=1003 to-addresses=92.92.92.13 to-ports=80 chain=dstnat protocol=tcp action=dst-nat
add comment="pxoay" dst-port=1004 to-addresses=92.92.92.14 to-ports=80 chain=dstnat protocol=tcp action=dst-nat


/ip dns static
remove [find]
add name=router address=92.92.92.1 ttl=600
add name=switch address=92.92.92.2 ttl=600
add name=home address=92.92.92.10 ttl=600
add name=esxi1 address=92.92.92.12 ttl=600
add name=monitor address=92.92.92.13 ttl=600
add name=pxoay address=92.92.92.14 ttl=600

/ip dns
set allow-remote-requests=yes servers=1.1.1.1,8.8.8.8,2001:4860:4860::8888,2606:4700:4700::1111
cache flush

/system ntp client servers
remove [find]
add address=20.189.79.72 iburst=yes
add address=208.75.88.4 iburst=yes
add address=vn.pool.ntp.org iburst=yes
add address=time.cloudflare.com iburst=yes
add address=time.google.com iburst=yes
add address=asia.pool.ntp.org iburst=yes

/system ntp server
set enabled=yes broadcast=no manycast=no multicast=no

/system clock set time-zone-name=Asia/Ho_Chi_Minh

/ip ssh
set host-key-type=ed25519
regenerate-host-key
set strong-crypto=yes
set always-allow-password-login=no
set ciphers=aes-gcm

/system package update download
/system reboot

