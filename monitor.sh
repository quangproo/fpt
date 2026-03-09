#!/bin/bash
set -e

mkdir -p ~/.ssh
chmod -R 700 ~/.ssh

cat << EOF | tee ~/.ssh/authorized_keys
<monitor.pub.pem>
EOF

cat << EOF | tee ~/.ssh/config > /dev/null
Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  ForwardAgent yes

Host github.com
  HostName ssh.github.com
  Port 443
  IdentityFile ~/.ssh/github.pri.pem
  User git
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

# ----------------------------------------------------------------------

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

echo "source ~/env.sh" >> ~/.bashrc

cat << EOF | tee ~/env.sh
source /etc/os-release
export DEBIAN_FRONTEND=noninteractive
export CCACHE_DIR=\${HOME}/.ccache
export CC="/usr/lib/ccache/gcc-15"
export CXX="/usr/lib/ccache/g++-15"
export LD_LIBRARY_PATH=/lib64:/usr/lib/x86_64-linux-gnu:\${LD_LIBRARY_PATH}
export PATH="/usr/local/pgsql/bin:/usr/lib/ccache:\${PATH}"
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

# ----------------------------------------------------------------------

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
sudo apt install -y salt-minion

sudo mkdir -p /etc/salt/master.d /var/log/salt /opt/salt /opt/pillar
cat << 'EOF' | sudo tee /etc/salt/minion.d/local.conf
master: 92.92.92.10
id: monitor
log_level: warning
log_file: /var/log/salt/minion.log
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now salt-minion

# ----------------------------------------------------------------------

sudo apt install -y \
	iptables iptables-persistent

sudo mkdir -p /etc/iptables
cat << 'EOF' | sudo tee /etc/iptables/rules.v4
*filter
:INPUT   DROP  [0:0]
:FORWARD DROP  [0:0]
:OUTPUT  ACCEPT [0:0]

-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p icmp --icmp-type echo-request -s 92.92.92.0/24 -j ACCEPT
-A INPUT -p tcp --dport 22    -s 92.92.92.0/24 -m conntrack --ctstate NEW -j ACCEPT
-A INPUT -p tcp --dport 80    -m conntrack --ctstate NEW -j ACCEPT
-A INPUT -p tcp --dport 443   -m conntrack --ctstate NEW -j ACCEPT
-A INPUT -p udp --dport 443   -j ACCEPT
-A INPUT -p tcp --dport 4505  -s 92.92.92.0/24 -m conntrack --ctstate NEW -j ACCEPT
-A INPUT -p tcp --dport 4506  -s 92.92.92.0/24 -m conntrack --ctstate NEW -j ACCEPT
-A INPUT -p tcp --dport 10051 -s 92.92.92.10   -m conntrack --ctstate NEW -j ACCEPT
-A INPUT -p tcp --dport 10051 -s 92.92.92.12   -m conntrack --ctstate NEW -j ACCEPT
-A INPUT -p tcp --dport 10050 -s 127.0.0.1     -m conntrack --ctstate NEW -j ACCEPT
-A INPUT -p udp --dport 514   -s 92.92.92.2    -j ACCEPT
-A INPUT -p udp --dport 162   -s 92.92.92.2    -j ACCEPT
-A INPUT -m limit --limit 5/min --limit-burst 10 -j LOG --log-prefix "iptables-DROP-IN: " --log-level 4
-A INPUT -j DROP

-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -p udp --dport 53   -d 92.92.92.1  -j ACCEPT
-A OUTPUT -p tcp --dport 53   -d 92.92.92.1  -j ACCEPT
-A OUTPUT -p udp --dport 123  -d 92.92.92.1  -j ACCEPT
-A OUTPUT -p udp --dport 161  -d 92.92.92.2  -j ACCEPT
-A OUTPUT -p tcp --dport 10050 -d 92.92.92.10 -j ACCEPT
-A OUTPUT -p tcp --dport 10050 -d 92.92.92.12 -j ACCEPT
-A OUTPUT -p tcp --dport 4505 -d 92.92.92.10 -j ACCEPT
-A OUTPUT -p tcp --dport 4506 -d 92.92.92.10 -j ACCEPT
-A OUTPUT -p tcp --dport 80   -j ACCEPT
-A OUTPUT -p tcp --dport 443  -j ACCEPT
-A OUTPUT -p tcp --dport 587  -j ACCEPT
-A OUTPUT -p icmp -j ACCEPT
-A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

COMMIT
EOF

sudo chmod 600 /etc/iptables/rules.v4
sudo sh -c 'iptables-restore < /etc/iptables/rules.v4'
sudo netfilter-persistent save
sudo iptables -L -n -v --line-numbers


# ----------------------------------------------------------------------

sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y

# ----------------------------------------------------------------------

sudo apt install -y \
  libreadline-dev zlib1g-dev \
  flex bison libxml2-dev libxslt-dev libssl-dev libxml2-utils \
  xsltproc libkrb5-dev libldap2-dev libpam0g-dev \
  tcl-dev libperl-dev gettext libicu-dev

sudo mkdir -p /opt/git
sudo chown -R vt_admin:vt_admin /opt/git

cd /opt/git
rm -rf postgres
git clone --depth 1 https://github.com/postgres/postgres.git
cd postgres
git checkout master
make distclean 2>/dev/null || true
./configure \
  --prefix=/usr/local/pgsql \
  --with-openssl --with-libxml --with-libxslt \
  --with-icu --with-python --with-llvm \
  --disable-debug --disable-cassert \
  CC="${CC}" CXX="${CXX}" \
  LDFLAGS="-flto=auto -fuse-linker-plugin -Wl,--as-needed -Wl,-O2 -Wl,--strip-all" \
  CFLAGS="-O3 -march=native -mtune=native -fomit-frame-pointer -flto=auto -fuse-linker-plugin -ftree-vectorize -funroll-loops -fno-semantic-interposition -DNDEBUG -pipe" \
  CXXFLAGS="-O3 -march=native -mtune=native -fomit-frame-pointer -flto=auto -fuse-linker-plugin -ftree-vectorize -funroll-loops -fno-semantic-interposition -DNDEBUG -pipe"
make -j$(($(nproc) - 1)) world-bin
sudo make install-world-bin

sudo useradd -m -d /var/lib/postgresql -s /bin/bash postgres
sudo rm -rf /var/lib/postgresql/data
sudo mkdir -p /var/lib/postgresql/data
sudo chown postgres:postgres -R /var/lib/postgresql/data
sudo chmod 700 /var/lib/postgresql/data

sudo -u postgres /usr/local/pgsql/bin/initdb \
  -D /var/lib/postgresql/data

sudo sed -i \
	's/^#\?dynamic_shared_memory_type\s*=.*/dynamic_shared_memory_type = sysv/' \
	/var/lib/postgresql/data/postgresql.conf


