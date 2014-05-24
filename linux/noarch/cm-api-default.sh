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

