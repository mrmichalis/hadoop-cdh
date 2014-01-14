# https://github.com/mrmichalis/vagrant-puppet-mysql/blob/b7f57d3bc47ab3187a0faeb658f56660fbb2c117/manifests/init.pp
# http://bitfieldconsulting.com/puppet-and-mysql-create-databases-and-users
include mysql::server
class mysql::server {
  $bin = '/usr/bin:/usr/sbin'

  package { "mysql-server": ensure => installed }
  package { "mysql": ensure => installed }

  service { "mysqld":
    enable => true,
    ensure => running,
    require => Package["mysql-server"],
  }
  # Set the root password.
  # exec { 'mysql::set_root_password':
    # unless  => "mysqladmin -uroot status",
    # command => "mysqladmin -uroot password ${root_password}",
    # path    => $bin,
    # require => Service['mysqld'],
  # } 
}

define mysql::db::create ($dbname = $title) {
  exec { "mysql::db::create_${dbname}":
    command => "mysql -uroot -e \"CREATE DATABASE IF NOT EXISTS ${dbname} DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci\"",
    path    => $mysql::server::bin,
    require => Service['mysqld'],
  }
}

define mysql::user::grant ($user = $title, $host, $password, $database, $table = '*', $privileges = 'ALL PRIVILEGES') {
  exec { "mysql::user::grant_${user}_${host}_${database}_${table}_${privileges}":
    command => "mysql -uroot -p${root_password} -e \"GRANT ${privileges} ON ${database}.${table} TO '${user}'@'${host}' IDENTIFIED BY '${password}'; FLUSH PRIVILEGES;\"",
    path    => $mysql::server::bin,
    require => Service['mysqld'],
  }
}

mysql::db::create { ['scm','hue','amon','smon','rman','hmon','nav','hive','temp']: }
mysql::user::grant { 'scm_all_privileges':
  user     => 'scm',
  host     => 'localhost',
  password => 'password',
  database => '*',
}
mysql::user::grant { 'hue_all_privileges':
  user     => 'hue',
  host     => 'localhost',
  password => 'password',
  database => '*',
}
mysql::user::grant { 'amon_all_privileges':
  user     => 'amon',
  host     => 'localhost',
  password => 'password',
  database => '*',
}
mysql::user::grant { 'smon_all_privileges':
  user     => 'smon',
  host     => 'localhost',
  password => 'password',
  database => '*',
}
mysql::user::grant { 'rman_all_privileges':
  user     => 'rman',
  host     => 'localhost',
  password => 'password',
  database => '*',
}
mysql::user::grant { 'hmon_all_privileges':
  user     => 'hmon',
  host     => 'localhost',
  password => 'password',
  database => '*',
}
mysql::user::grant { 'scm_all_privileges_lunix_lan':
  user     => 'scm',
  host     => $fqdn,
  password => 'password',
  database => '*',
}
mysql::user::grant { 'hue_all_privileges_lunix_lan':
  user     => 'hue',
  host     => $fqdn,
  password => 'password',
  database => '*',
}
mysql::user::grant { 'amon_all_privileges_lunix_lan':
  user     => 'amon',
  host     => $fqdn,
  password => 'password',
  database => '*',
}
mysql::user::grant { 'smon_all_privileges_lunix_lan':
  user     => 'smon',
  host     => $fqdn,
  password => 'password',
  database => '*',
}
mysql::user::grant { 'rman_all_privileges_lunix_lan':
  user     => 'rman',
  host     => $fqdn,
  password => 'password',
  database => '*',
}
mysql::user::grant { 'hmon_all_privileges_lunix_lan':
  user     => 'hmon',
  host     => $fqdn,
  password => 'password',
  database => '*',
}
mysql::user::grant { 'nav_all_privileges_lunix_lan':
  user     => 'nav',
  host     => $fqdn,
  password => 'password',
  database => '*',
}
mysql::user::grant { 'hive_all_privileges_lunix_lan':
  user     => 'hive',
  host     => $fqdn,
  password => 'password',
  database => '*',
}
mysql::user::grant { 'root_all_privileges_hosts':
  user     => 'root',
  host     => '%',
  password => 'password',
  database => '*',
}
mysql::user::grant { 'root_all_privileges_archive_cloudera_com':
  user     => 'root',
  host     => 'archive.cloudera.com',
  password => 'password',
  database => '*',
}
