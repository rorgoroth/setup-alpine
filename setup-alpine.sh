#!/usr/bin/env bash
# vim: set ts=4 sw=4:
#
# Sets up an Alpine Linux edge (x86_64) chroot. Must be run via sudo.
#
# Required environment variables:
# - INPUT_APK_TOOLS_URL
# - INPUT_EXTRA_KEYS
# - INPUT_EXTRA_REPOSITORIES
# - INPUT_MIRROR_URL
# - INPUT_PACKAGES
# - INPUT_SHELL_NAME
# - INPUT_VOLUMES
#
set -Eeuo pipefail

SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
readonly SCRIPT_PATH SCRIPT_DIR

readonly ALPINE_BRANCH='edge'
readonly ALPINE_ARCH='x86_64'
readonly ALPINE_BASE_PKGS='alpine-baselayout apk-tools busybox busybox-suid musl-utils'

: "${SUDO_USER:?must be run via sudo}"
RUNNER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
readonly RUNNER_HOME
readonly ROOTFS_BASE_DIR="$RUNNER_HOME/rootfs"
# The runner's work directory (e.g. /home/runner/work) containing the workspace.
WORK_DIR=$(dirname "${RUNNER_WORKSPACE:?}")
readonly WORK_DIR


err_handler() {
	local lno=$1
	set +e

	# Print error line with 4 lines before/after.
	awk -v LINENO="$lno" -v RED="\033[1;31m" -v RESET="\033[0m" '
		BEGIN { print "\n" RED "Error occurred at line " LINENO ":" RESET }
		NR > LINENO - 4 && NR < LINENO + 4 {
			pad = length(LINENO + 4); err = NR == LINENO
			printf "%s %" pad "d | %s%s\n", (err ? RED ">" : " "), NR, $0, (err ? RESET : "")
		}' "$SCRIPT_PATH"
	line=$(awk -v LINENO="$lno" 'NR == LINENO { print $0 }' "$SCRIPT_PATH")

	die "${_current_group:-"Error"}" \
	    "Error occurred at line $lno: $line (see the job log for more information)"
}
trap 'err_handler $LINENO' ERR


#=======================  F u n c t i o n s  =======================#

die() {
	local title=$1
	local msg=$2

	printf '::error title=setup-alpine: %s::%s\n' "$title" "$msg"
	exit 1
}

info() {
	printf '▷ %s\n' "$@"
}

# Creates an expandable group in the log with title $1.
group() {
	[ "${_current_group:-}" ] && endgroup

	printf '::group::%s\n' "$*"
	_current_group="$*"
}

# Closes the expandable group in the log.
endgroup() {
	echo '::endgroup::'
}

# Prints each whitespace-separated word of $1 on its own line (no glob expansion,
# nothing printed for an empty list).
words() {
	( set -f; for word in $1; do printf '%s\n' "$word"; done )
}

# Returns the pinned apk.static URL.
auto_apk_tools_url() {
	echo 'https://github.com/rorgoroth/setup-alpine/releases/download/apk.static-3.0.8/apk.static#!sha256!9c16dbcc6328da9c62906c6ba27f96a228b09327230ef7febea694ff15fc942d'
}

