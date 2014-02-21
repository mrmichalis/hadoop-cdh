#!/usr/bin/env bash

usage() {
  VERTMP=$(wget -qO - http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/ | awk 'BEGIN{ RS="<a *href *= *\""} NR>2 {sub(/".*/,"|");print;}' | grep "^4" | tr "/" " " | tr "\n" " ")
  VERLATEST=$(wget -qO - http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/ | awk 'BEGIN{ RS="<a *href *= *\""} NR>2 {sub(/".*/,"");print;}' | grep "^4" | tail -2 | head -1 | tr "/" " " )
cat << EOF
  usage: $0 --bin or --ver=4.8.0 [--psql OR --mysql] --jdk=[6 or 7]
  Options
    --bin                :   Use latest installer
    --ver [4.7.2]        :   Install/Upgrade version
    Available versions   :   ${VERTMP}

  Optional if none-selected this will be Embedded PSQL
    --db=e               :   Install/Upgrade cloudera-manager-server-db                             
    --db=m               :   Prepare MySQL Database

  JDK (default JDK6)
    --jdk=[6 or 7]     :   Install with JDK 6 or JDK 7
  
  Example:
    $0 --ver=${VERLATEST} --db=e --jdk=6
EOF
}

function installJava {
/  if [ $1 -ne "7" ]; then
    echo "* Oracle JDK 6u31 from CM..."
    command -v java >/dev/null 2>&1 || wget http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/4/RPMS/x86_64/jdk-6u31-linux-amd64.rpm -O /root/CDH/jdk-6u31-linux-amd64.rpm
    command -v java >/dev/null 2>&1 || rpm -ivh /root/CDH/jdk-6u31-linux-amd64.rpm

    echo "* Downloading Java Cryptography Extension (JCE) ..."
    wget --no-check-certificate --no-cookies --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com" http://download.oracle.com/otn-pub/java/jce_policy/6/jce_policy-6.zip -O /root/CDH/jce_policy-6.zip
    [[ -d "/usr/java/default/jre/lib/security/" ]] && unzip -oj /root/CDH/jce_policy-6.zip -d /usr/java/default/jre/lib/security/
  else
    if !(command -v java >/dev/null 2>&1); then
      echo "* Oracle JDK 7u25 from CM..."
      wget http://archive.cloudera.com/cm5/redhat/6/x86_64/cm/5/RPMS/x86_64/oracle-j2sdk1.7-1.7.0+update25-1.x86_64.rpm -O /root/CDH/oracle-j2sdk1.7-1.7.0+update25-1.x86_64.rpm
      command -v java >/dev/null 2>&1 || rpm -ivh /root/CDH/oracle-j2sdk1.7-1.7.0+update25-1.x86_64.rpm
      ln -s /usr/java/jdk1.7.0_25-cloudera/ /usr/java/latest
      ln -s /usr/java/latest /usr/java/default
      update-alternatives --install /usr/bin/java java /usr/java/default/bin/java 10
      echo "* Downloading Java Cryptography Extension (JCE 7) ..."
      wget --no-check-certificate --no-cookies --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com" http://download.oracle.com/otn-pub/java/jce/7/UnlimitedJCEPolicyJDK7.zip -O /root/CDH/UnlimitedJCEPolicyJDK7.zip
      [[ -d "/usr/java/default/jre/lib/security/" ]] && unzip -oj /root/CDH/UnlimitedJCEPolicyJDK7.zip -d /usr/java/default/jre/lib/security/
    fi
  fi
  echo "* Set JAVA_HOME in /etc/profile.d/jdk.sh ..."
  echo 'export JAVA_HOME=/usr/java/default' > /etc/profile.d/jdk.sh
  echo 'export PATH=$JAVA_HOME/bin:$PATH' >> /etc/profile.d/jdk.sh
}

function useRpm {
  yum clean all
  rpm --import http://archive.cloudera.com/cdh4/redhat/6/x86_64/cdh/RPM-GPG-KEY-cloudera
  cat << EOF > /etc/yum.repos.d/cloudera-manager.repo
[cloudera-manager]
# Packages for Cloudera Manager, Version 4, on RedHat or CentOS 6 x86_64
name=Cloudera Manager
baseurl=http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/$1/
gpgkey = http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/RPM-GPG-KEY-cloudera
gpgcheck = 1
EOF
}

startServices() {
 if [[ $SERVER_DB = "e" ]]; then 
  service cloudera-scm-server-db start
 fi
 for SERVICE_NAME in cloudera-scm-server $START_SCM_AGENT; do
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
#set -x
START_SCM_AGENT=
SERVER_DB=${SERVER_DB:-e}
JDK_VER=${JDK_VER:-6}
CMVERSION=${VERLATEST}

for target in "$@"; do
  case "$target" in
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
echo "============================================="
stopServices
if [[ -z $USEBIN ]]; then
  echo $0: using RPM Installer
  echo Installing JDK $JDK_VER
  installJava $JDK_VER
  echo Set cloudera-manager.repo to CM v$CMVERSION
  useRpm $CMVERSION
  yum install -y cloudera-manager-daemons cloudera-manager-server cloudera-manager-agent
  if [[ $SERVER_DB = "p" ]]; then
    echo Initialize MySQL
    sh /root/CDH/mysql-init.sh
    /usr/share/cmf/schema/scm_prepare_database.sh mysql scm scm password
  else 
    yum install -y cloudera-manager-server-db
  fi
  startServices
  exit 0
else
  echo $0: using Binary Installer
  echo "* Downloading the latest Cloudera Manager installer ..."
  wget -q "http://archive.cloudera.com/cm4/installer/latest/cloudera-manager-installer.bin" -O /root/CDH/cloudera-manager-installer.bin && chmod +x /root/CDH/cloudera-manager-installer.bin

  ./cloudera-manager-installer.bin --i-agree-to-all-licenses --noprompt --noreadme --nooptions
  #./cloudera-manager-installer.bin --use_embedded_db=0 --db_pw=cloudera_scm --no-prompt --i-agree-to-all-licenses --noreadme
  startServices
  exit 0
fi
