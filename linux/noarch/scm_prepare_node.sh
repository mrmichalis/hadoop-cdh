#!/bin/bash
# Copyright (c) 2011-2012 Cloudera, Inc. All rights reserved.

# Print a usage statement.
usage()
{
cat << EOF
usage: $0 [options]

Prepares this node for use by Cloudera Service and Configuration Manager (SCM):
o Installs necessary SCM agent packages.
o Installs necessary CDH packages.
o Configures the SCM agent.
o Starts the SCM agent.

If an error is encountered, all changes will be reverted.

OPTIONS
   -h|--host          Hostname or IP address of the SCM server. Default is the
                      first word of the SSH_CLIENT environment variable, if set.
   -p|--packages      File containing list of packages, one per line. Default
                      policy is that package is installed if not already installed.
                      This can be modified by the 'never' and 'always' files below.
                      If package is prefixed with "[optional]", then will not complain
                      if the package is unavailable.
   -a|--always        File containing list of packages to always install, even if
                      they are already installed, one per line
   -x|--x86_64        File containing list of packages that must be explicitly
                      installed as x86_64 architecture, one per line.
      --skipImpala    Don't try and install Impala
      --skipSolr      Don't try and install Solr
      --serverVersion Server version to check Agent and Daemons packages against.
                      If not passed, all versions will be accepted.
      --serverBuild   Server build number to check Agent and Daemons packages against.
                      If not passed, all build numbers will be accepted.
      -?|--help       Show this message.
EOF
}

# Find an element in an array
# @param $1 mixed  Needle
# @param $2 array  Haystack
# @return  Success (0) if value exists, Failure (1) otherwise
in_array() {
    local hay needle=$1
    shift
    for hay; do
        [[ $hay == $needle ]] && return 0
    done
    return 1
}

# Close the logging file descriptor. Called from an EXIT trap.
fd_close()
{
    STATUS=$?
    echo closing logging file descriptor
    exec 3>&-
    exit $STATUS
}

# Open a file descriptor for logging as a duplicate of stdout.
fd_open()
{
    echo opening logging file descriptor
    exec 3>&1
}

# Emit some text prefixed with a special marker that will convey a state change
# to a listening SCM server.
mark()
{
    # Check if we should abort the installation and uninstall. This function is
    # invoked often enough that the installation will be aborted with
    # reasonably low latency.
    if [[ -z $ROLLBACK && -f $ABORT_FILE ]]; then
        echo "detected abort"
        rollback
    fi

    MARKER="###CLOUDERA_SCM###"
    echo $MARKER "$@"
}

# Evaluate a command and write its output (both stdout and stderr) to the
# logging fd, wrapped with helpful BEGIN and END markers) as well as to
# stdout. The latter is to be consumed by the function's caller.
#
# Note that the logging fd is closed during command evaluation; otherwise it
# will be inherited by any forked children who forget to close it. Since it is
# a pipe, this may block the script from exiting.
#
# Order is important; fd 3 must be closed before redirecting stderr to stdout.
action_get()
{
    local RETVAL

    echo BEGIN "$@" 1>&3
    eval "$@" 3>&- 2>&1 | tee >(cat 1>&3)

    # This retrieves the second to last element in the PIPESTATUS array, which
    # should be the exit status of the evaluated command.
    RETVAL=${PIPESTATUS[${#PIPESTATUS[@]}-2]}
    echo "END ($RETVAL)" 1>&3

    return $RETVAL
}

# Used in cases where the caller doesn't care about the output of action().
action()
{
    action_get $@ > /dev/null 2>&1
}

# If an exit status was failure, echo something and rollback. Otherwise,
# continue execution.
fail_or_continue()
{
    local RET=$1
    shift

    if [[ $RET -ne 0 ]]; then
        echo "$@", giving up
        # Do not call rollback directly, give the user time to investigate.
        wait_for_rollback $RET
    fi
}

# Remove an installed package (by name).
package_remove()
{
    local PACKAGE=$1
    case $PACKAGER in
        yum)
            action $SUDO yum -y erase $PACKAGE
            ;;
        zypper)
            # The --force-resolution option tells zypper that, while uninstalling
            # this package, it should uninstall all dependent packages. Without it,
            # zypper will exit without doing anything.
            #
            # It should be safe to use as it is on by default in interactive mode.
            action $SUDO zypper --gpg-auto-import-keys -n rm --force-resolution \
                $PACKAGE
            ;;
        apt-get)
            action $SUDO apt-get -y remove $PACKAGE
            ;;
        *)
            echo unknown packager $PACKAGER, exiting
            exit 1
            ;;
    esac
}

# Install a package (by file or by name) from file or from a remote repository.
package_install()
{
    local PACKAGE=$1
    case $PACKAGER in
        yum)
            if [[ -f $PACKAGE ]]; then
                # We run yum with GPG signature checking disabled because this is
                # either a stand-alone package that may not have been signed, or
                # a signed package for which we don't have the key.
                action $SUDO yum -y --nogpgcheck localinstall $PACKAGE
            else
                in_array $PACKAGE "${X86_64_PACKAGES[@]}"
                if [[ $? -eq 0 ]]; then
                    action $SUDO yum -y install $PACKAGE.x86_64
                else
                    action $SUDO yum -y install $PACKAGE
                fi
            fi
            ;;
        zypper)
            action $SUDO zypper --gpg-auto-import-keys -n in $PACKAGE
            ;;
        apt-get)
            # To ensure non-interactivity force a file conflict resolution
            # policy: Do the default action, and if none is present, preserve
            # the existing file.
            action $SUDO apt-get -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' -y install $PACKAGE
            ;;
        *)
            echo unknown packager $PACKAGER, exiting
            exit 1
            ;;
    esac
}