sudo tee /etc/systemd/system/postgresql.service > /dev/null << 'EOF'
[Unit]
Description=PostgreSQL Database Server (Custom Build)
Documentation=https://www.postgresql.org/docs/
After=network.target

[Service]
Type=forking
User=postgres
Group=postgres
Environment=PGDATA=/var/lib/postgresql/data
PIDFile=/var/lib/postgresql/data/postmaster.pid
ExecStart=/usr/local/pgsql/bin/pg_ctl start -D /var/lib/postgresql/data -s -o "-p 5432 -c listen_addresses='*'"
ExecStop=/usr/local/pgsql/bin/pg_ctl stop -D /var/lib/postgresql/data -s -m fast
ExecReload=/usr/local/pgsql/bin/pg_ctl reload -D /var/lib/postgresql/data -s
Restart=on-failure
RestartSec=5s
TimeoutSec=300
TimeoutStartSec=300
TimeoutStopSec=300
LimitNOFILE=65536
LimitNPROC=4096
OOMScoreAdjust=-900

[Install]
WantedBy=multi-user.target
EOF
sudo chmod 644 /etc/systemd/system/postgresql.service

sudo systemctl daemon-reload
sudo systemctl enable --now postgresql

sudo rm -rf /opt/git/postgres


# ----------------------------------------------------------------------


sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:ondrej/php
sudo apt update
sudo apt install -y \
  php8.5 php8.5-fpm php8.5-pgsql \
  php8.5-bcmath php8.5-ctype php8.5-gd php8.5-mbstring \
  php8.5-xml php8.5-zip php8.5-curl php8.5-ldap

# export VER="5.4.8"
# cd /opt/git
# wget https://www.lua.org/ftp/lua-${VER}.tar.gz \
# 	-O /opt/git/lua.tar.gz
# tar -xzf /opt/git/lua.tar.gz
# cd lua-${VER}
# make linux test
# sudo make install
# lua -v
# rm -rf /opt/git/lua.tar.gz
# rm -rf /opt/git/lua-${VER}

# ----------------------------------------------------------------------

sudo apt install -y \
	libpcre3 libpcre3-dev zlib1g zlib1g-dev \
	libssl-dev libgd-dev libxml2 libxml2-dev uuid-dev \
	libpcre2-dev libgeoip-dev libxslt1-dev libatomic-ops-dev \
	libunwind-dev libyajl-dev libcurl4-openssl-dev liblmdb-dev \
	libmaxminddb-dev libfuzzy-dev ssdeep

cd /opt/git
rm -rf headers-more-nginx-module ngx_cache_purge ngx_devel_kit \
	lua-nginx-module lua-resty-core lua-resty-lrucache \
	set-misc-nginx-module echo-nginx-module lua-upstream-nginx-module
git clone https://github.com/openresty/headers-more-nginx-module.git
git clone https://github.com/FRiCKLE/ngx_cache_purge.git
git clone https://github.com/vision5/ngx_devel_kit.git
git clone https://github.com/openresty/lua-nginx-module.git
git clone https://github.com/openresty/lua-resty-core.git
git clone https://github.com/openresty/lua-resty-lrucache.git
git clone https://github.com/openresty/set-misc-nginx-module.git
git clone https://github.com/openresty/echo-nginx-module.git
git clone https://github.com/openresty/lua-upstream-nginx-module.git


cd /opt/git
rm -rf ngx_brotli
git clone --recurse-submodules https://github.com/google/ngx_brotli.git
rm -rf /opt/git/ngx_brotli/build
mkdir -p /opt/git/ngx_brotli/build
cd /opt/git/ngx_brotli/build
cmake -G Ninja \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_C_COMPILER="${CC}" \
	-DCMAKE_C_FLAGS="-O3 -march=native" \
	-DBUILD_SHARED_LIBS=OFF \
	../deps/brotli
ninja -j$(($(nproc) - 1))
sudo ninja install

cd /opt/git
rm -rf quictls
git clone --depth 1 https://github.com/quictls/openssl.git quictls
cd /opt/git/quictls
./Configure \
	enable-tls1_3 \
	no-shared \
	no-tests \
	--prefix=/opt/quictls \
	--openssldir=/opt/quictls/ssl \
	linux-x86_64 "-O3 -march=native -mtune=native -pipe"
make -j$(($(nproc) - 1))
sudo make install_sw

cd /opt/git
rm -rf luajit2
git clone https://github.com/openresty/luajit2.git
cd /opt/git/luajit2
make clean
make -j$(($(nproc) - 1)) \
	CFLAGS="-O3 -march=native -mtune=native -pipe"
sudo make install PREFIX=/opt/luajit
/opt/luajit/bin/luajit -v
export LUAJIT_LIB=/opt/luajit/lib
export LUAJIT_INC=/opt/luajit/include/luajit-2.1

cd /opt/git
rm -rf ModSecurity
git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity.git
cd ModSecurity
git submodule update --init --recursive
./build.sh
./configure \
	--prefix=/opt/modsecurity \
	--enable-shared \
	--enable-static \
	--with-yajl \
	--with-ssdeep \
	--with-lmdb \
	--with-maxmind \
	--with-pcre2 \
	CC="${CC}" CXX="${CXX}" \
	CFLAGS="-O3 -march=native -pipe" \
	CXXFLAGS="-O3 -march=native -pipe"
make -j$(($(nproc) - 1))
sudo make install
export MODSECURITY_LIB=/opt/modsecurity/lib
export MODSECURITY_INC=/opt/modsecurity/include

cd /opt/git
rm -rf ModSecurity-nginx
git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx.git

rm -rf /opt/git/ModSecurity-nginx/config
nano /opt/git/ModSecurity-nginx/config
# patch/ModSecurity-nginx/config

sudo ranlib /usr/lib/x86_64-linux-gnu/libGeoIP.a

export VER_NGINX="1.29.5"
cd /opt/git
wget https://nginx.org/download/nginx-${VER_NGINX}.tar.gz -O /opt/git/nginx.tar.gz
wget https://nginx.org/download/nginx-${VER_NGINX}.tar.gz.asc -O /opt/git/nginx.tar.gz.asc
wget https://nginx.org/keys/nginx_signing.key -O /opt/git/nginx_signing.key
gpg --import /opt/git/nginx_signing.key
gpg --verify /opt/git/nginx.tar.gz.asc /opt/git/nginx.tar.gz
tar -xzvf /opt/git/nginx.tar.gz -C /opt/git
cd /opt/git/nginx-${VER_NGINX}
make distclean 2>/dev/null || true

