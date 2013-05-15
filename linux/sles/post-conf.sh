#!/usr/bin/env bash
IPADDR=$(ip -f inet addr show dev eth0|awk '$1~/inet/{print $2}'|cut -d/ -f1)
NETMASK=$(ifconfig eth0|awk -F"Mask:" '$1~/inet /{print $2}')
HWADDR="$(ifconfig eth0 | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}')"
HOSTNAME="$(echo $IPADDR | tr '.' '-')"
DN="lunix.co"
FQDN="$HOSTNAME.$DN"
GATEWAY=$(route | grep default | cut -b 17-32 | cut -d " " -f 1)

echo "default $GATEWAY" >> /etc/sysconfig/network/routes
echo "$FQDN" > /etc/HOSTNAME

cat << EOF > /etc/sysconfig/network/ifcfg-eth0
DEVICE=eth0
NM_CONTROLLED=no
IPV6INIT=no
IPV6_AUTOCONF=no
USERCTL=no
ONBOOT=yes
BOOTPROTO=static
HWADDR=$HWADDR
IPADDR=$IPADDR
NETMASK=$NETMASK
GATEWAY=$GATEWAY
STARTMODE=auto
#RESOLV_MODS=no
EOF

cat << EOF > /etc/sysconfig/network/ifcfg-eth1
DEVICE=eth1
NM_CONTROLLED=no
IPV6INIT=no
IPV6_AUTOCONF=no
USERCTL=no
ONBOOT=no
BOOTPROTO=static
IPADDR=
NETMASK=
EOF

cat << EOF >> /etc/sysctl.conf
 
#disable_ipv6 content
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

#swappiness
#vm.swappiness = 0
EOF

cat << EOF > /etc/resolv.conf
search $DN
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

cat << EOF >> /etc/hosts

