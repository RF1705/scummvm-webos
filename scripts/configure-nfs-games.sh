#!/bin/sh
set -eu

app_id=org.scummvm.scummvm
config_file=/var/lib/webosbrew/scummvm-nfs.conf
hook_file=/var/lib/webosbrew/init.d/scummvm-nfs
mount_point=/media/internal/scummvm-games
jail_mount=/var/palm/jail/$app_id/media/internal/scummvm-games
pid_file=/tmp/scummvm-nfs-watcher.pid
log_file=/tmp/scummvm-nfs.log

is_mounted() {
	mountpoint -q "$1"
}

load_config() {
	if [ ! -r "$config_file" ]; then
		echo "Missing $config_file" >&2
		exit 1
	fi
	# The configuration is generated below after strict character validation.
	. "$config_file"
}

mount_share() {
	mkdir -p "$mount_point"
	if ! is_mounted "$mount_point"; then
		mount -t nfs -o "$NFS_OPTIONS" "$NFS_SOURCE" "$mount_point"
	fi
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

run_hook() {
	load_config

	tries=0
	until mount_share; do
		tries=$((tries + 1))
		if [ "$tries" -ge 30 ]; then
			echo "NFS mount failed after $tries attempts" >&2
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

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
	echo "Usage: $0 SERVER EXPORT [NFS_VERSION]" >&2
	echo "Example: $0 192.168.3.20 /volume1/ScummVM 3" >&2
	exit 2
fi

server=$1
export_path=$2
nfs_version=${3:-3}

case "$server" in
	*[!A-Za-z0-9._-]*|'')
		echo "Invalid NFS server name: $server" >&2
		exit 2
		;;
esac
case "$export_path" in
	/*)
		;;
	*)
		echo "The NFS export must be an absolute path." >&2
		exit 2
		;;
esac
case "$export_path" in
	*[!A-Za-z0-9._/-]*)
		echo "The NFS export contains unsupported characters." >&2
		exit 2
		;;
esac
case "$nfs_version" in
	3|4)
		;;
	*)
		echo "NFS version must be 3 or 4." >&2
		exit 2
		;;
esac

mkdir -p /var/lib/webosbrew/init.d
install -m 0755 "$0" "$hook_file"
{
	printf 'NFS_SOURCE=%s:%s\n' "$server" "$export_path"
	printf 'NFS_OPTIONS=ro,tcp,nolock,vers=%s,timeo=20,retrans=2\n' "$nfs_version"
} > "$config_file"
chmod 0600 "$config_file"

"$hook_file" --run
echo "NFS games mounted at $mount_point"