./configure \
	--prefix=/etc/nginx \
	--sbin-path=/usr/sbin/nginx \
	--modules-path=/usr/lib/nginx/modules \
	--conf-path=/etc/nginx/nginx.conf \
	--error-log-path=/var/log/nginx/error.log \
	--http-log-path=/var/log/nginx/access.log \
	--pid-path=/var/run/nginx.pid \
	--lock-path=/var/run/nginx.lock \
	--http-client-body-temp-path=/var/cache/nginx/client_temp \
	--http-proxy-temp-path=/var/cache/nginx/proxy_temp \
	--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
	--with-threads \
	--with-file-aio \
	--with-http_ssl_module \
	--with-http_v2_module \
	--with-http_v3_module \
	--with-http_realip_module \
	--with-http_gzip_static_module \
	--with-http_gunzip_module \
	--with-http_stub_status_module \
	--with-http_auth_request_module \
	--with-http_sub_module \
	--with-stream \
	--with-stream_ssl_module \
	--with-stream_realip_module \
	--with-compat \
	--add-module=/opt/git/ngx_devel_kit \
	--add-module=/opt/git/lua-nginx-module \
	--add-module=/opt/git/set-misc-nginx-module \
	--add-module=/opt/git/echo-nginx-module \
	--add-module=/opt/git/lua-upstream-nginx-module \
	--add-module=/opt/git/ngx_brotli \
	--add-module=/opt/git/headers-more-nginx-module \
	--add-module=/opt/git/ngx_cache_purge \
	--add-module=/opt/git/ModSecurity-nginx \
	--with-cc-opt="-O3 -march=native -mtune=native \
		-funroll-loops \
		-fstack-protector-strong \
		-flto=$(nproc) \
		-fomit-frame-pointer \
		-pipe \
		-I/opt/quictls/include \
		-I/opt/modsecurity/include \
		-I${LUAJIT_INC}" \
	--with-ld-opt="-flto=$(nproc) \
    -Wl,-O2 -Wl,--as-needed \
    -Wl,-Bstatic \
    -L/opt/quictls/lib64 -lssl -lcrypto \
    -L${LUAJIT_LIB} -l:libluajit-5.1.a \
    -L${MODSECURITY_LIB} -l:libmodsecurity.a \
    -l:libyajl_s.a -lpcre2-8 -llmdb -lmaxminddb -lGeoIP -lfuzzy \
    -lxml2 -lz -llzma -licuuc -licudata -licui18n \
    -Wl,-Bdynamic \
    -lcurl \
    -lm -ldl -lpthread -lstdc++"

make -j$(($(nproc) - 1))

sudo systemctl stop nginx 2>/dev/null || true
sudo systemctl disable nginx 2>/dev/null || true
sudo apt-get remove -y nginx nginx-core nginx-full nginx-light nginx-extras 2>/dev/null || true
sudo apt-get purge  -y nginx nginx-core nginx-full nginx-light nginx-extras 2>/dev/null || true
sudo rm -f /usr/sbin/nginx
sudo rm -f /usr/bin/nginx
sudo rm -f /var/run/nginx.pid
sudo rm -f /var/run/nginx.lock
sudo rm -f /etc/systemd/system/nginx.service
sudo rm -f /lib/systemd/system/nginx.service
sudo rm -rf /usr/lib/nginx
sudo rm -rf /var/cache/nginx
sudo rm -rf /var/log/nginx
sudo rm -rf /etc/nginx
sudo systemctl daemon-reload
sudo systemctl reset-failed

sudo make install


cd /opt/git
rm -rf coreruleset
git clone --depth 1 https://github.com/coreruleset/coreruleset.git
sudo mkdir -p /etc/nginx/modsecurity/crs
sudo cp -r coreruleset/rules /etc/nginx/modsecurity/crs/
sudo cp -r coreruleset/plugins /etc/nginx/modsecurity/crs/
sudo cp coreruleset/crs-setup.conf.example /etc/nginx/modsecurity/crs/crs-setup.conf
if [ -f /opt/modsecurity/share/modsecurity/unicode.mapping ]
then
	sudo cp /opt/modsecurity/share/modsecurity/unicode.mapping /etc/nginx/modsecurity/unicode.mapping
else
	sudo cp /opt/git/ModSecurity/unicode.mapping /etc/nginx/modsecurity/unicode.mapping
fi

sudo mkdir -p /var/log/nginx
for i in access.log error.log lua.log modsecurity_audit.log modsecurity_debug.log
do
	sudo touch /var/log/nginx/$i
	sudo chown nginx:nginx /var/log/nginx/$i
	sudo chmod 640 /var/log/nginx/$i
done


cat << 'EOF' | sudo tee /etc/nginx/modsecurity/modsecurity.conf > /dev/null
SecRuleEngine DetectionOnly
SecRequestBodyAccess On
SecRequestBodyLimit 13107200
SecRequestBodyNoFilesLimit 131072
SecRequestBodyLimitAction Reject
SecResponseBodyAccess Off
SecResponseBodyLimit 524288
SecResponseBodyLimitAction ProcessPartial
SecUploadDir /tmp
SecUploadKeepFiles Off
SecDebugLog /var/log/nginx/modsecurity_debug.log
SecDebugLogLevel 0
SecAuditEngine RelevantOnly
SecAuditLogRelevantStatus "^(?:5|4(?!04))"
SecAuditLogParts ABFHIJ
SecAuditLogType Serial
SecAuditLog /var/log/nginx/modsecurity_audit.log
SecArgumentSeparator &
SecCookieFormat 0
SecUnicodeMapFile /etc/nginx/modsecurity/unicode.mapping 20127
SecStatusEngine On
EOF

