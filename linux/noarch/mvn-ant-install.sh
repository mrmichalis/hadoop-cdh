#!/usr/bin/env bash

#echo "Install Maven 3.1.1"
#curl -L http://apache.mirror.anlx.net/maven/maven-3/3.1.1/binaries/apache-maven-3.1.1-bin.tar.gz -o apache-maven-3.1.1-bin.tar.gz
#tar xzvf apache-maven-3.1.1-bin.tar.gz -C /usr/local/ && ln -s /usr/local/apache-maven-3.1.1 /usr/local/maven

echo "Install Maven 2.2.1"
curl -L http://apache.mirror.anlx.net/maven/maven-2/2.2.1/binaries/apache-maven-2.2.1-bin.tar.gz -o apache-maven-2.2.1-bin.tar.gz
tar xzvf apache-maven-2.2.1-bin.tar.gz -C /usr/local/ && ln -s /usr/local/apache-maven-2.2.1/ /usr/local/maven

echo "Install Ant 1.9.3"
curl -L http://apache.mirror.anlx.net/ant/binaries/apache-ant-1.9.3-bin.tar.gz -o apache-ant-1.9.3-bin.tar.gz
tar xzvf apache-ant-1.9.3-bin.tar.gz -C /usr/local/ && ln -s /usr/local/apache-ant-1.9.3/ /usr/local/ant

echo "* Set ANT_HOME in /etc/profile.d/ant.sh ..."
echo 'export ANT_HOME=/usr/local/ant' > /etc/profile.d/ant.sh
echo 'export PATH=$ANT_HOME/bin:$PATH' >> /etc/profile.d/ant.sh

echo "* Set MVN_HOME in /etc/profile.d/mvn.sh ..."
echo 'export MVN_HOME=/usr/local/maven' > /etc/profile.d/mvn.sh
echo 'export PATH=$MVN_HOME/bin:$PATH' >> /etc/profile.d/mvn.sh