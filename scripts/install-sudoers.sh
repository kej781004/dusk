#!/bin/sh
# Grants Dusk permission to flip the two pmset settings it owns without a
# password prompt.
#
# `disablesleep` is the only reliable way to stop a closed lid from sleeping the
# Mac, and `lowpowermode` has no unprivileged API either — both live in a
# root-owned plist, so `pmset` has to run as root. Rather than asking for a
# password on every click, this installs a sudoers rule listing four exact
# commands. No wildcards: the rule cannot be stretched into running anything else.
#
# Run as root:  sudo sh install-sudoers.sh
# Undo:         sudo rm /etc/sudoers.d/dusk

set -eu

TARGET=/etc/sudoers.d/dusk

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root: sudo sh $0" >&2
    exit 1
fi

# SUDO_USER is the account that invoked sudo; that is who needs the grant, not root.
OWNER="${SUDO_USER:-$(stat -f '%Su' /dev/console)}"
if [ -z "$OWNER" ] || [ "$OWNER" = "root" ]; then
    echo "could not tell which user to grant this to" >&2
    exit 1
fi

STAGE="$(mktemp -t dusk-sudoers)"
trap 'rm -f "$STAGE"' EXIT

cat > "$STAGE" <<EOF
# Installed by Dusk (menu bar app).
# Allows only these four exact commands, so the switches work without a
# password. Remove with: sudo rm $TARGET
$OWNER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0
$OWNER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1
$OWNER ALL=(root) NOPASSWD: /usr/bin/pmset -a lowpowermode 0
$OWNER ALL=(root) NOPASSWD: /usr/bin/pmset -a lowpowermode 1
EOF

# A malformed file in sudoers.d breaks sudo for everything, so never install one
# that visudo has not accepted.
visudo -c -f "$STAGE" >/dev/null

install -m 440 -o root -g wheel "$STAGE" "$TARGET"
echo "installed $TARGET for $OWNER"
