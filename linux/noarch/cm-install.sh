#!/usr/bin/env bash
WGET="wget --no-check-certificate --no-cookies -nv"
usage() {
cat << EOF
  usage: $0 --bin or --ver=${VERLATEST//[[:blank:]]/} [--db=p OR --db=m] --jdk=[6 OR 7]
  Options
    --bin                           :   Use latest installer
    --ver [${VERLATEST//[[:blank:]]/}]        :   Install/Upgrade version
    Available versions              :   ${VERTMP}

  Optional if none-selected this will be Embedded PSQL
    --db=p                          :   Install/Upgrade cloudera-manager-server-db                             
    --db=m                          :   Prepare MySQL Database

  JDK (default JDK6)
    --jdk=[6 OR 7]                  :   Install with JDK 6 or JDK 7
  
  Agents
    --agent                         :   Install Agent only
    --startagent                    :   Start Agent after installation
    --cmhost=[hostname/ip]          :   Location of the CM Server Hosts
  
  Default
    --default            : Install similar to below parameters
                         : $0 --ver=${VERLATEST//[[:blank:]]/} --db=p --jdk=6
EOF
}

usefulCmds(){
echo "Useful commands"
cat <<EOF
 tail -f /var/log/cloudera-scm-server/cloudera-scm-server.log
 service cloudera-scm-server-db status
 service cloudera-scm-server status
 curl -i -u 'admin:admin' -X POST http://$(hostname -f):7180/api/v6/cm/trial/begin
 watch -n 1 nc -z $(hostname -f) 7180
EOF
}

function prepHiveDB() {
  export PGPASSWORD=$(head -1 /var/lib/cloudera-scm-server-db/data/generated_password.txt)
  SQLCMD=( """CREATE ROLE hive LOGIN PASSWORD 'hive';""" """CREATE DATABASE hive OWNER hive ENCODING 'UTF8';""" """ALTER DATABASE hive SET standard_conforming_strings = off;""" )
  for SQL in "${SQLCMD[@]}"; do    
    psql -A -t -d scm -U cloudera-scm -h localhost -p 7432 -c "${SQL}"
  done  
}

function installJava() {
  echo Installing JDK $1
  if [ $1 -ne "7" ]; then
    echo "* Oracle JDK 6u31 from CM..."
    command -v java >/dev/null 2>&1 || wget http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/4/RPMS/x86_64/jdk-6u31-linux-amd64.rpm -O /root/CDH/jdk-6u31-linux-amd64.rpm
    command -v java >/dev/null 2>&1 || rpm -ivh /root/CDH/jdk-6u31-linux-amd64.rpm

    echo "* Downloading Java Cryptography Extension (JCE) ..."
    # See https://github.com/flexiondotorg/oab-java6/blob/master/oab-java.sh
    $WGET --no-check-certificate --header "Cookie: oraclelicense=accept-securebackup-cookie;gpw_e24=http://edelivery.oracle.com" http://download.oracle.com/otn-pub/java/jce_policy/6/jce_policy-6.zip -O /root/CDH/jce_policy-6.zip
    [[ -d "/usr/java/default/jre/lib/security/" ]] && unzip -oj /root/CDH/jce_policy-6.zip -d /usr/java/default/jre/lib/security/
  else
    if !(command -v java >/dev/null 2>&1); then
      echo "* Oracle JDK 7u55 from CM..."
      VER="oracle-j2sdk1.7-1.7.0+update67-1.x86_64"
      wget http://archive.cloudera.com/cm5/redhat/6/x86_64/cm/5/RPMS/x86_64/${VER}.rpm -O /root/CDH/${VER}.rpm
      command -v java >/dev/null 2>&1 || rpm -ivh /root/CDH/${VER}.rpm
      ln -s /usr/java/jdk1.7.0_67-cloudera/ /usr/java/latest
      ln -s /usr/java/latest /usr/java/default
      update-alternatives --install /usr/bin/java java /usr/java/default/bin/java 10
      echo "* Downloading Java Cryptography Extension (JCE 7) ..."
      $WGET --no-check-certificate --header "Cookie: oraclelicense=accept-securebackup-cookie;gpw_e24=http://edelivery.oracle.com" http://download.oracle.com/otn-pub/java/jce/7/UnlimitedJCEPolicyJDK7.zip -O /root/CDH/UnlimitedJCEPolicyJDK7.zip
      [[ -d "/usr/java/default/jre/lib/security/" ]] && unzip -oj /root/CDH/UnlimitedJCEPolicyJDK7.zip -d /usr/java/default/jre/lib/security/
    fi
  fi
  echo "* Set JAVA_HOME in /etc/profile.d/jdk.sh ..."
  echo 'export JAVA_HOME=/usr/java/default' > /etc/profile.d/jdk.sh
  echo 'export PATH=$JAVA_HOME/bin:$PATH' >> /etc/profile.d/jdk.sh
}

function setRepo() {
  echo "Set cloudera-manager.repo to CM v$1"
  yum clean all 
  rpm --import http://archive.cloudera.com/cdh${REPOVER}/redhat/6/x86_64/cdh/RPM-GPG-KEY-cloudera
  cat << EOF > /etc/yum.repos.d/cloudera-manager.repo
[cloudera-manager]
# Packages for Cloudera Manager, Version ${REPOVER}, on RedHat or CentOS 6 x86_64
name=Cloudera Manager
baseurl=http://archive.cloudera.com/cm${REPOVER}/redhat/6/x86_64/cm/$1/
gpgkey = http://archive.cloudera.com/cm${REPOVER}/redhat/6/x86_64/cm/RPM-GPG-KEY-cloudera
gpgcheck = 1
EOF
}

function startServices() {
 if [[ $SERVER_DB = "p" ]]; then 
  service cloudera-scm-server-db start
  # trust everyone to access postgresql and signal pg to reload its config
  sed -ie 's/0 reject/0 trust/g' "/var/lib/cloudera-scm-server-db/data/pg_hba.conf"
  sudo -u cloudera-scm pg_ctl reload -D "/var/lib/cloudera-scm-server-db/data/"
  prepHiveDB
 fi
 for SERVICE_NAME in cloudera-scm-server $START_SCM_AGENT; do
  service $SERVICE_NAME start
 done
}

function stopServices() {
 for SERVICE_NAME in cloudera-scm-agent cloudera-scm-server cloudera-scm-server-db; do
  service $SERVICE_NAME stop
 done
}

function managerSettings() {
 # curl -u admin:admin http://$(hostname):7180/api/v5/cm/deployment > managerSettings.json
 INIT_FILE="/root/CDH/managerSettings.json"
 wget --nv "http://archive.cloudera.com/managerSettings.json" -O "$INIT_FILE"
 while ! exec 6<>/dev/tcp/$(hostname)/7180; do echo -e -n "Waiting for cloudera-scm-server to start..."; sleep 10; done
 if [ -f $INIT_FILE ]; then
   curl -u admin:admin http://$(hostname):7180/api/v5/cm/deployment?deleteCurrentDeployment=true --upload-file $INIT_FILE
   service cloudera-scm-server restart
 fi
}

#set -x
VERTMP4=$(wget -qO - http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/ | awk 'BEGIN{ RS="<a *href *= *\""} NR>2 {sub(/".*/,"|");print;}' | grep "^4" | tr "/" " " | tr "\n" " " | sed -e 's/^ *//')
VERTMP5=$(wget -qO - http://archive.cloudera.com/cm5/redhat/6/x86_64/cm/ | awk 'BEGIN{ RS="<a *href *= *\""} NR>2 {sub(/".*/,"|");print;}' | grep "^5" | tr "/" " " | tr "\n" " " | sed -e 's/^ *//')
CM4VER=$(wget -qO - http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/ | awk 'BEGIN{ RS="<a *href *= *\""} NR>2 {sub(/".*/,"");print;}' | grep "^4" | tail -2 | head -1 | tr "/" " " | sed -e 's/^ *//')
CM5VER=$(wget -qO - http://archive.cloudera.com/cm5/redhat/6/x86_64/cm/ | awk 'BEGIN{ RS="<a *href *= *\""} NR>2 {sub(/".*/,"");print;}' | grep "^5" | tail -1 | tr "/" " " | sed -e 's/^ *//')
VERLATEST="$CM5VER"
VERTMP="$VERTMP4 $VERTMP5"

START_SCM_AGENT=
SERVER_DB=${SERVER_DB:-p}
JDK_VER=${JDK_VER:-7}
CMVERSION=${VERLATEST//[[:blank:]]/}
USEBIN=${USEBIN:-false}
REPOVER=${REPOVER:-5}
MASTER_HOST=${MASTER_HOST//[[:blank:]]/}
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

for target in "$@"; do
  case "$target" in
  --startagent)
    START_SCM_AGENT=${START_SCM_AGENT:-cloudera-scm-agent}
    shift
    ;;
  --agent)
    INSTALL_AGENT_ONLY=${INSTALL_AGENTS:-true}
    shift
    ;;
  --cmhost*)
    CMHOST=$(echo $target | sed -e 's/^[^=]*=//g')
    shift
    ;;
  --ver*)
    CMVERSION=$(echo $target | sed -e 's/^[^=]*=//g')
    shift
    ;;
  --lic)
    MANAGERSETTINGS=${MANAGERSETTINGS:-true}
    shift
    ;;
  --bin)
    USEBIN=${USEBIN:-true}
    #echo "useBinInstaller"
    shift 
    ;;
  --db*)
    SERVER_DB=$(echo $target | sed -e 's/^[^=]*=//g')
    shift
    ;;
  --jdk*)
    JDK_VER=$(echo $target | sed -e 's/^[^=]*=//g')
    shift
    ;;
  --default)
    INSTALL_DEFAULT=${INSTALL_DEFAULT:-true}
    shift
    ;;    
  *)
    echo $target
    usage
    exit 1
  esac
