#!/usr/bin/env bash

#echo "Install Maven 3.1.1"
#curl -L http://mirror.gopotato.co.uk/apache/maven/maven-3/3.1.1/binaries/apache-maven-3.1.1-bin.tar.gz -o apache-maven-3.1.1-bin.tar.gz
#tar xzvf apache-maven-3.1.1-bin.tar.gz -C /usr/local/ && ln -s /usr/local/apache-maven-3.1.1 /usr/local/maven

echo "Install Maven 2.2.1"
curl -L http://www.mirrorservice.org/sites/ftp.apache.org/maven/maven-2/2.2.1/binaries/apache-maven-2.2.1-bin.tar.gz -o apache-maven-2.2.1-bin.tar.gz
tar xzvf apache-maven-2.2.1-bin.tar.gz -C /usr/local/ && ln -s /usr/local/apache-maven-2.2.1/ /usr/local/maven

echo "Install Ant 1.9.2"
curl -L http://apache.mirror.anlx.net//ant/binaries/apache-ant-1.9.2-bin.tar.gz -o apache-ant-1.9.2-bin.tar.gz
tar xzvf apache-ant-1.9.2-bin.tar.gz -C /usr/local/ && ln -s /usr/local/apache-ant-1.9.2/ /usr/local/ant

echo "Modify .bash_profile"
sed -i "s/PATH=/#PATH=/g" ~/.bash_profile
sed -i "s/export PATH/#export PATH/g" ~/.bash_profile

cat << EOF >> ~/.bash_profile
JAVA_HOME=/usr/java/default
ANT_HOME=/usr/local/ant
M2_HOME=/usr/local/maven
PATH=\${JAVA_HOME}/bin:\${M2_HOME}/bin:\${ANT_HOME}/bin:\${PATH}:\${HOME}/bin
export PATH M2_HOME ANT_HOME JAVA_HOME
EOF
