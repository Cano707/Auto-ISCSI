#!/bin/bash
set -eu

# >>> HELPER
check_exit_code() {
	if [[ $? -ne 0 ]]; then
		printf "$1" 1>&2
		exit 1
	fi
}

copy_check() {
	cp "$1" "$2"
	check_exit_code "Failed to copy $1 to $2\n"
}

prompt() {
	skip=0
	printf "$1"
	continue=""
	while [[ ! "$continue" =~ ^(y|n|a)$ ]]; do
		read -p "Continue (y/n/a)> " continue
	done

	if [[ "$continue" == "a" ]]; then
		printf "No operation performed. Have a nice life\n"
		exit 1
	fi

	if [[ "$continue" == 'n' ]]; then
		skip=1
	fi
}
# <<< HELPER

#>>> ENVIRONMENT
DESTDIR_SCRIPTS=/usr/local/sbin
DESTDIR_SERVICES=/etc/systemd/system
#<<< ENVIRONMENT

install() {
	# >>> SETUP
	systemd &>/dev/null || true
	if [[ $? -ne 0 ]]; then
		printf "Couldn't find systemd. Have a nice life.\n"
	fi
	# <<< SETUP

	# >>> INITIALIZE
	printf "Initializing...\n"
	bash ./scripts/login_iscsi.sh
	bash ./scripts/create_mount_units.sh
	check_exit_code "Failed to create mount units.\n"
	# >>> INITIALIZE

	#prompt "Install iscsi_utils.sh to $DESTDIR_UTILS\n"
	#printf "Installing..."
	#copy_check "./scripts/iscsi_utils.sh" "$DESTDIR_UTILS"
	#printf "Done\n"

	printf "Installing...\n\n"

	prompt "Install login_iscsi.sh to $DESTDIR_SCRIPTS\n"
	if [[ $skip -eq 0 ]]; then
		copy_check "./scripts/login_iscsi.sh" "$DESTDIR_SCRIPTS/login_iscsi"
		printf "Done\n"
	fi

	prompt "Install login_iscsi.service to $DESTDIR_SERVICES\n"
	if [[ $skip -eq 0 ]]; then
		copy_check "./services/login_iscsi.service" "$DESTDIR_SERVICES/"
		printf "Done\n"
	fi

	printf "Reload systemd daemon\n"
	systemctl daemon-reload
	check_exit_code "Failed to load systemd daemon\n\n"

	printf "Enable login_iscsi.service\n"
	systemctl enable login_iscsi.service
	check_exit_code "Failed to enable login_iscsi.service\n\n"
}

uninstall() {
	printf "Uninstalling...\n"

	prompt "Remove login_iscsi from $DESTDIR_SCRIPTS\n"
	if [[ $skip -eq 0 ]]; then
		rm "$DESTDIR_SCRIPTS/login_iscsi"
		printf "Done\n"
	fi

	prompt "Remove login_iscsi.service from $DESTDIR_SERVICES\n"
	if [[ $skip -eq 0 ]]; then
		rm "$DESTDIR_SERVICES/login_iscsi.service"
		printf "Done\n"
	fi

	prompt "Remove mount units from $DESTDIR_SERVICES"
	if [[ $skip -eq 0 ]]; then
		for file in $(find $DESTDIR_SERVICES -name "mnt-*"); do
			prompt "Remove mount unit $(basename $file)\n"
			if [[ $skip -eq 0 ]]; then
				rm $file
			fi
		done
	fi
}
set +u

if [[ "$1" == "install" ]]; then
	install
elif [[ "$1" == "uninstall" ]]; then
	uninstall
else
	printf "Unexpected argument. Expected either 'install' or 'uninstall'\n"
fi