done

echo "============================================="
echo CMVERSION: $CMVERSION
echo MANAGERSETTINGS: $MANAGERSETTINGS
echo USEBIN: $USEBIN
echo SERVER_DB: $SERVER_DB
echo JDK_VER: $JDK_VER
echo CMHOST $CMHOST
echo START $START_SCM_AGENT
echo "============================================="
if [[ $CMVERSION == *4* ]]; then
  REPOVER="4";
fi
stopServices
if [[ $USEBIN == "false" ]]; then
  echo $0: using RPM Installer  
  installJava $JDK_VER
  setRepo $CMVERSION
  if [[ $INSTALL_AGENT_ONLY == "true" ]]; then
    if [ -z "$CMHOST" ]; then
      echo "Provide CM Server hostname or IP with parameter --cmhost=[hostname/ip]"
      exit 0
    else
       yum install -y cloudera-manager-daemons cloudera-manager-agent
      cp /etc/cloudera-scm-agent/config.ini /etc/cloudera-scm-agent/config.ini.backup.$TIMESTAMP
      sed -ie "s/server_host=localhost/server_host=${CMHOST}/g" /etc/cloudera-scm-agent/config.ini
      service cloudera-scm-agent start
    fi
  else
    yum install -y cloudera-manager-daemons cloudera-manager-server cloudera-manager-agent
    CMHOST=$(hostname -f); sed -ie "s/server_host=localhost/server_host=${CMHOST}/g" /etc/cloudera-scm-agent/config.ini
    if [[ $SERVER_DB = "m" ]]; then
      echo Initialize MySQL
      sh /root/CDH/mysql-init.sh
      echo /usr/share/cmf/schema/scm_prepare_database.sh mysql scm scm password
    else 
      yum install -y cloudera-manager-server-db*      
    fi
    startServices
    usefulCmds
    exit 0
  fi  

else
  echo $0: using Binary Installer
  echo "* Downloading the latest Cloudera Manager installer ..."
  wget -nv "http://archive.cloudera.com/cm${REPOVER}/installer/${CMVERSION//[[:blank:]]/}/cloudera-manager-installer.bin" -O /root/CDH/cloudera-manager-installer.bin && chmod +x /root/CDH/cloudera-manager-installer.bin

  ./cloudera-manager-installer.bin --i-agree-to-all-licenses --noprompt --noreadme --nooptions
  #./cloudera-manager-installer.bin --use_embedded_db=0 --db_pw=cloudera_scm --no-prompt --i-agree-to-all-licenses --noreadme
  startServices
  usefulCmds
  exit 0
fi