cat << 'EOF' | sudo tee /etc/nginx/modsecurity/main.conf > /dev/null
Include /etc/nginx/modsecurity/modsecurity.conf
Include /etc/nginx/modsecurity/crs/crs-setup.conf
Include /etc/nginx/modsecurity/crs/plugins/*-config.conf
Include /etc/nginx/modsecurity/crs/plugins/*-before.conf
Include /etc/nginx/modsecurity/crs/rules/*.conf
Include /etc/nginx/modsecurity/crs/plugins/*-after.conf
EOF

sudo chown -R root:nginx /etc/nginx/modsecurity
sudo find /etc/nginx/modsecurity -type d -exec chmod 750 {} \;
sudo find /etc/nginx/modsecurity -type f -exec chmod 640 {} \;
sudo touch /var/log/nginx/modsecurity_audit.log /var/log/nginx/modsecurity_debug.log
sudo chown nginx:nginx /var/log/nginx/modsecurity_audit.log /var/log/nginx/modsecurity_debug.log


sudo mkdir -p /etc/nginx/modsecurity/crs/plugins
sudo mkdir -p /etc/nginx/antibot

cat << 'EOF' | sudo tee /etc/nginx/modsecurity/crs/plugins/antibot-config.conf > /dev/null
# antibot plugin — disabled, challenge handled by Lua in nginx directly
EOF
cat << 'EOF' | sudo tee /etc/nginx/modsecurity/crs/plugins/antibot-before.conf > /dev/null
# antibot-before placeholder
EOF
cat << 'EOF' | sudo tee /etc/nginx/modsecurity/crs/plugins/antibot-after.conf > /dev/null
# antibot-after placeholder
EOF
# rm -rf antibot-plugin
# git clone --depth 1 git@github.com:coreruleset/antibot-plugin.git
# cd antibot-plugin
# sudo cp plugins/antibot-before.conf /etc/nginx/modsecurity/crs/plugins/
# sudo cp plugins/antibot-after.conf /etc/nginx/modsecurity/crs/plugins/
# sudo cp plugins/antibot-config.conf.example /etc/nginx/modsecurity/crs/plugins/antibot-config.conf
# sudo sed -i 's/^#\(.*antibot-plugin_enabled.*\)/\1/' /etc/nginx/modsecurity/crs/plugins/antibot-config.conf
# sudo cp antibot-plugin/plugins/antibot.html /etc/nginx/antibot/challenge.html 2>/dev/null || true

sudo tee /etc/nginx/antibot/challenge.html > /dev/null << 'EOF'
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Checking your browser</title></head>
<body>
<p>Please wait, verifying your browser...</p>
<script>
	document.cookie = "antibot=" + btoa(navigator.userAgent + Date.now()) + "; path=/";
	setTimeout(function(){ location.reload(); }, 1500);
</script>
</body>
</html>
EOF

sudo chown -R root:nginx /etc/nginx/modsecurity/crs/plugins
sudo chmod -R 750 /etc/nginx/modsecurity/crs/plugins
sudo chown -R root:nginx /etc/nginx/antibot
sudo chmod -R 750 /etc/nginx/antibot

cd /opt/git
VER_LUAROCKS="3.13.0"
wget https://luarocks.github.io/luarocks/releases/luarocks-${VER_LUAROCKS}.tar.gz -O luarocks.tar.gz
tar -xzf luarocks.tar.gz
cd luarocks-${VER_LUAROCKS}
make clean
./configure \
	--prefix=/opt/luajit \
	--with-lua=/opt/luajit \
	--with-lua-include=${LUAJIT_INC}
make -j$(($(nproc) - 1))
sudo make install
/opt/luajit/bin/luarocks --version

cd /opt/git/lua-resty-lrucache
sudo make install PREFIX=/etc/nginx
cd /opt/git/lua-resty-core
sudo make install PREFIX=/etc/nginx

sudo mkdir -p /var/cache/nginx/{client_temp,proxy_temp,fastcgi_temp}
sudo groupadd --system nginx 2>/dev/null || true
sudo useradd  --system \
	--gid nginx \
	--no-create-home \
	--home-dir /nonexistent \
	--shell /usr/sbin/nologin \
	--comment "nginx web server" \
	nginx 2>/dev/null || true
sudo chown -R nginx:nginx /var/log/nginx
sudo chown -R nginx:nginx /var/cache/nginx
sudo chown -R root:nginx  /etc/nginx
sudo chmod -R 750 /etc/nginx
sudo chown root:root /usr/sbin/nginx
sudo chmod 755 /usr/sbin/nginx


sudo mkdir -p /etc/nginx/layer7

cat << 'EOF' | sudo tee /etc/nginx/nginx.conf > /dev/null
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
events { worker_connections 1024; }
http {
	modsecurity on;
	modsecurity_rules_file /etc/nginx/modsecurity/main.conf;
	lua_package_path  "/etc/nginx/lib/lua/?.lua;;";
	lua_package_cpath "/etc/nginx/lib/lua/?.so;;";
	init_by_lua_block {
		require "resty.core"
		collectgarbage("collect")
		require "logger"
	}
	lua_code_cache on;
	log_format json_access escape=json
		'{'
			'"time":"$time_iso8601",'
			'"remote_addr":"$remote_addr",'
			'"method":"$request_method",'
			'"uri":"$uri",'
			'"args":"$args",'
			'"status":$status,'
			'"bytes_sent":$bytes_sent,'
			'"request_time":$request_time,'
			'"upstream_addr":"$upstream_addr",'
			'"upstream_status":"$upstream_status",'
			'"upstream_response_time":"$upstream_response_time",'
			'"http_referer":"$http_referer",'
			'"http_user_agent":"$http_user_agent",'
			'"http_x_forwarded_for":"$http_x_forwarded_for",'
			'"request_id":"$request_id"'
		'}';
	access_log /var/log/nginx/access.log json_access buffer=64k flush=5s gzip;
	include mime.types;
	default_type application/octet-stream;
	sendfile on;
	keepalive_timeout 65;
	map $request_id $req_id { default $request_id; }
	include /etc/nginx/layer7/*.conf;
}
EOF

cat << EOF | sudo tee /etc/nginx/layer7/default.conf > /dev/null
server {
	listen 80;
	server_name localhost;
	error_log /var/log/nginx/error.log warn;
	location / {
		root html;
		index index.html index.htm;
	}
	location /lua-test {
		default_type text/plain;
		content_by_lua_block {
			local log = require "logger"
			log.info("lua-test hit")
			ngx.say("Lua OK - ", jit.version)
		}
	}
	error_page 500 502 503 504 /50x.html;
	location = /50x.html { root html; }
}
EOF

cat << 'EOF' | sudo tee /etc/logrotate.d/nginx > /dev/null
/var/log/nginx/access.log
/var/log/nginx/error.log
/var/log/nginx/lua.log
{
	daily
	rotate 30
	compress
	delaycompress
	missingok
	notifempty
	create 0640 nginx nginx
	sharedscripts
	dateext
	dateformat -%Y%m%d
	postrotate
		if [ -f /var/run/nginx.pid ]
		then
			kill -USR1 $(cat /var/run/nginx.pid)
		fi
	endscript
}
EOF

cat << 'EOF' | sudo tee /etc/logrotate.d/modsecurity > /dev/null
/var/log/nginx/modsecurity_audit.log
/var/log/nginx/modsecurity_debug.log
{
	daily
	rotate 30
	compress
	delaycompress
	missingok
	notifempty
	create 0640 nginx nginx
	sharedscripts
	dateext
	dateformat -%Y%m%d
	postrotate
		if [ -f /var/run/nginx.pid ]
		then
			kill -USR1 $(cat /var/run/nginx.pid)
		fi
	endscript
}
EOF
sudo chmod 644 /etc/logrotate.d/nginx /etc/logrotate.d/modsecurity

sudo logrotate --debug /etc/logrotate.d/nginx
sudo logrotate --debug /etc/logrotate.d/modsecurity

sudo mkdir -p /etc/nginx/lib/lua

cat << 'EOF' | sudo tee /etc/nginx/lib/lua/logger.lua > /dev/null
local _M = {}
local log_file = "/var/log/nginx/lua.log"
local level_map = {
	debug = ngx.DEBUG,
	info = ngx.INFO,
	warn = ngx.WARN,
	error = ngx.ERR,
}
local function write(level, msg)
  ngx.log(level, msg)
end
function _M.debug(msg) write(ngx.DEBUG,  msg) end
function _M.info(msg)  write(ngx.INFO,   msg) end
function _M.warn(msg)  write(ngx.WARN,   msg) end
function _M.error(msg) write(ngx.ERR,    msg) end
return _M
EOF
sudo chown root:nginx /etc/nginx/lib/lua/logger.lua
sudo chmod 640 /etc/nginx/lib/lua/logger.lua

sudo ldconfig

sudo nginx -t

cat << 'EOF' | sudo tee /etc/systemd/system/nginx.service > /dev/null
[Unit]
Description=NGINX HTTP Server
After=network.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true
NoNewPrivileges=false

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now nginx
sudo systemctl status nginx

cd /opt/git
for i in \
	headers-more-nginx-module ngx_cache_purge ngx_brotli quictls \
	ngx_devel_kit lua-nginx-module lua-resty-core lua-resty-lrucache \
	set-misc-nginx-module echo-nginx-module lua-upstream-nginx-module \
	luajit2 coreruleset ModSecurity ModSecurity-nginx luarocks.tar.gz \
	nginx.tar.gz nginx.tar.gz.asc nginx_signing.key \
	nginx-${VER_NGINX} luarocks-${VER_LUAROCKS}
do
	sudo rm -rf /opt/git/${i}
done

# ----------------------------------------------------------------------

wget https://repo.zabbix.com/zabbix/8.0/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_8.0%2B${ID}${VERSION_ID}_all.deb \
  -O /tmp/zabbix.deb
sudo dpkg -i /tmp/zabbix.deb
rm -rf /tmp/zabbix.deb

sudo apt install -y \
	zabbix-server-pgsql zabbix-frontend-php \
	zabbix-sql-scripts zabbix-agent \
	rsyslog logrotate \
	snmp snmptrapd snmp-mibs-downloader libsnmp-dev

# ----------------------------------------------------------------------

export ZabbixDB="<ZabbixDB>"
export ZabbixUI="<ZabbixUI>"

sudo -u postgres bash -c "cat >> /var/lib/postgresql/data/pg_hba.conf << 'EOF'
# TYPE  DATABASE  USER  ADDRESS  METHOD
host  zabbix  zabbix   127.0.0.1/32  scram-sha-256
EOF"
sudo systemctl reload postgresql

sudo -u postgres /usr/local/pgsql/bin/psql << EOF
DROP DATABASE IF EXISTS zabbix;
DROP USER IF EXISTS zabbix;
CREATE USER zabbix WITH ENCRYPTED PASSWORD '${ZabbixDB}';
CREATE DATABASE zabbix OWNER zabbix
  LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8';
GRANT ALL PRIVILEGES ON DATABASE zabbix TO zabbix;
GRANT ALL ON SCHEMA public TO zabbix;
EOF

# ----------------------------------------------------------------------

sudo apt install -y pgbouncer

sudo groupadd --system pgbouncer 2>/dev/null || true
sudo useradd  --system \
	--gid pgbouncer \
	--no-create-home \
	--home-dir /nonexistent \
	--shell /usr/sbin/nologin \
	--comment "PgBouncer connection pooler" \
	pgbouncer 2>/dev/null || true
	
sudo mkdir -p /etc/pgbouncer /var/log/pgbouncer /var/run/pgbouncer
sudo chown pgbouncer:pgbouncer /var/log/pgbouncer /var/run/pgbouncer

sudo -u postgres /usr/local/pgsql/bin/psql \
	-h 127.0.0.1 -t -A \
	-c "SELECT '\"' || usename || '\" \"' || passwd || '\"'
		FROM pg_shadow WHERE usename = 'zabbix';" \
	> /tmp/pgbouncer_userlist.txt
sudo mv /tmp/pgbouncer_userlist.txt /etc/pgbouncer/userlist.txt
sudo chown pgbouncer:pgbouncer /etc/pgbouncer/userlist.txt
sudo chmod 640 /etc/pgbouncer/userlist.txt

cat << 'EOF' | sudo tee /etc/pgbouncer/pgbouncer.ini > /dev/null
[databases]
zabbix = host=127.0.0.1 port=5432 dbname=zabbix

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_file = /etc/pgbouncer/userlist.txt
auth_type = scram-sha-256
pool_mode = transaction
default_pool_size = 40
max_client_conn = 200
reserve_pool_size = 5
reserve_pool_timeout = 3
server_idle_timeout = 60
client_idle_timeout = 120
server_lifetime = 3600
logfile = /var/log/pgbouncer/pgbouncer.log
pidfile = /var/run/pgbouncer/pgbouncer.pid
log_connections = 0
log_disconnections = 0
log_stats   = 1
stats_period = 60
admin_users  = postgres
stats_users  = postgres
EOF
sudo chown pgbouncer:pgbouncer /etc/pgbouncer/pgbouncer.ini
sudo chmod 640 /etc/pgbouncer/pgbouncer.ini

cat << 'EOF' | sudo tee /etc/systemd/system/pgbouncer.service > /dev/null
[Unit]
Description=PgBouncer connection pooler for PostgreSQL
After=postgresql.service
Requires=postgresql.service

[Service]
Type=forking
User=pgbouncer
Group=pgbouncer
PIDFile=/var/run/pgbouncer/pgbouncer.pid
RuntimeDirectory=pgbouncer
RuntimeDirectoryMode=0755
ExecStart=/usr/sbin/pgbouncer -d /etc/pgbouncer/pgbouncer.ini
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now pgbouncer


cat << EOF | sudo tee /etc/zabbix/zabbix_server.conf > /dev/null
DBHost=127.0.0.1
DBName=zabbix
DBUser=zabbix
DBPassword=${ZabbixDB}
DBPort=6432
ListenIP=0.0.0.0
ListenPort=10051
StartPollers=10
StartPollersUnreachable=2
StartTrappers=5
StartPingers=3
StartDiscoverers=2
StartHTTPPollers=2
StartTimers=2
StartEscalators=2
StartAlerters=3
StartPreprocessors=4
StartDBSyncers=4
CacheSize=64M
HistoryCacheSize=32M
HistoryIndexCacheSize=16M
TrendCacheSize=16M
ValueCacheSize=64M
VMwareCacheSize=8M
HousekeepingFrequency=1
MaxHousekeeperDelete=5000
LogType=file
LogFile=/var/log/zabbix/zabbix_server.log
LogFileSize=10
DebugLevel=3
LogSlowQueries=3000
Timeout=10
TrapperTimeout=300
UnreachablePeriod=45
UnavailableDelay=60
UnreachableDelay=15
AlertScriptsPath=/usr/lib/zabbix/alertscripts
ExternalScripts=/usr/lib/zabbix/externalscripts
FpingLocation=/usr/bin/fping
TmpDir=/tmp
PidFile=/run/zabbix/zabbix_server.pid
SocketDir=/run/zabbix
AllowUnsupportedDBVersions=1
SNMPTrapperFile=/var/log/zabbix/snmptraps.log
StartSNMPTrapper=1
EOF
sudo chmod 640 /etc/zabbix/zabbix_server.conf
sudo chown root:zabbix /etc/zabbix/zabbix_server.conf


cat << EOF | sudo tee /etc/zabbix/zabbix_agentd.conf > /dev/null
PidFile=/run/zabbix/zabbix_agentd.pid
LogFile=/var/log/zabbix/zabbix_agentd.log
LogFileSize=10
Server=127.0.0.1
ServerActive=127.0.0.1
Hostname=Zabbix server
LogRemoteCommands=1
Include=/etc/zabbix/zabbix_agentd.d/*.conf
EOF
sudo chmod 640 /etc/zabbix/zabbix_agentd.conf
sudo chown root:zabbix /etc/zabbix/zabbix_agentd.conf


sudo mkdir -p /etc/php/8.5/fpm/pool.d
cat << EOF | sudo tee /etc/php/8.5/fpm/pool.d/zabbix.conf > /dev/null
[zabbix]
user  = www-data
group = www-data
listen = /run/php/php8.5-fpm-zabbix.sock
listen.owner = nginx
listen.group = nginx
listen.mode  = 0660
pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 8
pm.max_requests = 500
php_value[session.save_handler] = files
php_value[session.save_path]    = /var/lib/php/sessions
php_value[max_execution_time] = 300
php_value[memory_limit] = 128M
php_value[post_max_size] = 16M
php_value[upload_max_filesize] = 2M
php_value[max_input_time] = 300
php_value[max_input_vars] = 10000
php_value[date.timezone] = Asia/Ho_Chi_Minh
EOF

sudo systemctl restart php8.5-fpm


sudo mv /etc/nginx/layer7/default.conf /etc/nginx/layer7/default.conf.disable
cat << 'EOF' | sudo tee /etc/nginx/layer7/zabbix_base.conf.disable > /dev/null
server {
	listen 80;
	root /usr/share/zabbix/ui;
	index index.php;
	client_max_body_size 16M;
	access_log  /var/log/nginx/zabbix.access.log;
	error_log   /var/log/nginx/zabbix.error.log;
	location = /favicon.ico { log_not_found off; access_log off; }
	location = /robots.txt  { allow all; log_not_found off; access_log off; }
	location ~* \.(htaccess|htpasswd|conf|bak|sql|sh)$ {deny all;}
	location ~ ^/(app|include|modules|local)/ {deny all;}
	location / { try_files $uri $uri/ /index.php$is_args$args; }
	location ~ \.php$ {
		include fastcgi_params;
		fastcgi_pass unix:/run/php/php8.5-fpm-zabbix.sock;
		fastcgi_index index.php;
		fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
		fastcgi_param HTTP_PROXY "";
		fastcgi_buffers 8 16k;
		fastcgi_buffer_size 32k;
		fastcgi_read_timeout 300;
	}
	location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
		expires 30d;
		add_header Cache-Control "public, no-transform";
		log_not_found off;
	}
}
EOF

cat << 'EOF' | sudo tee /etc/nginx/layer7/zabbix_antibot.conf > /dev/null
geo $antibot_trusted {
	default 0;
	127.0.0.1/32 1;
	92.92.92.0/24 1;
}

server {
	listen 80;
	root /usr/share/zabbix/ui;
	index index.php;
	client_max_body_size 16M;
	access_log /var/log/nginx/zabbix.access.log json_access buffer=32k flush=5s gzip;
	error_log  /var/log/nginx/zabbix.error.log warn;
	access_by_lua_block {
		if ngx.var.antibot_trusted == "1" then return end
		local uri = ngx.var.uri
		if uri:match("%.js$") or uri:match("%.css$")
			or uri:match("%.png$") or uri:match("%.ico$")
			or uri:match("%.woff2?$")
		then return end
		if uri == "/antibot-challenge" or uri == "/antibot-verify" then return end
		local cookie = ngx.var.cookie_antibot
		if cookie ~= "verified" then
			local returnto = ngx.escape_uri(ngx.var.request_uri)
			return ngx.redirect("/antibot-challenge?returnto=" .. returnto, ngx.HTTP_FOUND)
		end
	}
	location = /favicon.ico { log_not_found off; access_log off; }
	location = /robots.txt  { allow all; log_not_found off; access_log off; }
	location ~* \.(htaccess|htpasswd|conf|bak|sql|sh)$ { deny all; }
	location ~ ^/(app|include|modules|local)/ { deny all; }
	location = /antibot-challenge {
		default_type text/html;
		root /etc/nginx/antibot;
		try_files /challenge.html =503;
		add_header Cache-Control "no-store, no-cache, must-revalidate" always;
		add_header Pragma "no-cache" always;
	}
	location = /antibot-verify {
		default_type application/json;
		content_by_lua_block {
			local args   = ngx.req.get_uri_args()
			local returnto = args.returnto
			if not returnto or returnto:sub(1,1) ~= "/" then returnto = "/" end
			ngx.header["Set-Cookie"] = table.concat({
				"antibot=verified",
				"Path=/",
				"HttpOnly",
				"SameSite=Lax",
				"Max-Age=3600",
			}, "; ")
			return ngx.redirect(returnto, ngx.HTTP_FOUND)
		}
	}
	location / { try_files $uri $uri/ /index.php$is_args$args; }
	location ~ \.php$ {
		include fastcgi_params;
		fastcgi_pass unix:/run/php/php8.5-fpm-zabbix.sock;
		fastcgi_index index.php;
		fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
		fastcgi_param HTTP_PROXY "";
		fastcgi_buffers 8 16k;
		fastcgi_buffer_size 32k;
		fastcgi_read_timeout 300;
	}
	location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
		expires 30d;
		add_header Cache-Control "public, no-transform";
		log_not_found off;
	}
}
EOF


sudo nginx -t

sudo usermod -aG zabbix zabbix
sudo chown -R zabbix:zabbix /var/log/zabbix

sudo wget https://download.mikrotik.com/routeros/7.21.3/mikrotik.mib \
	-O /usr/share/snmp/mibs/MIKROTIK-MIB-7.21.3.txt
sudo wget https://download.mikrotik.com/routeros/7.19.6/mikrotik.mib \
	-O /usr/share/snmp/mibs/MIKROTIK-MIB-7.19.6.txt
sudo rm -f /usr/share/snmp/mibs/MIKROTIK-MIB.txt
sudo ln -s /usr/share/snmp/mibs/MIKROTIK-MIB-7.21.3.txt /usr/share/snmp/mibs/MIKROTIK-MIB.txt
sudo mkdir -p /etc/snmp/snmptrapd.conf.d
cat << EOF | sudo tee /etc/snmp/snmptrapd.conf > /dev/null
includeDir /etc/snmp/snmptrapd.conf.d
doNotLogTraps no
mibs +MIKROTIK-MIB
EOF

sudo touch /var/log/zabbix/snmptraps.log
sudo chmod 640 /var/log/zabbix/snmptraps.log
cat << EOF | sudo tee /etc/logrotate.d/zabbix-snmptraps > /dev/null
/var/log/zabbix/snmptraps.log {
	daily
	rotate 30
	compress
	delaycompress
	missingok
	notifempty
	create 0640 zabbix zabbix
	postrotate /usr/lib/rsyslog/rsyslog-rotate
	endscript
}
EOF

sudo apt install -y libsnmp-perl
sudo mkdir -p /usr/share/zabbix/mibs
sudo wget "https://git.zabbix.com/projects/ZBX/repos/zabbix/raw/misc/snmptrap/zabbix_trap_receiver.pl" \
  -O /usr/share/zabbix/mibs/zabbix_trap_receiver.pl
sudo sed -i \
  "s|^\$SNMPTrapperFile = '/tmp/zabbix_traps.tmp';|\$SNMPTrapperFile = '/var/log/zabbix/snmptraps.log';|" \
  /usr/share/zabbix/mibs/zabbix_trap_receiver.pl
sudo chmod 755 /usr/share/zabbix/mibs/zabbix_trap_receiver.pl
sudo chown root:zabbix /usr/share/zabbix/mibs/zabbix_trap_receiver.pl

sudo mkdir -p /etc/systemd/system/zabbix-server.service.d
cat << 'EOF' | sudo tee /etc/systemd/system/zabbix-server.service.d/override.conf
[Unit]
After=postgresql.service pgbouncer.service
Before=postgresql.service pgbouncer.service

[Service]
TimeoutStopSec=30
KillMode=mixed
KillSignal=SIGTERM
FinalKillSignal=SIGKILL
ExecStop=/bin/sh -c 'pkill -TERM -f zabbix_server || true'
ExecStopPost=/bin/sh -c 'sleep 3; pkill -9 -f zabbix_server 2>/dev/null || true'
ExecStopPost=/bin/rm -f /run/zabbix/zabbix_server.pid
EOF


# ------------------------------

sudo apt install -y \
	libsnmp-dev libssh2-1-dev libevent-dev libcurl4-openssl-dev

cd /opt/git
rm -rf zabbix
git clone --depth 1 https://github.com/zabbix/zabbix.git
cd zabbix
sed -i '/disable.*nonstandard use.*string literal/{N;N;N;N;d}' src/libs/zbxdb/dbconn.c
./bootstrap.sh
make clean
./configure \
	--enable-server \
	--with-postgresql=/usr/local/pgsql/bin/pg_config \
	--with-openssl \
	--with-libcurl \
	--with-libxml2 \
	--with-net-snmp \
	--with-ssh2
make -j$(($(nproc) - 1))
sudo cp src/zabbix_server/zabbix_server /usr/sbin/zabbix_server

sudo rm -rf /usr/share/zabbix/ui
sudo cp -r ui /usr/share/zabbix/ui
sudo chown -R www-data:www-data /usr/share/zabbix/ui
sudo chmod -R 755 /usr/share/zabbix/ui

cd /opt/git/zabbix
make dbschema
cat database/postgresql/schema.sql \
	database/postgresql/images.sql \
	database/postgresql/data.sql | \
	sudo -u postgres /usr/local/pgsql/bin/psql -U zabbix zabbix

ZabbixUIHash=$(php -r "echo password_hash('${ZabbixUI}', PASSWORD_BCRYPT, ['cost' => 10]);")
sudo -u postgres /usr/local/pgsql/bin/psql -U zabbix zabbix << EOF
UPDATE users SET passwd='${ZabbixUIHash}' WHERE username='Admin';
EOF

cat << EOF | sudo tee /usr/share/zabbix/ui/conf/zabbix.conf.php > /dev/null 
<?php
\$DB['TYPE'] = 'POSTGRESQL';
\$DB['SERVER'] = '127.0.0.1';
\$DB['PORT'] = '6432';
\$DB['DATABASE'] = 'zabbix';
\$DB['USER'] = 'zabbix';
\$DB['PASSWORD'] = '${ZabbixDB}';
\$DB['SCHEMA'] = 'public';
\$DB['ENCRYPTION'] = false;
\$ZBX_SERVER = '127.0.0.1';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = 'Zabbix server';
\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
EOF
sudo chown www-data:www-data /usr/share/zabbix/ui/conf/zabbix.conf.php
sudo chmod 640 /usr/share/zabbix/ui/conf/zabbix.conf.php

rm -rf /opt/git/zabbix

# /opt/git/zabbix/src/libs/zbxdb/dbconn.c
# ----------
# -	/* disable "nonstandard use of \' in a string literal" warning */
# -	if (0 < (ret = dbconn_execute(db, "set escape_string_warning to off")))
# -		ret = ZBX_DB_OK;
# -
# -	if (ZBX_DB_OK != ret)
# -		goto out;
# +	/* disable "nonstandard use of \' in a string literal" warning */
# +	/* escape_string_warning GUC was removed in PostgreSQL 18 */
# +	if (180000 > db_get_server_version())
# +	{
# +		if (0 < (ret = dbconn_execute(db, "set escape_string_warning to off")))
# +			ret = ZBX_DB_OK;
# +
# +		if (ZBX_DB_OK != ret)
# +			goto out;
# +	}


