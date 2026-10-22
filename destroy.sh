#!/usr/bin/env bash
# vim: set ts=4 sw=4:
set -eo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
readonly SCRIPT_DIR

# Kill all processes that have some file opened in the chroot, except this script.
echo 'Terminating remaining processes in the chroot'
if lsof -Fp -p "^$$" "$SCRIPT_DIR" | sed -n 's/^p//p' | xargs -r kill; then
	sleep 1

	if lsof -Fp -p "^$$" "$SCRIPT_DIR" >/dev/null; then
		echo 'Waiting 5 sec for processes to terminate before killing them...'
		sleep 5
		lsof -Fp -p "^$$" "$SCRIPT_DIR" | sed -n 's/^p//p' | xargs -r kill -SIGKILL
	fi
fi

# Unmounts all filesystems under the specified directory tree (deepest first).
# The literal prefix match (with trailing slash) avoids touching sibling
# directories such as "$SCRIPT_DIR-AbC123".
mapfile -t mounts < <(awk -v dir="$SCRIPT_DIR/" 'index($2, dir) == 1 { print $2 }' /proc/mounts | sort -r)

failed=false
for path in "${mounts[@]}"; do
	echo "Unmounting $path"
	umount -fn "$path" || failed=true
done

if $failed; then
	echo "Skipping removal of $SCRIPT_DIR due to previous error(s)" >&2
else
	echo "Removing $SCRIPT_DIR" >&2
	rm -rf --one-file-system "$SCRIPT_DIR"
fi
