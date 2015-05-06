#!/bin/bash
###########################################
#  Feel free to copy & share this script  #
###########################################

raspi_client_ip="192.168.10.50" # the IP the Raspberry should use to connect to the router
raspi_client_nm="255.255.255.0" # the netmask of the routers subnet
raspi_client_nw="192.168.10.0" # the network address of the subnet
raspi_client_gw="192.168.10.1" # the IP of your router
raspi_gateway_ip="192.168.10.200" # the IP the clients will use as their gateway

# Your hide.me credentials
username="XXXXXXXXXXXXXX"
password="XXXXXXXXXXXXXX"

server="https://hide.me/setup/ovpn/type/ovpn/server/17" # Default: Netherlands

# Don't change anything beyond this point
###########################################

# Check for root priviliges
if [[ $EUID -ne 0 ]]; then
   printf "Please run as root:\nsudo %s\n" "${0}"
   exit 1
fi

# Install required packages
apt-get update && apt-get -y install openvpn iptables-persistent

# Create config
cd /etc/openvpn
wget $server -O config.zip
unzip config.zip
rm config.zip
shopt -s nullglob
for f in *.ovpn
do
    sed -i 's/^auth-user-pass$/auth-user-pass user_pass.txt/' $f
    echo 'script-security 2' >> $f
    echo 'up update-resolv-conf' >> $f
    echo 'down update-resolv-conf' >> $f
    rename 's/.ovpn/.conf/' $f
done
cat > user_pass.txt <<EOF
$username
$password
EOF

# Reconfigure interfaces
cat > /etc/network/interfaces <<EOF
auto eth0
iface eth0 inet static
address $raspi_client_ip
gateway $raspi_client_gw
netmask $raspi_client_nm

auto eth0:0
iface eth0:0 inet static
address $raspi_gateway_ip
EOF

# configure DNS
cat > /etc/resolvconf.conf <<EOF
nameserver raspi_client_gw
EOF

# Setup IPTables
iptables -A FORWARD -s $raspi_client_nw/$raspi_client_nm -i eth0:0 -o eth0 -m conntrack --ctstate NEW -j REJECT
iptables -A FORWARD -s $raspi_client_nw/$raspi_client_nm -i eth0:0 -o tun0 -m conntrack --ctstate NEW -j ACCEPT
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
iptables-save > /etc/iptables/rules.v4

# Enable IP forwarding
cp /etc/sysctl.conf /etc/sysctl.conf.old
sed -i 's/.*net\.ipv4\.ip_forward=.*/net\.ipv4\.ip_forward=1/' /etc/sysctl.conf

# Restart the interface 
sudo ip link set eth0 down && sudo ip link set eth0 up