# Check if a package (by name) is available.
package_is_available()
{
    local PACKAGE=$1
    local RET=
    local VERSION_MATCH=
    local BUILD_MATCH=
    local OUTPUT=

    case $PACKAGER in
        yum)
            OUTPUT=$(action_get $SUDO yum info $PACKAGE)
            RET=$?
            # Only yum actually lets us match each separately
            echo "$OUTPUT" | grep -E "Version[[:space:]]*:[[:space:]]$SERVER_VERSION"
            VERSION_MATCH=$?
            echo "$OUTPUT" | grep -E "Release[[:space:]]*:[[:space:]].*$SERVER_BUILD"
            BUILD_MATCH=$?
            ;;
        zypper)
            action "$SUDO zypper --gpg-auto-import-keys -n se --match-exact -t package \
                $PACKAGE"
            RET=$?
            action "$SUDO zypper info $PACKAGE | grep -E 'Version:[[:space:]]$SERVER_VERSION-.*\.$SERVER_BUILD'"
            VERSION_MATCH=$?
            BUILD_MATCH=$VERSION_MATCH
            ;;
        apt-get)
            OUTPUT=$(action_get $SUDO apt-cache show $PACKAGE)
            RET=$?
            echo "$OUTPUT" | grep -E "Version:[[:space:]]$SERVER_VERSION-.*\.$SERVER_BUILD\~.*"
            VERSION_MATCH=$?
            BUILD_MATCH=$VERSION_MATCH
            ;;
        *)
            echo unknown packager $PACKAGER, exiting
            exit 1
            ;;
    esac

    # cloudera-manager packages are only considered available if their version
    # and build number match the server provided values.
    if [[ `echo $PACKAGE | grep -E '^cloudera-manager'` ]]; then
        if [[ $VERSION_MATCH -ne 0 || $BUILD_MATCH -ne 0 ]]; then
            echo "$PACKAGE must have Version=$SERVER_VERSION and Build=$SERVER_BUILD, exiting"
            exit 1
        fi
    fi

    return $RET
}

# Check if a package (by name) should be installed.
# Returns:
#   0: Package is not already installed and should be installed.
#   1: Package is already installed and should not be upgraded.
#   2: Package is already installed and should be upgraded.
package_should_be_installed()
{
    local PACKAGE=$1
    case $PACKAGER in
        yum)
            action $SUDO yum list installed $PACKAGE
            ;;
        zypper)
            action "$SUDO zypper --gpg-auto-import-keys -n se -i --match-exact -t package \
                $PACKAGE | grep -E '^i[[:space:]]*\|[[:space:]]*$PACKAGE'"
            ;;
        apt-get)
            action "$SUDO dpkg -l $PACKAGE | grep -E '^ii[[:space:]]*$PACKAGE[[:space:]]*'"
            ;;
        *)
            echo unknown packager $PACKAGER, exiting
            exit 1
            ;;
    esac

    if [[ $? -ne 0 ]]; then
        return 0
    fi

    action "echo $ALWAYS_INSTALL_PACKAGES | grep $PACKAGE"
    if [[ $? -eq 0 ]]; then
        return 2
    else
        return 1
    fi
}

# Is a package blacklisted?
package_is_blacklisted()
{
    local PACKAGE=$1
    for pkgIter in "${NEVER_INSTALL_PACKAGES[@]}"
    do
        if [ "$pkgIter" = "$PACKAGE" ]; then
            return 0
        fi
    done
    return 1
}

# Remove all repo files installed by this script.
remove_repo_files()
{
    mark REPO_REMOVE
    for FILE in $INSTALLED_REPO_FILES; do
        $SUDO rm -f "$FILE"
        # Restore backup (the most recently created backup)
        BACKUP="$(ls -1t "$FILE".~*~ | head -n 1)"
        if [[ "$BACKUP" != "" ]]; then
            $SUDO mv "$BACKUP" "$FILE"
            echo repository file $FILE restored
        else
            echo repository file $FILE removed
        fi
    done
}

# Remove all remote packages installed by this script.
remove_remote_packages()
{
    for PACKAGE in $INSTALLED_PACKAGES; do
        mark PACKAGE_REMOVE $PACKAGE
        package_remove $PACKAGE
        echo remote package $PACKAGE removed
    done
}

# Clean out the package manager's repository cache.
do_packager_clean_cache()
{
    case $PACKAGER in
        yum)
            action $SUDO $PACKAGER clean all
            # Manually remove stuff to work around a RHEL5/CentOS5 issue where
            # yum only cleans metadata for repos found in /etc/yum.repos.d.
            action $SUDO rm -Rf /var/cache/yum/*
            ;;
        zypper)
            # As of SLES11 SP1, zypper will remove all cached metadata, even
            # for repos that are no longer listed in /etc/zypp/repos.d.
            action $SUDO $PACKAGER clean --all
            ;;
        apt-get)
            # man apt-get(8) suggests that --list-cleanup (the default) will
            # automatically remove obsolete files from /var/lib/apt/lists. So
            # apt-get update after removing sources.list entries should suffice?
            action $SUDO $PACKAGER update
            ;;
        *)
            echo unknown packager $PACKAGER, exiting
            exit 1
            ;;
    esac
}

# Like the above, but make an actual state change.
packager_clean_cache()
{
    mark PACKAGER_CLEAN_CACHE

    do_packager_clean_cache
}

# Undo agent configuration changes made by this script.
unconfigure_agent()
{
    if [[ -n $AGENT_CONFIGURED ]]; then
        mark AGENT_UNCONFIGURE
        action "$SUDO sed -e 's/\(server_host=\).*/\1localhost/' -i $AGENT_CONFIG"
        if [[ $? -eq 0 ]]; then
            echo scm agent unconfigured
        fi
    fi
}

