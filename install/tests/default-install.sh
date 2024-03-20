#!/usr/bin/env bash

# Tests that an unconfigured installation works properly.
# WARNING: this test makes changes to the local filesystem and is intended to be run in a containerized environment.

set -o errexit
source ./test-util.sh

cp "$HOME/.profile" "$HOME/.profile.bak"

cleanup () {
    set +o errexit

    mv "$HOME/.profile.bak" "$HOME/.profile"

    if has_command "swiftly" ; then
       swiftly uninstall -y latest > /dev/null
    fi

    rm -r "$HOME/.local/share/swiftly"
    rm "$HOME/.local/bin/swiftly"
}
trap cleanup EXIT

case "$(get_os)" in
    "ubuntu1804")
        system_deps=(binutils
                     git
                     libc6-dev
                     libcurl4-openssl-dev
                     libedit2
                     libgcc-5-dev
                     libpython3.6
                     libstdc++-5-dev
                     libxml2-dev
                     pkg-config
                     tzdata
                     zip
                     zlib1g-dev)
        ;;

    "ubuntu2004")
        system_deps=(binutils
                     git
                     gnupg2
                     libc6-dev
                     libcurl4-openssl-dev
                     libedit2
                     libgcc-9-dev
                     libpython3.8
                     libstdc++-9-dev
                     libxml2-dev
                     libz3-dev
                     pkg-config
                     tzdata
                     zip
                     zlib1g-dev)
        ;;

    "ubuntu2204")
        system_deps=(binutils
                     git
                     gnupg2
                     libc6-dev
                     libcurl4-openssl-dev
                     libedit2
                     libgcc-11-dev
                     libpython3-dev
                     libstdc++-11-dev
                     libxml2-dev
                     libz3-dev
                     pkg-config
                     tzdata
                     zip
                     zlib1g-dev)
        ;;

    "amazonlinux2")
        system_deps=(binutils
                     gcc
                     git
                     glibc-static
                     libcurl-devel
                     libedit
                     libicu
                     libxml2-devel
                     tar
                     unzip
                     zip
                     zlib-devel)
        ;;

    "rhel-ubi9")
        system_deps=(git
                     gcc-c++
                     libcurl-devel
                     libedit-devel
                     libuuid-devel
                     libxml2-devel
                     ncurses-devel
                     python3-devel
                     rsync
                     sqlite-devel
                     unzip
                     zip)
        ;;

    *)
        echo "Unrecognized platform"
        exit 1
        ;;
esac

if has_command apt-get ; then
    apt-get update
    apt-get remove -y "${system_deps[@]}"
elif has_command yum ; then
    yum remove -y "${system_deps[@]}"
fi

printf "1\n" | ./swiftly-install.sh

# .profile should be updated to update PATH.
bash --login -c "swiftly --version"

. "$HOME/.local/share/swiftly/env.sh"

if ! has_command "swiftly" ; then
    test_fail "Can't find swiftly on the PATH"
fi

if [[ ! -d "$HOME/.local/share/swiftly/toolchains" ]]; then
    test_fail "the toolchains directory was not created in SWIFTLY_HOME_DIR"
fi

echo "Verifying system dependencies were installed..."
for dep in "${system_deps[@]}"; do
    if has_command dpkg ; then
        if ! dpkg --status "$dep" > /dev/null ; then
            test_fail "System dependency $dep was not installed properly"
        fi
    elif has_command rpm ; then
        if ! rpm -q "$dep" > /dev/null ; then
            test_fail "System dependency $dep was not installed properly"
        fi
    fi
    echo "System dependency $dep was installed successfully"
done


if ! gpg --list-keys Swift ; then
    test_fail "Swift PGP keys were not installed by default."
fi

swiftly install latest

swift --version

test_pass
