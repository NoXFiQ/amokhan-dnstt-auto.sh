#!/bin/bash

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Function for colored echo
print_color() {
    echo -e "${2}${1}${NC}"
}

# Function to show banner
show_banner() {
    clear
    echo -e "${RED}"
    figlet -f slant "ELITE-X" 2>/dev/null || echo "======== ELITE-X SLOWDNS ========"
    echo -e "${GREEN}           Version 3.0 - Ultimate Edition${NC}"
    echo -e "${YELLOW}================================================${NC}"
    echo ""
}

# Function to show dashboard
show_dashboard() {
    clear
    # Get system information
    SERVER_IP=$(curl -s ifconfig.me)
    SERVER_LOCATION=$(curl -s http://ip-api.com/json/$SERVER_IP | jq -r '.city + ", " + .country' 2>/dev/null || echo "Unknown")
    SERVER_ISP=$(curl -s http://ip-api.com/json/$SERVER_IP | jq -r '.isp' 2>/dev/null || echo "Unknown")
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    USED_RAM=$(free -m | awk '/^Mem:/{print $3}')
    FREE_RAM=$(free -m | awk '/^Mem:/{print $4}')
    SERVER_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    SUBDOMAIN=$(cat /etc/elite-x/subdomain 2>/dev/null || echo "Not configured")
    PUBLIC_KEY=$(cat /etc/dnstt/server.pub 2>/dev/null | cut -c1-50 || echo "Not generated")
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}                    ELITE-X SLOWDNS v3.0                       ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${WHITE}  Subdomain    :${GREEN} $SUBDOMAIN${NC}"
    echo -e "${CYAN}║${WHITE}  Public Key   :${GREEN} ${PUBLIC_KEY}...${NC}"
    echo -e "${CYAN}║${WHITE}  IP Address   :${GREEN} $SERVER_IP${NC}"
    echo -e "${CYAN}║${WHITE}  Location     :${GREEN} $SERVER_LOCATION${NC}"
    echo -e "${CYAN}║${WHITE}  ISP          :${GREEN} $SERVER_ISP${NC}"
    echo -e "${CYAN}║${WHITE}  Total RAM    :${GREEN} ${TOTAL_RAM} MB${NC}"
    echo -e "${CYAN}║${WHITE}  Used RAM     :${YELLOW} ${USED_RAM} MB${NC}"
    echo -e "${CYAN}║${WHITE}  Free RAM     :${GREEN} ${FREE_RAM} MB${NC}"
    echo -e "${CYAN}║${WHITE}  Server Time  :${GREEN} $SERVER_TIME${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

if [ "$(id -u)" -ne 0 ]; then
    print_color "[-] Run as root: sudo bash install.sh" "$RED"
    exit 1
fi

show_banner

print_color "Welcome to ELITE-X SlowDNS Installation" "$CYAN"
print_color "========================================" "$YELLOW"
echo ""
read -p "$(echo -e $RED"Enter Your Subdomain (e.g., ns-ex.elitex.sbs): "$NC)" TDOMAIN
read -p "$(echo -e $RED"Enter MTU Value [default: 1800]: "$NC)" MTU_INPUT
MTU=${MTU_INPUT:-1800}
read -p "$(echo -e $RED"Enter DNSTT Port [default: 5300]: "$NC)" DNSTT_PORT_INPUT
DNSTT_PORT=${DNSTT_PORT_INPUT:-5300}
read -p "$(echo -e $RED"Enter DNS Port [default: 53]: "$NC)" DNS_PORT_INPUT
DNS_PORT=${DNS_PORT_INPUT:-53}

echo ""
print_color "Starting ELITE-X DNSTT AUTO INSTALL..." "$GREEN"
sleep 2

mkdir -p /etc/elite-x
echo "$TDOMAIN" > /etc/elite-x/subdomain

print_color "Stopping old services..." "$YELLOW"
for svc in dnstt dnstt-server slowdns dnstt-smart dnstt-elite-x dnstt-elite-x-proxy; do
    systemctl disable --now "$svc" 2>/dev/null || true
done

fuser -k 53/udp 2>/dev/null || true

if [ -f /etc/systemd/resolved.conf ]; then
    print_color "Configuring systemd-resolved..." "$YELLOW"
    sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
    sed -i 's/^#\?DNS=.*/DNS=8.8.8.8 8.8.4.4/' /etc/systemd/resolved.conf
    systemctl restart systemd-resolved
    ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
fi

print_color "Installing dependencies..." "$YELLOW"
apt update -y
apt upgrade -y
apt install -y figlet lolcat python3 python3-pip git curl wget unzip zip \
               net-tools bc jq screen cron iptables ufw fail2ban \
               nginx certbot python3-certbot-nginx build-essential \
               netcat-openbsd dnsutils speedtest-cli htop neofetch \
               apache2-utils squid3

print_color "Installing dnstt-server..." "$YELLOW"
curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 -o /usr/local/bin/dnstt-server
chmod +x /usr/local/bin/dnstt-server

mkdir -p /etc/dnstt /var/log/dnstt /etc/elite-x/users /etc/elite-x/banner

print_color "Generating encryption keys..." "$YELLOW"
if [ ! -f /etc/dnstt/server.key ]; then
    cd /etc/dnstt
    dnstt-server -gen-key -privkey-file server.key -pubkey-file server.pub
    cd ~
fi
chmod 600 /etc/dnstt/server.key
chmod 644 /etc/dnstt/server.pub

SERVER_IP=$(curl -s ifconfig.me)
SERVER_LOCATION=$(curl -s http://ip-api.com/json/$SERVER_IP | jq -r '.city + ", " + .country' 2>/dev/null || echo "Unknown")
SERVER_ISP=$(curl -s http://ip-api.com/json/$SERVER_IP | jq -r '.isp' 2>/dev/null || echo "Unknown")
PUBKEY=$(cat /etc/dnstt/server.pub)

print_color "Creating DNSTT service..." "$YELLOW"
cat >/etc/systemd/system/dnstt-elite-x.service <<EOF
[Unit]
Description=ELITE-X DNSTT Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/dnstt-server \\
  -udp :${DNSTT_PORT} \\
  -mtu ${MTU} \\
  -privkey-file /etc/dnstt/server.key \\
  ${TDOMAIN} 127.0.0.1:22
Restart=always
RestartSec=5
KillSignal=SIGTERM
TimeoutStopSec=10
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

print_color "Installing optimized EDNS proxy..." "$YELLOW"
cat >/usr/local/bin/dnstt-edns-proxy.py <<'EOF'
#!/usr/bin/env python3
import socket
import threading
import struct
import time
import os

# Optimized configuration for maximum speed
LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = 53
UPSTREAM_HOST = "127.0.0.1"
UPSTREAM_PORT = 5300

# Optimized buffer sizes for 20Mbps+ speed
EXTERNAL_EDNS_SIZE = 4096
INTERNAL_EDNS_SIZE = 65535
SOCKET_BUFFER_SIZE = 1048576  # 1MB buffer
THREAD_POOL_SIZE = 100

# Connection pool
class ConnectionPool:
    def __init__(self, max_size=50):
        self.pool = []
        self.max_size = max_size
        self.lock = threading.Lock()
    
    def get(self):
        with self.lock:
            if self.pool:
                return self.pool.pop()
        return socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    def put(self, sock):
        with self.lock:
            if len(self.pool) < self.max_size:
                self.pool.append(sock)
            else:
                sock.close()

pool = ConnectionPool()

def optimize_socket(sock):
    """Optimize socket for maximum performance"""
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, SOCKET_BUFFER_SIZE)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, SOCKET_BUFFER_SIZE)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, 'SO_REUSEPORT'):
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    return sock

def patch_edns(data, size):
    """Optimized EDNS patching"""
    if len(data) < 12:
        return data
    
    try:
        qd, an, ns, ar = struct.unpack("!HHHH", data[4:12])
    except:
        return data
    
    offset = 12
    
    def skip_name(b, off):
        while off < len(b):
            l = b[off]
            off += 1
            if l == 0:
                break
            if l & 0xC0 == 0xC0:
                off += 1
                break
            off += l
        return off
    
    # Skip questions
    for _ in range(qd):
        offset = skip_name(data, offset)
        offset += 4
    
    # Skip answers and authority
    for _ in range(an + ns):
        offset = skip_name(data, offset)
        if offset + 10 > len(data):
            return data
        _, _, _, rdlength = struct.unpack("!HHIH", data[offset:offset + 10])
        offset += 10 + rdlength
    
    # Modify EDNS
    new_data = bytearray(data)
    for _ in range(ar):
        offset = skip_name(data, offset)
        if offset + 10 > len(data):
            return data
        t, = struct.unpack("!H", data[offset:offset + 2])
        if t == 41:  # EDNS option
            new_data[offset + 2:offset + 4] = struct.pack("!H", size)
            return bytes(new_data)
        _, _, rdlength = struct.unpack("!HIH", data[offset + 2:offset + 10])
        offset += 10 + rdlength
    
    return data

def handle_client(data, addr):
    """Handle DNS query with maximum speed"""
    sock = pool.get()
    sock = optimize_socket(sock)
    sock.settimeout(2)  # Reduced timeout for faster response
    
    try:
        # Send optimized query
        sock.sendto(patch_edns(data, INTERNAL_EDNS_SIZE), 
                   (UPSTREAM_HOST, UPSTREAM_PORT))
        
        # Receive response
        response, _ = sock.recvfrom(65535)
        
        # Send optimized response
        client_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        client_sock = optimize_socket(client_sock)
        client_sock.sendto(patch_edns(response, EXTERNAL_EDNS_SIZE), addr)
        client_sock.close()
        
    except socket.timeout:
        pass
    except Exception as e:
        print(f"Error: {e}")
    finally:
        pool.put(sock)

def main():
    """Main server loop with thread pooling"""
    server_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    server_sock = optimize_socket(server_sock)
    server_sock.bind((LISTEN_HOST, LISTEN_PORT))
    
    print(f"ELITE-X EDNS Proxy running on port {LISTEN_PORT}")
    print(f"Optimized for 20Mbps+ speed with 1ms ping")
    
    while True:
        try:
            data, addr = server_sock.recvfrom(65535)
            thread = threading.Thread(target=handle_client, args=(data, addr))
            thread.daemon = True
            thread.start()
        except Exception as e:
            print(f"Server error: {e}")

if __name__ == "__main__":
    main()
EOF

chmod +x /usr/local/bin/dnstt-edns-proxy.py

# Create proxy service
print_color "Creating EDNS proxy service..." "$YELLOW"
cat >/etc/systemd/system/dnstt-elite-x-proxy.service <<EOF
[Unit]
Description=ELITE-X EDNS Proxy
After=network-online.target dnstt-elite-x.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/dnstt-edns-proxy.py
Restart=always
RestartSec=3
KillSignal=SIGTERM
TimeoutStopSec=10
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF


print_color "Setting up banner management..." "$YELLOW"
cat >/etc/elite-x/banner/default <<'EOF'
===============================================
      WELCOME TO ELITE-X VPN SERVICE
===============================================
     High Speed • Secure • Unlimited
===============================================
EOF


print_color "Creating user management system..." "$YELLOW"
cat >/usr/local/bin/elite-x-user <<'EOF'
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

USER_DB="/etc/elite-x/users"
mkdir -p $USER_DB

add_user() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}                     CREATE SSH + DNS USER                      ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    read -p "$(echo -e $GREEN"Password: "$NC)" password
    read -p "$(echo -e $GREEN"Expire days: "$NC)" days
    
    if id "$username" &>/dev/null; then
        echo -e "${RED}User already exists!${NC}"
        return
    fi
    
    # Create system user
    useradd -m -s /bin/false "$username"
    echo "$username:$password" | chpasswd
    
    # Calculate expiry date
    expire_date=$(date -d "+$days days" +"%Y-%m-%d")
    chage -E "$expire_date" "$username"
    
    # Save user info
    cat > $USER_DB/$username <<INFO