# Stop the SCM agent if it was started by this script.
stop_agent()
{
    if [[ -n $AGENT_STARTED ]]; then
        mark AGENT_STOP
        action $SUDO $SERVICE cloudera-scm-agent stop
        echo scm agent stopped
    fi
}

# Wait for rollback command or rollback timeout.
wait_for_rollback()
{
    echo "waiting for rollback request"
    mark WAITING_FOR_ROLLBACK
    while true;
    do
        if [[ -f $ROLLBACK_FILE || -f $ABORT_FILE ]]; then
            echo "detected rollback request"
            break
        fi
        sleep 1
    done
    rollback
}

# Undo the installation process in reverse order.
rollback()
{
    echo "rolling back installation"
    
    local RET=$1
    if [[ -z $RET ]]; then
        RET=1
    fi

    ROLLBACK=1
    mark ROLLBACK
    echo rollback started

    stop_agent
    unconfigure_agent
    remove_remote_packages
    remove_repo_files
    packager_clean_cache
    cloud_specific_unconfigure

    mark FAILURE
    echo rollback completed
    exit $RET
}

# Start the SCM agent.
start_agent()
{
    mark AGENT_START
    action "$SERVICE cloudera-scm-agent status | grep running"
    local RUNNING=$?

    if [[ $RUNNING -ne 0 ]]; then
        CMD=start
        AGENT_STARTED=1
    else
        CMD=restart
    fi
    action $SUDO $SERVICE cloudera-scm-agent $CMD
    EXIT_CODE=$?
    echo agent logs:
    for log in ${AGENT_LOGS[@]}
    do
        action_get "$SUDO tail -n 50 $log | sed 's/^/>>/'"
    done
    echo end of agent logs.
    fail_or_continue $EXIT_CODE scm agent could not be ${CMD}ed
    echo scm agent ${CMD}ed
}

# Configure the SCM agent to communicate with the SCM server.
configure_agent()
{
    mark AGENT_CONFIGURE

    # Since cloud hostnames/IPs change if you start/stop instances, we want agent
    # to use an ID that is independent of the hostname.
    if [[ -n $CLOUD_INSTANCE_ID ]]; then # if we're working with a cloud machine, basically
        action "$SUDO sed -e 's/\(CMF_AGENT_ARGS=\).*/\1\"--host_id $CLOUD_INSTANCE_ID\"/' -i $AGENT_ARGS"
    fi
    action "grep server_host=$SCM_HOSTNAME $AGENT_CONFIG"
    if [[ $? -ne 0 ]]; then
        action "$SUDO sed -e 's/\(server_host=\).*/\1$SCM_HOSTNAME/' -i $AGENT_CONFIG"
        fail_or_continue $? scm agent could not be configured
        echo scm agent configured
        AGENT_CONFIGURED=1
    else
        echo scm agent is already configured
    fi
}

# Returns the instance ID if we're on a public cloud machine. Returns an empty
# string if we're not.
set_public_cloud_instance_id()
{
    # A check for each of the cloud providers that we support.
    set_aws_instance_id
    if [[ -n $AWS_INSTANCE_ID ]]; then
        CLOUD_INSTANCE_ID=$AWS_INSTANCE_ID
    fi
}

# Returns true if wget is present on the system, false otherwise. Takes
# one parameter: the name of the cloud provider for which we're about to
# perform a wget-based check.
test_wget_before_provider_check()
{
    local PROVIDER=$1
    [[ -n $(action_get which wget) ]]
    WGET_EXISTS=$?
    if [[ ! $WGET_EXISTS ]]; then
        echo "wget not found, skipping $PROVIDER test"
    fi
    return $WGET_EXISTS
}

# Sets the AWS instance ID if we're on AWS.
set_aws_instance_id()
{
    if test_wget_before_provider_check "AWS"; then
        PUBLIC_HOSTNAME=$(action_get 'wget -qO- -T 1 -t 1 http://169.254.169.254/latest/meta-data/public-hostname && /bin/echo')
        if echo $PUBLIC_HOSTNAME | grep -qE "\.amazonaws\.com$"; then
            AWS_INSTANCE_ID=$(action_get 'wget -qO- -T 1 -t 1 http://169.254.169.254/latest/meta-data/instance-id && /bin/echo')
        fi
    fi
}

