#!/usr/bin/env bash

###############################################################
# Discourse upgrade script for unsupported installs.          #
#                                                             #
# Author: Brendan Corcoran (@bcorcoran)                       #
#                                                             #
# Please be aware that this, too, is unsupported.             #
# This script performs the same actions as the docker upgrade #
# If interested, see: http://git.io/sScXVg                    #
###############################################################

# Discourse user: The user discourse runs under
DISCOURSE_USER=

# Discourse user home: The home directory of above user (the one containing .rvm)
DISCOURSE_USERHOME=

# Discourse directory: The directory that discourse install is located
DISCOURSE_DIR=

# App Server Selection
# Options:
# unicorn = Unicorn; Remember to configure discourse/config/unicorn.conf.rb and nginx upstream block!
APP_SERVER=unicorn

pre_run_test() {
	# Check for required commands
	local ERR=0
	for REQUIRED in git grep awk bundle ruby
	do
		if ! command -v $REQUIRED >/dev/null 2>&1 ; then
			echo "This script requires the ${REQUIRED} command."
			let ERR=$ERR+1
		fi
	done
	
	for REQV in DISCOURSE_USER DISCOURSE_USERHOME DISCOURSE_DIR ; do
		if [ -z ${!REQV} ] ; then
			echo "${REQV} variable not set!"
			let ERR=$ERR+1
		fi
	done
	
	if [ $ERR -gt 0 ] ; then
		echo -e "\e[1;31mDiscourse upgrade script pre-test failed.\e[0m"
		exit 1
	else
		unset ERR
		echo "Discourse upgrade script pre-test passed."
	fi
}

pre_run_test

upgrade_discourse() {
	
	# Go to discourse dir
	cd ${DISCOURSE_DIR}
	
	# get pid of unicorn master
	local UNICORN_PID=`ps -fu ${DISCOURSE_USER} | grep 'unicorn master' | grep -v grep | awk '{print $2}'`
	
	# get latest code
	echo -e "\e[1;33mGetting latest discourse code...\e[0m"
	local CURRENT_BRANCH=`git branch | grep "*" | awk '{print $2}'`
	
	git fetch
	
	if [ "${CURRENT_BRANCH}" != "tests-passed" ] ; then
		git checkout tests-passed
	fi
	
	git reset --hard HEAD@{upstream}
	
	echo -e "\e[1;33mRunning discourse upgrades (bundle install, migration, asset compile)...\e[0m"
	
	# Bundle install
	bundle install --deployment --without test --without development
	
	# Run migration
	RUBY_GC_MALLOC_LIMIT=90000000 RAILS_ENV=production \
		bundle exec rake multisite:migrate
	
	# Compile assets
	RUBY_GC_MALLOC_LIMIT=90000000 RAILS_ENV=production \
		bundle exec rake assets:precompile
	
	# Kill old processes
	echo -e "\n\e[1;33mAttempting to kill unicorn...\e[0m\n"
	
	for PID in ${UNICORN_PID} ; do
		if [ -n "${PID}" -a "${PID}" -gt 0 ] ; then
			kill $PID;
			
			if [ $? -eq 0 ] ; then
				echo "Unicorn (pid:${PID}) killed. Runit should catch up in a bit."
			else
				echo "Tried to kill app server pid:${PID}, but failed."
			fi
		else
			echo "Unicorn process not found."
		fi
	done
	
	echo -e "\n\e[1;32mUpgrade is complete. Reload NGINX now, if necessary, to complete upgrade.\e[0m"
}

echo -e "\e[1;33;42mDiscourse Upgrade Script\e[0m\n"

echo "The following are your configuration values: "

echo "Discourse User: ${DISCOURSE_USER}"
echo "Discourse User Home Directory: ${DISCOURSE_USERHOME}"
echo "Discourse Directory: ${DISCOURSE_DIR}"
echo "App Server: ${APP_SERVER}"

echo 
read -p "Are these values correct? [Y/n]: " YN

case $YN in
	[Nn] ) echo "Upgrade script aborted."; exit 0 ;;
	[Yy]|* ) upgrade_discourse ;; 
esac

