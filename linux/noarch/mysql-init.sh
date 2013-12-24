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

chkconfig mysqld on
service mysqld start
sleep 10

for service in scm hue amon smon rman hmon nav hive temp; do
  mysql -u root -e "CREATE DATABASE IF NOT EXISTS $service DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
  mysql -u root -e "GRANT ALL ON *.* TO '$service'@'localhost' IDENTIFIED BY 'password' WITH GRANT OPTION;"
  mysql -u root -e "GRANT ALL ON *.* TO '$service'@'$(hostname -f)' IDENTIFIED BY 'password' WITH GRANT OPTION;"
  mysql -u root -e "GRANT ALL ON *.* TO '$service'@'%' IDENTIFIED BY 'password' WITH GRANT OPTION;"
  mysql -u root -e "GRANT ALL ON *.* TO '$service'@'%.lunix.lan' IDENTIFIED BY 'password' WITH GRANT OPTION;"
  mysql -u root -e "GRANT ALL ON *.* TO 'root'@'archive.cloudera.com' IDENTIFIED BY 'password' WITH GRANT OPTION;"
done
mysql -u root -e 'show databases;'

# http://www.cloudera.com/content/cloudera-content/cloudera-docs/CM4Ent/latest/Cloudera-Manager-Installation-Guide/cmig_install_path_B.html
# /usr/share/cmf/schema/scm_prepare_database.sh mysql -h localhost -u temp -ppassword --scm-host localhost scm scm password

  
