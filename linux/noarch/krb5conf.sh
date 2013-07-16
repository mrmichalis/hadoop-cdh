#!/usr/bin/env bash
#http://www.cloudera.com/content/cloudera-content/cloudera-docs/CDH4/latest/CDH4-Security-Guide/cdh4sg_topic_3.html
#http://www.cloudera.com/content/cloudera-content/cloudera-docs/CM4Ent/latest/Cloudera-Manager-Managing-Clusters/cmmc_hadoop_security.html

if [ $# -lt 1 ]; then
    echo "usage: $0 [REALM]" 1>&2
    exit 1
fi

#pre-req
yum install krb5-server krb5-workstation krb5-libs -y
echo "* Downloading Java Cryptography Extension (JCE) ..."
wget --no-check-certificate --no-cookies --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com" http://download.oracle.com/otn-pub/java/jce_policy/6/jce_policy-6.zip -O /root/CDH/jce_policy-6.zip
[[ -d "/usr/java/default/jre/lib/security/" ]] && unzip -oj /root/CDH/jce_policy-6.zip -d /usr/java/default/jre/lib/security/

REALM=${1^^}
FQDN=$(hostname -f)
(
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
cp /etc/krb5.conf /etc/krb5.conf.backup.$TIMESTAMP
cp /var/kerberos/krb5kdc/kadm5.acl /var/kerberos/krb5kdc/kadm5.acl.backup.$TIMESTAMP
cp /var/kerberos/krb5kdc/kdc.conf /var/kerberos/krb5kdc/kdc.conf.backup.$TIMESTAMP
sed -n 'H;${x;s/  supported_enctypes = .*\n/  max_life = 1d\n  max_renewable_life = 7d\n&/;p;}' /var/kerberos/krb5kdc/kdc.conf.backup.$TIMESTAMP > /var/kerberos/krb5kdc/kdc.conf
sed -n 'H;${x;s/ ticket_lifetime = .*\n/ max_life = 1d\n max_renewable_life = 7d\n&/;p;}' /etc/krb5.conf.backup.$TIMESTAMP > /etc/krb5.conf
sed -i "s/kerberos.example.com/$FQDN/g" /etc/krb5.conf
sed -i "s/example.com/$FQDN/g" /etc/krb5.conf
sed -i "s/EXAMPLE.COM/$REALM/g" /etc/krb5.conf
sed -i "s/EXAMPLE.COM/$REALM/g" /var/kerberos/krb5kdc/kadm5.acl
sed -i "s/EXAMPLE.COM/$REALM/g" /var/kerberos/krb5kdc/kdc.conf
)
 
(
echo "Creating the KDC with password: cloudera"
kdb5_util -P "cloudera" create -s

chkconfig krb5kdc on
chkconfig kadmin on
service krb5kdc start
service kadmin start
sleep 10 
kadmin.local -q "addprinc root/admin"
kadmin.local -q "addprinc hdfs@$REALM"

echo "Generating cloudera-scm/admin principal for Cloudera Manager"
kadmin.local >/dev/null <<EOF
addprinc -randkey cloudera-scm/admin
xst -k cmf.keytab cloudera-scm/admin
EOF
 
echo "cloudera-scm/admin@LUNIX.CO" > /etc/cloudera-scm-server/cmf.principal
mv cmf.keytab /etc/cloudera-scm-server/cmf.keytab
chown cloudera-scm:cloudera-scm /etc/cloudera-scm-server/cmf.keytab /etc/cloudera-scm-server/cmf.principal
chmod 0600 /etc/cloudera-scm-server/cmf.keytab /etc/cloudera-scm-server/cmf.principal
)

dd if=/dev/urandom of=/etc/hadoop/hadoop-http-auth-signature-secret bs=1024 count=1
# Additional Kerberos post-conf
# adduser mko -G hdfs,hadoop -u 10001 -d /home/mko -m
# hadoop fs -mkdir /user/mko
# hadoop fs -chown mko:supergroup /user/mko
# curl -v -u mko:xxxxx --negotiate http://$(hostname -f):50070/dfshealth.jsp
# userdel -f -r mko 
# usermod -a -G root mko
