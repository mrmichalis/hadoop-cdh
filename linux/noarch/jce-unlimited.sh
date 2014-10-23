#!/usr/bin/env bash

LOC_6=$(rpm -ql "jdk" | grep "/usr/java/jdk1.6" | sort | head -n 1)
LOC_7=$(rpm -ql "oracle-j2sdk1.7" | grep "/usr/java/jdk1.7" | sort | head -n 1)
SECURITY_6="local_policy.jar.6 US_export_policy.jar.6"
SECURITY_7="local_policy.jar.7 US_export_policy.jar.7"

echo Java 6 prefix is "$LOC_6"
echo Java 7 prefix is "$LOC_7"

for file in $SECURITY_6; do
	target=$(basename $file .6)
	full_target="$LOC_6/jre/lib/security/$target"
	if [ -e "$full_target" ]; then
	  echo "Installing unlimited strength $target for Java 6"
	  echo "Target directory $full_target"
	  curl -L "https://github.com/mrmichalis/hadoop-cdh/raw/master/linux/noarch/security/$file" -o "$full_target"
	else
	  echo "Did not find expected $full_target. Not copying new policy file."
	fi
done

for file in $SECURITY_7; do
	target=$(basename $file .7)
	full_target="$LOC_7/jre/lib/security/$target"
	if [ -e "$full_target" ]; then
	  echo "Installing unlimited strength $target for Java 7"
	  echo "Target directory $full_target"
	  curl -L "https://github.com/mrmichalis/hadoop-cdh/raw/master/linux/noarch/security/$file" -o "$full_target"
	else
	  echo "Did not find expected $full_target. Not copying new policy file."
	fi
done
