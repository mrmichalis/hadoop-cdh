#!/usr/bin/env bash
function usage() {
  echo "usage: $0 -a=[HOST_IP_ADDRESS] or -f=[HOSTLIST_FILE]" 1>&2
  echo " "
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

function configure {
  HOST=$1
  IPADDR=$(ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')
  echo "Connecting to $HOST..."
  ssh root@$HOST "grep $(hostname -d) /etc/hosts" >> /etc/hosts
  scp /etc/hosts root@$HOST:/etc/hosts
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
