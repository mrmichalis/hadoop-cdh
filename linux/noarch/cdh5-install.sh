#!/usr/bin/env bash
export JDK_7="oracle-j2sdk1.7-1.7.0+update67-1.x86_64.rpm"
command -v java >/dev/null 2>&1 || wget http://archive.cloudera.com/cm5/redhat/6/x86_64/cm/5/RPMS/x86_64/$JDK_7 -O /root/CDH/$JDK_7 && rpm -ivh /root/CDH/$JDK_7
sudo yum --nogpgcheck localinstall http://archive.cloudera.com/cdh5/one-click-install/redhat/6/x86_64/cloudera-cdh-5-0.x86_64.rpm -y
rpm --import http://archive.cloudera.com/cdh5/redhat/6/x86_64/cdh/RPM-GPG-KEY-cloudera

#http://www.cloudera.com/content/cloudera/en/documentation/cdh5/v5-1-x/CDH5-Quick-Start/cdh5qs_yarn_pseudo.html
yum clean all
yum -y install hadoop-conf-pseudo

#Step 1: Format the NameNode
sudo -u hdfs hdfs namenode -format

#Step 2: Start HDFS
for x in `cd /etc/init.d ; ls hadoop-hdfs-*` ; do sudo service $x start ; done
#for x in `cd /etc/init.d ; ls hadoop-hdfs-*` ; do sudo service $x restart ; done

sudo -u hdfs hadoop fs -mkdir -p /tmp/hadoop-yarn/staging/history/done_intermediate
sudo -u hdfs hadoop fs -chown -R mapred:mapred /tmp/hadoop-yarn/staging 
sudo -u hdfs hadoop fs -chmod -R 1777 /tmp 
sudo -u hdfs hadoop fs -mkdir -p /var/log/hadoop-yarn
sudo -u hdfs hadoop fs -chown yarn:mapred /var/log/hadoop-yarn

sudo -u hdfs hadoop fs -ls -R /

#Step 5: Start YARN
sudo service hadoop-yarn-resourcemanager start 
sudo service hadoop-yarn-nodemanager start 
sudo service hadoop-mapreduce-historyserver start

#Step 6: Create User Directories
groupadd supergroup -g 10001
useradd mko -G supergroup,hdfs,hadoop,root -u 10002 -d /home/mko -m
sudo -u hdfs hadoop fs -mkdir /user/mko
sudo -u hdfs hadoop fs -chown mko:supergroup /user/mko
mkdir -p /home/hdfs && chown -R hdfs:hdfs /home/hdfs


sudo -u hdfs hadoop jar /usr/lib/hadoop-0.20-mapreduce/hadoop-examples.jar pi 10 10