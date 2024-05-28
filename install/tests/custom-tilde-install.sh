#!/usr/bin/env bash

# Tests that custom install paths that include the "~" character are expanded properly.
# WARNING: this test makes changes to the local filesystem and is intended to be run in a containerized environment.

set -o errexit
source ./test-util.sh

export CUSTOM_HOME_DIR_NAME="tilde-substitution-test-home"
export CUSTOM_HOME_DIR="$HOME/$CUSTOM_HOME_DIR_NAME"
export CUSTOM_BIN_DIR="$CUSTOM_HOME_DIR/bin"

touch "$HOME/.profile"
cp "$HOME/.profile" "$HOME/.profile.bak"

cleanup () {
    rm -r "$CUSTOM_HOME_DIR"
    mv "$HOME/.profile.bak" "$HOME/.profile"
}
trap cleanup EXIT

# Swiftly needs these things at a minimum and will abort telling the user
#  if they are missing.
if has_command apt-get ; then
    apt-get update
    apt-get install -y ca-certificates gpg # These are needed for swiftly
elif has_command yum ; then
    yum install -y ca-certificates gpg # These are needed for swiftly to function
fi

# Make sure that the "~" character is handled properly.
printf "1\n" | SWIFTLY_HOME_DIR=~/"${CUSTOM_HOME_DIR_NAME}" SWIFTLY_BIN_DIR=~/"${CUSTOM_HOME_DIR_NAME}/bin" $(get_swiftly) list

# .profile should be updated to update PATH and SWIFTLY_HOME_DIR/SWIFTLY_BIN_DIR.
bash --login -c "swiftly --version"

. "$CUSTOM_HOME_DIR/env.sh"

if ! has_command "swiftly" ; then
    test_fail "Can't find swiftly on the PATH"
fi

if [[ "$SWIFTLY_HOME_DIR" != "$CUSTOM_HOME_DIR" ]]; then
    test_fail "SWIFTLY_HOME_DIR ($SWIFTLY_HOME_DIR) did not equal $CUSTOM_HOME_DIR"
fi

if [[ "$SWIFTLY_BIN_DIR" != "$CUSTOM_BIN_DIR" ]]; then
    test_fail "SWIFTLY_BIN_DIR ($SWIFTLY_BIN_DIR) did not equal $CUSTOM_BIN_DIR"
fi

if [[ ! -d "$CUSTOM_HOME_DIR/toolchains" ]]; then
    test_fail "the toolchains directory was not created in SWIFTLY_HOME_DIR"
fi

test_pass
