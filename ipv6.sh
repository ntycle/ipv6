#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# ===== AUTO DETECT INTERFACE =====
IFACE=$(ip route get 8.8.8.8 | awk '{print $5}')

# ===== RANDOM STRING =====
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# ===== GEN IPV6 =====
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# ===== INSTALL 3PROXY =====
install_3proxy() {
    echo "[+] Installing 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/refs/tags/0.8.13.tar.gz"
    wget -qO- $URL | tar -xzf-
    cd 3proxy-0.8.13 || exit 1
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd "$WORKDIR" || exit 1
}

# ===== GEN 3PROXY CONFIG =====
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

# ===== EXPORT PROXY FOR USER =====
gen_proxy_file_for_user() {
cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

# ===== GEN DATA =====
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "user$port/$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

# ===== GEN IPV6 ADD SCRIPT =====
gen_ifconfig() {
cat <<EOF
$(awk -F "/" '{print "ip -6 addr add " $5 "/64 dev " ENVIRON["IFACE"]}' ${WORKDATA})
EOF
}

# ================== MAIN ==================

echo "[+] Using interface: $IFACE"

WORKDIR="/home/bkns"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p "$WORKDIR"
cd "$WORKDIR" || exit 1

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "[+] IPv4: $IP4"
echo "[+] IPv6 prefix: $IP6::/64"

FIRST_PORT=22000
LAST_PORT=22700

install_3proxy

gen_data > "$WORKDATA"
gen_ifconfig > "$WORKDIR/boot_ifconfig.sh"
chmod +x "$WORKDIR/boot_ifconfig.sh"

gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg

cat >> /etc/rc.d/rc.local <<EOF
bash $WORKDIR/boot_ifconfig.sh
ulimit -n 10048
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

chmod +x /etc/rc.d/rc.local
systemctl enable rc-local
systemctl start rc-local

bash /etc/rc.local

gen_proxy_file_for_user

echo "[+] DONE. Proxy list saved in proxy.txt"
