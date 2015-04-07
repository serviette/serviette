#!/bin/bash

#################################################
# General 
#################################################

function install_base {
    # Set hostname
    echo serviette > /etc/hostname
    
    # Allow every user to use DNS resolution                                                                                                                                            
    chmod a+r /etc/resolv.conf
    
    # Update package list
    aptitude -y update
    
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
deb http://ftp.debian.org/debian jessie main non-free
deb https://repositories.collabora.co.uk/debian/ jessie rpi2
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
    aptitude -y install zsh vim less gzip git-core curl python g++ iw wpasupplicant wireless-tools bridge-utils screen tmux mosh ed strace cowsay figlet toilet at pv mmv iputils-tracepath tre-agrep urlscan urlview autossh elinks irssi-scripts ncftp sc byobu mc tree atop iftop iotop nmap antiword moreutils net-tools whois pwgen haveged usbutils w3m htop nethack
}

#################################################
# Network Settings
#################################################

function configure_network {
    # Firmware for rt2800usb (USB WiFi) 
    aptitude install firmware-ralink

    cat > /etc/network/interfaces <<EOF
# interfaces(5) file used by ifup(8) and ifdown (8)                                                                                                                                  
auto lo
iface lo inet loopback

# LAN - Wired
auto eth0

# LAN - Wifi
auto wlan1
iface wlan1 inet manual
    wpa-roam /etc/wpa_supplicant/wpa-roam.conf

# Access Point
auto wlan0
iface wlan0 inet static
    address 192.168.23.1
    netmask 255.255.255.0

# Default connection
iface default inet dhcp
EOF

    # Add virtual host
    cat >> /etc/hosts <<EOF
192.168.23.1    serviette serviette.lan bin.serviette.lan sic.serviette.lan irc.serviette.lan xmpp.serviette.lan ftp.serviette.lan keyserver.serviette.lan pads.serviette.lan
EOF

    # Make some basic settings at boot time
    sed -i '$ d' /etc/rc.local

    cat > /etc/rc.local <<EOF
#!/bin/sh -e
# Enable IPv4 forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Masquerade outgoing traffic from interface eth0 and wlan1
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -t nat -A POSTROUTING -o wlan1 -j MASQUERADE

# Block outgoing and forwarded communication with other PGP/GPG keyservers
# but still enable local communication (nginx reverse proxy)
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -p TCP --dport 11371 -j REJECT
iptables -A OUTPUT -p UDP --dport 11371 -j REJECT
iptables -A FORWARD -p UDP --dport 11371 -j REJECT
iptables -A FORWARD -p TCP --dport 11371 -j REJECT

exit 0
EOF
}

#################################################
# Wireless Access Point
#################################################

function install_hostapd {
    # Install HostAPd
    aptitude -y install hostapd
    
    # Create cHostAPd configuration file
    cat - << EOF > /etc/hostapd/hostapd.conf
interface=wlan0
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
}    

#################################################
# DNS & DHCP Server
#################################################

function install_dnsmasq {
    # Install Dnsmasq
    aptitude -y install dnsmasq
    
    # Create Dnsmasq configuration
    cat - << EOF > /etc/dnsmasq.conf
interface=wlan0
domain=serviette.lan
dhcp-range=192.168.23.50,192.168.23.150,12h
EOF
    
    # Restart Dnsmasq to adopt changes
    service dnsmasq restart
}

#################################################
#  FTP Server
#################################################

function install_ftpd {
    aptitude -y install vsftpd
}

#################################################
#  HTTP Server
#################################################

function install_httpd {
    # Install Nginx, FastCGI Wrapper and PHP5 (CGI)
    aptitude -y install nginx-light fcgiwrap php5-cgi php5-fpm

    # Make sure that every new users gets his own public_html
    mkdir /etc/skel/public_html

    # Allow HTTP server user to create new users, required for self-service portal
    cat > /etc/sudoers <<EOF
www-data ALL=(root) NOPASSWD: /usr/sbin/useradd"
EOF

    # Create public default host
    cat > /etc/nginx/sites-available/serviette.lan <<EOF
server {
        server_name serviette.lan

        root /var/www;
        index index.html index.htm;

        location ~ \.php$ {
               fastcgi_pass unix:/var/run/php5-fpm.sock;
               fastcgi_index index.php;
               include /etc/nginx/fastcgi_params;
        }        

}
EOF

    # Increase server_names_hash_bucket_size, due to number of virtual servers
    sed -i 's/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/' /etc/nginx/nginx.conf


    ln -s /etc/nginx/sites-available/serviette.lan /etc/nginx/sites-enabled/serviette.lan

    # The default server_names_hash_bucket_size proved to be too small.
    sed -i 's/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/' /etc/nginx/nginx.conf

    # Restart Nginx to adopt changes 
    service nginx restart
}

