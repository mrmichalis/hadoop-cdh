#!/usr/bin/env bash

function install {
 if [ $(egrep -ic "192.168.1.245" "/etc/hosts") -eq 0 ]; then
  echo "192.168.1.245 archive.cloudera.com" >> /etc/hosts
  echo "192.168.1.245 beta.cloudera.com" >> /etc/hosts
 fi
 ./cloudera-manager-installer.bin --i-agree-to-all-licenses --noprompt --noreadme --nooptions
}

function managerSettings {
 # curl -u admin:admin http://$(hostname):7180/api/v3/cm/deployment > managerSettings.json
 INIT_FILE="/root/CDH/managerSettings.json"
 wget "http://archive.cloudera.com/managerSettings.json" -O "$INIT_FILE"
 while ! exec 6<>/dev/tcp/$(hostname)/7180; do echo -e -n "Waiting for cloudera-scm-server to start..."; sleep 10; done
 if [ -f $INIT_FILE ]; then
   curl --upload-file $INIT_FILE -u admin:admin http://$(hostname):7180/api/v3/cm/deployment?deleteCurrentDeployment=true
   service cloudera-scm-server restart
 fi
}

set -x
install

for target in "$@"; do
  case "$target" in
  lic)
    (managerSettings)
    ;;  
  esac
done

exit 0