# If we're on the public cloud, we need to turn off iptables,
# disable selinux, etc. so that CM/CDH work. Normally, users have to do this
# for themselves, but we want to make public cloud installs as easy as
# possible (at the occassional expense of concealing low-level details like
# these from the user).
cloud_specific_configure()
{
    set_public_cloud_instance_id
    if [[ -n $CLOUD_INSTANCE_ID ]]; then
        mark CLOUD_SPECIFIC_CONFIGURE
        # We assume that there's no custom iptables configuration -- either iptables
        # is on in the default rc[0-6].d directories and off everywhere else
        # (i.e. the state that results when "$CHKCONFIG iptables $CHKCONFIG_START" is run),
        # or it's off everywhere (i.e. the state that results when "$CHKCONFIG
        # iptables $CHKCONFIG_STOP" is run). In a rollback situation, we're simply going to
        # restore an "on" state using "$CHKCONFIG iptables $CHKCONFIG_START," so
        # we can't restore any custom configurations. This shouldn't be a problem,
        # as custom configurations shouldn't be present on cloud nodes poeple give to us anyway.
        if [[ -f /etc/init.d/iptables ]]; then
            if [[ $OS == "RHEL" || $OS == "SLES" ]]; then
                action $SUDO $CHKCONFIG iptables
                IPTABLES_CHKCONFIG_ORIG_ON=$?
                if [[ $IPTABLES_CHKCONFIG_ORIG_ON -eq 0 ]]; then
                    action $SUDO $CHKCONFIG iptables $CHKCONFIG_STOP
                fi
            elif [[ $OS == "Debian" || $OS == "Ubuntu" ]]; then
                # In order to determine whether iptables was originally on, we need this
                # regex (in the grep) to check whether the original list of rc symlinks, which is printed when
                # we disable iptables, contains a start entry (denoted by an "S" at the beginning
                # of the symlink name). The new list of symlinks is printed as well, but we don't need to
                # worry about that because it will contain only "K" -- kill -- entries, and no "S" ones.
                [[ -n $(action_get "$SUDO $CHKCONFIG iptables $CHKCONFIG_STOP | grep -e /etc/rc[0-6]\.d/S") ]]
                IPTABLES_CHKCONFIG_ORIG_ON=$?
            fi
            # "Chain" should always be present in the output of "status" if iptables is running
            action "$SUDO $SERVICE iptables status | grep Chain"
            IPTABLES_SERVICE_ORIG_ON=$?
            if [[ $IPTABLES_SERVICE_ORIG_ON -eq 0 ]]; then
                action $SUDO $SERVICE iptables stop
            fi
        fi
        if [[ $OS == "RHEL" ]]; then
            # This command doesn't strictly require SUDO, but sometimes it's located
            # in /usr/sbin, so we need to use SUDO to make sure that /usr/sbin is in
            # our PATH.
            [[ $(action_get $SUDO getenforce) == "Enforcing" ]]
            RHEL_ENFORCE_ORIG_ENFORCING=$?
            if [[ $RHEL_ENFORCE_ORIG_ENFORCING -eq 0 ]]; then
                action $SUDO setenforce Permissive
            fi
            action grep -e ^SELINUX=enforcing /etc/selinux/config
            RHEL_SELINUX_ORIG_ENFORCING=$?
            if [[ $RHEL_SELINUX_ORIG_ENFORCING -eq 0 ]]; then
                action "$SUDO sed -e 's/^SELINUX=enforcing/SELINUX=disabled/' -i /etc/selinux/config"
            fi
        fi
        prepare_unmounted_cloud_volumes
    fi
}

# Format and mount all unmounted volumes on cloud nodes.
# Volumes will be mounted as /data0, /data1, ... /data[n-1],
# where n is the number of unmounted volumes.
# The larger cloud instance types have a large amount
# of AVAILABLE storage, but only a fraction of it is
# actually formatted and mounted at instance creation
# time.
prepare_unmounted_cloud_volumes()
{
    # Each line contains an entry like /dev/<device name>
    MOUNTED_VOLUMES=$(action_get "df -h | grep -o -E \"^/dev/[^[:space:]]*\"")
    # Each line contains an entry like <device name> (no /dev/ prefix)
    # (This awk script prints the last field of every line with line number
    # greater than 2.)
    ALL_PARTITIONS=$(action_get "awk 'FNR > 2 {print \$NF}' /proc/partitions")
    COUNTER=0
    for part in $ALL_PARTITIONS; do
        # If this partition does not end with a number (likely a partition of a
        # mounted volume), is not equivalent to the alphabetic portion of another
        # partition with digits at the end (likely a volume that has already been
        # mounted), and is not contained in $MOUNTED_VOLS
        if [[ !($part =~ [0-9]$) && !($ALL_PARTITIONS =~ $part[0-9]) && $MOUNTED_VOLUMES != *$part* ]]; then
            prep_disk "/data$COUNTER" "/dev/$part"
            COUNTER=$(($COUNTER+1))
        fi
    done
}

cloud_specific_unconfigure()
{
    # Roll back the changes we made for a cloud install (see
    # cloud_specific_configure() above).
    if [[ -n $CLOUD_INSTANCE_ID ]]; then
        mark CLOUD_SPECIFIC_UNCONFIGURE
        if [[ $IPTABLES_CHKCONFIG_ORIG_ON && $IPTABLES_CHKCONFIG_ORIG_ON -eq 0 ]]; then
            action $SUDO $CHKCONFIG iptables $CHKCONFIG_START
        fi
        if [[ $IPTABLES_SERVICE_ORIG_ON && $IPTABLES_SERVICE_ORIG_ON -eq 0 ]]; then
            action $SUDO $SERVICE iptables start
        fi
        if [[ $RHEL_ENFORCE_ORIG_ENFORCING && $RHEL_ENFORCE_ORIG_ENFORCING -eq 0 ]]; then
            action $SUDO setenforce Enforcing
        fi
        if [[ $RHEL_SELINUX_ORIG_ENFORCING && $RHEL_SELINUX_ORIG_ENFORCING -eq 0 ]]; then
            action "$SUDO sed -e 's/^SELINUX=disabled/SELINUX=enforcing/' -i /etc/selinux/config"
        fi
    fi
}


