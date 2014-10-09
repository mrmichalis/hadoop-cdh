#!/usr/bin/env bash
set -x

#start -init
mkdir -p /root/CDH
sed -i 's/alias/#alias/g' /root/.bashrc
#echo "set -o vi"    >> /root/.bashrc
echo "alias vi=vim" >> /root/.bashrc
sed -i 's/ls -l/ls -ltr/g' /etc/profile.d/colorls.*

cat << EOF >> /root/.bashrc
# Auto-screen invocation. see: http://taint.org/wk/RemoteLoginAutoScreen
# if we're coming from a remote SSH connection, in an interactive session
# then automatically put us into a screen(1) session.   Only try once
# -- if $STARTED_SCREEN is set, don't try it again, to avoid looping
# if screen fails for some reason.
if [ "\$PS1" != "" -a "\${STARTED_SCREEN:-x}" = x -a "\${SSH_TTY:-x}" != x ]
then
  STARTED_SCREEN=1 ; export STARTED_SCREEN
  [ -d \$HOME/lib/screen-logs ] || mkdir -p \$HOME/lib/screen-logs
  sleep 1
  screen -RR && exit 0
  # normally, execution of this rc script ends here...
  echo "Screen failed! continuing with normal bash startup"
fi
# [end of auto-screen snippet]

#export JAVA_HOME=/usr/java/default
#export PATH=$PATH:$JAVA_HOME/bin;$JAVA_HOME/jre/bin
EOF

function installPdsh() {
  echo "Installing Parallel Distributed Shell v2.29"
  wget --no-check-certificate --no-cookies -nv https://pdsh.googlecode.com/files/pdsh-2.29.tar.bz2 -O /root/CDH/pdsh-2.29.tar.bz2
  tar xjvf /root/CDH/pdsh-2.29.tar.bz2 -C /root/CDH/ && pushd /root/CDH/pdsh-2.29/
  ./configure --with-ssh
  make
  make install
  echo 'export PDSH_SSH_ARGS_APPEND="-o ConnectTimeout=5 -o CheckHostIP=no -o StrictHostKeyChecking=no"' >> /root/.bashrc
  export PDSH_SSH_ARGS_APPEND="-o ConnectTimeout=5 -o CheckHostIP=no -o StrictHostKeyChecking=no"
  popd
}

yum install -y nc screen
echo "* Install Puppet 6.10 repo"
rpm -ivh https://yum.puppetlabs.com/el/6/products/x86_64/puppetlabs-release-6-10.noarch.rpmecho "* Install Puppet 6.10 repo"
echo "* Install Puppet CM API and pre-requisites"
yum install -y puppet git python-argparse sshpass libffi-devel python-setuptools
yum groupinstall -y "Development tools"
easy_install pip
git clone https://github.com/openstack/python-novaclient.git /root/python-novaclient && pip install /root/python-novaclient
git clone https://github.com/cloudera/cm_api.git /root/cm_api && pip install /root/cm_api/python
#pip install fabric && cat /dev/null > /usr/lib/python2.6/site-packages/Fabric-1.9.0-py2.6.egg-info/requires.txt
installPdsh

echo "* install NFS Utils"
yum install -y nfs-utils

#http://www.cyberciti.biz/faq/unable-to-read-consumer-identity-rhn-yum-warning/
if grep -q -i "Red Hat" /etc/redhat-release; then
  sed -i 's/1/0/g' /etc/yum/pluginconf.d/product-id.conf 
  sed -i 's/1/0/g' /etc/yum/pluginconf.d/subscription-manager.conf
fi
echo "192.168.88.250 archive.cloudera.com" >> /etc/hosts
echo "192.168.88.250 archive-primary.cloudera.com" >> /etc/hosts
echo "192.168.88.250 beta.cloudera.com" >> /etc/hosts
#end -init

wget --no-check-certificate -nv 'https://github.com/mrmichalis/hadoop-cdh/raw/master/linux/noarch/.screenrc' -O /root/.screenrc
wget --no-check-certificate -nv 'https://github.com/mrmichalis/hadoop-cdh/raw/master/linux/noarch/post-download.lst' -O /root/CDH/post-download.lst

POST_OPTIONS=$(cat /root/CDH/post-download.lst)
for OPT in ${POST_OPTIONS[@]}; do
  wget --no-check-certificate -nv "https://github.com/mrmichalis/hadoop-cdh/raw/master/linux/noarch/${OPT}" -O /root/CDH/${OPT} && chmod +x /root/CDH/${OPT}
done;

# Make sure udev doesn't block our network
# http://6.ptmc.org/?p=164
echo "* Cleaning up udev rules ..."
rm /etc/udev/rules.d/70-persistent-net.rules
mkdir /etc/udev/rules.d/70-persistent-net.rules
# rm -rf /dev/.udev/
# rm /lib/udev/rules.d/75-persistent-net-generator.rules

#* Installing SSH keys...
curl -L https://raw.githubusercontent.com/mrmichalis/hadoop-cdh/master/linux/noarch/keys/get_ssh_keys.sh | bash

# http://fredkschott.com/post/2014/02/git-log-is-so-2005/
git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%C(bold blue)<%an>%Creset' --abbrev-commit"

# Zero out the free space to save space in the final image:
#echo "* Zeroing out unused space ..."
#dd if=/dev/zero of=/EMPTY bs=1M
#rm -f /EMPTY
