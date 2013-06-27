#!/usr/bin/env bash
set -x

#start -init
sed -i 's/alias/#alias/g' /root/.bashrc
#http://www.cyberciti.biz/faq/unable-to-read-consumer-identity-rhn-yum-warning/
if grep -q -i "Red Hat" /etc/redhat-release; then
  sed -i 's/1/0/g' /etc/yum/pluginconf.d/product-id.conf 
  sed -i 's/1/0/g' /etc/yum/pluginconf.d/subscription-manager.conf
fi
echo "192.168.1.245 archive.cloudera.com" >> /etc/hosts
echo "192.168.1.245 beta.cloudera.com" >> /etc/hosts
mkdir -p /root/CDH
#end -init

echo "* Downloading the latest Cloudera Manager installer ..."
wget -q http://archive.cloudera.com/cm4/installer/latest/cloudera-manager-installer.bin -O /root/CDH/cloudera-manager-installer.bin
chmod +x /root/CDH/cloudera-manager-installer.bin

cat << EOF > /root/CDH/dep-download.sh
#!/usr/bin/env bash
echo "* Oracle JDK 6u31 from CM..."
command -v java >/dev/null 2>&1 || wget http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/4/RPMS/x86_64/jdk-6u31-linux-amd64.rpm -O /root/CDH/jdk-6u31-linux-amd64.rpm

echo "* Downloading MySQL Connector-J ..."
curl -L http://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.25.tar.gz/from/http://cdn.mysql.com/ | tar xzv
[[ -d "/usr/share/java/" && ! -e "/usr/share/java/mysql-connector-java.jar" ]] && cp /root/CDH/mysql-connector-java-5.1.25/mysql-connector-java-5.1.25-bin.jar /usr/share/java/mysql-connector-java.jar
[[ -d "/opt/cloudera/parcels/CDH/lib/hive/lib/" && ! -e "/opt/cloudera/parcels/CDH/lib/hive/lib/mysql-connector-java.jar" ]] && ln -s /root/CDH/mysql-connector-java-5.1.25/mysql-connector-java-5.1.25-bin.jar 
[[ -d "/var/lib/oozie/" && ! -e "/var/lib/oozie/mysql-connector-java.jar" ]] && ln -s /usr/share/java/mysql-connector-java.jar /var/lib/oozie/mysql-connector-java.jar

echo "* ExtJS library to enable Oozie webconsole ..."
wget http://extjs.com/deploy/ext-2.2.zip -O /root/CDH/ext-2.2.zip
[ -d "/var/lib/oozie/ext-2.2/" ] || unzip /root/CDH/ext-2.2.zip -d /var/lib/oozie/

echo "* Downloading Java Cryptography Extension (JCE) ..."
wget --no-check-certificate --no-cookies --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com" http://download.oracle.com/otn-pub/java/jce_policy/6/jce_policy-6.zip -O /root/CDH/jce_policy-6.zip
[ -d "/usr/java/default/jre/lib/security/" ] && unzip -oj /root/CDH/jce_policy-6.zip -d /usr/java/default/jre/lib/security/

EOF
chmod +x /root/CDH/dep-download.sh

cat << EOF > /root/CDH/mysql-init.sh
#!/usr/bin/env bash
service mysqld start
yum install -y expect
expect -c " 
set timeout 5
spawn mysql_secure_installation
 
expect \"Enter current password for root (enter for none):\"
send \"\r\"
expect \"Set root password?\"
send \"n\r\"
expect \"Remove anonymous users?\"
send \"n\r\"
expect \"Disallow root login remotely?\"
send \"n\r\"
expect \"Remove test database and access to it?\"
send \"n\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
" 
yum remove -y expect

curl -L http://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.25.tar.gz/from/http://cdn.mysql.com/ | tar xzv
[[ -d "/usr/share/java/" && ! -e "/usr/share/java/mysql-connector-java.jar" ]] && cp /root/CDH/mysql-connector-java-5.1.25/mysql-connector-java-5.1.25-bin.jar /usr/share/java/mysql-connector-java.jar
[[ -d "/opt/cloudera/parcels/CDH/lib/hive/lib/" && ! -e "/opt/cloudera/parcels/CDH/lib/hive/lib/mysql-connector-java.jar" ]] && ln -s /root/CDH/mysql-connector-java-5.1.25/mysql-connector-java-5.1.25-bin.jar 

chkconfig mysqld on
service mysqld start
sleep 10

for service in amon smon rman hmon nav hive; do
  mysql -u root -e "create database \$service DEFAULT default character set utf8 collate utf8_general_ci;"
  mysql -u root -e "grant all on \$service.* TO '\$service'@'localhost' IDENTIFIED BY 'password';"
  mysql -u root -e "grant all on \$service.* TO '\$service'@'192-168-1-109.lunix.co' IDENTIFIED BY 'password';"
  mysql -u root -e "grant all on \$service.* TO '\$service'@'%.lunix.co' IDENTIFIED BY 'password';"
done
mysql -u root -e 'show databases;'

EOF
chmod +x /root/CDH/mysqlinit.sh


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

cat << EOF > /root/CDH/orajava-install.sh
#!/usr/bin/env bash
echo "* Downloading and Installing Oracle Java SDK 6u41 from Oracle ..."
JAVA_URL="http://download.oracle.com/otn-pub/java/jdk/6u43-b01/jdk-6u43-linux-x64-rpm.bin"
JAVA_FILENAME=\$(echo \$JAVA_URL | cut -d/ -f8)
wget --no-check-certificate --no-cookies --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com" \$JAVA_URL -O /root/CDH/\$JAVA_FILENAME
chmod +x /root/CDH/\$JAVA_FILENAME
touch answers && sh \$JAVA_FILENAME < answers && /bin/rm answers
EOF
chmod +x /root/CDH/orajava-install.sh

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
  echo "192.168.1.245 beta.cloudera.com" >> /etc/hosts
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

# Make sure udev doesn't block our network
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

# Zero out the free space to save space in the final image:
#echo "* Zeroing out unused space ..."
#dd if=/dev/zero of=/EMPTY bs=1M
#rm -f /EMPTY