#################################################
# NODE.JS
#################################################

function install_nodejs {
    # Install NodeJS
    curl -sL https://deb.nodesource.com/setup | bash -
    aptitude install -y nodejs
}

#################################################
# HASTE-SERVER
#################################################

function install_haste {

    # Install Etherpad-lite
    useradd -m haste
    su haste -c "cd ~ && git clone git://github.com/seejohnrun/haste-server.git"
    su haste -c "cd ~/haste-server && npm install"

    # Create executable file for haste-server
    cat - << EOF > /home/haste/run.sh
#!/bin/bash

cd ~/haste-server
npm start
EOF

    chown haste:haste /home/haste/run.sh
    chmod +x /home/haste/run.sh
    
    # Create haste-server config
    cat - << EOF > /home/haste/haste-server/config.js
{

  "host": "0.0.0.0",
  "port": 7777,

  "keyLength": 10,

  "maxLength": 400000,

  "staticMaxAge": 86400,

  "recompressStaticAssets": true,

  "logging": [
    {
      "level": "verbose",
      "type": "Console",
      "colorize": true
    }
  ],

  "keyGenerator": {
    "type": "phonetic"
  },

  "storage": {
    "type": "file",
    "path": "./data"
  },

  "documents": {
    "about": "./about.md"
  }

}
EOF


    # Install and configure haste-server init script
    wget https://github.com/serviette/serviette/raw/master/haste-server.init -O /etc/init.d/haste-server
    chmod +x /etc/init.d/haste-server
    mkdir /var/log/haste-server
    chown haste:haste /var/log/haste-server/
    update-rc.d haste-server defaults
    
    # Start Etherpad-lite
    service haste-server start

    # Create and endable virtual host
    cat > /etc/nginx/sites-available/bin.serviette.lan <<EOF
server{
  server_name bin.serviette.lan;
  location / {
    proxy_pass http://127.0.0.1:7777;
  }
}
EOF

    ln -s /etc/nginx/sites-available/bin.serviette.lan /etc/nginx/sites-enabled/bin.serviette.lan

    /etc/init.d/nginx restart
}

#################################################
# ETHERPAD-LITE
#################################################

function install_etherpad {
    # Install Etherpad-lite
    useradd -m etherpad
    su etherpad -c "cd ~ && git clone git://github.com/ether/etherpad-lite.git"
    su etherpad -c "cd ~/etherpad-lite && npm install ep_list_pads && npm install ep_adminpads && npm install ep_markdown && npm install ep_markdownify"
    

    su etherpad -c "cp ~/etherpad-lite/settings.json.template ~/etherpad-lite/settings.json"
    echo "Please enable an admin user in the Etherpad-lite configuration"
    read -p "Press [Enter] key to open Etherpad-lite configuration file..."
    
    
    su etherpad -c "vim ~/etherpad-lite/settings.json"
    
    # Install and configure Etherpad-lite init script
    wget https://github.com/serviette/serviette/raw/master/etherpad-lite.init -O /etc/init.d/etherpad-lite 
    chmod +x /etc/init.d/etherpad-lite
    mkdir /var/log/etherpad-lite
    chown etherpad:etherpad /var/log/etherpad-lite/
    update-rc.d etherpad-lite defaults
    
    # Start Etherpad-lite
    service etherpad-lite start

    # Create and endable virtual host
    cat > /etc/nginx/sites-available/pads.serviette.lan <<EOF
server{
  server_name pads.serviette.lan;
  location / {
    proxy_pass http://127.0.0.1:9001;
  }
}
EOF

    ln -s /etc/nginx/sites-available/pads.serviette.lan /etc/nginx/sites-enabled/pads.serviette.lan

    /etc/init.d/nginx restart
}