sudo sed -i 's/if (!array_key_exists(\$widget_last_type, \$known_widgets)) {/if ($widget_last_type === null || !array_key_exists($widget_last_type, $known_widgets)) {/' \
	/usr/share/zabbix/ui/include/classes/helpers/CDashboardHelper.php

# /usr/share/zabbix/ui/include/classes/helpers/CDashboardHelper.php
# ----------
# -	$widget_last_type = CProfile::get('web.dashboard.last_widget_type');
# -
# -	if (!array_key_exists($widget_last_type, $known_widgets)) {
# +	$widget_last_type = CProfile::get('web.dashboard.last_widget_type');
# +
# +	if ($widget_last_type === null || !array_key_exists($widget_last_type, $known_widgets)) {

# ------------------------------

sudo systemctl daemon-reload
sudo systemctl restart nginx
sudo systemctl restart logrotate
sudo systemctl enable --now snmptrapd
sudo systemctl enable --now zabbix-server
sudo systemctl enable --now zabbix-agent

unset DBPassword
unset UIPassword
unset UIPasswordHash

# ----------------------------------------------------------------------

export DEVICE_ID="0xXXXXXXXXXXXXX"  # /snmp print
export DEVICE_NAME="zabbix-iser"
export DEVICE_SHA256="<switch_sha256>"
export DEVICE_AES128="<switch_aes>"


