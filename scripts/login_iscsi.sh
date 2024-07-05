#!/bin/bash
set -e

trap "exit 1" SIGINT

# >>> HELPER
log() {
	if [[ $DEBUG ]]; then
		echo $1
	else
		echo $1 | logger -t $PROG_INTERNAL
	fi
}

fatal() {
	echo $1 | tee >(logger -t $PROG_INTERNAL) >(xargs -0 -I{} bash -c 'printf "%s\n" "{}"')
	kill -s SIGINT $TOP_PID
}

notify() {
	local summary=$1
	local body=$2
	local display=":$(ls /tmp/.X11-unix/* | grep -o "[[:digit:]] ")"
	local user=$(who | grep ":$active_display" | awk '{printf("%s\n", $1)}' | head -n 1)
	local uid=$(id -u $user)
	sudo -u $user DISPLAY=$display DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus notify-send -a "$PROG" -u normal "$summary" "$body"
}
# <<< HELPER

# >>> SETUP
: ${DEBUG:=1}
DATE=$(date +"%Y%m%d")
PROG="ISCSI Autologin"
PROG_INTERNAL="login_iscsi"
TOP_PID=##
# <<< SETUP

# >>> SESSION MANAGMENT
login() {
	timeout 1 iscsiadm -m node --loginall=all
	if [[ $? -ne 0 ]]; then
		local msg="Login to ISCSI was unsuccessful."
		notify "Failed login" $msg
		fatal "$msg Aborting."
	else
		log Login successful
	fi
}

check_session() {
	iscsiadm -m session &>/dev/null
	session=$?
}

establish_session() {
	set +e
	check_session
	set -e
	if [[ $DEBUG -ne 0 ]]; then
		log "Session request returned $session"
	fi

	if [[ $session -eq 21 ]]; then
		echo No Session
		login
	fi
	log "Session established"
}
# <<< SESSION MANAGMENT

# >>> MAIN
establish_session
# <<< MAIN
