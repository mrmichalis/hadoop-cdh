curl -X PUT -H 'Content-Type:application/json' -u admin:admin -d '{
"items" : [
  {
    "name" : "SESSION_TIMEOUT",
    "value" : "359999999999996416"
  }
]
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