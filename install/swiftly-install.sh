#!/usr/bin/env bash

# swiftly-install
# Script used to install and configure swiftly.
# 
# This script will download the latest released swiftly executable and install it
# to $SWIFTLY_BIN_DIR, or ~/.local/bin if that variable isn't specified.
#
# This script will also create a directory at $SWIFTLY_HOME_DIR, or
# $XDG_DATA_HOME/swiftly if that variable isn't specified. If XDG_DATA_HOME is also unset,
# ~/.local/share/swiftly will be used as a default instead. swiftly will use this directory
# to store platform information, downloaded toolchains, and other state required to manage
# the toolchains.
#
# After installation, the script will create $SWIFTLY_HOME_DIR/env.sh, which can be sourced
# to properly set up the environment variables required to run swiftly. Unless --no-modify-profile
# was specified, the script will also update ~/.profile, ~/.bash_profile, or ~/.zprofile,
# depending on the value of $SHELL and the existence of the files, to source the env.sh file.
# This will ensure that future logins will automatically configure SWIFTLY_HOME_DIR, SWIFTLY_BIN_DIR,
# and PATH.
#
# Unless the --disable-confirmation flag is set, this script will allow the runner to
# configure either of those two directory paths.
#
# curl is required to run this script.

set -o errexit
shopt -s extglob

has_command () {
    command -v "$1" > /dev/null
}

read_input_with_default () {
    echo -n "> "
    read READ_INPUT_RETURN

    if [ -z "$READ_INPUT_RETURN" ]; then
        READ_INPUT_RETURN="$1"
    fi
}

# Replaces the actual path to $HOME at the beginning of the provided string argument with
# the string "$HOME". This is used when printing to stdout.
# e.g. "home/user/.local/bin" => "$HOME/.local/bin"
replace_home_path () {
    if [[ "$1" =~ ^"$HOME"(/|$) ]]; then
        echo "\$HOME${1#$HOME}"
    else
        echo "$1"
    fi
}

# Replaces the string "$HOME" or "~" in the argument with the actual value of $HOME.
# e.g. "$HOME/.local/bin" => "/home/user/.local/bin"
# e.g. "~/.local/bin" => "/home/user/.local/bin"
expand_home_path () {
    echo "${1/#@(~|\$HOME)/$HOME}"
}

# Prints the provided argument using the terminal's bold text effect.
bold () {
    echo "$(tput bold)$1$(tput sgr0)"
}

SWIFTLY_INSTALL_VERSION="0.1.0"

MODIFY_PROFILE="true"

for arg in "$@"; do
    case "$arg" in
        "--help" | "-h")
            cat <<EOF
swiftly-install $SWIFTLY_INSTALL_VERSION
The installer for swiftly.

USAGE:
    swiftly-install [FLAGS]

FLAGS:
    -y, --disable-confirmation  Disable confirmation prompt.
    --no-modify-profile         Do not attempt to modify the profile file to set environment 
                                variables (e.g. PATH) on login.
    -h, --help                  Prints help information.
    --version                   Prints version information.
EOF
            exit 0
            ;;

        "--disable-confirmation" | "-y")
            DISABLE_CONFIRMATION="true"
            ;;

        "--no-modify-profile")
            MODIFY_PROFILE="false"
            ;;

        "--version")
            echo "$SWIFTLY_INSTALL_VERSION"
            exit 0
            ;;

        *)
            echo "Error: unrecognized flag \"$arg\""
            exit 1
            ;;
    esac
done

if ! has_command "curl" ; then
    echo "Error: curl must be installed to download swiftly"
    exit 1
fi

if [[ -f "/etc/os-release" ]]; then
    OS_RELEASE="/etc/os-release"
elif [[ -f "/usr/lib/os-release" ]]; then
    OS_RELEASE="/usr/lib/os-release"
else
    echo "Error: could not detect OS information"
    exit 1
fi

source "$OS_RELEASE"

