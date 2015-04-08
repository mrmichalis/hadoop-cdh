curl -X PUT -H 'Content-Type:application/json' -u admin:admin -d '{
"items" : [
  {
    "name" : "SESSION_TIMEOUT",
    "value" : "359999999999996416"
  },{
      "name" : "SECURITY_REALM",
      "value" : "LUNIX.LAN"
  }
]
}' http://$(hostname -f):7180/api/v4/cm/config

# Description: "Allows Cloudera to collect usage data, including the use of Google Analytics."
curl -X PUT -H 'Content-Type:application/json' -u admin:admin -d '{
  "items" : [ {
      "name" : "ALLOW_USAGE_DATA",
      "value" : "false"
  } ]
}' http://$(hostname -f):7180/api/v4/cm/config

# Description: "LDAP Example"
curl -X PUT -H 'Content-Type:application/json' -u admin:admin -d '{
  "items" : [ {
      "name" : "AUTH_BACKEND_ORDER",
      "value" : "DB_THEN_LDAP"
    }, {
      "name" : "LDAP_BIND_DN",
      "value" : "cn=Administrator,cn=users,dc=lunix,dc=lan"
    }, {
      "name" : "LDAP_BIND_PW",
      "value" : "password"
    }, {
      "name" : "LDAP_GROUP_SEARCH_FILTER",
      "value" : "memberOf=CN=Domain Admins,CN=Users,DC=LUNIX,DC=LAN"
    }, {
      "name" : "LDAP_URL",
      "value" : "ldap://AD-HOST:389"
    }, {
      "name" : "LDAP_USER_GROUPS",
      "value" : "Users,Domain Admins"
    }, {
      "name" : "LDAP_USER_SEARCH_BASE",
      "value" : "CN=Users,DC=LUNIX,DC=LAN"
    }, {
      "name" : "LDAP_USER_SEARCH_FILTER",
      "value" : "sAMAccountName={0}"
    }, {
      "name" : "NT_DOMAIN",
      "value" : "LUNIX.LAN"
    } ]
}' http://$(hostname -f):7180/api/v4/cm/config

curl -X PUT -H 'Content-Type:application/json' -u admin:admin -d '{
"items" : [
  {
    "name" : "firehose_activity_purge_duration_hours",
    "value" : "24"
  },
  {
    "name" : "firehose_attempt_purge_duration_hours",
    "value" : "24"
  },
  {
    "name" : "timeseries_expiration_hours",
    "value" : "24"
  }
]
}' http://$(hostname -f):7180/api/v4/cm/service/roleConfigGroups/mgmt1-ACTIVITYMONITOR-BASE/config

curl -X PUT -H 'Content-Type:application/json' -u admin:admin -d '{
"items" : [
  {
    "name" : "timeseries_expiration_hours",
    "value" : "24"
  }
]
}' http://$(hostname -f):7180/api/v4/cm/service/roleConfigGroups/mgmt1-SERVICEMONITOR-BASE/config


curl -X PUT -H 'Content-Type:application/json' -u admin:admin -d '{
"items" : [
  {
    "name" : "timeseries_expiration_hours",
    "value" : "24"
  }
]
}' http://$(hostname -f):7180/api/v4/cm/service/roleConfigGroups/mgmt1-HOSTMONITOR-BASE/config


curl -X POST -u admin:admin http://$(hostname -f):7180/api/v4/cm/service/commands/restart

# curl -u admin:admin -X POST http://$(hostname -f):7180/api/v5/clusters/Cluster%201%20-%20CDH4/services/mapreduce1/roleCommands/refresh -H "Content-Type:application/json" -d '{"items":["mapreduce1-JOBTRACKER-6f46bf2f3bd625ffe9b041c0f725fbf4"]}'
# curl -u admin:admin -X POST http://$(hostname -f):7180/api/v5/clusters/Cluster%201%20-%20CDH4/services/hdfs1/config -H "Content-Type:application/json" -d '{ "items" : [ {"name" : "dfs_replication","value" : "1"} ]}'

# API Change Monitoring settings "Host Clock Offset Thresholds"# # for host with hostid 7eac56ed-4be0-4d88-b5b8-263438fa9ce4
# curl -u admin:admin -X PUT -H "Content-Type:application/json" -d '{
#   "items" : [ {
#   "name" : "host_clock_offset_thresholds",
#   "value" : "{\"warning\":\"10000\",\"critical\":\"200000\"}"
#   } ]
# }' http://$(hostname -f):7180/api/v8/hosts/7eac56ed-4be0-4d88-b5b8-263438fa9ce4/config
# #python
# api = ApiResource("cm-host")
# host = api.get_host("7eac56ed-4be0-4d88-b5b8-263438fa9ce4")
# host.update_config({"host_clock_offset_thresholds":"{\"warning\":\"60000\",\"critical\":\"20000\"}"})

# # for each individual host on your cluster CM API
# for h in api.get_all_hosts():
#   h.update_config({"host_clock_offset_thresholds":"{\"warning\":\"10000\",\"critical\":\"200000\"}"})

# # for host in listed in CM
# curl -X PUT -H 'Content-Type:application/json' -u admin:admin -d '{
#   "items" : [ {
#     "name" : "host_clock_offset_thresholds",
#     "value" : "{\"warning\":\"60000\",\"critical\":\"100000\"}"
#   } ]
# }' http://$(hostname -f):7180/api/v8/cm/allHosts/config
# # python
# cm = api.get_cloudera_manager()
# cm.update_all_hosts_config({"host_clock_offset_thresholds":"{\"warning\":\"60000\",\"critical\":\"20000\"}"})

