#!/bin/sh
# vim: set ts=4 sw=4:
set -e

user=$USER
case "$1" in
	-r | --root) user='root'; shift;;
esac

rootfs=$(cd "$(dirname "$0")"/.. && pwd)
oldpwd=$(pwd)
envfile=/tmp/.env.sh

# Pass the job's environment into the chroot. It may contain secrets, so keep
# the file private to the target user and remove it as soon as it's sourced.
(umask 077 && export | sudo tee "$rootfs$envfile" >/dev/null)
sudo chown "$user" "$rootfs$envfile"

exec sudo chroot "$rootfs" \
	/bin/su "$user" \
		/bin/sh -lc ". $envfile; rm -f $envfile; cd '$oldpwd' 2>/dev/null; exec \"\$@\"" -- \
			/bin/sh -eo pipefail "$@"
