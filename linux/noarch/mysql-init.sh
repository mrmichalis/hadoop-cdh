#!/usr/bin/env bash
service mysqld start
yum install -y expect
expect -c " 
set timeout 5
spawn mysql_secure_installation
 
expect \"Enter current password for root (enter for none):\"
send \"\r\"
expect \"Set root password?\"
send \"n\r\"
expect \"Remove anonymous users?\"
send \"n\r\"
expect \"Disallow root login remotely?\"
send \"n\r\"
expect \"Remove test database and access to it?\"
send \"n\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
" 
yum remove -y expect

curl -L http://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.25.tar.gz/from/http://cdn.mysql.com/ | tar xzv
[[ -d "/usr/share/java/" && ! -e "/usr/share/java/mysql-connector-java.jar" ]] && cp /root/CDH/mysql-connector-java-5.1.25/mysql-connector-java-5.1.25-bin.jar /usr/share/java/mysql-connector-java.jar
[[ -d "/opt/cloudera/parcels/CDH/lib/hive/lib/" && ! -e "/opt/cloudera/parcels/CDH/lib/hive/lib/mysql-connector-java.jar" ]] && ln -s /root/CDH/mysql-connector-java-5.1.25/mysql-connector-java-5.1.25-bin.jar 

chkconfig mysqld on
service mysqld start
sleep 10

for service in amon smon rman hmon nav hive; do
  mysql -u root -e "create database $service default character set utf8 collate utf8_general_ci;"
  mysql -u root -e "grant all on $service.* TO '$service'@'localhost' IDENTIFIED BY 'password';"
  mysql -u root -e "grant all on $service.* TO '$service'@'$(hostname -f)' IDENTIFIED BY 'password';"
  mysql -u root -e "grant all on $service.* TO '$service'@'%.lunix.co' IDENTIFIED BY 'password';"  
done
mysql -u root -e 'show databases;'
