#!/usr/bin/env bash

if [ $# -lt 1 ]; then
  echo "usage: $0 [hosts list]" 1>&2
  exit 1
fi
HOSTSLIST=$1
IPADDR=$(ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')

if [ -a $HOSTSLIST ]; then
 for IP in $(cat $HOSTSLIST | grep -v $IPADDR); do ssh root@$IP "grep $(hostname -d) /etc/hosts" >> /etc/hosts; done
 for IP in $(cat $HOSTSLIST | grep -v $IPADDR); do scp /etc/hosts root@$IP:/etc/hosts; done
fi
