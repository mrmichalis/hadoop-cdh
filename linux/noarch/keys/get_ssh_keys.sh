#!/usr/bin/env bash
echo "* Installing SSH keys..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh
wget --no-check-certificate -nv 'https://raw.githubusercontent.com/gdgt/cmapi/master/keys/authorized_keys' -O /root/.ssh/authorized_keys
wget --no-check-certificate -nv 'https://raw.githubusercontent.com/gdgt/cmapi/master/keys/id_rsa' -O /root/.ssh/id_rsa
wget --no-check-certificate -nv 'https://raw.githubusercontent.com/gdgt/cmapi/master/keys/id_rsa.pub' -O /root/.ssh/id_rsa.pub
chmod 600 /root/.ssh/authorized_keys /root/.ssh/id_rsa /root/.ssh/id_rsa.pub
chown -R root /root/.ssh
