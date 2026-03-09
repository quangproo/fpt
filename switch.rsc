/ip address set [find address="192.168.88.1/24"] address=92.92.92.2/24

/user set [find name=admin] password=<switch_pass>

/interface bridge
add name=iser \
	mtu=9000 \
	vlan-filtering=yes \
	protocol-mode=rstp \
	ingress-filtering=yes \
	igmp-snooping=no \
	arp=disabled \
	fast-forward=no \
	comment="iSER Storage Network"

/interface bridge port
remove [find interface=sfp-sfpplus1]
remove [find interface=sfp-sfpplus2]
remove [find interface=sfp-sfpplus3]
remove [find interface=sfp-sfpplus4]
remove [find interface=sfp-sfpplus5]
remove [find interface=sfp-sfpplus6]
remove [find interface=sfp-sfpplus7]
remove [find interface=sfp-sfpplus8]

/interface bridge port
add bridge=iser interface=sfp-sfpplus1 pvid=100 hw=yes frame-types=admit-only-untagged-and-priority-tagged edge=yes point-to-point=yes
add bridge=iser interface=sfp-sfpplus2 pvid=100 hw=yes frame-types=admit-only-untagged-and-priority-tagged edge=yes point-to-point=yes
add bridge=iser interface=sfp-sfpplus3 pvid=100 hw=yes frame-types=admit-only-untagged-and-priority-tagged edge=yes point-to-point=yes
add bridge=iser interface=sfp-sfpplus4 pvid=100 hw=yes frame-types=admit-only-untagged-and-priority-tagged edge=yes point-to-point=yes
add bridge=iser interface=sfp-sfpplus5 pvid=100 hw=yes frame-types=admit-only-untagged-and-priority-tagged edge=yes point-to-point=yes
add bridge=iser interface=sfp-sfpplus6 pvid=100 hw=yes frame-types=admit-only-untagged-and-priority-tagged edge=yes point-to-point=yes
add bridge=iser interface=sfp-sfpplus7 pvid=100 hw=yes frame-types=admit-only-untagged-and-priority-tagged edge=yes point-to-point=yes
add bridge=iser interface=sfp-sfpplus8 pvid=100 hw=yes frame-types=admit-only-untagged-and-priority-tagged edge=yes point-to-point=yes

/interface ethernet
set sfp-sfpplus1 mtu=9000 l2mtu=9214 tx-flow-control=on rx-flow-control=on auto-negotiation=no speed=10Gbps full-duplex=yes
set sfp-sfpplus2 mtu=9000 l2mtu=9214 tx-flow-control=on rx-flow-control=on auto-negotiation=no speed=10Gbps full-duplex=yes
set sfp-sfpplus3 mtu=9000 l2mtu=9214 tx-flow-control=on rx-flow-control=on auto-negotiation=no speed=10Gbps full-duplex=yes
set sfp-sfpplus4 mtu=9000 l2mtu=9214 tx-flow-control=on rx-flow-control=on auto-negotiation=no speed=10Gbps full-duplex=yes
set sfp-sfpplus5 mtu=9000 l2mtu=9214 tx-flow-control=on rx-flow-control=on auto-negotiation=no speed=10Gbps full-duplex=yes
set sfp-sfpplus6 mtu=9000 l2mtu=9214 tx-flow-control=on rx-flow-control=on auto-negotiation=no speed=10Gbps full-duplex=yes
set sfp-sfpplus7 mtu=9000 l2mtu=9214 tx-flow-control=on rx-flow-control=on auto-negotiation=no speed=10Gbps full-duplex=yes
set sfp-sfpplus8 mtu=9000 l2mtu=9214 tx-flow-control=on rx-flow-control=on auto-negotiation=no speed=10Gbps full-duplex=yes

/interface bridge vlan
add bridge=iser vlan-ids=100 \
  untagged=sfp-sfpplus1,sfp-sfpplus2,sfp-sfpplus3,sfp-sfpplus4,sfp-sfpplus5,sfp-sfpplus6,sfp-sfpplus7,sfp-sfpplus8

/ip route add dst-address=0.0.0.0/0 gateway=92.92.92.1