sudo systemctl stop snmptrapd

sudo touch /var/log/zabbix/${DEVICE_NAME}.log
sudo chown zabbix:zabbix /var/log/zabbix/${DEVICE_NAME}.log
sudo chmod 640 /var/log/zabbix/${DEVICE_NAME}.log

cat << EOF | sudo tee /etc/rsyslog.d/${DEVICE_NAME}.conf > /dev/null
module(load="imudp")
input(type="imudp" port="514")
template(name="MikrotikFormat" type="string"
  string="%timegenerated:::date-rfc3339% %HOSTNAME% %syslogtag%%msg%\n")
if (\$fromhost-ip == '92.92.92.2') then {
	action(
		type="omfile"
		file="/var/log/zabbix/${DEVICE_NAME}.log"
		template="MikrotikFormat"
		fileCreateMode="0640"
		dirCreateMode="0750"
		fileOwner="zabbix"
		fileGroup="zabbix"
	)
	stop
}
EOF
sudo rsyslogd -N1

cat << EOF | sudo tee /etc/logrotate.d/${DEVICE_NAME} > /dev/null
/var/log/zabbix/${DEVICE_NAME}.log {
	daily
	rotate 30
	compress
	delaycompress
	missingok
	notifempty
	create 0640 zabbix zabbix
	postrotate /usr/lib/rsyslog/rsyslog-rotate
	endscript
}
EOF