case "$ID" in
    "amzn")
        if [[ "$VERSION_ID" != "2" ]]; then
            echo "Error: Unsupported Amazon Linux version: $PRETTY_NAME"
            exit 1
        fi
        PLATFORM_NAME="amazonlinux2"
        PLATFORM_NAME_FULL="amazonlinux2"
        ;;

    "ubuntu")
        case "$UBUNTU_CODENAME" in
            "jammy")
                PLATFORM_NAME="ubuntu2204"
                PLATFORM_NAME_FULL="ubuntu22.04"
                ;;

            "focal")
                PLATFORM_NAME="ubuntu2004"
                PLATFORM_NAME_FULL="ubuntu20.04"
                ;;

            "bionic")
                PLATFORM_NAME="ubuntu1804"
                PLATFORM_NAME_FULL="ubuntu18.04"
                ;;

            *)
                echo "Error: Unsupported Ubuntu version: $PRETTY_NAME"
                exit 1
                ;;
        esac
        ;;

    *)
        echo "Error: Unsupported platform: $PRETTY_NAME"
        exit 1
        ;;
esac

RAW_ARCH="$(uname -m)"
case "$RAW_ARCH" in
    "x86_64")
        ARCH="x86_64"
        PLATFORM_ARCH="null"
        ;;

    "aarch64" | "arm64")
        ARCH="aarch64"
        PLATFORM_ARCH='"aarch64"'
        ;;

    *)
        echo "Error: Unsupported CPU architecture: $RAW_ARCH"
        ;;
esac

JSON_OUT=$(cat <<EOF
{
  "platform": {
    "name": "$PLATFORM_NAME",
    "nameFull": "$PLATFORM_NAME_FULL",
    "namePretty": "$PRETTY_NAME",
    "architecture": $PLATFORM_ARCH
  },
  "installedToolchains": [],
  "inUse": null
}
EOF
)

PROFILE_FILE="$HOME/.profile"
case "$SHELL" in
    "*zsh")
        PROFILE_FILE="$HOME/.zprofile"
        ;;
    "*bash")
        if [[ -f "$HOME/.bash_profile" ]]; then
            PROFILE_FILE="$HOME/.bash_profile"
        fi
        ;;
    *)
esac

echo "This script will install swiftly, a Swift toolchain installer and manager."
echo ""

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
DEFAULT_HOME_DIR="$DATA_DIR/swiftly"
HOME_DIR="${SWIFTLY_HOME_DIR:-$DEFAULT_HOME_DIR}"
DEFAULT_BIN_DIR="$HOME/.local/bin"
BIN_DIR="${SWIFTLY_BIN_DIR:-$DEFAULT_BIN_DIR}"

while [ -z "$DISABLE_CONFIRMATION" ]; do
    echo "Current installation options:"
    echo ""
    printf "  %40s: $(bold $(replace_home_path $HOME_DIR))\n" "Data and configuration files directory"
    printf "  %40s: $(bold $(replace_home_path $BIN_DIR))\n" "Executables installation directory"
    printf "  %40s: $(bold $MODIFY_PROFILE)\n" "Modify login config ($(replace_home_path $PROFILE_FILE))"
    echo ""
    echo "Select one of the following:"
    echo "1) Proceed with the installation (default)"
    echo "2) Customize the installation"
    echo "3) Cancel"

    read_input_with_default "1"
    case "$READ_INPUT_RETURN" in
        # Just hitting enter will proceed with the default installation.
        "1" | "1)")
            break
            ;;

        "2" | "2)")
            echo "Enter the swiftly data and configuration files directory (default $(replace_home_path $HOME_DIR)): "
            read_input_with_default "$HOME_DIR"
            HOME_DIR="$(expand_home_path $READ_INPUT_RETURN)"

            echo "Enter the swiftly executables installation directory (default $(replace_home_path $BIN_DIR)): "
            read_input_with_default "$BIN_DIR"
            BIN_DIR="$(expand_home_path $READ_INPUT_RETURN)"

            if [[ "$MODIFY_PROFILE" == "true" ]]; then
                MODIFY_PROFILE_PROMPT="(Y/n)"
            else
                MODIFY_PROFILE_PROMPT="(y/N)"
            fi
            echo "Modify login config ($(replace_home_path $PROFILE_FILE))? $MODIFY_PROFILE_PROMPT"
            read_input_with_default "$MODIFY_PROFILE"

            case "$READ_INPUT_RETURN" in
                "y" | "Y")
                    MODIFY_PROFILE="true"
                ;;

                "n" | "N")
                    MODIFY_PROFILE="false"
                ;;

                *)
                ;;
            esac
            ;;

        *)
            echo "Cancelling installation"
            exit 0
            ;;
    esac
