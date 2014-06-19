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

DISCOURSE_USER=
DISCOURSE_USERHOME=
DISCOURSE_DIR=

pre_run_test() {
	# Check for required commands
	local ERR=0
	for REQUIRED in git grep awk bundle ruby bootup_bluepill
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
	local THINSOCK_PID=`ps -fu ${DISCOURSE_USER} | grep thin | grep -v grep | awk '{print $2}'`
	
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
	echo "\n\e[1;33mAttempting to kill processes...\e[0m\n"
	
	if [ -n "${SIDEKIQ_PID}" -a "${SIDEKIQ_PID}" -gt 0 ] ; then
		kill ${SIDEKIQ_PID};
		echo "Sidekiq (pid:${SIDEKIQ_PID}) killed."
	else
		echo "Sidekiq process not found."
	fi
	
	if [ -n "${BLUEPILL_PID}" -a "${BLUEPILL_PID}" -gt 0 ] ; then
		kill ${BLUEPILL_PID};
		echo "Bluepill (pid:${BLUEPILL_PID}) killed."
	else
		echo "Bluepill process not found."
	fi
	
	for PID in ${THINSOCK_PID} ; do
		if [ -n "${PID}" -a "${PID}" -gt 0 ] ; then
			kill $PID;
			echo "Thin server (pid:${PID}) killed."
		else
			echo "Thin server process not found."
		fi
	done
	
	echo -e "\e[1;33mRestarting bluepill...\e[0m"
	# Restart bluepill
	RUBY_GC_MALLOC_LIMIT=90000000 RAILS_ENV=production RAILS_ROOT=${DISCOURSE_DIR} NUM_WEBS=2 \
		${DISCOURSE_USERHOME}/.rvm/bin/bootup_bluepill --no-privileged -c ~/.bluepill load ${DISCOURSE_DIR}/config/discourse.pill
		
	echo -e "\n\e[1;32mUpgrade is complete. Reload NGINX now, if necessary, to complete upgrade.\e[0m"
}

echo -e "\e[1;33;42mDiscourse Upgrade Script\e[0m\n"

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