# This function was lifted from the file prepare_all_disks.sh in the Whirr project.
# It has been modified slightly to use our custom logging mechanism (action/action_get),
# to ensure appropriate permissions (i.e. $SUDO's added), to take advantage of our
# knowledge of the OS's package management system (i.e. use of $PACKAGER), and to
# use ext* rather than xfs.
prep_disk()
{
  mount=$1
  device=$2
  automount=${3:-false}

  FS=ext4
  action which mkfs.$FS
  # Fall back to ext3
  if [[ $? -ne 0 ]]; then
    FS=ext3
  fi
  # is device formatted?
  if [ $(action_get mountpoint -q -x $device) ]; then
    echo "$device is formatted"
  else
    echo "warning: ERASING CONTENTS OF $device"
    action $SUDO mkfs.$FS -f $device
  fi
  # is device mounted?
  action "mount | grep -q $device"
  if [ $? == 0 ]; then
    echo "$device is mounted"
    if [ ! -d $mount ]; then
      echo "Symlinking to $mount"
      action "$SUDO ln -s $(grep $device /proc/mounts | awk '{print $2}') $mount"
    fi
  else
    echo "Mounting $device on $mount"
    if [ ! -e $mount ]; then
      action $SUDO mkdir $mount
    fi
    action $SUDO mount -o defaults,noatime $device $mount
    if $automount ; then
      action "$SUDO echo \"$device $mount $FS defaults,noatime 0 0\" >> /etc/fstab"
    fi
  fi
}

# Install the core set of Hadoop and SCM packages using the configured
# repositories. Some of them may have already been installed via
# install_local_packages. That's OK; they will be skipped.
install_remote_packages()
{
    for PACKAGE in $PACKAGES; do
        local IS_OPTIONAL=false
        if [[ "$PACKAGE" =~ "#optional#" ]]; then
            IS_OPTIONAL=true
            # strip out prefix
            PACKAGE="${PACKAGE:10}"
        fi
        package_is_blacklisted $PACKAGE
        if [[ $? -eq 0 ]]; then
            continue
        fi

        mark PACKAGE_INSTALL $PACKAGE
        package_should_be_installed $PACKAGE
        local SHOULD_INSTALL=$?
        if [[ $SHOULD_INSTALL -ne 1 ]]; then
            package_is_available $PACKAGE
            local IS_AVAILABLE=$?
            # It's ok if optional packages are missing
            if $IS_OPTIONAL && [ $IS_AVAILABLE -ne 0 ]; then
                echo "$PACKAGE not available, continuing"
                continue
            fi
            fail_or_continue $IS_AVAILABLE remote package $PACKAGE is not available
            package_install $PACKAGE
            fail_or_continue $? remote package $PACKAGE could not be installed
            echo remote package $PACKAGE installed
            if [[ $SHOULD_INSTALL -eq 0 ]]; then
                # Insert the newly installed package at the "head" so that rollback
                # will uninstall packages in reverse order.
                INSTALLED_PACKAGES="$PACKAGE $INSTALLED_PACKAGES"
            fi
        else
            echo remote package $PACKAGE is already installed
        fi
        #
        # We need to turn off all bundled init scripts that come with
        # CDH packages to allow SCM to manage process lifetime. If packages
        # are built correctly, no init scripts should be provided for any
        # CDH package that we install from here.
        #
        # As of CDH3u1 both Hue and Oozie are guilty of this.
        # As of CDH4b2 both Hadoop-httpfs and Oozie are guilty of this.
        #
        if [[ -x /etc/init.d/$PACKAGE ]]; then
            case $PACKAGE in
                hadoop-httpfs)
                    # To add insult to injury, httpfs is autostarted by the package
                    action $SUDO $SERVICE $PACKAGE stop
                    echo disabling auto-start for $PACKAGE
                    action $SUDO $CHKCONFIG $PACKAGE $CHKCONFIG_STOP
                    # Bash 4 support fallthrough. RHEL5 is, naturally, too old.
                    ;;
                hue|oozie)
                    echo disabling auto-start for $PACKAGE
                    action $SUDO $CHKCONFIG $PACKAGE $CHKCONFIG_STOP
                    ;;
                *)
                    ;;
            esac
        fi
        # CDH-5672: There are no words.
        case $PACKAGE in
            hue-beeswax)
                action $SUDO chown hue.hue /var/log/hue/beeswax_server.*
                ;;
            hue-jobsub)
                action $SUDO chown hue.hue /var/log/hue/jobsubd.*
                ;;
            *)
                ;;
        esac
    done
}

# Validate that a repo file contains a repository reference that isn't clearly
# meant for the other type of distro (yum/zupper vs apt)
validate_repo_file()
{
    local file="$1"
    echo validating format of repository file $file

    # This is not a comprehensive check, but it's sufficient to catch the
    # specific case where the user used an apt source instead of a yum repo and
    # vice versa
    case $PACKAGER in
        apt-get)
            grep -q -E '^deb +([^ ]+) +([^ ]+) +(.+)$' $file
            fail_or_continue $? repository file $repo is not a valid apt source. A yum/zypper repo could have accidentally been entered.
            ;;
        yum|zypper)
            head -n 3 $file | tail -n 1 | grep -q -v 'baseurl = deb '
            fail_or_continue $? repository file $repo does not contain a valid url. It appears a Debian apt source was accidentally entered.
            ;;
        *)
            echo unknown packager $PACKAGER, exiting
            exit 1
            ;;
    esac
    
}

