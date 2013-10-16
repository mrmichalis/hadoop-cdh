#!/usr/bin/env bash
echo "* Downloading and Installing Oracle Java SDK 6u45 from Oracle ..."
#32-bit http://download.oracle.com/otn/java/jdk/6u45-b06/jdk-6u45-linux-i586-rpm.bin
#64-bit http://download.oracle.com/otn-pub/java/jdk/6u45-b06/jdk-6u45-linux-x64-rpm.bin
JAVA_URL="http://download.oracle.com/otn-pub/java/jdk/6u45-b06/jdk-6u45-linux-x64-rpm.bin"
JAVA_FILENAME=$(echo $JAVA_URL | cut -d/ -f8)
wget --no-check-certificate --no-cookies --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com" $JAVA_URL -O /root/CDH/$JAVA_FILENAME
chmod +x /root/CDH/$JAVA_FILENAME
touch answers && sh $JAVA_FILENAME < answers && /bin/rm answers
