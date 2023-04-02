#!/bin/bash

# This script assumes that you have already installed Proxmox and have one NIC configured with an IP address.
# This script also assumes that you have already set up a WireGuard VPN server with a working configuration.

# Set the IP address that all VMs will use
IP_ADDRESS="192.168.1.10"

# Set the network interface name that is connected to your LAN
NETWORK_INTERFACE="eth0"

# Set the subnet mask for your network
SUBNET_MASK="255.255.255.0"

# Set the gateway IP address for your network
GATEWAY="192.168.1.1"

# Set the WireGuard interface name
WG_INTERFACE="wg0"

# Set the WireGuard configuration file path
WG_CONFIG="/etc/wireguard/wg0.conf"

# Configure Proxmox to use the specified IP address and route all traffic through WireGuard
cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto $NETWORK_INTERFACE
iface $NETWORK_INTERFACE inet manual
    pre-up ip link set dev $NETWORK_INTERFACE up
    post-down ip link set dev $NETWORK_INTERFACE down

auto $WG_INTERFACE
iface $WG_INTERFACE inet manual
    pre-up ip link add dev $WG_INTERFACE type wireguard
    post-down ip link del dev $WG_INTERFACE

# Configure WireGuard VPN interface
iface $WG_INTERFACE inet static
    address $IP_ADDRESS
    netmask $SUBNET_MASK
    gateway $GATEWAY
    pre-up wg-quick up $WG_CONFIG
    post-down wg-quick down $WG_CONFIG
EOF

# Restart the network interface with the new configuration
ifdown $NETWORK_INTERFACE && ifup $NETWORK_INTERFACE

# Configure all VMs to use the specified IP address as their default gateway through WireGuard VPN
for vmid in $(qm list | awk '{print $1}' | grep -v VMID); do
  qm set $vmid --net0 "virtio=$NETWORK_INTERFACE,bridge=vmbr0,firewall=1,ip=$IP_ADDRESS/$SUBNET_MASK,gw=$IP_ADDRESS"
done

# Configure Proxmox to use the WireGuard VPN as well
sed -i 's/^nameserver .*$/nameserver 10.0.0.1/g' /etc/resolv.conf
sed -i 's/^#DNS=/DNS=10.0.0.1/g' /etc/systemd/resolved.conf
systemctl restart systemd-resolved.service
echo "nameserver 10.0.0.1" > /etc/resolvconf/resolv.conf.d/head
systemctl restart resolvconf.service
wg-quick up $WG_CONFIG

# Confirm that Proxmox is using the WireGuard VPN
ping google.com