if ! sudo grep -q "${DEVICE_NAME}" /var/lib/snmp/snmptrapd.conf 2>/dev/null
then
cat << EOF | sudo tee -a /var/lib/snmp/snmptrapd.conf > /dev/null
createUser -e ${DEVICE_ID} ${DEVICE_NAME} SHA-256 "${DEVICE_SHA256}" AES "${DEVICE_AES128}"
EOF
fi
sudo chmod 600 /var/lib/snmp/snmptrapd.conf

cat << EOF | sudo tee /etc/snmp/snmptrapd.conf.d/${DEVICE_NAME}.conf > /dev/null
authUser log,execute,net ${DEVICE_NAME} priv
traphandle default /usr/bin/perl /usr/share/zabbix/mibs/zabbix_trap_receiver.pl
EOF
sudo chmod 640 /etc/snmp/snmptrapd.conf.d/${DEVICE_NAME}.conf
sudo chown root:zabbix /etc/snmp/snmptrapd.conf.d/${DEVICE_NAME}.conf

sudo systemctl start snmptrapd
sudo systemctl restart rsyslog
sudo systemctl restart zabbix-agent



# ----------------------------------------------------------------------
# Zabbix UI
# ----------------------------------------------------------------------

# wget "https://git.zabbix.com/projects/ZBX/repos/zabbix/raw/templates/net/mikrotik_snmp/template_net_mikrotik_snmp.yaml" \
#	-O snmp_mikrotik.yaml

