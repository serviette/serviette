#!/bin/sh

#################################################
# General 
#################################################

# Set hostname
echo serviette > /etc/hostname

# Allow every user to use DNS resolution                                                                                                                                            
chmod a+r /etc/resolv.conf

# Configure locales
aptitude -y install locales

cat > /etc/locale.gen <<EOF 
de_AT.UTF-8 UTF-8
de_CH.UTF-8 UTF-8
de_DE.UTF-8 UTF-8
en_US.UTF-8 UTF-8
EOF

locale-gen

# Set up Debian's sources.list
cat > /etc/apt/sources.list <<EOL
deb http://ftp.de.debian.org/debian wheezy main contrib non-free
deb http://ftp.de.debian.org/debian wheezy-updates main contrib non-free
deb http://ftp.de.debian.org/debian-security wheezy/updates main contrib non-free
EOL

# Install latest system updates
aptitude update && aptitude -y upgrade

# Reset SSH hostkeys
rm /etc/ssh/*.pub /etc/ssh/*_key
dpkg-reconfigure openssh-server

# Set time zone
echo "Europe/Berlin" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata

# Install basic tools
aptitude -y install zsh vim less gzip git-core curl python g++ iw wpasupplicant wireless-tools bridge-utils screen tmux mosh ed strace cowsay figlet toilet at pv mmv iputils-tracepath tre-agrep urlscan urlview autossh elinks irssi-scripts ncftp sc byobu mc tree atop iftop iotop nmap antiword moreutils net-tools whois pwgen haveged


#################################################
# Network Settings
#################################################

# Firmware for rt2800usb (USB WiFi) 
aptitude install firmware-ralink

cat > /etc/network/interfaces <<EOF
# interfaces(5) file used by ifup(8) and ifdown (8)                                                                                                                                  
auto lo
iface lo inet loopback

# Wired LAN
auto eth0

# Wifi LAN
auto wlan0
iface wlan0 inet manual
    wpa-roam /etc/wpa_supplicant/wpa-roam.conf

# Access Point
auto wlan1
iface wlan1 inet static
    address 192.168.23.1
    netmask 255.255.255.0

# Default connection
iface default inet dhcp
EOF

# Make some basic settings at boot time
sed -i '$ d' /etc/rc.local

cat > /etc/rc.local <<EOF
# Make the blue LED only flash on activity on SD card
echo mmc0 > /sys/class/leds/led1/trigger

# Enable IPv4 forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Masquerade outgoing traffic from interface eth0 and wlan0
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE

# Block outgoing and forwarded communication with other PGP/GPG keyservers
iptables -A OUTPUT -p TCP --dport 11371 -j REJECT
iptables -A OUTPUT -p UDP --dport 11371 -j REJECT
iptables -A FORWARD -p UDP --dport 11371 -j REJECT
iptables -A FORWARD -p TCP --dport 11371 -j REJECT

exit 0
EOF


#################################################
# ETHERPAD-LITE
#################################################

# Install NodeJS
curl -sL https://deb.nodesource.com/setup | bash -
aptitude install -y nodejs

# Install Etherpad-lite
useradd -m etherpad
su etherpad -s /bin/bash
git clone git://github.com/ether/etherpad-lite.git
cd ~/etherpad-lite
npm install ep_list_pads
npm install ep_adminpads
npm install ep_markdown
npm install ep_markdownify

echo "Please enable an admin user in the Etherpad-lite configuration"
read -p "Press [Enter] key to open Etherpad-lite configuration file..."

vim ~/etherpad-lite/settings.json

exit

# Install and configure Etherpad-lite init script
wget https://github.com/serviette/serviette/raw/master/etherpad-lite.init -O /etc/init.d/etherpad-lite 
chmod +x /etc/init.d/etherpad-lite
mkdir /var/log/etherpad-lite
chown etherpad:etherpad /var/log/etherpad-lite/
update-rc.d etherpad-lite defaults

# Start Etherpad-lite
service etherpad-lite start


#################################################
# XMPP Server
#################################################

# Install Prosody XMPP server
aptitude -y install prosody

# Create Prosody configuration
cat > /etc/prosody/conf.d/serviette.cfg.lua <<EOF
VirtualHost "serviette.lan"
    allow_registration = true
    authentication = "internal_hashed"
    groups_file = "/etc/prosody/serviette_groups.txt"
EOF

# Download Prosody PAM authentication module
wget https://raw.githubusercontent.com/augustf/prosody-mod_auth_pam/master/mod_auth_pam.lua -O /usr/lib/prosody/modules/mod_auth_pam.lua

# Enable Prosody groups support
sed -i 's/--"groups"/"groups"/' /etc/prosody/prosody.cfg.lua 

# Restart Prosody to adopt changes
service prosody restart


#################################################
# PGP/GPG Key Server
#################################################

# Install Synchronizing OpenPGP Key Server
aptitude -y install sks

# Initialize Synchronizing OpenPGP Key Server database
sks build
chown -Rc debian-sks:debian-sks /var/lib/sks/DB

# Disable communication with other key servers
echo '# Empty - Do not communicate with other keyservers.' >/etc/sks/mailsync
echo '# Empty - Do not communicate with other keyservers.' >/etc/sks/membership

# Enable start via init script
echo 'initstart=yes' >/etc/default/sks

# Start Synchronizing OpenPGP Key Server
service sks start


#################################################
#  HTTP Server
#################################################

# Install Nginx, FastCGI Wrapper and PHP5 (CGI)
aptitude -y install nginx-light fcgiwrap php5-cgi

# Make sure that every new users gets his own public_html
mkdir /etc/skel/public_html

# Allow HTTP server user to create new users, required for self-service portal
cat > /etc/sudoers <<EOF
www-data ALL=(root) NOPASSWD: /usr/sbin/useradd"
EOF

# Restart Nginx to adopt changes 
service nginx restart


#################################################
# Ikiwiki
#################################################

# Install IkiWiki
aptitude -y install ikiwiki


#################################################
# IRC Server
#################################################

# Install ngIRCd
aptitude -y install ngircd

# Configure hostname if IRC server
sed -i 's/Name = irc.example.net/Name = irc.serviette.lan/' /etc/ngircd/ngircd.conf

# Restart ngIRCd to adopt changes
service ngircd restart


#################################################
# Wireless Access Point
#################################################

# Install HostAPd
aptitude -y install hostapd

# Create cHostAPd configuration file
cat - << EOF > /etc/hostapd/hostapd.conf
interface=wlan1
bridge=br0
driver=nl80211
country_code=DE
ssid=serviette
hw_mode=g
channel=6
wpa=2
wpa_passphrase=serviette
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
auth_algs=1
macaddr_acl=0
EOF

# Specify configuration file
sed -i 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/' /etc/default/hostapd

# Restart HostAPd to adopt changes
service hostapd restart


#################################################
# DNS & DHCP Server
#################################################

# Install Dnsmasq
aptitude -y install dnsmasq

# Create Dnsmasq configuration
cat - << EOF > /etc/dnsmasq.conf
interface=wlan1
domain=serviette.lan
dhcp-range=192.168.0.50,192.168.0.150,12h
EOF

# Restart Dnsmasq to adopt changes
service dnsmasq restart


#################################################
#  SharingIsCaring
#################################################

# Install SharingIsCaring
useradd -m sharingiscaring
su sharingiscaring -s /bin/bash
cd ~
npm install git://github.com/c3d2/sharingiscaring.git

# Create executable file for SharingIsCaring
cat - << EOF > /home/sharingiscaring/run.sh
#!/bin/bash

cd $HOME
export PORT=8090
./node_modules/.bin/sharingiscaring
EOF

chmod +x /home/sharingiscaring/run.sh
exit

# Install and configure SharingIsCaring init script
wget https://github.com/serviette/serviette/raw/master/sharingiscaring.init -O /etc/init.d/sharingiscaring
chmod +x /etc/init.d/sharingiscaring
mkdir /var/log/sharingiscaring
chown sharingiscaring:sharingiscaring /var/log/sharingiscaring/
update-rc.d sharingiscaring defaults

# Start SharingIsCaring
service sharingiscaring start


#################################################
# SMTP & IMAP Server/Client
################################################# 

# Install Exim, Dovecot and Mutt
aptitude -y install exim4-light dovecot-imapd mutt

# Create Exim configuration the Debian way
cat - << EOF > /etc/exim4/update-exim4.conf.conf
dc_eximconfig_configtype='local'
dc_other_hostnames='serviette.lan'
dc_local_interfaces='127.0.0.1 ; ::1'
dc_readhost=''
dc_relay_domains=''
dc_minimaldns='false'
dc_relay_nets=''
dc_smarthost=''
CFILEMODE='644'
dc_use_split_config='false'
dc_hide_mailname=''
dc_mailname_in_oh='true'
dc_localdelivery='mail_spool'
EOF

# Create Exim configuration from configuration template
update-exim4.conf

# Restart Exim to adopt changes
service exim4 restart
