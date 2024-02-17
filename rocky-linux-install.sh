#!/bin/bash

# OS: Rocky Linux 9.3 (Minimal Install without GUI) - VM
# LAN Port Open: TCP 22(SSH), TCP 9090(COCKPIT), TCP/UDP 15636, TCP/UDP 15637
# WAN Port Forward: TCP/UDP 15636, TCP/UDP 15637

# CHANGE YOUR OWN
ENSHROUDED_SERVER_GAMEPORT=15636
ENSHROUDED_SERVER_QUERYPORT=15637

read -p "Please Enter Your Machine Host Name: " HOSTNAME
read -p "Please Enter Your Machine FQDN or DDNS Name (Fully Qualified Domain Name): " FQDN
read -p "Please Enter a Name of Your Enshrouded Server: " ENSHROUDED_SERVER_NAME
read -p "Please Input a Server Password: " ENSHROUDED_SERVER_PASSWORD
read -p "Please Input a Max Player Count (Max.16): " ENSHROUDED_SERVER_MAXPLAYERS

# Disable SELinux
sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

# Delete Linux Kickstart File
rm -f /root/anaconda-ks.cfg

# Install VM Tools
dnf install -y open-vm-tools

# Merge and Resize the /home Partition
umount -f /home
lvremove -f "/dev/mapper/rl_$(echo "$HOSTNAME" | awk '{print tolower($0)}')-home"
lvextend -l +100%FREE "/dev/mapper/rl_$(echo "$HOSTNAME" | awk '{print tolower($0)}')-root"
xfs_growfs /
sed -i "s|^/dev/mapper/rl_.*-home|#&|" /etc/fstab

# System Update
dnf -y update

# Enable the EPEL Repository
dnf install -y epel-release

# Disable IPv6
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
sysctl -p

# Set Host Name
echo "$FQDN" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1   localhost localhost.localdomain $FQDN $HOSTNAME
::1         localhost localhost.localdomain $FQDN $HOSTNAME
EOF

# Install Packages
dnf install -y telnet wget tar screen htop git curl nmap-ncat

# Install Cockpit Web Console
dnf install -y cockpit
systemctl enable --now cockpit.socket
sed -i 's/^root/# root/' /etc/cockpit/disallowed-users

# Disable Firewall
systemctl disable --now firewalld

# Install SteamCMD
adduser steam
echo -e "password\npassword" | passwd steam --stdin
dnf install -y glibc.i686 libstdc++.i686 tmux screen
su - steam -c 'curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf -'
su - steam -c "/home/steam/steamcmd.sh +@sSteamCmdForcePlatformType windows +force_install_dir /home/steam/EnshroudedServer/ +login anonymous +app_update 2278520 validate +quit"

# Download and Install Wine's required development tools and dependencies
dnf groupinstall 'Development Tools' -y
dnf install gcc libX11-devel freetype-devel zlib-devel libxcb-devel libxslt-devel libgcrypt-devel libxml2-devel gnutls-devel libpng-devel libjpeg-turbo-devel libtiff-devel dbus-devel fontconfig-devel xorg-x11-server-Xvfb -y
wget -O wine-9.0.tar.xz https://dl.winehq.org/wine/source/9.0/wine-9.0.tar.xz
tar -xvf wine-9.0.tar.xz
cd wine-9.0
./configure --enable-win64
make -j$(nproc)
make install
ln -s /usr/local/bin/wine64 /usr/local/bin/wine
cd ..
rm -rf wine-9.0.tar.xz wine-9.0

# Download and Install Winetricks
wget -O /usr/local/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x /usr/local/bin/winetricks

# Create Winetricks script
cat << EOF > /home/steam/winetricks.sh
#!/bin/bash
export DISPLAY=:1.0
Xvfb :1 -screen 0 1024x768x16 &
env WINEDLLOVERRIDES="mscoree=d" wineboot --init /nogui
winetricks corefonts
winetricks sound=disabled
winetricks -q --force vcrun2022
wine winecfg -v win10
rm -rf /home/steam/.cache
EOF
chmod +x /home/steam/winetricks.sh
chown -R steam:steam /home/steam/winetricks.sh

# Create Enshrouded Server Dirs
mkdir -p /home/steam/EnshroudedServer
mkdir -p /home/steam/EnshroudedServer/savegame
mkdir -p /home/steam/EnshroudedServer/logs

# Create Enshrouded Server Config File
touch /home/steam/EnshroudedServer/enshrouded_server.json
cat << EOF >> /home/steam/EnshroudedServer/enshrouded_server.json
{
    "name": "$(echo $ENSHROUDED_SERVER_NAME)",
    "password": "$(echo $ENSHROUDED_SERVER_PASSWORD)",
    "saveDirectory": "./savegame",
    "logDirectory": "./logs",
    "ip": "0.0.0.0",
    "gamePort": $(echo $ENSHROUDED_SERVER_GAMEPORT),
    "queryPort": $(echo $ENSHROUDED_SERVER_QUERYPORT),
    "slotCount": $(echo $ENSHROUDED_SERVER_MAXPLAYERS)
}
EOF

# Create Enshrouded Server Service Script
touch /home/steam/EnshroudedServer/Start.sh
cat << EOF >> /home/steam/EnshroudedServer/Start.sh
#!/bin/sh
export WINEARCH=win64
wine64 /home/steam/EnshroudedServer/enshrouded_server.exe
EOF
chmod +x /home/steam/EnshroudedServer/Start.sh
chown -R steam:steam /home/steam/

# Create System Service
cat <<EOF > /etc/systemd/system/enshrouded.service
[Unit]
Description=Enshrouded Server
After=syslog.target network.target

[Service]
ExecStartPre=/home/steam/steamcmd.sh +@sSteamCmdForcePlatformType windows +force_install_dir /home/steam/EnshroudedServer/ +login anonymous +app_update 2278520 validate +quit
ExecStart=/home/steam/EnshroudedServer/Start.sh
User=steam
Group=steam
Type=simple
Restart=on-failure
RestartSec=60
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable enshrouded.service

# Reboot
shutdown -r now