#################################################
# XMPP Server
#################################################

function install_prosody {
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
}

#################################################
# PGP/GPG Key Server
#################################################

function install_sks {
    # Install Synchronizing OpenPGP Key Server
    aptitude -y install sks
    
    # Initialize Synchronizing OpenPGP Key Server database
    sks build
    chown -Rc debian-sks:debian-sks /var/lib/sks/DB
    
    # Disable communication with other key servers
    echo '# Empty - Do not communicate with other keyservers.' > /etc/sks/mailsync
    echo '# Empty - Do not communicate with other keyservers.' > /etc/sks/membership
    
    # Enable start via init script
    echo 'initstart=yes' > /etc/default/sks
    
    # Start Synchronizing OpenPGP Key Server
    service sks start

    cat > /etc/nginx/sites-available/keyserver.serviette.lan <<EOF
server{
  server_name keyserver.serviette.lan;
  location / {
    proxy_pass http://127.0.0.1:11371;
  }
}
EOF

    ln -s /etc/nginx/sites-available/keyserver.serviette.lan /etc/nginx/sites-enabled/keyserver.serviette.lan

    /etc/init.d/nginx restart
}

#################################################
# Ikiwiki
#################################################

function install_ikiwiki {
    # Install IkiWiki
    aptitude -y install ikiwiki
}

#################################################
# IRC Server
#################################################

function install_ngircd {
    # Install ngIRCd
    aptitude -y install ngircd
    
    # Configure hostname if IRC server
    sed -i 's/Name = irc.example.net/Name = irc.serviette.lan/' /etc/ngircd/ngircd.conf
    
    # Restart ngIRCd to adopt changes
    service ngircd restart
}


#################################################
# BitlBee 
#################################################

function install_bitlbee {
    # Install BitlBee
    aptitude -y install bitlbee

}

#################################################
#  SharingIsCaring
#################################################

function install_sharingiscaring {
    # Install SharingIsCaring
    useradd -m sharingiscaring
    su sharingiscaring -c "cd ~ && npm install git://github.com/c3d2/sharingiscaring.git"
    
    # Create executable file for SharingIsCaring
    cat - << EOF > /home/sharingiscaring/run.sh
#!/bin/bash

cd ~
export PORT=8090
./node_modules/.bin/sharingiscaring
EOF
    
    chown sharingiscaring:sharingiscaring /home/sharingiscaring/run.sh
    chmod +x /home/sharingiscaring/run.sh
    
    # Install and configure SharingIsCaring init script
    wget https://github.com/serviette/serviette/raw/master/sharingiscaring.init -O /etc/init.d/sharingiscaring
    chmod +x /etc/init.d/sharingiscaring
    mkdir /var/log/sharingiscaring
    chown sharingiscaring:sharingiscaring /var/log/sharingiscaring/
    update-rc.d sharingiscaring defaults
    
    # Start SharingIsCaring
    service sharingiscaring start

    # Create and endable virtual host
    cat > /etc/nginx/sites-available/sic.serviette.lan <<EOF
server{
  server_name sic.serviette.lan;
  location / {
    proxy_pass http://127.0.0.1:8090;
  }
}
EOF

    ln -s /etc/nginx/sites-available/sic.serviette.lan /etc/nginx/sites-enabled/sic.serviette.lan

    /etc/init.d/nginx restart
}

#################################################
# SMTP & IMAP Server/Client
################################################# 

function install_email {
    # Install Exim, Dovecot and Mutt
    aptitude -y install exim4-daemon-light dovecot-imapd mutt
    
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
}


#################################################
# SMTP & IMAP Server/Client
################################################# 

function install_sipwitch {
    # Install Sipwitch
    aptitude -y install Sipwitch

    # Automatically load available plugins
    sed -i 's/#PLUGINS=.*/PLUGINS="auto"/' /etc/default/sipwitch

    # Start Sipwitch
    /etc/init.d/sipwitch start
}


#install_base
#configure_network
#install_hostapd
#install_dnsmasq
#install_ftpd
#install_httpd
#install_nodejs
#install_etherpad
#install_haste
#install_sharingiscaring
#install_ikiwiki
#install_sks
#install_prosody
#install_ngircd
#install_bitlbee
#install_email
#install_sipwitch