Alerts / Media types / Create media type
	Name: contact@quang.pro
	Type: Email
	Email provider: Gmail
	Email: contact@quang.pro
	Authentication: Username and password
	Password: <Gmail App>
	Message format: HTML
	Enabled: True

Users / Users / Admin / Media / Add
	Type: contact@quang.pro
	Send to: contact@quang.pro
	Use if severity: [High, Disaster]

Alerts / Actions / Trigger actions / Create action
	Action
		Name: Email
		Conditions:
			Type: Trigger severity
			Operator: >=
			Severity: High
		Enabled: True
	Operations:
		Default operation step duration: 1h
		Operations:
			Operation: Send message
			Send to users: Admin
			Send to media type: contact@quang.pro
		Recovery operations:
			Operation: Notify all involved

Data Collection / Hosts groups / Create host group
	Group name: Network

# ------------------------------

echo $DEVICE_NAME
echo $DEVICE_SHA256  # <switch_sha256>
echo $DEVICE_AES128  # <switch_aes>

Data Collection / Hosts / Create host
	Host name: $DEVICE_NAME
	Host groups: Network
	Templates: clear
	Interface / SNMP:
		SNMP: 92.92.92.2
		Port: 161
		SNMP version: SNMPv3
		Security name: $DEVICE_NAME
		Security level: authPriv
		Authentication protocol: SHA256
		Authentication passphrase: $DEVICE_SHA256
		Privacy protocol: AES128
		Privacy passphrase: $DEVICE_AES128
	
Data Collection / Hosts / Zabbix Server / Items / Create item
	Name: $DEVICE_NAME
	Type: Zabbix agent
	Key: log[/var/log/zabbix/$DEVICE_NAME.log,TX DROP|RX DROP|PAUSE TX|PAUSE RX|COUNTER RESET,UTF-8,10,skip]
	Type of information: Log
	Update interval: 30s
	Host interface: 127.0.0.1:10050

Data Collection / Hosts / $DEVICE_NAME  / Items / Create item
	Name: SNMP traps
	Type: SNMP trap
	Key: snmptrap.fallback
	Type of information: Log


Data Collection / Hosts / $DEVICE_NAME / Triggers / Create trigger
	Name: TX/RX Drop
	Severity: Disaster
	Problem expression:
		find(/Zabbix server/log[/var/log/zabbix/$DEVICE_NAME.log,TX DROP|RX DROP|PAUSE TX|PAUSE RX|COUNTER RESET,UTF-8,10,skip],60s,"regexp","TX DROP|RX DROP")=1
	Recovery expression:
		find(/Zabbix server/log[/var/log/zabbix/$DEVICE_NAME.log,TX DROP|RX DROP|PAUSE TX|PAUSE RX|COUNTER RESET,UTF-8,10,skip],180s,"regexp","TX DROP|RX DROP")=0

	Name: Pause frame
	Severity: High
	Problem expression:
		find(/Zabbix server/log[/var/log/zabbix/$DEVICE_NAME.log,TX DROP|RX DROP|PAUSE TX|PAUSE RX|COUNTER RESET,UTF-8,10,skip],60s,"regexp","PAUSE TX|PAUSE RX")=1
	Recovery expression:
		find(/Zabbix server/log[/var/log/zabbix/$DEVICE_NAME.log,TX DROP|RX DROP|PAUSE TX|PAUSE RX|COUNTER RESET,UTF-8,10,skip],180s,"regexp","PAUSE TX|PAUSE RX")=0

	Name: Interface down
	Severity: High
	Problem expression:
		find(/$DEVICE_NAME/snmptrap.fallback,120s,"like","linkDown")=1  # echo $DEVICE_NAME before paste
	Recovery expression:
		find(/$DEVICE_NAME/snmptrap.fallback,120s,"like","linkUp")=1  # echo $DEVICE_NAME before paste

	Name: Link flap
	Severity: Warning
	Problem expression:
		find(/Zabbix server/log[/var/log/zabbix/$DEVICE_NAME.log,TX DROP|RX DROP|PAUSE TX|PAUSE RX|COUNTER RESET,UTF-8,10,skip],60s,"regexp","COUNTER RESET")=1
	Recovery expression:
		find(/Zabbix server/log[/var/log/zabbix/$DEVICE_NAME.log,TX DROP|RX DROP|PAUSE TX|PAUSE RX|COUNTER RESET,UTF-8,10,skip],180s,"regexp","COUNTER RESET")=0