# Install repository files provided by the server.
install_repo_files()
{
    mark REPO_INSTALL
	if [[ ! -d $LOCAL_REPOS ]]; then
        fail_or_continue 1 could not find repository files
	fi

    for repo in `find "$LOCAL_REPOS"/*`; do
       validate_repo_file $repo
       echo installing repository file $repo
       $SUDO install -m 644 --backup=numbered "$repo" "$REPO_DEST"/
       fail_or_continue $? repository file $repo could not be installed
       echo repository file $repo installed
       INSTALLED_REPO_FILES="$REPO_DEST/$(basename $repo) $INSTALLED_REPO_FILES"
    done

    case $PACKAGER in
        apt-get)
            action $SUDO apt-key add $LOCAL_DIR/archive.key
            fail_or_continue $? archive GPG key could not be installed
            ;;
        *)
            ;;
    esac
}

# Refresh the packager's metadata cache
refresh_metadata()
{
    mark REFRESH_METADATA

    # Blow away any old metadata first.
    do_packager_clean_cache

    case $PACKAGER in
        apt-get)
            action $SUDO $PACKAGER update
            ;;
        yum)
            action $SUDO $PACKAGER makecache
            ;;
        zypper)
            action $SUDO $PACKAGER --gpg-auto-import-keys -n refresh
            ;;
        *)
            echo unknown packager $PACKAGER, exiting
            exit 1
            ;;
    esac
    # Commented out for now as apt repos are not set up, leading to warnings
    #fail_or_continue $? could not refresh package metadata
}

# Try to find a fully-qualified domain name (FQDN) for the SCM server host and
# make sure it is alive.
detect_scm_server()
{
    mark DETECT_SCM
    FQDN=$(action_get host -t PTR $SCM_HOSTNAME)
    if [[ $? -eq 0 ]]; then
        PATTERN='.* domain name pointer (.*)\.'
        if [[ $FQDN =~ $PATTERN ]]; then
            echo using ${BASH_REMATCH[1]} as scm server hostname
            SCM_HOSTNAME=${BASH_REMATCH[1]}
        fi
    fi
    # Ping may not always be available, so we check to see
    # if we could establish a connection to the heartbeat
    # port.
    action which python
    if [[ $? -ne 0 ]]; then
      echo "Python not installed... skipping check for connectivity to SCM server."
    else
      action "python -c 'import socket; import sys; s = socket.socket(socket.AF_INET); s.settimeout(5.0); s.connect((sys.argv[1], int(sys.argv[2]))); s.close();' $SCM_HOSTNAME $SCM_HEARTBEAT_PORT"
      fail_or_continue $? could not contact scm server at $SCM_HOSTNAME:$SCM_HEARTBEAT_PORT
    fi
}

# Set up shell variables for a SLES-based distro.
distro_setup_sles()
{
    case $1 in
        11)
            LOCAL_REPOS=$LOCAL_DIR/repos/sles$1
            REPO_DEST=/etc/zypp/repos.d
            PACKAGER=zypper
            SERVICE=/sbin/service
            CHKCONFIG=/sbin/chkconfig
            CHKCONFIG_STOP="off"
            CHKCONFIG_START="on"
            ;;
        *)
            echo unsupported SLES release, exiting
            exit 1
            ;;
    esac
}

# Set up shell variables for a RHEL-based distro.
distro_setup_rhel()
{
    case $1 in
        5|6)
            LOCAL_REPOS=$LOCAL_DIR/repos/rhel$1
            REPO_DEST=/etc/yum.repos.d
            PACKAGER=yum
            SERVICE=/sbin/service
            CHKCONFIG=/sbin/chkconfig
            CHKCONFIG_STOP="off"
            CHKCONFIG_START="on"
            ;;
        *)
            echo unsupported RHEL release, exiting
            exit 1
            ;;
    esac
}

distro_setup_debian()
{
    case $1 in
        lucid)
            LOCAL_REPOS=$LOCAL_DIR/repos/ubuntu_lucid
            ;;
        maverick)
            LOCAL_REPOS=$LOCAL_DIR/repos/ubuntu_maverick
            ;;
        precise)
            LOCAL_REPOS=$LOCAL_DIR/repos/ubuntu_precise
            ;;
        6.*)
            LOCAL_REPOS=$LOCAL_DIR/repos/debian_squeeze
            ;;
        *)
            echo "unsupported Debian or Ubuntu release, exiting"
            exit 1
            ;;
    esac

    # Silence interactive debs...
    export DEBIAN_FRONTEND=noninteractive

    REPO_DEST=/etc/apt/sources.list.d
    PACKAGER=apt-get
    SERVICE=/usr/sbin/service
    CHKCONFIG=/usr/sbin/update-rc.d
    CHKCONFIG_STOP="disable"
    CHKCONFIG_START="enable"
    # This is garbage but it's way too painful to solve generically
    PACKAGES=$(echo $PACKAGES | sed -e 's/jdk/oracle-j2sdk1.6/')
    ALWAYS_INSTALL_PACKAGES=$(echo $ALWAYS_INSTALL_PACKAGES | sed -e 's/jdk/oracle-j2sdk1.6/')
}