/system ntp client
set enabled=yes
/system ntp client servers
add address=92.92.92.1
/system clock set time-zone-name=Asia/Ho_Chi_Minh

/ip dns set servers=92.92.92.1 allow-remote-requests=no

/ip ssh
set host-key-type=ed25519
regenerate-host-key
set strong-crypto=yes
set always-allow-password-login=no
set ciphers=aes-gcm

/ip service
set telnet disabled=yes
set ftp disabled=yes

/system identity set name=switch

/interface bridge set iser \
	admin-mac=[/interface bridge get iser mac-address] \
	auto-mac=no

/ip firewall filter
remove [find]
add chain=input action=accept connection-state=established,related comment="INPUT: established/related"
add chain=input action=drop connection-state=invalid comment="INPUT: drop invalid"
add chain=input action=accept protocol=icmp src-address=92.92.92.0/24 comment="INPUT: ICMP from LAN"
add chain=input action=accept protocol=tcp dst-port=22 src-address=92.92.92.0/24 connection-state=new comment="INPUT: SSH from LAN"
add chain=input action=accept protocol=tcp dst-port=80 src-address=92.92.92.0/24 connection-state=new comment="INPUT: Webfig from LAN"
add chain=input action=accept protocol=udp dst-port=161 src-address=92.92.92.13 comment="INPUT: SNMP from Zabbix"
add chain=input action=log log-prefix="FW-DROP-IN: " log=yes comment="INPUT: log before drop"
add chain=input action=drop comment="INPUT: drop all"
add chain=output action=accept connection-state=established,related comment="OUTPUT: established/related"
add chain=output action=drop connection-state=invalid comment="OUTPUT: drop invalid"
add chain=output action=accept protocol=icmp comment="OUTPUT: ICMP"
add chain=output action=accept protocol=udp dst-port=53 dst-address=92.92.92.1 comment="OUTPUT: DNS UDP to router"
add chain=output action=accept protocol=tcp dst-port=53 dst-address=92.92.92.1 comment="OUTPUT: DNS TCP to router"
add chain=output action=accept protocol=udp dst-port=123 dst-address=92.92.92.1 comment="OUTPUT: NTP to router"
add chain=output action=accept protocol=udp dst-port=514 dst-address=92.92.92.13 comment="OUTPUT: Syslog to Zabbix"
add chain=output action=accept protocol=udp dst-port=162 dst-address=92.92.92.13 comment="OUTPUT: SNMP trap to Zabbix"
add chain=output action=accept protocol=tcp dst-port=4505 dst-address=92.92.92.13 connection-state=new comment="OUTPUT: Salt publish to master"
add chain=output action=accept protocol=tcp dst-port=4506 dst-address=92.92.92.13 connection-state=new comment="OUTPUT: Salt return to master"
add chain=output action=accept protocol=udp dst-port=443 comment="OUTPUT: HTTP/3 QUIC package update"
add chain=output action=accept protocol=tcp dst-port=443 comment="OUTPUT: HTTPS package update"
add chain=output action=accept protocol=tcp dst-port=80 comment="OUTPUT: HTTP package update"
add chain=output action=log log-prefix="FW-DROP-OUT: " log=yes comment="OUTPUT: log before drop"
add chain=output action=drop comment="OUTPUT: drop all"
add chain=forward action=drop comment="FORWARD: no IP routing on this device"

/system package update download
/system reboot

# ---------------------------

/snmp community
add name=zabbix-iser \
	addresses=92.92.92.13/32 \
	security=private \
	read-access=yes \
	write-access=no \
	authentication-protocol=SHA256 \
	encryption-protocol=AES \
	authentication-password=<switch_sha256> \
	privacy-password=<switch_aes>
:foreach c in=[find name!="zabbix-iser"] do={ remove $c }

/snmp set \
	enabled=yes \
	contact="contact@quang.pro" \
	location="switch" \
	trap-version=3 \
	trap-community=zabbix-iser \
	trap-generators=interfaces \
	trap-target=92.92.92.13

/system logging action
add name=zabbix-syslog \
	target=remote \
	remote=92.92.92.13 \
	remote-port=514 \
	syslog-facility=local7 \
	syslog-severity=auto \
	bsd-syslog=no