$IPADDR $FQDN $HOSTNAME
EOF
echo
echo "################################"
echo "# Running Post Configuration   #"
echo "################################"
(
mkdir -p /root/CDH

echo "* Downloading the latest Cloudera Manager installer ..."
wget -q http://archive.cloudera.com/cm4/installer/latest/cloudera-manager-installer.bin -O /root/CDH/cloudera-manager-installer.bin
chmod +x /root/CDH/cloudera-manager-installer.bin

cat << EOF > /root/CDH/vboxadditions.sh
#!/usr/bin/env bash

VBOX_VERSION="\$(wget -q -O - http://download.virtualbox.org/virtualbox/LATEST.TXT)"
echo "* Downloading virtualbox Linux Additions version $VBOX_VERSION..."
# wget -q "http://download.virtualbox.org/virtualbox/\$VBOX_VERSION/VBoxGuestAdditions_\$VBOX_VERSION.iso" -O "/root/CDH/VBoxGuestAdditions_\$VBOX_VERSION.iso"
curl -L -O "http://download.virtualbox.org/virtualbox/\$VBOX_VERSION/VBoxGuestAdditions_\$VBOX_VERSION.iso"

mount -o loop "VBoxGuestAdditions_\$VBOX_VERSION.iso" /mnt
sh /mnt/VBoxLinuxAdditions.run --nox11
umount /mnt

echo "rm VBoxGuestAdditions_\$VBOX_VERSION.iso"
EOF
chmod +x /root/CDH/vboxadditions.sh

cat << EOF > /root/CDH/downloadjava.sh
#!/usr/bin/env bash

echo "* Downloading Oracle Java SDK 6u31 from Cloudera ..."
wget http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/4/RPMS/x86_64/jdk-6u31-linux-amd64.rpm -O jdk-6u31-linux-amd64.rpm

echo "* Downloading and Installing Oracle Java SDK 6u41 from Oracle ..."
JAVA_URL="http://download.oracle.com/otn-pub/java/jdk/6u43-b01/jdk-6u43-linux-x64-rpm.bin"
JAVA_FILENAME=\$(echo \$JAVA_URL | cut -d/ -f8)
wget --no-check-certificate --no-cookies --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com" \$JAVA_URL -O /root/CDH/\$JAVA_FILENAME
chmod +x /root/CDH/\$JAVA_FILENAME
touch answers && sh \$JAVA_FILENAME < answers && /bin/rm answers

echo "* Downloading Java Cryptography Extension (JCE) ..."
wget --no-check-certificate --no-cookies --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com" http://download.oracle.com/otn-pub/java/jce_policy/6/jce_policy-6.zip -O /root/CDH/jce_policy-6.zip
EOF
chmod +x /root/CDH/downloadjava.sh

cat << EOF > /root/CDH/getip.sh
#!/usr/bin/env bash

if [ \$# -lt 1 ]; then
  echo "usage: \$0 [hosts list]" 1>&2
  exit 1
fi
HOSTSLIST=\$1
IPADDR=\$(ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print \$1}')

if [ -a \$HOSTSLIST ]; then
 for IP in \$(cat \$HOSTSLIST | grep -v \$IPADDR); do ssh root@\$IP "grep 192.168.1. /etc/hosts" >> /etc/hosts; done
 for IP in \$(cat \$HOSTSLIST | grep -v \$IPADDR); do scp /etc/hosts root@\$IP:/etc/hosts; done
fi
EOF
chmod +x /root/CDH/getip.sh

cat << EOF > /root/CDH/cm-install.sh
#!/usr/bin/env bash

function install {
 if [ \$(egrep -ic "192.168.1.245" "/etc/hosts") -eq 0 ]; then
   echo "192.168.1.245 archive.cloudera.com" >> /etc/hosts
 fi
 ./cloudera-manager-installer.bin --i-agree-to-all-licenses --noprompt --noreadme --nooptions
}

function managerSettings {
 # curl -u admin:admin http://\$(hostname):7180/api/v3/cm/deployment > managerSettings.json
 INIT_FILE="/root/CDH/managerSettings.json"
 wget "http://archive.cloudera.com/managerSettings.json" -O "\$INIT_FILE"
 while ! exec 6<>/dev/tcp/\$(hostname)/7180; do echo -e -n "Waiting for cloudera-scm-server to start..."; sleep 10; done
 if [ -f \$INIT_FILE ]; then
   curl --upload-file \$INIT_FILE -u admin:admin http://\$(hostname):7180/api/v3/cm/deployment?deleteCurrentDeployment=true
   service cloudera-scm-server restart
 fi
}

set -x
install

for target in "\$@"; do
	case "\$target" in
	lic)
		(managerSettings)
		;;	
	esac
done

exit 0
EOF
chmod +x /root/CDH/cm-install.sh

# Make sure Udev doesn't block our network
# http://6.ptmc.org/?p=164
echo "* Cleaning up udev rules ..."
rm /etc/udev/rules.d/70-persistent-net.rules
mkdir /etc/udev/rules.d/70-persistent-net.rules
# rm -rf /dev/.udev/
# rm /lib/udev/rules.d/75-persistent-net-generator.rules

#Install vagrant keys. See: https://github.com/mitchellh/vagrant/tree/master/keys
echo "* Installing SSH keys..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh
wget --no-check-certificate 'https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub' -O /root/.ssh/authorized_keys
wget --no-check-certificate 'https://raw.github.com/mitchellh/vagrant/master/keys/vagrant' -O /root/.ssh/id_rsa
wget --no-check-certificate 'https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub' -O /root/.ssh/id_rsa.pub
chmod 600 /root/.ssh/authorized_keys /root/.ssh/id_rsa /root/.ssh/id_rsa.pub
chown -R root /root/.ssh

echo "* restart NTP ..."
/etc/init.d/ntp restart 

# Zero out the free space to save space in the final image:
echo "* Zeroing out unused space ..."
#dd if=/dev/zero of=/EMPTY bs=1M
#rm -f /EMPTY

) 2>&1 | /usr/bin/tee /root/post-install.log