# Distro detection using /etc/*-release files.
#
# Modern distros expose the lsb_release binary for distro detection, but not
# only is it not installed by default on SLES11, but lsb_release can't be used
# to differentiate between vanilla SLES11 and SLES11 SP1. The /etc/*-release
# files system is older, but it's reliable and always available.
detect_distro()
{
    local RHEL_FILE=/etc/redhat-release
    local SLES_FILE=/etc/SuSE-release
    local UBUNTU_FILE=/etc/lsb-release
    local DEBIAN_FILE=/etc/debian_version

    mark DETECT_DISTRO

    if [[ -f $RHEL_FILE ]]; then
        OS="RHEL"
        action grep Tikanga $RHEL_FILE
        if [[ $? -eq 0 ]]; then
            echo $RHEL_FILE '==>' RHEL 5
            RHEL_VERSION=5
        fi
        if [[ -z $RHEL_VERSION ]]; then
            action "grep 'CentOS release 5' $RHEL_FILE"
            if [[ $? -eq 0 ]]; then
                echo $RHEL_FILE '==>' CentOS 5
                RHEL_VERSION=5
            fi
        fi
        if [[ -z $RHEL_VERSION ]]; then
            action "grep 'Scientific Linux release 5' $RHEL_FILE"
            if [[ $? -eq 0 ]]; then
                echo $RHEL_FILE '==>' Scientific Linux 5
                RHEL_VERSION=5
            fi
        fi
        if [[ -z $RHEL_VERSION ]]; then
            action grep Santiago $RHEL_FILE
            if [[ $? -eq 0 ]]; then
                echo $RHEL_FILE '==>' RHEL 6
                RHEL_VERSION=6
            fi
        fi
        if [[ -z $RHEL_VERSION ]]; then
            action "grep 'CentOS Linux release 6' $RHEL_FILE"
            if [[ $? -eq 0 ]]; then
                echo $RHEL_FILE '==>' CentOS 6
                RHEL_VERSION=6
            fi
        fi
        if [[ -z $RHEL_VERSION ]]; then
            action "grep 'CentOS release 6' $RHEL_FILE"
            if [[ $? -eq 0 ]]; then
                echo $RHEL_FILE '==>' CentOS 6
                RHEL_VERSION=6
            fi
        fi
        if [[ -z $RHEL_VERSION ]]; then
            action "grep 'Scientific Linux release 6' $RHEL_FILE"
            if [[ $? -eq 0 ]]; then
                echo $RHEL_FILE '==>' Scientific Linux 6
                RHEL_VERSION=6
            fi
        fi
        distro_setup_rhel $RHEL_VERSION
    elif [[ -f $SLES_FILE ]]; then
        OS="SLES"
        action "grep 'SUSE Linux Enterprise Server 11' $SLES_FILE"
        if [[ $? -eq 0 ]]; then
            SP_LINE=$(action_get grep PATCHLEVEL $SLES_FILE)
            if [[ $? -eq 0 ]]; then
                SP=$(action_get "echo $SP_LINE | cut -d = -f 2")
                if (($SP > 0)); then
                    echo $SLES_FILE '==>' SLES 11 \(SP$SP\)
                    SLES_VERSION=11
                fi
            fi
        fi
        distro_setup_sles $SLES_VERSION
    elif [[ -f $UBUNTU_FILE ]]; then
        OS="Ubuntu"
        action "grep 'Ubuntu' $UBUNTU_FILE"
        if [[ $? -eq 0 ]]; then
            CODE_LINE=$(action_get grep DISTRIB_CODENAME $UBUNTU_FILE)
            if [[ $? -eq 0 ]]; then
                CODENAME=$(action_get "echo $CODE_LINE | cut -d = -f 2")
            fi
        fi
        distro_setup_debian $CODENAME
    elif [[ -f $DEBIAN_FILE ]]; then
        OS="Debian"
        # Debian *must* come after ubuntu as ubuntu provides a debian_version
        # file too
        CODENAME=$(action_get "cat $DEBIAN_FILE")
        distro_setup_debian $CODENAME
    else
        echo unsupported distro, exiting
        exit 1
    fi
}

# Make sure we have root privileges. If not, we'll try to use sudo or pbrun.
detect_root()
{
    mark DETECT_ROOT

    echo "effective UID is $EUID"
    if [[ $EUID -ne 0 ]]; then
        action which pbrun
        if [[ $? -eq 0 ]]; then
            # If pbrun is installed, then it's there to be used
            SUDO="pbrun "
            # We're not aware of a way to test if pbrun requires a password.
            # People who use it should know what they're doing.
        else
	        action sudo -S id < /dev/null
	        if [[ $? -eq 0 ]]; then
	            SUDO="sudo "
	        else
	            echo need root privileges but sudo requires password, exiting
	            exit 1
	        fi
	    fi
	    echo "Using '$SUDO' to acquire root privileges"
    fi
}

# Acquire the global installation lock or block until it can be acquired.
take_lock()
{
    # flock will wait until the lock is available and will release the lock
    # when the file descriptor is closed (e.g. when the script terminates). The
    # lock is placed in /tmp because /var/lock isn't guaranteed to be writable
    # by normal users.
    #
    # Important notes:
    # o The lock file will be left behind on the filesystem. This is harmless.
    # o The lock file is vulnerable to symlink attacks. Don't use this on
    #   machines where non-privileged users can't be trusted not to DoS the
    #   system.
    mark TAKE_LOCK

    # Create the lock file with a permissive umask so that unprivileged users
    # can also lock it. Note that we don't use action_get because umask changes
    # inside an eval appear to be reset after the eval.
    OLD_UMASK=$(umask)
    umask 0
    exec 4>$LOCK_FILE
    RET=$?
    umask $OLD_UMASK
    fail_or_continue $RET could not open lock file
    action flock 4
    fail_or_continue $? could not acquire installation lock
}

