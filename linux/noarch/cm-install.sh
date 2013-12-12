#!/usr/bin/env bash
START_SCM_AGENT=''
SERVER_DB=''
JDK_VER=''

usage() {
  VERTMP=$(wget -qO - http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/ | awk 'BEGIN{ RS="<a *href *= *\""} NR>2 {sub(/".*/,"|");print;}' | grep "^4" | tr "/" " " | tr "\n" " ")
  echo "usage: $0 --bin or --version=4.6.0 [--embed-db OR --mysql-db] --jdk=[6 or 7]" 1>&2
  echo "Options" 1>&2
  echo "  --bin              :   Use latest installer" 1>&2
  echo "  --version=[4.2.1]  :   Install/Upgrade version" 1>&2
  echo "  Available versions :   | $VERTMP" 1>&2  
  echo " "
  echo "Optional" 1>&2
  echo "  --embed-db         :   Install/Upgrade cloudera-manager-server-db" 1>&2
  echo "  --mysql-db         :   Prepare MySQL Database" 1>&2
  echo " "
  echo "JDK (default JDK6)" 1>&2
  echo "  --jdk=[6 or 7]     :   Install with JDK 6 or JDK 7" 1>&2
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

function installJava {
  JDK_VER=`echo $1 | sed -e 's/^[^=]*=//g'`
  if [ $JDK_VER -ne "7" ]; then 
    echo "* Oracle JDK 6u31 from CM..."
    command -v java >/dev/null 2>&1 || wget http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/4/RPMS/x86_64/jdk-6u31-linux-amd64.rpm -O /root/CDH/jdk-6u31-linux-amd64.rpm
    command -v java >/dev/null 2>&1 || rpm -ivh /root/CDH/jdk-6u31-linux-amd64.rpm
    
    echo "* Downloading Java Cryptography Extension (JCE) ..."
    wget --no-check-certificate --no-cookies --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com" http://download.oracle.com/otn-pub/java/jce_policy/6/jce_policy-6.zip -O /root/CDH/jce_policy-6.zip
    [[ -d "/usr/java/default/jre/lib/security/" ]] && unzip -oj /root/CDH/jce_policy-6.zip -d /usr/java/default/jre/lib/security/   
  else
    echo "* Oracle JDK 7u25 from CM..."
    command -v java >/dev/null 2>&1 || wget http://archive.cloudera.com/cm5/redhat/6/x86_64/cm/5/RPMS/x86_64/oracle-j2sdk1.7-1.7.0+update25-1.x86_64.rpm -O /root/CDH/oracle-j2sdk1.7-1.7.0+update25-1.x86_64.rpm 
    command -v java >/dev/null 2>&1 || rpm -ivh /root/CDH/oracle-j2sdk1.7-1.7.0+update25-1.x86_64.rpm
    
    echo "* Downloading Java Cryptography Extension (JCE 7) ..."
    wget --no-check-certificate --no-cookies --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com" http://download.oracle.com/otn-pub/java/jce/7/UnlimitedJCEPolicyJDK7.zip -O /root/CDH/UnlimitedJCEPolicyJDK7.zip
    [[ -d "/usr/java/default/jre/lib/security/" ]] && unzip -oj /root/CDH/UnlimitedJCEPolicyJDK7.zip -d /usr/java/default/jre/lib/security/
  fi
}

function useBinInstaller {
  ./cloudera-manager-installer.bin --i-agree-to-all-licenses --noprompt --noreadme --nooptions
  #./cloudera-manager-installer.bin --use_embedded_db=0 --db_pw=cloudera_scm --no-prompt --i-agree-to-all-licenses --noreadme
}

function useRpm {
  yum clean all
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
 for SERVICE_NAME in $SERVER_DB cloudera-scm-server $START_SCM_AGENT; do
  service $SERVICE_NAME start
 done
}
 
stopServices() {
 for SERVICE_NAME in cloudera-scm-agent cloudera-scm-server cloudera-scm-server-db; do
  service $SERVICE_NAME stop
 done
}

function managerSettings {
 # curl -u admin:admin http://$(hostname):7180/api/v5/cm/deployment > managerSettings.json
 INIT_FILE="/root/CDH/managerSettings.json"
 wget "http://archive.cloudera.com/managerSettings.json" -O "$INIT_FILE"
 while ! exec 6<>/dev/tcp/$(hostname)/7180; do echo -e -n "Waiting for cloudera-scm-server to start..."; sleep 10; done
 if [ -f $INIT_FILE ]; then
   curl --upload-file $INIT_FILE -u admin:admin http://$(hostname):7180/api/v5/cm/deployment?deleteCurrentDeployment=true
   service cloudera-scm-server restart
 fi
}
if [ $# -lt 1 ]; then
  usage
  exit 1
fi
stopServices
set -x
for target in "$@"; do
  case "$target" in
  --version*)
    useRpm $target
    yum install -y cloudera-manager-daemons cloudera-manager-server cloudera-manager-agent
    # if [ -z $START_SCM_AGENT ] && promptyn "Do you wish to start cloudera-scm-agent? [y/n]"; then 
      # echo "$START_SCM_AGENT"
      # START_SCM_AGENT=${START_SCM_AGENT:-cloudera-scm-agent}
    # fi     
    [[ -z /home/hdfs ]] || mkdir -p /home/hdfs && chown -R hdfs:hdfs /home/hdfs
    shift
    ;;
  --embed-db)    
    SERVER_DB=${SERVER_DB:-cloudera-manager-server-db}
    yum install -y cloudera-manager-daemons cloudera-manager-server cloudera-manager-agent $SERVER_DB    
    shift
    ;;
  --mysql-db)    
    sh /root/CDH/mysql-init.sh
    /usr/share/cmf/schema/scm_prepare_database.sh mysql scm scm password
    #/usr/share/cmf/schema/scm_prepare_database.sh mysql -h localhost -u temp -ppassword --scm-host localhost scm scm password
    #yum install -y cloudera-manager-daemons cloudera-manager-server cloudera-manager-agent    
    shift
    ;;
  --lic)
    managerSettings
    shift
    ;;  
  --bin)
    useBinInstaller
    shift
    ;;  
  --jdk*)
    installJava $target
    shift
    ;;
  *)
    usage
    exit 1    
  esac
done
startServices

exit 0