Username: $username
Password: $password
Expire: $expire_date
Created: $(date +"%Y-%m-%d %H:%M:%S")
INFO
    
    # Get server details
    SERVER=$(cat /etc/elite-x/subdomain 2>/dev/null || echo "Not configured")
    PUBKEY=$(cat /etc/dnstt/server.pub 2>/dev/null || echo "Not generated")
    
    clear
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}                  ELITE-X SLOW DNS DETAILS                       ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}Username     :${CYAN} $username${NC}"
    echo -e "${WHITE}Password     :${CYAN} $password${NC}"
    echo -e "${WHITE}Server Name  :${CYAN} $SERVER${NC}"
    echo -e "${WHITE}Public Key   :${CYAN} $PUBKEY${NC}"
    echo -e "${WHITE}Expire Date  :${CYAN} $expire_date${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Quote: Always Remember ELITE-X when you see X${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
}

list_users() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}                     LIST OF ACTIVE USERS                       ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    
    if [ -z "$(ls -A $USER_DB 2>/dev/null)" ]; then
        echo -e "${RED}No users found${NC}"
        return
    fi
    
    for user in $USER_DB/*; do
        if [ -f "$user" ]; then
            echo -e "${GREEN}$(basename $user)${NC}"
            cat "$user"
            echo -e "${CYAN}───────────────────────────────────────────────────────${NC}"
        fi
    done
}

delete_user() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}                     DELETE USER                               ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    
    read -p "$(echo -e $GREEN"Username to delete: "$NC)" username
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User does not exist!${NC}"
        return
    fi
    
    userdel -r "$username"
    rm -f $USER_DB/$username
    echo -e "${GREEN}User $username deleted successfully${NC}"
}

case $1 in
    add) add_user ;;
    list) list_users ;;
    del) delete_user ;;
    *)
        echo "Usage: elite-x-user {add|list|del}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/elite-x-user

print_color "Creating main menu..." "$YELLOW"
cat >/usr/local/bin/elite-x <<'EOF'
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Banner function
show_banner() {
    clear
    echo -e "${RED}"
    figlet -f slant "ELITE-X" 2>/dev/null || echo "======== ELITE-X SLOWDNS ========"
    echo -e "${GREEN}           Version 3.0 - Ultimate Edition${NC}"
    echo -e "${YELLOW}================================================${NC}"
    echo ""
}

# Dashboard function
show_dashboard() {
    clear
    SERVER_IP=$(curl -s ifconfig.me)
    SERVER_LOCATION=$(curl -s http://ip-api.com/json/$SERVER_IP | jq -r '.city + ", " + .country' 2>/dev/null || echo "Unknown")
    SERVER_ISP=$(curl -s http://ip-api.com/json/$SERVER_IP | jq -r '.isp' 2>/dev/null || echo "Unknown")
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    USED_RAM=$(free -m | awk '/^Mem:/{print $3}')
    FREE_RAM=$(free -m | awk '/^Mem:/{print $4}')
    SERVER_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    SUBDOMAIN=$(cat /etc/elite-x/subdomain 2>/dev/null || echo "Not configured")
    PUBLIC_KEY=$(cat /etc/dnstt/server.pub 2>/dev/null | cut -c1-50 || echo "Not generated")
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}                    ELITE-X SLOWDNS v3.0                       ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${WHITE}  Subdomain    :${GREEN} $SUBDOMAIN${NC}"
    echo -e "${CYAN}║${WHITE}  Public Key   :${GREEN} ${PUBLIC_KEY}...${NC}"
    echo -e "${CYAN}║${WHITE}  IP Address   :${GREEN} $SERVER_IP${NC}"
    echo -e "${CYAN}║${WHITE}  Location     :${GREEN} $SERVER_LOCATION${NC}"
    echo -e "${CYAN}║${WHITE}  ISP          :${GREEN} $SERVER_ISP${NC}"
    echo -e "${CYAN}║${WHITE}  Total RAM    :${GREEN} ${TOTAL_RAM} MB${NC}"
    echo -e "${CYAN}║${WHITE}  Used RAM     :${YELLOW} ${USED_RAM} MB${NC}"
    echo -e "${CYAN}║${WHITE}  Free RAM     :${GREEN} ${FREE_RAM} MB${NC}"
    echo -e "${CYAN}║${WHITE}  Server Time  :${GREEN} $SERVER_TIME${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Main menu function
main_menu() {
    while true; do
        show_dashboard
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}                       MAIN MENU                                ${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${WHITE} 1.${CYAN} Create SSH + DNS User${NC}"
        echo -e "${WHITE} 2.${CYAN} Create/Edit Banner${NC}"
        echo -e "${WHITE} 3.${CYAN} Delete Banner${NC}"
        echo -e "${WHITE} 4.${CYAN} List All Users${NC}"
        echo -e "${WHITE} 5.${CYAN} Delete User${NC}"
        echo -e "${WHITE} 6.${CYAN} Restart Services${NC}"
        echo -e "${WHITE} 7.${CYAN} Check Service Status${NC}"
        echo -e "${WHITE} 8.${CYAN} Speed Test${NC}"
        echo -e "${WHITE} 9.${CYAN} Uninstall Script${NC}"
        echo -e "${WHITE} 00.${RED} Exit${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
        read -p "$(echo -e $GREEN"Choose option: "$NC)" choice
        
        case $choice in
            1)
                elite-x-user add
                read -p "Press Enter to continue..."
                ;;
            2)
                nano /etc/elite-x/banner/message
                echo -e "${GREEN}Banner saved!${NC}"
                read -p "Press Enter to continue..."
                ;;
            3)
                rm -f /etc/elite-x/banner/message
                echo -e "${GREEN}Banner deleted!${NC}"
                read -p "Press Enter to continue..."
                ;;
            4)
                elite-x-user list
                read -p "Press Enter to continue..."
                ;;
            5)
                elite-x-user del
                read -p "Press Enter to continue..."
                ;;
            6)
                systemctl restart dnstt-elite-x
                systemctl restart dnstt-elite-x-proxy
                echo -e "${GREEN}Services restarted!${NC}"
                read -p "Press Enter to continue..."
                ;;
            7)
                systemctl status dnstt-elite-x --no-pager
                systemctl status dnstt-elite-x-proxy --no-pager
                read -p "Press Enter to continue..."
                ;;
            8)
                speedtest-cli --simple
                read -p "Press Enter to continue..."
                ;;
            9)
                read -p "Are you sure? (y/n): " confirm
                if [ "$confirm" = "y" ]; then
                    systemctl stop dnstt-elite-x dnstt-elite-x-proxy
                    systemctl disable dnstt-elite-x dnstt-elite-x-proxy
                    rm -f /etc/systemd/system/dnstt-elite-x*
                    rm -rf /etc/dnstt
                    rm -rf /etc/elite-x
                    rm -f /usr/local/bin/dnstt-*
                    rm -f /usr/local/bin/elite-x*
                    echo -e "${GREEN}Uninstalled successfully!${NC}"
                    exit 0
                fi
                ;;
            00|0)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option!${NC}"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Run main menu
main_menu
EOF

chmod +x /usr/local/bin/elite-x


print_color "Configuring firewall..." "$YELLOW"
if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp
    ufw allow 53/udp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
fi

# Optimize system for maximum performance
print_color "Optimizing system for maximum performance..." "$YELLOW"

# Add network optimizations
cat >> /etc/sysctl.conf <<EOF

# ELITE-X Network Optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
EOF


modprobe tcp_bbr
echo "tcp_bbr" >> /etc/modules-load.d/modules.conf


sysctl -p


echo "alias elitex='elite-x'" >> ~/.bashrc
echo "alias menu='elite-x'" >> ~/.bashrc

print_color "Starting services..." "$YELLOW"
systemctl daemon-reload
systemctl enable dnstt-elite-x.service
systemctl enable dnstt-elite-x-proxy.service
systemctl start dnstt-elite-x.service
systemctl start dnstt-elite-x-proxy.service

echo "installed" > /etc/elite-x/installed

clear
show_dashboard
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}         ELITE-X SLOWDNS INSTALLED SUCCESSFULLY                 ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}DOMAIN      :${CYAN} $TDOMAIN${NC}"
echo -e "${WHITE}MTU         :${CYAN} $MTU${NC}"
echo -e "${WHITE}DNSTT PORT  :${CYAN} $DNSTT_PORT${NC}"
echo -e "${WHITE}DNS PORT    :${CYAN} $DNS_PORT${NC}"
echo -e "${WHITE}PUBLIC KEY  :${CYAN} $PUBKEY${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Type ${GREEN}elite-x${YELLOW} or ${GREEN}menu${YELLOW} to access the management panel${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"

if ! grep -q "elite-x" ~/.bashrc; then
    echo "clear" >> ~/.bashrc
    echo "elite-x" >> ~/.bashrc
fi