# Find the CM hostname from SSH environment variables.
configure_scm_hostname()
{
    SSH_ENV_VARS=( "SSH_CLIENT" "SSH_CONNECTION" "SSH2_CLIENT" )
    for ENV_VAR in $SSH_ENV_VARS; do
      eval VAR_VALUE=\$$ENV_VAR
      if [[ -n $VAR_VALUE ]]; then
          SSH_VAR=$VAR_VALUE
          echo using $ENV_VAR to get the SCM hostname: $VAR_VALUE
          break
      fi
    done

    if [[ -z $SSH_VAR && -n $SSH_RHOST ]]; then
        # It's been reported that when connecting to a local Tectia SSH server
        # the SSH_RHOST value can end up being "hostname.fully.qualified,hostname"
        # and this is why we're taking the first part before the comma if one exists
        SSH_VAR=$(echo $SSH_RHOST | cut -d, -f1)
        echo using SSH_RHOST to get the SCM hostname: $SSH_RHOST
    fi

    SSH_CLIENT_ARRAY=($SSH_VAR)
    SCM_HOSTNAME=${SSH_CLIENT_ARRAY[0]}
}

# Parse short and long option parameters.
parse_arguments()
{
    GETOPT=`getopt -n $0 -o h:,p:,a:,x:,? -l help,host:,packages:,always:,x86_64:,skipImpala:,skipSolr:,server_version:,server_build: -- "$@"`
    RETVAL=$?
    if [[ $RETVAL -ne 0 ]]; then
        usage
        exit $RETVAL
    fi
    eval set -- "$GETOPT"
    while true;
    do
        case "$1" in
            -h|--host)
                SCM_HOSTNAME=$2
                shift 2
                ;;
            -p|--packages)
                PACKAGES=$(cat "$2")
                shift 2
                ;;
            -a|--always)
                ALWAYS_INSTALL_PACKAGES=$(cat "$2")
                shift 2
                ;;
            -x|--x86_64)
                X86_64_PACKAGES=( $(cat "$2") )
                shift 2
                ;;
            --skipImpala)
                SKIP_IMPALA=$2
                shift 2
                ;;
            --skipSolr)
                SKIP_SOLR=$2
                shift 2
                ;;
            --server_version)
                SERVER_VERSION=$2
                shift 2
                ;;
            --server_build)
                SERVER_BUILD=$2
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                usage
                exit 1
                ;;
        esac
    done

    # No hostname specified on the command line. Check SSH environment variables.
    if [[ -z $SCM_HOSTNAME ]]; then
        configure_scm_hostname
    fi

    # Must be set to continue.
    if [[ -z $SCM_HOSTNAME ]]; then
        echo $0: could not find hostname or IP address of SCM server
        usage
        exit 1
    fi
}

ROLLBACK=
PACKAGER=
INSTALLED_PACKAGES=
LOCAL_DIR=$(dirname $0)
AGENT_CONFIG=/etc/cloudera-scm-agent/config.ini
AGENT_ARGS=/etc/default/cloudera-scm-agent
AGENT_LOG_DIR=/var/log/cloudera-scm-agent/
AGENT_LOGS=($AGENT_LOG_DIR/cloudera-scm-agent.out \
            $AGENT_LOG_DIR/cloudera-scm-agent.log)
SCM_HOSTNAME=
# Currently not configurable.
SCM_HEARTBEAT_PORT=7182
SUDO=
LOCK_FILE=/tmp/.scm_prepare_node.lock
ABORT_FILE=$LOCAL_DIR/aborted
ROLLBACK_FILE=$LOCAL_DIR/rollback
CLOUD_INSTANCE_ID=
IMPALA_PACKAGE="impala impala-shell"
SOLR_PACKAGE="solr solr-doc search solr-mapreduce flume-ng-solr hue-search hbase-solr hbase-solr-doc"
SKIP_IMPALA="false"
SKIP_SOLR="false"
SERVER_VERSION=".*"
SERVER_BUILD=".*"

parse_arguments "$@"

# Don't install Impala if skip option is specified
if [[ $SKIP_IMPALA = "true" ]]; then
    NEVER_INSTALL_PACKAGES="$IMPALA_PACKAGE"
fi

# Don't install Solr if skip option is specified
if [[ $SKIP_SOLR = "true" ]]; then
    NEVER_INSTALL_PACKAGES="$NEVER_INSTALL_PACKAGES $SOLR_PACKAGE"
fi

# Convert NEVER_INSTALL_PACKAGES to an array
if [ -n "$NEVER_INSTALL_PACKAGES" ]; then
    NEVER_INSTALL_PACKAGES=( $NEVER_INSTALL_PACKAGES )
fi

# Setup the logging file descriptor.
fd_open
trap fd_close EXIT

mark SCRIPT_START

take_lock
detect_root
detect_distro
detect_scm_server
cloud_specific_configure
install_repo_files
refresh_metadata
install_remote_packages
configure_agent
start_agent

mark SCRIPT_SUCCESS
echo all done
