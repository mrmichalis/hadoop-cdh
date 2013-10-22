#!/usr/bin/env bash
usage() {
  VERTMP=$(wget -qO - http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/ | awk 'BEGIN{ RS="<a *href *= *\""} NR>2 {sub(/".*/,"|");print;}' | grep "^4" | tr "/" " " | tr "\n" " ")
  echo "usage: $0 --bin or --version=4.6.0 [--embed-db]" 1>&2
  echo "Options" 1>&2
  echo "  --bin              :   Use latest installer" 1>&2
  echo "  --version=[4.2.1]  :   Install/Upgrade version" 1>&2
  echo "  Available versions :   | $VERTMP" 1>&2  
  echo " "
  echo "Optional" 1>&2
  echo "  --embed-db         :   Install/Upgrade cloudera-manager-server-db" 1>&2
  echo "  --mysql-db         :   Prepare MySQL Database" 1>&2
  echo " "
}

function promptyn () {
  while true; do
    read -p "$1 " yn
    case $yn in
      [Yy]* ) return 0;;
      [Nn]* ) return 1;;
      * ) echo "Please answer with [y]es or [n]o.";;
    esac
  done
}

function redirectHosts {
 if [ $(egrep -ic "192.168.88.250" "/etc/hosts") -eq 0 ]; then
  echo "192.168.88.250 archive.cloudera.com" >> /etc/hosts
  echo "192.168.88.250 beta.cloudera.com" >> /etc/hosts
 fi
}

function installJava {
  command -v java >/dev/null 2>&1 || wget http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/4/RPMS/x86_64/jdk-6u31-linux-amd64.rpm -O /root/CDH/jdk-6u31-linux-amd64.rpm
  command -v java >/dev/null 2>&1 || rpm -ivh /root/CDH/jdk-6u31-linux-amd64.rpm
}

function useBinInstaller {
./cloudera-manager-installer.bin --i-agree-to-all-licenses --noprompt --noreadme --nooptions
#./cloudera-manager-installer.bin --use_embedded_db=0 --db_pw=cloudera_scm --no-prompt --i-agree-to-all-licenses --noreadme
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
 for SERVICE_NAME in cloudera-scm-server cloudera-scm-server-db $START_SCM_AGENT; do
  service $SERVICE_NAME start
 done
}
 
stopServices() {
 for SERVICE_NAME in cloudera-scm-agent cloudera-scm-server cloudera-scm-server-db; do
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
    START_SCM_AGENT=''
    if [ -z $START_SCM_AGENT ] && promptyn "Do you wish to start cloudera-scm-agent? [y/n]"; then 
      echo "$START_SCM_AGENT"
      START_SCM_AGENT=${START_SCM_AGENT:-cloudera-scm-agent}
      service cloudera-scm-agent start
    fi 
    startServices
    [[ -z /home/hdfs ]] || mkdir -p /home/hdfs && chown -R hdfs:hdfs /home/hdfs
    shift
    ;;
  --embed-db)
    stopServices
    SERVER_DB=${SERVER_DB:-cloudera-manager-server-db}
    yum install -y cloudera-manager-daemons cloudera-manager-server cloudera-manager-agent $SERVER_DB
    startServices
    shift
    ;;
  --mysql-db)
    stopServices
    /usr/share/cmf/schema/scm_prepare_database.sh mysql scm scm password
    yum install -y cloudera-manager-daemons cloudera-manager-server cloudera-manager-agent
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
