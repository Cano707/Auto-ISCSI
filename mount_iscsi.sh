#!bin/bash
set -e

trap "exit 1" SIGINT

: ${DEBUG:=0}
DATE=$(date +"%Y%m%d")
PROG="ISCSI Automount"
PROG_INTERNAL="mount_iscsi"
TOP_PID=##
MOUNT_LOGDIR="/var/log/$PROG_INTERNAL"
MOUNT_LOGFILE="$MOUNT_LOGDIR/$DATE"

declare -A targets
: ${mount_dir:='/mnt'}

fatal() {
	echo $1 | logger -t $PROG_INTERNAL
	kill -s SIGINT $TOP_PID
}

log() {
	if [[ $DEBUG ]]; then
		echo $1
	else
		echo $1 | logger -t $PROG_INTERNAL
	fi
}

# >>> HELPER
create_log_file() {
	if [[ ! -d $MOUNT_LOGDIR ]]; then
		mkdir $MOUNT_LOGDIR
	fi
	if [[ ! -f $MOUNT_LOGFILE ]]; then
		touch $MOUNT_LOGFILE
	fi
}

del_logs() {
	log "Clean logs"
	for file in $(find $MOUNT_LOGDIR -mtime +10); do
		rm $file
	done
}

notify() {
	local summary=$1
	local body=$2
	local display=":$(ls /tmp/.X11-unix/* | grep -o "[[:digit:]] ")"
	local user=$(who | grep ":$active_display" | awk '{printf("%s\n", $1)}' | head -n 1)
	local uid=$(id -u $user)
	sudo -u $user DISPLAY=$display DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus notify-send -a "$PROG" -u normal "$summary" "$body"
}
# <<<HELPER

# >>> SESSION
login() {
	timeout 1 iscsiadm -m node --loginall=all
	if [[ $? -ne 0 ]]; then
		echo "A"
		local msg="Login to ISCSI was unsuccessful."
		notify "Failed login" $msg
		fatal "$msg Aborting."
	else
		log Login successful
	fi
}

check_session() {
	iscsiadm -m session &>/dev/null
}

establish_session() {
	set +e
	check_session
	session=$?
	set -e

	if [[ $DEBUG ]]; then
		log "Session request returned $session"
	fi

	if [[ $session -eq 21 ]]; then
		echo No Session
		login
	fi
	log "Session established"
}
# <<< SESSION

# >>> RETRIEVE DATA
get_targets() {
	# Returns FQN;DEVICE, e.g. iqn.2005-10.org.freenas.ctl:nas.iscsi;/dev/sdb
	targets=$(lsscsi -td | tr -s ' ' | grep iscsi | cut -d' ' -f3,4 | awk '{ "cut -d, -f1 <<<"$1 | getline target; printf("%s;%s\n", target, $2) }')
	if [[ $DEBUG ]]; then
		log "Targets retrieved: $targets"
	fi
}

match_share_name() {
	share_name=$(echo $1 | python -c 'import sys, re; print(re.search(r":(\w+).",sys.stdin.readline()).group(1))')
}
# >>> RETRIEVE DATA

run_mount() {
	printf "%s\n" "----------------" >>"$MOUNT_LOGFILE"
	printf "%s\n" "$(date)" >>"$MOUNT_LOGFILE"

	for target in ${targets[@]}; do
		log "Mounting $target"

		#TODO: Scan for partitions
		target_name=$(echo $target | cut -d';' -f1)
		device_name=$(echo $target | cut -d';' -f2)
		log "Device name: $device_name"
		log "Target name: $target_name"

		match_share_name $target_name ":(.+)\.(?=iscsi)"
		log "Share name: $share_name"

		mount_point="/mnt/$share_name"
		unit_name=$(systemd-escape --suffix=mount --path $mount_point)
		unit_file="/etc/systemd/system/$unit_name"
		if [[ -f $unit_file ]]; then
			log "Mount unit exists: $unit_file. Continue."
			continue
		fi

		mkdir -p $mount_point
		log "Mount point created: $mount_point"

		cat <<EOF >"$unit_file"
[Unit]
Description=Mount ISCSI drive $share_name to $mount_point
After=network.target

[Mount]
What=${device_name}1
Where=$mount_point
Type=auto
Options=rw,exec,dev,user,

[Install]
WantedBy=multi-user.target
EOF

		log "Mount unit created $unit_file with device ${device_name}1"

		systemctl daemon-reload
		log "Systemctl daemon reloaded."

		systemctl start "$unit_name"
		log "Mount unit started."

		printf "%s\n" "$unit_file" >>"$MOUNT_LOGFILE"
	done
}

# ------------- MAIN -------------

create_log_file
del_logs
establish_session
sleep 5 # Sleep 5 seconds such that iscsi can finish creating the devices
get_targets
run_mount
