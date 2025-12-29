#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
set -e

# ================== AUTO DETECT INTERFACE ==================
IFACE=$(ip route get 8.8.8.8 | awk '{print $5}')

echo "[+] Network interface: $IFACE"

# ================== RANDOM STRING ==================
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# ================== GEN IPV6 ==================
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# ================== INSTALL 3PROXY ==================
install_3proxy() {
    echo "[+] Installing dependencies"
    apt-get update
    apt-get install -y wget build-essential gcc make
    
    echo "[+] Installing 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/refs/tags/0.8.13.tar.gz"
    wget -qO- "$URL" | tar -xzf-
    cd 3proxy-0.8.13
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd "$WORKDIR"
}

# ================== GEN 3PROXY CONFIG ==================
gen_3proxy() {
cat <<EOF
daemon
maxconn 4000
nserver 1.1.1.1
nserver 8.8.8.8
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{print "allow " $1 "\nproxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\nflush\n"}' ${WORKDATA})
EOF
}

# ================== EXPORT PROXY LIST ==================
gen_proxy_file_for_user() {
awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA} > proxy.txt
}

# ================== GEN DATA ==================
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "user$port/$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

# ================== GEN IPV6 ADD SCRIPT ==================
gen_ifconfig() {
awk -F "/" '{print "ip -6 addr add " $5 "/64 dev '"$IFACE"'"}' ${WORKDATA}
}

# ================== MAIN ==================
WORKDIR="/home/bkns"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# IPv4
IP4=$(curl -4 -s icanhazip.com)

# IPv6 PREFIX /64 (LẤY TỪ HỆ THỐNG – CHUẨN VULTR)
IP6=$(ip -6 addr show dev "$IFACE" scope global | \
      awk '/inet6/ {print $2}' | head -n1 | cut -d/ -f1 | cut -d: -f1-4)

if [[ -z "$IP6" ]]; then
    echo "[ERROR] IPv6 /64 prefix not found"
    exit 1
fi

echo "[+] IPv4: $IP4"
echo "[+] IPv6 prefix: $IP6::/64"

# PORT RANGE
FIRST_PORT=20000
LAST_PORT=20100

install_3proxy

gen_data > "$WORKDATA"
gen_ifconfig > "$WORKDIR/boot_ifconfig.sh"
chmod +x "$WORKDIR/boot_ifconfig.sh"

gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg

# Tạo rc.local nếu chưa tồn tại
if [ ! -f /etc/rc.local ]; then
    echo '#!/bin/bash' > /etc/rc.local
    echo 'exit 0' >> /etc/rc.local
    chmod +x /etc/rc.local
fi

cat >> /etc/rc.local <<EOF
bash $WORKDIR/boot_ifconfig.sh
ulimit -n 10048
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

chmod +x /etc/rc.local
systemctl enable rc-local
systemctl start rc-local

bash /etc/rc.local

gen_proxy_file_for_user

echo "[+] DONE!"
echo "[+] Proxy list: $WORKDIR/proxy.txt"