/system logging
add action=zabbix-syslog topics=interface,critical
add action=zabbix-syslog topics=interface,error
add action=zabbix-syslog topics=interface,warning
add action=zabbix-syslog topics=system,warning
add action=zabbix-syslog topics=system,error
add action=zabbix-syslog topics=system,critical

/system script
add name=check-pause-frames \
	policy=read,write,test \
	source={
	:local threshold 50
	:local ports {"sfp-sfpplus1";"sfp-sfpplus2";"sfp-sfpplus3";"sfp-sfpplus4";"sfp-sfpplus5";"sfp-sfpplus6";"sfp-sfpplus7";"sfp-sfpplus8"}
	:global pf_init
	:global pf_prev_txp1; :global pf_prev_rxp1 :global pf_prev_txd1; :global pf_prev_rxd1
	:global pf_prev_txp2; :global pf_prev_rxp2 :global pf_prev_txd2; :global pf_prev_rxd2
	:global pf_prev_txp3; :global pf_prev_rxp3 :global pf_prev_txd3; :global pf_prev_rxd3
	:global pf_prev_txp4; :global pf_prev_rxp4 :global pf_prev_txd4; :global pf_prev_rxd4
	:global pf_prev_txp5; :global pf_prev_rxp5 :global pf_prev_txd5; :global pf_prev_rxd5
	:global pf_prev_txp6; :global pf_prev_rxp6 :global pf_prev_txd6; :global pf_prev_rxd6
	:global pf_prev_txp7; :global pf_prev_rxp7 :global pf_prev_txd7; :global pf_prev_rxd7
	:global pf_prev_txp8; :global pf_prev_rxp8 :global pf_prev_txd8; :global pf_prev_rxd8
	:local prevTxP {$pf_prev_txp1;$pf_prev_txp2;$pf_prev_txp3;$pf_prev_txp4;$pf_prev_txp5;$pf_prev_txp6;$pf_prev_txp7;$pf_prev_txp8}
	:local prevRxP {$pf_prev_rxp1;$pf_prev_rxp2;$pf_prev_rxp3;$pf_prev_rxp4;$pf_prev_rxp5;$pf_prev_rxp6;$pf_prev_rxp7;$pf_prev_rxp8}
	:local prevTxD {$pf_prev_txd1;$pf_prev_txd2;$pf_prev_txd3;$pf_prev_txd4;$pf_prev_txd5;$pf_prev_txd6;$pf_prev_txd7;$pf_prev_txd8}
	:local prevRxD {$pf_prev_rxd1;$pf_prev_rxd2;$pf_prev_rxd3;$pf_prev_rxd4;$pf_prev_rxd5;$pf_prev_rxd6;$pf_prev_rxd7;$pf_prev_rxd8}
	:for i from=1 to=8 do={
		:local ifname ($ports->($i - 1))
		:local isUp false
		:do {
			:set isUp [/interface ethernet get [find name=$ifname] running]
		} on-error={ :set isUp false }
		:if ($isUp) do={
			:local txDrop 0 :local rxDrop 0 :local txPause 0 :local rxPause 0
			:do {
				:local ifRef [/interface find name=$ifname]
				:local ifStats [/interface print stats as-value from=$ifRef]
				:if ([:len $ifStats] > 0) do={
					:local rec ($ifStats->0)
					:if (($rec->"tx-drop") != "") do={:set txDrop [:tonum ($rec->"tx-drop")]}
					:if (($rec->"rx-drop") != "") do={:set rxDrop [:tonum ($rec->"rx-drop")]}
				}
			} on-error={}
			:do {
				:local ethRef [/interface ethernet find name=$ifname]
				:local es [/interface ethernet print stats as-value from=$ethRef]
				:if ([:len $es] > 0) do={
					:local rec ($es->0)
					:if (($rec->"tx-pause") != "") do={:set txPause [:tonum ($rec->"tx-pause")]}
					:if (($rec->"rx-pause") != "") do={:set rxPause [:tonum ($rec->"rx-pause")]}
				}
			} on-error={}
			:if ($pf_init != true) do={
				/log info \
					message=("pf-check: baseline " . $ifname . " txP=" . $txPause . " rxP=" . $rxPause . " txD=" . $txDrop . " rxD=" . $rxDrop) \
					topics=interface,info
			} else={
				:local deltaTxP ($txPause - [:tonum ($prevTxP->($i-1))])
				:local deltaRxP ($rxPause - [:tonum ($prevRxP->($i-1))])
				:local deltaTxD ($txDrop  - [:tonum ($prevTxD->($i-1))])
				:local deltaRxD ($rxDrop  - [:tonum ($prevRxD->($i-1))])
				:if ($deltaTxP < 0) do={
					/log warning \
						message=("COUNTER RESET " . $ifname . " tx-pause (link flap?)") \
						topics=interface,warning
					:set deltaTxP 0
				}
				:if ($deltaRxP < 0) do={
					/log warning \
						message=("COUNTER RESET " . $ifname . " rx-pause (link flap?)") \
						topics=interface,warning
					:set deltaRxP 0
				}
				:if ($deltaTxD < 0) do={
					/log warning \
						message=("COUNTER RESET " . $ifname . " tx-drop (link flap?)") \
						topics=interface,warning
					:set deltaTxD 0
				}
				:if ($deltaRxD < 0) do={
					/log warning \
						message=("COUNTER RESET " . $ifname . " rx-drop (link flap?)") \
						topics=interface,warning
					:set deltaRxD 0
				}
				:if ($deltaTxP > $threshold) do={
					/log warning \
						message=("PAUSE TX " . $ifname . " delta=" . $deltaTxP) \
						topics=interface,warning
				}
				:if ($deltaRxP > $threshold) do={
					/log warning \
						message=("PAUSE RX " . $ifname . " delta=" . $deltaRxP) \
						topics=interface,warning
				}
				:if ($deltaTxD > 0) do={
					/log error \
						message=("TX DROP " . $ifname . " delta=" . $deltaTxD) \
						topics=interface,error
				}
				:if ($deltaRxD > 0) do={
					/log error \
						message=("RX DROP " . $ifname . " delta=" . $deltaRxD) \
						topics=interface,error
				}
			}
			:if ($i = 1) do={:set pf_prev_txp1 $txPause; :set pf_prev_rxp1 $rxPause :set pf_prev_txd1 $txDrop;  :set pf_prev_rxd1 $rxDrop}
			:if ($i = 2) do={:set pf_prev_txp2 $txPause; :set pf_prev_rxp2 $rxPause :set pf_prev_txd2 $txDrop;  :set pf_prev_rxd2 $rxDrop}
			:if ($i = 3) do={:set pf_prev_txp3 $txPause; :set pf_prev_rxp3 $rxPause :set pf_prev_txd3 $txDrop;  :set pf_prev_rxd3 $rxDrop}
			:if ($i = 4) do={:set pf_prev_txp4 $txPause; :set pf_prev_rxp4 $rxPause :set pf_prev_txd4 $txDrop;  :set pf_prev_rxd4 $rxDrop}
			:if ($i = 5) do={:set pf_prev_txp5 $txPause; :set pf_prev_rxp5 $rxPause :set pf_prev_txd5 $txDrop;  :set pf_prev_rxd5 $rxDrop}
			:if ($i = 6) do={:set pf_prev_txp6 $txPause; :set pf_prev_rxp6 $rxPause :set pf_prev_txd6 $txDrop;  :set pf_prev_rxd6 $rxDrop}
			:if ($i = 7) do={:set pf_prev_txp7 $txPause; :set pf_prev_rxp7 $rxPause :set pf_prev_txd7 $txDrop;  :set pf_prev_rxd7 $rxDrop}
			:if ($i = 8) do={:set pf_prev_txp8 $txPause; :set pf_prev_rxp8 $rxPause :set pf_prev_txd8 $txDrop;  :set pf_prev_rxd8 $rxDrop}
		}
	}
	:set pf_init true
}

/system scheduler
add name=pause-frame-check \
	interval=30s \
	on-event=check-pause-frames \
	policy=read,write,test
