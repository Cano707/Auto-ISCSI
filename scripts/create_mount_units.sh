#!bin/bash
set -e

trap "exit 1" SIGINT

# >>> SETUP
: ${DEBUG:=0}
DATE=$(date +"%Y%m%d")
PROG="ISCSI Automount"
PROG_INTERNAL="mount_iscsi"
TOP_PID=##

declare -A targets
: ${mount_dir:='/mnt'}
# <<< SETUP

# >>> SESSION
check_session() {
	set +e
	iscsiadm -m session &>/dev/null
	session=$?
	set -e
}
# <<< SESSION

# >>> RETRIEVE DATA
get_targets() {
	# Returns FQN;DEVICE, e.g. iqn.2005-10.org.freenas.ctl:nas.iscsi;/dev/sdb
	targets=$(lsscsi -td | tr -s ' ' | grep iscsi | cut -d' ' -f3,4 | awk '{ "cut -d, -f1 <<<"$1 | getline target; printf("%s;%s\n", target, $2) }')
	if [[ $DEBUG ]]; then
		printf "Targets retrieved: $targets\n"
	fi
}

match_share_name() {
	share_name=$(echo $1 | python -c 'import sys, re; print(re.search(r":(\w+).",sys.stdin.readline()).group(1))')
}
# >>> RETRIEVE DATA

run_mount() {
	for target in ${targets[@]}; do
		printf "Mounting $target\n"

		#TODO: Scan for partitions
		target_name=$(echo $target | cut -d';' -f1)
		device_name=$(echo $target | cut -d';' -f2)
		printf "Device name: $device_name\n"
		printf "Target name: $target_name\n"

		match_share_name $target_name ":(.+)\.(?=iscsi)"
		printf "Share name: $share_name\n"

		mount_point="/mnt/$share_name"
		unit_name=$(systemd-escape --suffix=mount --path $mount_point)
		unit_file="/etc/systemd/system/$unit_name"
		if [[ -f $unit_file ]]; then
			printf "Mount unit exists: $unit_file. Continue.\n"
			continue
		fi

		mkdir -p $mount_point
		printf "Mount point created: $mount_point\n"

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

		printf "Mount unit created $unit_file with device ${device_name}\n"

		systemctl daemon-reload
		printf "Systemctl daemon reloaded.\n"

		systemctl start "$unit_name"
		printf "Mount unit started.\n"

		printf "%s\n" "$unit_file\n"
	done
}

# ------------- MAIN -------------

check_session
get_targets
run_mount
exit 0