done

if [[ -d "$HOME_DIR" ]]; then
    if [[ "$DISABLE_CONFIRMATION" == "true" ]]; then
        echo "Overwriting existing swiftly installation at $(replace_home_path $HOME_DIR)"
    else
        echo "Existing swiftly installation detected at $(replace_home_path $HOME_DIR), overwrite? (Y/n)"

        while [[ true ]]; do
            read_input_with_default "y"
            case "$READ_INPUT_RETURN" in
                "y" | "Y")
                    break
                ;;

                "n" | "N" | "q")
                    echo "Cancelling installation"
                    exit 0
                ;;

                *)
                    echo "Please input \"y\" or \"n\"."
                    ;;
            esac
        done
    fi

    rm -r $HOME_DIR
fi

mkdir -p $HOME_DIR/toolchains
mkdir -p $BIN_DIR

EXECUTABLE_NAME="swiftly-$ARCH-unknown-linux-gnu"
DOWNLOAD_URL="https://github.com/swift-server/swiftly/releases/latest/download/$EXECUTABLE_NAME"
echo "Downloading swiftly from $DOWNLOAD_URL..."
curl \
    --retry 3 \
    --location \
    --header "Accept: application/octet-stream" \
    "$DOWNLOAD_URL" \
    --output "$BIN_DIR/swiftly"

chmod +x "$BIN_DIR/swiftly"

echo "$JSON_OUT" > "$HOME_DIR/config.json"

# Verify the downloaded executable works. The script will exit if this fails due to errexit.
SWIFTLY_HOME_DIR="$HOME_DIR" SWIFTLY_BIN_DIR="$BIN_DIR" "$BIN_DIR/swiftly" --version > /dev/null

echo ""
echo "swiftly has been succesfully installed!"
echo ""

ENV_OUT=$(cat <<EOF
export SWIFTLY_HOME_DIR="$(replace_home_path $HOME_DIR)"
export SWIFTLY_BIN_DIR="$(replace_home_path $BIN_DIR)"
if [[ ":\$PATH:" != *":\$SWIFTLY_BIN_DIR:"* ]]; then
   export PATH="\$SWIFTLY_BIN_DIR:\$PATH"
fi
EOF
)

echo "$ENV_OUT" > "$HOME_DIR/env.sh"

if [[ "$MODIFY_PROFILE" == "true" ]] && [[ -f "$PROFILE_FILE" ]]; then
    SOURCE_LINE=". $(replace_home_path $HOME_DIR)/env.sh"

    # Only append the line if it isn't in .profile already.
    if [[ ! "$(cat $PROFILE_FILE)" =~ "$SOURCE_LINE" ]]; then
        echo "$SOURCE_LINE" >> "$PROFILE_FILE"
    fi
fi

if ! has_command "swiftly" || [[ "$HOME_DIR" != "$DEFAULT_HOME_DIR" || "$BIN_DIR" != "$DEFAULT_BIN_DIR" ]] ; then
    echo "Once you log in again, swiftly should be accessible from your PATH."
    echo "To begin using swiftly from your current shell, first run the following command:"
    echo ""
    echo "    . $(replace_home_path $HOME_DIR)/env.sh"
    echo ""
    echo "Then to install the latest version of Swift, run 'swiftly install latest'"
else
    echo "To install the latest version of Swift, run 'swiftly install latest'"
fi