# Downloads a file from URL $1 to path $2 and verify its integrity.
# URL must end with '#!sha256!' followed by a SHA-256 checksum of the file.
download_file() {
	local url=${1%\#*}  # strips '#' and everything after
	local sha256=${1##*\#\!sha256\!}  # strips '#!sha256!' and everything before
	local filepath=$2

	[ -f "$filepath" ] \
		&& sha256_check "$filepath" "$sha256" >/dev/null 2>&1 \
		&& return 0

	mkdir -p "$(dirname "$filepath")" \
		&& curl --connect-timeout 10 --retry 3 --retry-all-errors -fsSL -o "$filepath" "$url" \
		&& sha256_check "$filepath" "$sha256"
}

# Checks SHA-256 checksum $2 of the given file $1.
sha256_check() {
	local filepath=$1
	local sha256=$2

	(cd "$(dirname "$filepath")" \
		&& echo "$sha256  ${filepath##*/}" | sha256sum -c)
}

# Binds the directory $1 at the mountpoint $2 and sets propagation to private.
mount_bind() {
	local src=$1
	local dir=$2

	mkdir -p "$dir"
	mount -v --rbind "$src" "$dir"
	mount --make-rprivate "$dir"
}


#============================  M a i n  ============================#

if [ "$(uname -m)" != "$ALPINE_ARCH" ]; then
	die 'Unsupported host' \
	    "Only $ALPINE_ARCH hosts are supported, but this one is $(uname -m)."
fi

if [ "$INPUT_APK_TOOLS_URL" = auto ]; then
	INPUT_APK_TOOLS_URL="$(auto_apk_tools_url)"
fi

case "$INPUT_APK_TOOLS_URL" in
	https://*\#\!sha256\!* | http://*\#\!sha256\!*) ;;  # valid
	*) die 'Invalid input parameter: apk-tools-url' \
	       "The value must start with https:// or http:// and end with '#!sha256!' followed by a SHA-256 hash of the file to be downloaded, but got: $INPUT_APK_TOOLS_URL"
esac

mapfile -t extra_keys < <(words "$INPUT_EXTRA_KEYS")
mapfile -t extra_repos < <(words "$INPUT_EXTRA_REPOSITORIES")
mapfile -t packages < <(words "$INPUT_PACKAGES")
mapfile -t volumes < <(words "$INPUT_VOLUMES")

for path in ${extra_keys[@]+"${extra_keys[@]}"}; do
	if ! [ -r "$GITHUB_WORKSPACE/$path" ]; then
		die 'Invalid input parameter: extra-keys' \
		    "File does not exist in workspace or is not readable: $path."
	fi
done

if ! [[ $INPUT_SHELL_NAME =~ ^[a-zA-Z][a-zA-Z0-9_.~+@%-]*$ ]]; then
	die 'Invalid input parameter: shell-name' \
	    "Expected value matching regex ^[a-zA-Z][a-zA-Z0-9_.~+@%-]*$, but got: $INPUT_SHELL_NAME."
fi


#-----------------------------------------------------------------------
group 'Prepare rootfs directory'

rootfs_dir="$ROOTFS_BASE_DIR/alpine-$ALPINE_BRANCH"
if [ -e "$rootfs_dir" ]; then
	mkdir -p "$ROOTFS_BASE_DIR"
	rootfs_dir=$(mktemp -d "$rootfs_dir-XXXXXX")
	chmod 755 "$rootfs_dir"
else
	mkdir -p "$rootfs_dir"
fi
info "Alpine will be installed into: $rootfs_dir"

# Register the rootfs for cleanup right away, so the post step can unmount
# and remove it even when the setup fails half way through.
install -Dv -m755 "$SCRIPT_DIR"/destroy.sh "$rootfs_dir"/destroy.sh
if [ "${GITHUB_STATE:-}" ]; then
	echo "root_path=$rootfs_dir" >> "$GITHUB_STATE"
fi

cd "$RUNNER_TEMP"


#-----------------------------------------------------------------------
group 'Download static apk-tools'

APK="$RUNNER_TEMP/apk"

info "Downloading ${INPUT_APK_TOOLS_URL%\#*}"
download_file "$INPUT_APK_TOOLS_URL" "$APK"
chmod +x "$APK"


#-----------------------------------------------------------------------
group "Initialize Alpine Linux $ALPINE_BRANCH ($ALPINE_ARCH)"

cd "$rootfs_dir"

info 'Creating /etc/apk/repositories:'
mkdir -p etc/apk
printf '%s\n' \
	"$INPUT_MIRROR_URL/$ALPINE_BRANCH/main" \
	"$INPUT_MIRROR_URL/$ALPINE_BRANCH/community" \
	${extra_repos[@]+"${extra_repos[@]}"} \
	| tee etc/apk/repositories

mkdir -p etc/apk/keys
install -m644 -t etc/apk/keys "$SCRIPT_DIR"/keys/*.pub

for path in ${extra_keys[@]+"${extra_keys[@]}"}; do
	cp "$GITHUB_WORKSPACE/$path" etc/apk/keys/
done

cat /etc/resolv.conf > etc/resolv.conf

info "Installing base packages into $(pwd)"
# shellcheck disable=SC2086  # ALPINE_BASE_PKGS is a word list
$APK add \
	--root . \
	--initdb \
	--no-progress \
	--update-cache \
	--arch "$ALPINE_ARCH" \
	$ALPINE_BASE_PKGS alpine-release


#-----------------------------------------------------------------------
group 'Bind filesystems into chroot'

mkdir -p proc
mount -v -t proc none proc
mount_bind /dev dev
mount_bind /sys sys
mount_bind "$WORK_DIR" "${WORK_DIR#/}"

# Some systems (Ubuntu?) symlinks /dev/shm to /run/shm.
if [ -L /dev/shm ] && [ -d /run/shm ]; then
	mount_bind /run/shm run/shm
fi

for vol in ${volumes[@]+"${volumes[@]}"}; do
	src=${vol%%:*}
	dst=${vol#*:}

	mount_bind "$src" "${dst#/}"
done


#-----------------------------------------------------------------------
group 'Copy action scripts'

install -Dv -m755 "$SCRIPT_DIR"/alpine.sh abin/"$INPUT_SHELL_NAME"


#-----------------------------------------------------------------------
if [ ${#packages[@]} -gt 0 ]; then
	group 'Install packages'

	pkgs="${packages[*]}"
	cat > .setup.sh <<-SHELL
		echo '▷ Installing $pkgs'
		apk add --update-cache $pkgs
	SHELL
	abin/"$INPUT_SHELL_NAME" --root /.setup.sh
fi


#-----------------------------------------------------------------------
group "Set up user $SUDO_USER"

cat > .setup.sh <<-SHELL
	echo '▷ Creating user $SUDO_USER with uid ${SUDO_UID:-1000}'
	adduser -u '${SUDO_UID:-1000}' -G users -s /bin/sh -D '$SUDO_USER'

	if [ -d /etc/sudoers.d ]; then
		echo '▷ Adding sudo rule:'
		echo '$SUDO_USER ALL=(ALL) NOPASSWD: ALL' | tee '/etc/sudoers.d/$SUDO_USER'
		chmod 440 '/etc/sudoers.d/$SUDO_USER'
	fi
	if [ -d /etc/doas.d ]; then
		echo '▷ Adding doas rule:'
		echo 'permit nopass keepenv $SUDO_USER' | tee '/etc/doas.d/$SUDO_USER.conf'
	fi
SHELL
abin/"$INPUT_SHELL_NAME" --root /.setup.sh

rm .setup.sh
endgroup
#-----------------------------------------------------------------------

echo "root-path=$rootfs_dir" >> "$GITHUB_OUTPUT"
echo "$rootfs_dir/abin" >> "$GITHUB_PATH"
