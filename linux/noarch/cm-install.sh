#!/usr/bin/env bash

usage() {
  VERTMP=$(wget -qO - http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/ | awk 'BEGIN{ RS="<a *href *= *\""} NR>2 {sub(/".*/,"|");print;}' | grep "^4" | tr "/" " " | tr "\n" " ")
cat << EOF
  usage: ./cm-install.sh --bin or --ver=4.7.2 [--psql OR --mysql] --jdk=[6 or 7]
  Options
    --bin                :   Use latest installer
    --ver [4.7.2]        :   Install/Upgrade version
    Available versions  :   $VERTMP

  Optional if none-selected this will be MySQL
    --psql               :   Install/Upgrade cloudera-manager-server-db
    --mysql              :   Prepare MySQL Database

  JDK (default JDK6)
    --jdk=[6 or 7]     :   Install with JDK 6 or JDK 7
EOF

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
  echo $JDK_VER
  if [ $JDK_VER -ne "7" ]; then
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

function useBinInstaller {
  echo "* Downloading the latest Cloudera Manager installer ..."
  wget -q "http://archive.cloudera.com/cm4/installer/latest/cloudera-manager-installer.bin" -O /root/CDH/cloudera-manager-installer.bin && chmod +x /root/CDH/cloudera-manager-installer.bin
  
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
#set -x
START_SCM_AGENT=
SERVER_DB=
JDK_VER=

stopServices
for target in "$@"; do
  case "$target" in
  --jdk*)
    installJava $target
    shift
    ;;
  --ver*)
    useRpm $target
    yum install -y cloudera-manager-daemons cloudera-manager-server cloudera-manager-agent
    shift
    ;;
  --psql)
    server_db=${server_db:-cloudera-manager-server-db}
    yum install -y $server_db
    shift
    ;;
  --mysql)
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
  *)
    echo $target
    usage
    exit 1
  esac
done
startServices

exit 0
