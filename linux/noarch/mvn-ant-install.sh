#!/usr/bin/env bash

MVN_VER=3.2.1
ANT_VER=1.9.4

#echo "Install Maven 2.2.1"
#curl -L http://apache.mirror.anlx.net/maven/maven-2/2.2.1/binaries/apache-maven-2.2.1-bin.tar.gz -o apache-maven-2.2.1-bin.tar.gz
#tar xzvf apache-maven-2.2.1-bin.tar.gz -C /usr/local/ && ln -s /usr/local/apache-maven-2.2.1/ /usr/local/maven

echo "Install Maven $MVN_VER"
curl -L http://apache.mirror.anlx.net/maven/maven-$(echo $MVN_VER | cut -d'.' -f 1)/$MVN_VER/binaries/apache-maven-$MVN_VER-bin.tar.gz -o apache-maven-$MVN_VER-bin.tar.gz
tar xzvf apache-maven-$MVN_VER-bin.tar.gz -C /usr/local/ && ln -s /usr/local/apache-maven-$MVN_VER /usr/local/maven

echo "Install Ant $ANT_VER"
curl -L http://apache.mirror.anlx.net/ant/binaries/apache-ant-$ANT_VER-bin.tar.gz -o apache-ant-$ANT_VER-bin.tar.gz
tar xzvf apache-ant-$ANT_VER-bin.tar.gz -C /usr/local/ && ln -s /usr/local/apache-ant-$ANT_VER/ /usr/local/ant

echo "* Set ANT_HOME in /etc/profile.d/ant.sh ..."
echo 'export ANT_HOME=/usr/local/ant' > /etc/profile.d/ant.sh
echo 'export PATH=$ANT_HOME/bin:$PATH' >> /etc/profile.d/ant.sh
. /etc/profile.d/ant.sh

echo "* Set MVN_HOME in /etc/profile.d/mvn.sh ..."
echo 'export MVN_HOME=/usr/local/maven' > /etc/profile.d/mvn.sh
echo 'export PATH=$MVN_HOME/bin:$PATH' >> /etc/profile.d/mvn.sh
. /etc/profile.d/mvn.sh