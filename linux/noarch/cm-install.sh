#!/usr/bin/env bash
usage() {
  echo "usage: $0 --version=4.5.1 or --bin (--embed-db)" 1>&2
  echo "Optional: --embed-db      : install cloudera-manager-server-db" 1>&2
  echo "Available versions: " 1>&2
  wget -qO - http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/ | awk 'BEGIN{ RS="<a *href *= *\""} NR>2 {sub(/".*/,"|");print;}' | grep "^4" | tr "/" " " | tr "\n" " "
  echo ""
}

function redirectHosts {
 if [ $(egrep -ic "192.168.1.245" "/etc/hosts") -eq 0 ]; then
  echo "192.168.1.245 archive.cloudera.com" >> /etc/hosts
  echo "192.168.1.245 beta.cloudera.com" >> /etc/hosts
 fi
}

function installJava {
  command -v java >/dev/null 2>&1 || wget http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/4/RPMS/x86_64/jdk-6u31-linux-amd64.rpm -O /root/CDH/jdk-6u31-linux-amd64.rpm
  command -v java >/dev/null 2>&1 || rpm -ivh /root/CDH/jdk-6u31-linux-amd64.rpm
}

function useBinInstaller {
 ./cloudera-manager-installer.bin --i-agree-to-all-licenses --noprompt --noreadme --nooptions
}

function useRpm {
CMVERSION=`echo $1 | sed -e 's/^[^=]*=//g'`
rpm --import http://archive.cloudera.com/cdh4/redhat/6/x86_64/cdh/RPM-GPG-KEY-cloudera
cat << EOF > /etc/yum.repos.d/cloudera-manager.repo
[cloudera-manager]
# Packages for Cloudera Manager, Version 4, on RedHat or CentOS 6 x86_64
name=Cloudera Manager
baseurl=http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/$CMVERSION/
gpgkey = http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/RPM-GPG-KEY-cloudera
gpgcheck = 1
EOF
}
 
startServices() {
 for SERVICE_NAME in cloudera-scm-server-db cloudera-scm-server cloudera-scm-agent; do
  service $SERVICE_NAME start
 done
}
 
stopServices() {
 for SERVICE_NAME in cloudera-scm-server cloudera-scm-agent cloudera-scm-server-db; do
  service $SERVICE_NAME stop
 done
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
if [ $# -lt 1 ]; then
  usage
  exit 1
fi

set -x
for target in "$@"; do
  case "$target" in
  --version*)
    redirectHosts
    installJava
    stopServices
    useRpm $target
    yum install -y cloudera-manager-daemons cloudera-manager-server cloudera-manager-agent
    startServices
    shift
    ;;
  --embed-db)
    stopServices
    SERVER_DB=${SERVER_DB:-cloudera-manager-server-db}
    yum install -y cloudera-manager-daemons cloudera-manager-server cloudera-manager-agent $SERVER_DB
    startServices
    shift
    ;;
  --lic)
    managerSettings
    shift
    ;;  
  --bin)
    redirectHosts
    useBinInstaller
    shift
    ;;  
  *)
    usage
    exit 1    
  esac
done

exit 0
