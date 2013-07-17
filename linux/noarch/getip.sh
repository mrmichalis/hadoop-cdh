#!/usr/bin/env bash
usage() {
  echo "usage: $0 -a=[HOST_IP_ADDRESS] or -f=[HOSTLIST_FILE]" 1>&2
  echo "Options" 1>&2
  echo " "
}

if [ $# -lt 1 ]; then
  echo "usage: $0 [hosts list]" 1>&2
  exit 1
fi

IPADDR=$(ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')
function configure {
  for IP in $($1 | grep -v $IPADDR); do ssh root@$IP "grep $(hostname -d) /etc/hosts" >> /etc/hosts; done
  for IP in $($1 | grep -v $IPADDR); do scp /etc/hosts root@$IP:/etc/hosts; done
}

for target in "$@"; do
  case "$target" in
  -f*)
    HOSTSLIST=$(echo $target | sed -e 's/^[^=]*=//g')    
    for h in $(cat $HOSTSLIST); do    
      configure $h
    done
    shift
    ;;
  -a*)
    HOSTSLIST=$(echo $target | sed -e 's/^[^=]*=//g')    
    configure $HOSTSLIST
    shift
    ;;
  *)
    usage
    exit 1
  esac
done

exit 0
