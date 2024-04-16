#!bin/bash
trap "exit 1" SIGINT

PROG="mount_iscsi"
TOP_PID=##

function fatal {
	echo $1
	kill -s SIGINT $TOP_PID
}

declare -A targets
: ${session:=''}
: ${mount_dir:='/mnt'}
#devices=""

function log {
	echo $1 | logger -t ABACKUP
}

function login {
	iscsiadm -m node --loginall=all
	if [[ $? -ne 0 ]]; then
		fatal Login was unsuccesful. Aborting.
	else
		log Login successful
	fi
}

function check_session {
	session=$(sudo iscsiadm -m session 2>&1)
}

function establish_session {
	check_session

	# If no session is active, log in
	if [[ x$session == x"iscsiadm: No active sessions." ]]; then
		echo No Session
		echo Logging in...
		login
	fi
	echo "Session established"
}

function get_devices {
	targets=$(lsscsi -td | tr -s ' ' | grep iscsi | cut -d' ' -f3,4 | awk '{ "cut -d, -f1 <<<"$1 | getline target; printf("%s;%s\n", target, $2) }')
}

function match_share_name {
	share_name=$(echo $1 | perl -ne '/:(.+)\.(?=iscsi)/ && print $1')
}

function check_mounted_dir {
	echo "Check if $1 is mount point"
	mount | awk -v dir="$1" '
    BEGIN {
        print "Starting check for:", dir
    }
    {
        gsub(/^[ \t]+|[ \t]+$/, "", dir)
        if ($3 == "/mnt/"dir) {
            exit 0;
        }
    }
    ENDFILE {
        print "Mount point not found for:", dir
        exit 1;
    }' >/dev/null 2>&1
	is_mounted=$?
	echo "$1 is mounted: $is_mounted"
	echo
}

function run_mount {
	for target in ${targets[@]}; do
		echo '[i] Performing on ' $target
		target_name=$(echo $target | cut -d';' -f1)
		device_name=$(echo $target | cut -d';' -f2)
		echo '[i] Device name ' $device_name
		echo '[i] Target name ' $target_name
		match_share_name $target_name ":(.+)\.(?=iscsi)"
		echo '[i] Share name ' $share_name
		if [[ -d '/mnt/'$share_name ]]; then
			echo "[i] Mount dir /mnt/$share_name exists."
			check_mounted_dir $share_name
			if [[ $is_mounted -eq 0 ]]; then
				echo "[i] $target_name is already mounted on /mnt/$share_name"
				echo "[i] Skip $share_name"
				continue
			fi
		else
			echo "Create mount dir /mnt/$share_name"
			mkdir /mnt/$share_name
			if [[ $? -ne 0 ]]; then
				fatal "Failed to create mount dir '/mnt/$share_name'"
			fi
		fi

		# mount to directory
		echo "Mount $share_name on $device_name to /mnt/$share_name"
		mount ${device_name}1 /mnt/$share_name
		echo
	done
}

# ------------- MAIN -------------

establish_session
sleep 5 # Sleep 5 seconds such that iscsi can finish creating the devices
get_devices
run_mount
