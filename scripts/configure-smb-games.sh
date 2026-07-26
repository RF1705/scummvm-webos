#!/bin/sh
set -eu

app_id=org.scummvm.scummvm
install_dir=/var/lib/webosbrew/bin
rclone_bin=$install_dir/rclone-smb
rclone_config=/var/lib/webosbrew/rclone-smb.conf
mount_config=/var/lib/webosbrew/scummvm-smb.conf
hook_file=/var/lib/webosbrew/init.d/scummvm-smb
mount_point=/media/internal/scummvm-games
jail_mount=/var/palm/jail/$app_id/media/internal/scummvm-games
pid_file=/tmp/scummvm-smb-watcher.pid
log_file=/tmp/scummvm-smb.log

is_mounted() {
	mountpoint -q "$1"
}

read_setting() {
	sed -n "s/^$1=//p" "$mount_config" | sed -n '1p'
}

watch_jail() {
	trap 'rm -f "$pid_file"' EXIT
	echo "$$" > "$pid_file"

	while :; do
		scummvm_pid=$(pidof scummvm.bin 2>/dev/null | awk '{print $1}')
		if [ -n "$scummvm_pid" ] && is_mounted "$mount_point"; then
			mkdir -p "$jail_mount"
			if ! is_mounted "$jail_mount"; then
				mount --bind "$mount_point" "$jail_mount"
				mount -o remount,bind,ro "$jail_mount"
			fi
		elif is_mounted "$jail_mount"; then
			umount "$jail_mount" || true
		fi
		sleep 2
	done
}

mount_share() {
	remote=$(read_setting SMB_REMOTE)
	if [ -z "$remote" ]; then
		echo "Missing SMB_REMOTE in $mount_config" >&2
		return 1
	fi

	mkdir -p "$mount_point"
	if is_mounted "$mount_point"; then
		return 0
	fi

	"$rclone_bin" mount "fritzbox:$remote" "$mount_point" \
		--config "$rclone_config" \
		--daemon \
		--daemon-wait 20s \
		--read-only \
		--allow-other \
		--uid 5118 \
		--gid 5000 \
		--dir-perms 0555 \
		--file-perms 0444 \
		--buffer-size 4M \
		--vfs-cache-mode off \
		--vfs-read-chunk-size 4M \
		--vfs-read-chunk-size-limit 32M \
		--dir-cache-time 1m \
		--log-file "$log_file" \
		--log-level INFO
}

run_hook() {
	if [ ! -x "$rclone_bin" ] || [ ! -r "$rclone_config" ] ||
	   [ ! -r "$mount_config" ]; then
		echo "SMB helper is not configured." >&2
		exit 1
	fi

	tries=0
	until mount_share; do
		tries=$((tries + 1))
		if [ "$tries" -ge 30 ]; then
			echo "SMB mount failed after $tries attempts" >&2
			exit 1
		fi
		sleep 2
	done

	if [ -r "$pid_file" ] && kill -0 "$(sed -n '1p' "$pid_file")" 2>/dev/null; then
		exit 0
	fi
	watch_jail >> "$log_file" 2>&1 &
}

if [ "$(id -u)" -ne 0 ]; then
	echo "Run this script as root on the TV." >&2
	exit 1
fi

if [ "${1-}" = "--run" ] || [ "$#" -eq 0 ]; then
	run_hook
	exit 0
fi

if [ "$#" -ne 3 ]; then
	echo "Usage: $0 SERVER SHARE_OR_PATH USER" >&2
	echo "Example: $0 fritz.box FRITZ.NAS/ScummVM scummvm" >&2
	exit 2
fi

server=$1
remote=$2
user=$3

case "$server" in
	*[!A-Za-z0-9._-]*|'')
		echo "Invalid SMB server name: $server" >&2
		exit 2
		;;
esac
case "$remote" in
	/*|''|*[!A-Za-z0-9._/-]*)
		echo "Invalid SMB share/path: $remote" >&2
		exit 2
		;;
esac
case "$user" in
	*[!A-Za-z0-9._@+-]*|'')
		echo "Invalid SMB user name." >&2
		exit 2
		;;
esac

source_bin=${RCLONE_SMB_BIN:-$(dirname "$0")/rclone-smb}
if [ ! -x "$source_bin" ]; then
	echo "Place the ARMv7 rclone-smb binary next to this script or set RCLONE_SMB_BIN." >&2
	exit 1
fi

printf 'FRITZ!Box password for %s: ' "$user" >&2
stty -echo
trap 'stty echo' EXIT HUP INT TERM
IFS= read -r password
stty echo
trap - EXIT HUP INT TERM
printf '\n' >&2

obscured_password=$("$source_bin" obscure "$password")
unset password

mkdir -p "$install_dir" /var/lib/webosbrew/init.d
install -m 0755 "$source_bin" "$rclone_bin"
install -m 0755 "$0" "$hook_file"
{
	printf '[fritzbox]\n'
	printf 'type = smb\n'
	printf 'host = %s\n' "$server"
	printf 'user = %s\n' "$user"
	printf 'pass = %s\n' "$obscured_password"
	printf 'domain = WORKGROUP\n'
} > "$rclone_config"
printf 'SMB_REMOTE=%s\n' "$remote" > "$mount_config"
chmod 0600 "$rclone_config" "$mount_config"

"$rclone_bin" lsd "fritzbox:$remote" \
	--config "$rclone_config" \
	--max-depth 1 >/dev/null
"$hook_file" --run

echo "FRITZ!NAS games mounted read-only at $mount_point"
