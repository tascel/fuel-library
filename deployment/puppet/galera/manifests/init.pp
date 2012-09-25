# 
# wget https://launchpad.net/codership-mysql/5.5/5.5.23-23.6/+download/mysql-server-wsrep-5.5.23-23.6-amd64.deb
# wget https://launchpad.net/galera/2.x/23.2.1/+download/galera-23.2.1-amd64.deb
# aptitude install mysql-client libdbd-mysql-perl libdbi-perl
# aptitude install libssl0.9.8
# dpkg -i mysql-server-wsrep-5.5.23-23.6-amd64.deb 
# dpkg -i galera-23.2.1-amd64.deb 
# vi /etc/mysql/conf.d/wsrep.cnf 
# /etc/init.d/mysql start
# 
class galera($cluster_name, $master_ip = false, $node_address = $ipaddress_eth0) {

  include galera::params

  $mysql_user         = $::galera::params::mysql_user
  $mysql_password     = $::galera::params::mysql_password
  $libgalera_prefix   = $::galera::params::libgalera_prefix

  # $mysql_wsrep_prefix = 'https://launchpad.net/codership-mysql/5.5/5.5.23-23.6/+download'
  # $galera_prefix      = 'https://launchpad.net/galera/2.x/23.2.1/+download'
  $mysql_wsrep_prefix = 'http://download.mirantis.com/epel-fuel/x86_64'
  $galera_prefix      = $mysql_wsrep_prefix

  case $::osfamily {
    'RedHat': {
      $pkg_prefix  = $mysql_wsrep_prefix
      $pkg_version = '5.5.27-1.el6.x86_64'

      if !defined(Class['selinux']) {
        class { 'selinux' :
          mode   => 'disabled',
          before => Package['MySQL-server']
        }
      }

      # install dependencies
      Galera::Pkg_add {
        pkg_prefix  => $pkg_prefix,
        pkg_version => $pkg_version,
        before      => Package['MySQL-server']
      }

      galera::pkg_add { 'MySQL-client': }
      galera::pkg_add { 'MySQL-shared': }

      file { '/etc/my.cnf' :
        ensure  => present,
        source  => 'puppet:///modules/galera/my.cnf',
        before  => Service['mysql-galera']
      }

      package { 'wget' :
        ensure => present,
        before => Exec['download-wsrep', 'download-galera']
      }

      package { 'perl' :
        ensure => present,
        before => Galera::Pkg_add['MySQL-client']
      }
    }
    'Debian': {
      package { "mysql-client" :
        ensure => present,
        before => Package["MySQL-server"]
      }
    }
  }

  service { "mysql-galera" :
    name        => "mysql",
    ensure      => "running",
    require     => [Package["MySQL-server", "galera"], File["/etc/mysql/conf.d/wsrep.cnf"]],
    subscribe   => File["/etc/mysql/conf.d/wsrep.cnf"],
    hasrestart  => true,
    hasstatus   => true,
  }

  package { [$::galera::params::libssl_package, $::galera::params::libaio_package] :
    ensure      => present,
    before      => Package["galera", "MySQL-server"]
  }

  package { "MySQL-server" :
    ensure      => present,
    provider    => $::galera::params::pkg_provider,
    source      => "/tmp/${::galera::params::mysql_server_package}",
    require     => [Exec["download-wsrep"], File["/etc/mysql/conf.d/wsrep.cnf"]]
  }

  exec { "download-wsrep" :
    command     => "/usr/bin/wget -P/tmp ${mysql_wsrep_prefix}/${::galera::params::mysql_server_package}",
    creates     => "/tmp/${::galera::params::mysql_server_package}"
  }

  package { "galera" :
    ensure      => present,
    provider    => $::galera::params::pkg_provider,
    source      => "/tmp/${::galera::params::galera_package}",
    require     => Exec["download-galera"],
  }

  exec { "download-galera" :
    command     => "/usr/bin/wget -P/tmp ${galera_prefix}/${::galera::params::galera_package}",
    creates     => "/tmp/${::galera::params::galera_package}",
  }

  file { ["/etc/mysql", "/etc/mysql/conf.d" ] :
    ensure => directory,
    before => File["/etc/mysql/conf.d/wsrep.cnf"]
  }

  file { "/etc/mysql/conf.d/wsrep.cnf" :
    ensure      => present,
    content     => template("galera/wsrep.cnf.erb"),
    ## require     => Package["galera"],
  }

  exec { "set-mysql-password" :
    unless      => "/usr/bin/mysql -u${mysql_user} -p${mysql_password}",
    command     => "/usr/bin/mysql -uroot -e \
                   \"set wsrep_on='off';\
                   delete from mysql.user where user='';\
                   grant all on *.* to '${mysql_user}'@'%' identified by '${mysql_password}';\
                   grant usage on *.* to 'cluster_watcher'@'%';\
                   flush privileges;\"",
    require     => Service["mysql-galera"],
    subscribe   => Service["mysql-galera"],
    refreshonly => true,
  }

  exec { "wait-for-synced-state" :
    require     => Exec["set-mysql-password"],
    logoutput   => true,
    command     => "/usr/bin/mysql -Nbe \"show status like 'wsrep_local_state_comment'\" | /bin/grep -q Synced",
    try_sleep   => 5,
    tries       => 6,
  }

}
