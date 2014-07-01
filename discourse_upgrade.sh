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

# Number of thin server processes: This must match the number of entries in your nginx config's upstream block.
# 4 is the default in discourse/config/nginx.sample.conf
NUM_THIN_SERVERS=4

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
	
	# get pids of sidekik, bluepill, and thin server sockets
	   local SIDEKIQ_PID=`ps -fu ${DISCOURSE_USER} | grep sidekiq.*busy | grep -v grep | awk '{print $2}'`
	  local BLUEPILL_PID=`ps -fu ${DISCOURSE_USER} | grep bluepilld | grep -v grep | awk '{print $2}'`
	local APP_SERVER_PID=`ps -fu ${DISCOURSE_USER} | grep thin | grep -v grep | awk '{print $2}'`
	
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
	echo -e "\n\e[1;33mAttempting to kill processes...\e[0m\n"
	
	if [ -n "${SIDEKIQ_PID}" -a "${SIDEKIQ_PID}" -gt 0 ] ; then
		kill ${SIDEKIQ_PID};
		echo "Sidekiq (pid:${SIDEKIQ_PID}) killed."
	else
		echo "Sidekiq process not found."
	fi
	
	# Kill bluepill if we're using thin
	if [ "${APP_SERVER}" == "thin" ] ; then
		if [ -n "${BLUEPILL_PID}" -a "${BLUEPILL_PID}" -gt 0 ] ; then
			kill ${BLUEPILL_PID};
			echo "Bluepill (pid:${BLUEPILL_PID}) killed."
		else
			echo "Bluepill process not found."
		fi
	fi
	
	for PID in ${APP_SERVER_PID} ; do
		if [ -n "${PID}" -a "${PID}" -gt 0 ] ; then
			kill $PID;
			
			if [ $? -eq 0 ] ; then
				echo "App server (pid:${PID}) killed."
			else
				echo "Tried to kill app server pid:${PID}, but failed."
			fi
		else
			echo "App server process not found."
		fi
	done
	
	# Restart app server
	echo -e "\e[1;33mRestarting app server...\e[0m"
	
	RUBY_GC_MALLOC_LIMIT=90000000 RAILS_ENV=production RAILS_ROOT=${DISCOURSE_DIR} NUM_WEBS=${NUM_THIN_SERVERS} \
		${DISCOURSE_USERHOME}/.rvm/bin/bootup_bluepill --no-privileged -c ~/.bluepill load ${DISCOURSE_DIR}/config/discourse.pill
	
	echo -e "\n\e[1;32mUpgrade is complete. Reload web server now, if necessary.\e[0m"
}

echo -e "\e[1;33;42mDiscourse Upgrade Script (thin/bluepill edition)\e[0m\n"

echo "The following are your configuration values: "

echo "Discourse User: ${DISCOURSE_USER}"
echo "Discourse User Home Directory: ${DISCOURSE_USERHOME}"
echo "Discourse Directory: ${DISCOURSE_DIR}"

echo 
read -p "Are these values correct? [Y/n]: " YN

case $YN in
	[Nn] ) echo "Upgrade script aborted."; exit 0 ;;
	[Yy]|* ) upgrade_discourse ;; 
esac

