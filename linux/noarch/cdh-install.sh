#!/usr/bin/env bash
command -v java >/dev/null 2>&1 || wget http://archive.cloudera.com/cm4/redhat/6/x86_64/cm/4/RPMS/x86_64/jdk-6u31-linux-amd64.rpm -O /root/CDH/jdk-6u31-linux-amd64.rpm && rpm -ivh /root/CDH/jdk-6u31-linux-amd64.rpm
wget http://archive.cloudera.com/cdh4/one-click-install/redhat/6/x86_64/cloudera-cdh-4-0.x86_64.rpm && yum -y --nogpgcheck localinstall cloudera-cdh-4-0.x86_64.rpm
rpm --import http://archive.cloudera.com/cdh4/redhat/6/x86_64/cdh/RPM-GPG-KEY-cloudera 

#http://www.cloudera.com/content/cloudera-content/cloudera-docs/CDH4/latest/CDH4-Quick-Start/cdh4qs_topic_3_2.html
yum -y install hadoop-0.20-conf-pseudo

#Step 2: Start HDFS
for x in `cd /etc/init.d ; ls hadoop-hdfs-*` ; do sudo service $x start ; done

sudo -u hdfs hadoop fs -mkdir /tmp 
sudo -u hdfs hadoop fs -chmod -R 1777 /tmp

sudo -u hdfs hadoop fs -mkdir -p /var/lib/hadoop-hdfs/cache/mapred/mapred/staging
sudo -u hdfs hadoop fs -chmod 1777 /var/lib/hadoop-hdfs/cache/mapred/mapred/staging
sudo -u hdfs hadoop fs -chown -R mapred /var/lib/hadoop-hdfs/cache/mapred
sudo -u hdfs hadoop fs -mkdir /user/hdfs 
sudo -u hdfs hadoop fs -chown hdfs /user/hdfs

sudo -u hdfs hadoop fs -ls -R /

#Step 6: Start MapReduce
for x in `cd /etc/init.d ; ls hadoop-0.20-mapreduce-*` ; do sudo service $x start ; done

sudo -u hdfs hadoop jar /usr/lib/hadoop-0.20-mapreduce/hadoop-examples.jar pi 10 10


"use_embedded_db"

mysql -u root -e "CREATE DATABASE IF NOT EXISTS cloudera_scm DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
mysql -u root -e "GRANT ALL ON *.* TO 'cloudera_scm'@'localhost' IDENTIFIED BY 'cloudera_scm' WITH GRANT OPTION;"
mysql -u root -e "GRANT ALL ON *.* TO '$service'@'$(hostname -f)' IDENTIFIED BY 'password' WITH GRANT OPTION;"
mysql -u root -e "GRANT ALL ON *.* TO '$service'@'%.lunix.co' IDENTIFIED BY 'password' WITH GRANT OPTION;"
mysql -u root -e "GRANT ALL ON *.* TO '$service'@'%' IDENTIFIED BY 'password' WITH GRANT OPTION;"