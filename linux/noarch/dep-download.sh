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
