# Swiftly design document

This document contains the high level design of swiftly. Not all features have been implemented yet. Note that this document is subject to change as the implementation progresses.

## Index

- [Linux](#linux)
  - [Installation of swiftly](#installation-of-swiftly)
  - [Installation of a Swift toolchain](#installation-of-a-swift-toolchain)
- [macOS](#macos)
  - [Installation of swiftly](#installation-of-swiftly-1)
  - [Installation of a Swift toolchain](#installation-of-a-swift-toolchain-1)
- [Interface](#interface)
  - [Toolchain names and versions](#toolchain-names-and-versions)
  - [Commands](#commands)
- [Detailed design](#detailed-design)
  - [Implementation sketch - Core](#implementation-sketch---core)
  - [Implementation sketch - Ubuntu 20.04](#implementation-sketch---ubuntu-2004)
  - [Implementation sketch - macOS](#implementation-sketch---macos)
  - [`config.json` schema](#configjson-schema)

## Installation of swiftly

The installation of swiftly is divided into two phases: delivery and initialization. Delivery of the swiftly binary can be accomplished using different methods:

* Shell "one-liner" with a string of commands that can be copy/pasted into the user's shell to securely download from the trusted website and proceed to initialization
* Direct download from a trusted website with guidance on the correct binary for the user's platform to download and then how move on to initialization
* System-level package (e.g. homebrew, pkg, apt-get, rpm) that downloads and places the swiftly binary in a system location outside of the user's home directory, often runnable from the user's path
* Manual compilation of the swiftly binary from this git repository (e.g. from a development environment)

We'll need an initialization phase, which detects information about the OS and distribution in the case of Linux. The initialization mode is also responsible for setting up the directory structure for the toolchains (if necessary), setting up the shell environment for the user, and determining any operating system level dependencies that are required, but missing. Swiftly has its own configuration stored in the form of a `config.json` file, which will be created as part of initialization. None of the delivery methods can perform all of these steps on their own. System package managers don't normally update all users' environment or update the user's home directory structure directly.

Swiftly can perform these tasks itself with the capabilities provided by the Swift language and libraries, such as rich argument parsing, and launching system processes provided that the binary is delivered to the user. The trigger for the initialization is done via an `init` subcommand with some initialization detection for the other subcommands to help guide users who have gone off track.

```
swiftly init
```

Also, the swiftly binary itself is copied into this location if it is not run from a system location, managed by a system package manager. In this case the user is notified that a copy of swiftly has been made in the swiftly bin directory (where the symlinks to the toolchain commands will be managed) so that they can remove the temporary copy that they used to initialize.

## Swiftly upgrade

As part of swiftly's regular operations it can detect that the current configuration is out of date and error out. The `config.json` file contains a version at the moment it was created or last upgraded. In the case of an older version it will direct the user to run init to perform the upgrade. If a downgrade situation is detected then swiflty will fail with an error.

There is also a self-update mechanism that will automate the delivery of the new swiftly binary, verifies it and runs the init subcommand to initiate the upgrade procedure. Note that the self-update will error out without performing any operations if swiftly is installed in the system, outside of the user's home directory.

## Linux

### Installation of a Swift toolchain

A simple setup for managing the toolchains could look like this:

```
~/.local/share/swiftly
   |
   -- toolchains/
   |
   -- config.json
```

The toolchains (i.e. the contents of a given Swift download tarball) would be contained in the toolchains directory, each named according to the major/minor/patch version. `config.json` would contain any required metadata (e.g. the latest Swift version, which toolchain is selected, etc.). If pulling in Foundation to use `JSONEncoder`/`JSONDecoder` (or some other JSON tool) would be a problem, we could also use something simpler.

The `~/.local/bin` directory would include symlinks pointing to the `bin` directory of the "active" toolchain, if any.

This is all very similar to how rustup does things, but I figure there's no need to reinvent the wheel here.

## macOS

### Installation of a Swift toolchain

The contents of `~/.swiftly` would look like this:

```
~/.swiftly

   |
   -- bin/
   |
   -- active-toolchain/
   |
   -- config.json
   |
   – env
```

Instead of downloading tarballs containing the toolchains and storing them directly in `~/.swiftly/toolchains`, we instead install Swift toolchains to `~/Library/Developer/Toolchains` via the `.pkg` files provided for download at swift.org. (Side note: we’ll need to request that other versions than the latest be made available). To select a toolchain for use, we update the symlink at `~/.swiftly/active-toolchain` to point to the desired toolchain in `~/Library/Developer/Toolchains`. In the env file, we’ll contain a line that looks like `export PATH=”$HOME/.swiftly/active-toolchain/usr/bin:$PATH`, so the version of swift being used will automatically always be from the active toolchain. `config.json` will contain version information about the selected toolchain as well as its actual location on disk.

This scheme works for ensuring the version of Swift used on the command line can be controlled, but it doesn’t affect the active toolchain used by Xcode. From what I can tell, there doesn’t seem to be a way to tell Xcode which toolchain to use except through the GUI, which won’t work for us. A possible solution would be to have the active-toolchain symlink live with the rest of the toolchains, and then the user could select it from the GUI (we could name it something like “swiftly Active Toolchain” or something to indicate that it’s managed by swiftly). Alternatively, we could figure out how Xcode selects toolchains and do what it does in swiftly manually.

## Interface

### Toolchain names and versions

Specific toolchains will be referred to via their full version names or snapshot dates. Here are a few examples:

- `5.1.2` refers to the 5.1.2 stable release
- `5.1-snapshot-YYYY-MM-DD` refers to the snapshot release of 5.1 on the given date
- `main-snapshot-YYYY-MM-DD` refers to the main snapshot on the given date

The latest version of a given toolchain can be selected by leaving off the patch version (for releases) or the date (for snapshots). This will allow users to switch to/from releases and snapshots without having to remember specific dates or major/minor/patch combinations. Additionally, the special string “latest” can also be used to refer to the latest installed or available release toolchain.

### Commands

The swiftly cli tool will have seven commands: install, update, uninstall, list, use, available-snapshots, and available-releases.

#### install

##### Install of latest version of Swift

`swiftly install latest`

This will install the latest available stable release of Swift. If the latest version is already installed, a message will be printed indicating so. If the latest minor version is already installed, a message will be printed indicating so and directing the user to `swiftly update latest` to update it if they wish to.

##### Installing a specific release version of Swift

To install a specific version of Swift, the user can provide it. 

If a patch version isn't specified, it’ll install the latest patch version that matches the minor version provided. If a version is already installed that has the same major and minor version, a message will be printed indicating so and directing the user to `swiftly update a.b` if they wish to check for updates. 

If a user specifies a patch version, it will be installed unless that exact version is already installed.

`swiftly install 5.3`

`swiftly install 5.3.1`

##### Installing the latest snapshot from the main

This will install the latest available “main” toolchain. If that toolchain has already been installed, a message indicating so will be printed that indicates so.

`swiftly install main-snapshot`

##### Installing a specific snapshot from the main by date

`swiftly install main-snapshot-2022-1-28`

##### Installing latest snapshot from a swift version development branch

This will install the latest snapshot toolchain associated with the given `a.b` release. If that toolchain has already been installed, a message indicating so will be printed.

`swiftly install 5.5-snapshot`

Installing a specific snapshot from a swift version development branch

`swiftly install 5.5-snapshot-2022-1-28`

#### uninstall

Uninstalling versions of Swift should be in a similar form to install. Uninstalling a toolchain that is currently “in use” (see the “use” command section below) will cause swiftly to use the latest Swift release toolchain that is installed. If none are, the latest snapshot will be used. If no snapshots are installed either, then a message will be printed indicating that all Swift versions are uninstalled.

The user will always be prompted for confirmation before uninstalling any toolchain(s).

##### Uninstall a specific Swift release

To uninstall all toolchains associated with a given minor release, a user can specify just a major/minor version pair. The user will be prompted indicating how many toolchains will be uninstalled and asked for confirmation before proceeding.

`swiftly uninstall 5.3`

To uninstall a specific toolchain, a full major/minor/patch version must be provided:

`swiftly uninstall 5.3.1`

##### Uninstall snapshots

To uninstall all snapshot toolchains associated with a given major/minor version pair a.b, the version “a.b-snapshot” can be provided.

`swiftly uninstall 5.3-snapshot`

Similarly, all “main” snapshot toolchains can be uninstalled by providing “main-snapshot” as the version. 

`swiftly uninstall main-snapshot`

Uninstalling a specific snapshot is also similar to installing:

`swiftly uninstall 5.3-snapshot-2022-01-28`

`swiftly uninstall main-snapshot-2022-01-28`

#### list

To list all the versions of swift installed on your system

`swiftly list`

#### use

“Using” a toolchain sets it as the active toolchain, meaning it will be the one found via $PATH and invoked via `swift` commands executed in the shell. Only a single toolchain can be used at a given time. Using a toolchain doesn’t uninstall anything; it only updates symlinks so that the requested toolchain can be found by the shell. 

To use the toolchain associated with the most up-to-date Swift version, the “latest” version can be specified:

`swiftly use latest`

To use a specific stable version of Swift already installed, specify the major/minor/patch version:

`swiftly use 5.3.1`

To use the latest installed patch version associated with a given major/minor version pair, the patch can be omitted:

`swiftly use 5.3`

To use a specific snapshot version, specify the full snapshot version name:

`swiftly use 5.3-snapshot-YYYY-MM-DD`

To use the latest installed snapshot associated with a given version, the date can be omitted:

`swiftly use 5.3-snapshot`

To use a specific main snapshot, specify the full snapshot version name:

`swiftly use main-snapshot-YYYY-MM-DD`

To use the latest installed main snapshot, leave off the date:

`swiftly use main-snapshot`

#### update

Update replaces a given toolchain with a later version of that toolchain. For a stable release, this means updating to a later patch version. For snapshots, this means updating to the most recently available snapshot. 

If no version is provided, update will update the currently selected toolchain to its latest version while removing the old version. The newly installed version will be used.

`swiftly update`

If the latest version of the currently selected toolchain is already installed, a message will be printed indicating so and asking the user if they’d instead like to uninstall the current toolchain.

To update the latest installed stable version, the “latest” version can be provided:

`swiftly update latest`

To update to the latest patch release of a given major/minor version, only the major/minor pair need to be provided. This will update the latest installed toolchain associated with that major/minor version to the latest patch release for that major/minor version.

`swiftly update 5.3`

You can also specify a full version to update that toolchain to the latest patch available for that major/minor version:

`swiftly update 5.3.1`

Similarly, to update the latest snapshot associated with a specific version, the “a.b-snapshot” version can be supplied:

`swiftly update 5.3-snapshot`

You can also update the latest installed main snapshot to the latest available one by just providing `main-snapshot`:

`swiftly update main-snapshot`

#### list-available

The `list-available` command can be used to list the latest toolchains that Apple has made available to install. This will indicate if updates are available to any already installed toolchains.

`swiftly list-available`

To get a list of releases for a given major version, a version can be supplied:

`swiftly list-available 5`

To get a list of releases for a given `major.minor` version, a version can be supplied:

`swiftly list-available 5.5`

To get a snapshot name for install you can use the pass in a snapshot branch. Below will list all the snapshots available from the main.

`swiftly list-available main-snapshot`

To get a list of snapshots for a swift version development branch use

`swiftly list-available 5.5-snapshot`

#### self-update

This command checks to see if there are new versions of `swiftly` itself and upgrades to them if so.

`swiftly self-update`

## Detailed Design

Swiftly itself will be a SPM project consisting of several executable products, one per supported platform, and all of these will share the core module that handles argument parsing, printing help information, and dispatching commands. Each platform’s executable will be built to statically link the stdlib so that they can be run without having installed Swift first.

Within the core module, the following protocol will be defined:

``` swift
protocol Platform {
    /// The name of the platform as it is used in the Swift download URLs.
    /// For instance, for Ubuntu 16.04 this would return “ubuntu1604”.
    /// For macOS / Xcode, this would return “xcode”. 
    var name: String { get }

    /// A human-readable / pretty-printed version of the platform’s name, used for terminal
    /// output and logging.
    /// For example, “Ubuntu 18.04” would be returned on Ubuntu 18.04.
    var namePretty: String { get }

    /// Downloads a toolchain associated with the given version and returns
    /// a URL pointing to where it was downloaded to, which will be a temporary location.
    /// To get the URL to download from, name() and the provided version can be used.
    ///
    /// This will likely be the same on all platforms, so it’ll either have a default implementation
    /// or be omitted from the actual protocol.
    func download(version: String) async throws -> URL
    
    /// Checks whether the given system dependencies have been installed yet or not.
    /// If not, print a helpful message indicating which ones are missing and how to install them.
    func verifySystemDependencies(_ dependencies: [Dependency])

    /// Installs a toolchain from a file on disk pointed to by the given URL.
    /// After this completes, a user can “use” the toolchain.
    func install(from: URL, version: String) throws

    /// Uninstalls a toolchain associated with the given version.
    /// If this version is in use, the next latest version will be used afterwards.
    func uninstall(version: String) throws

    /// Select the toolchain associated with the given version.
    func use(version: String) throws

    /// List the installed toolchains.
    func listToolchains() -> [Toolchain]

    /// Get a list of snapshot builds for the platform. If a version is specified, only
    /// return snapshots associated with the version.
    /// This will likely have a default implementation.
    func listAvailableSnapshots(version: String? = nil) async -> [Snapshot]

    /// Update swiftly itself, if a new version has been released.
    /// This will likely have a default implementation.
    func selfUpdate() async throws
}
```

Platform specific modules will contain implementations of this protocol, and the core module will use these implementations to install and manage Swift versions.

### Implementation Sketch - Core

#### Argument parsing

We’ll use https://www.swift.org/blog/argument-parser/ to handle most of the effort of implementing the CLI.

#### Installing a toolchain

In the case that the user provides a version number, core first attempts to parse it and ensure its a valid version string. We then resolve it to a full version according to the following table:

| User Input                                | Resolved Version                               | Notes                                                      |
|-------------------------------------------|------------------------------------------------|------------------------------------------------------------|
| `a.b.c`                                   | `a.b.c`                                        | Nothing to do here                                         |
| `a.b`                                     | `a.b.<latest patch version>`                   | Need to do a network lookup to get the patch version       |
| `a.b-snapshot`                            | `a.b-snapshot-<date of latest snapshot>`       | Need to do a network lookup to get the patch version       |
| `a.b-DEVELOPMENT-SNAPSHOT`                | `a-b-snapshot-<date of latest snapshot>`       | Supports parsing for ease of use, needs a network lookup   |
| `a-b-snapshot-YYYY-mm-dd`                 | `a-b-snapshot-YYYY-mm-dd`                      | Nothing to do here                                         |
| `a.b-DEVELOPMENT-SNAPSHOT-YYYY-mm-dd-a`   | `a-b-snapshot-YYYY-mm-dd`                      | swiftly supports parsing formats like this for ease of use |
| `a.b-DEVELOPMENT-SNAPSHOT-YYYY-mm-dd`     | `a-b-snapshot-YYYY-mm-dd`                      | swiftly supports parsing formats like this for ease of use |
| `main-snapshot`                           | `main-snapshot-<date of latest main snapshot>` | Need to do a lookup to get the latest snapshot             |
| `swift-DEVELOPMENT-SNAPSHOT`              | `main-snapshot-<date of latest main snapshot>` | Supports parsing for ease of use, needs a network lookup   |
| `main-snapshot-YYYY-mm-dd`                | `main-snapshot-YYYY-mm-dd`                     | Nothing to do here                                         |
| `swift-DEVELOPMENT-SNAPSHOT-YYYY-mm-dd-a` | `main-snapshot-YYYY-mm-dd`                     | swiftly supports parsing formats like this for ease of use |
| `swift-DEVELOPMENT-SNAPSHOT-YYYY-mm-dd`   | `main-snapshot-YYYY-mm-dd`                     | swiftly supports parsing formats like this for ease of use |

Once we have resolved the version, we first check to see if it has already been installed, and if so, print a message indicating so and return. 

If swiftly determines the toolchain hasn't been installed yet, it will pass the toolchain version to the platform’s `download()` function. See the [Downloading a toolchain](#downloading-a-toolchain) section for more information on the download process. Once the download is complete, the URL of the file on disk is passed to `install()`, which will perform the platform specific installation steps required.

Once the installation completes, if the installed toolchain is the only version of Swift installed by swiftly, the `use()` function will be called to set it as the active one.

Finally, swiftly will then get the toolchain's list of system dependencies, if any. To do this, it can find the list for the specific version being installed on https://github.com/apple/swift-installer-scripts. These lists of dependencies are not present there as of right now, so we'll have to add them. In the future, it's possible that we could bundle such dependency lists within the toolchains themselves. If there are any system dependencies associated with the given version, swiftly will check that each is installed using `verifySystemDependencies()`. If any are not, then a message is printed indicating so and how a user can install them. For more information on how this will be implemented, see [Verifying system dependencies](#verifying-system-dependencies).

#### Verifying system dependencies

In order to run Swift on Linux, there are a number of system dependencies that need to be installed. We could consider having swiftly detect and install these dependencies for the user, but we decided that it was best if it doesn't modify the system outside of handling toolchains in `~/.local/share/swiftly`. Instead, swiftly will just attempt to detect if any required system libraries are missing and, if so, print helpful, platform-specific messages indicating how a user could install them. In the future, swiftly will use an API from swift.org to discover the list of required dependencies per Swift version / platform. Until then, a list will manually be maintained in this repository.

Determining whether the system has these installed or not is a bit of a tricky problem and varies from platform to platform. The mechanism for doing so on each will be as follows:

1. Attempt to use the platforms packaging software (e.g. `dpkg` or `rpm`)
2. If the package can't be found, try to fall back to using `pkg-config` to see if was manually installed
    
If neither of these steps find the package, then we'll consider the dependency as not installed, and print a message that shows users how to install it using the system package manager (e.g. `apt` on Ubuntu).

SPM has some code for detecting system libraries too, so it's possible we could integrate that here instead of using this approach.

#### Downloading a toolchain

To construct the URL, the full (`a.b.c`) version string will be combined with the value returned from `Platform.name()`. For example, the URL for version `a.b.c` would be constructed as follows:

`https://download.swift.org/swift-a.b.c-release/<Platform.name()>/swift-a.b.c-RELEASE/swift-a.b.c-RELEASE-<Platform.name()>.tar.gz`

If a “main-snapshot” version is provided, the URL will contain `swift-DEVELOPMENT-SNAPSHOT-YYYY-MM-DD` in place of `swift-a.b.c-RELEASE`.

If the version provided matches `a.b-snapshot`, then the URL will instead contain `swift-a.b-DEVELOPMENT-SNAPSHOT-YYYY-MM-DD` in place of `swift-a.b.c-RELEASE`.

Once the URL has been constructed, swiftly will use `AsyncHTTPClient` to download the toolchain, whether it be a `.pkg` or tarball, to an arbitrary temporary location. swiftly will print progress information to stdout during this process.

Once the download completes, the hash of the downloaded toolchain will be compared against the checksum provided via swift.org. If that passes, the on-disk URL of the toolchain will be returned.

##### Official swift.org URLs

The future swift.org API that swiftly will use to discover available toolchain versions will also provide the download URLs for those toolchains, obviating the need for swiftly to construct the URLs itself. These URLs could be signed by swift.org, ensuring their authenticity.

#### Using a toolchain

Given a version string `a.b[.c]`, swiftly first checks `config.json` to see if we have a version installed for `a.b[.c]`. If not, print a message indicating so and prompt the user to execute swiftly install `a.b[.c]`. If there is such a version, invoke the use function for the given platform. If the user only provides an `a.b` version string, use the latest installed patch version of the given minor version (e.g. `a.b.2` works fine for `a.b`). If they provide a full `a.b.c`, the installed version must match exactly.

The same process applies for snapshot-style versions.

See the chart in the [Installing a Toolchain](#installing-a-toolchain) section for information on how a version string is resolved to a complete version.

#### Updating a toolchain

Given a version string `a.b[.c]`, swiftly first checks `config.json` to see if we have such a version. If `a.b.c` is provided, we must have that exact version for this check to succeed. If they provide `a.b` only, then the latest installed `a.b.x` version will suffice. If we have determined that a matching version is installed, we then attempt to install the latest patch version of the given `a.b` minor version by passing `a.b` to install() (See [Installing a Toolchain](#installing-a-toolchain) above). If that installation succeeds, the previously latest installed patch of `a.b` is removed.

Given a version string `main-snapshot[-YYYY-MM-DD]` or `a.b-snapshot[-YYYY-MM-DD]`, we perform a similar process: check if a matching version exists already and, if so, pass either `main-snapshot` or `a.b-snapshot` to `install()` respectively. If installation succeeds, remove the latest matching version found before installation.

#### Uninstalling a toolchain

Given a version string `a.b[.c]`, check that we have such a toolchain installed per config.json. If all of `a.b.c` is provided, this must match exactly. If only `a.b` is provided, all `a.b.c` will match and will be uninstalled. Always prompt the user before proceeding with the uninstallation, confirming all of the uninstallations are correct. If a matching version is installed, first delete the entry in `config.json` associated with that version. Then delete the folder in `~/.local/share/swiftly/toolchains` associated with it. If that toolchain was in use, use the installed toolchain with the latest Swift version, if any, per [Using a toolchain](#using-a-toolchain).

Snapshots work similarly. If a date is provided in the snapshot version, attempt to uninstall only that snapshot. Otherwise, attempt to uninstall all matching snapshots after ensuring this is what the user intended.

#### Listing installed toolchains

`config.json` will be read from and the toolchain versions will be printed. One section will contain release versions installed and one section will contain the snapshots. An asterisk will denote the toolchain currently in use.

#### Updating `swiftly` itself

The `self-update` command can be used to update `swiftly`. It will do so by first checking for the latest version via git tags (or some other method if we want). If the currently installed one matches the latest version, nothing is done and a message is printed indicating `swiftly` is already up to date. 

If the tag is a newer version than the installed one, a prompt indicating the new version is available will be printed, asking if the user would like to update to it. If they say yes, then the new version will be downloaded to a temporary directory, and the old `swiftly` binary will be replaced with the new one. On macOS and Linux based systems, swapping out the currently running executable shouldn't be a problem, but if we ever expand `swiftly` to Windows, we'll need to investigate other options here.

### Implementation Sketch - Ubuntu 20.04

#### Verifying system dependencies

`verifySystemDependencies` accepts an array of structs that each provide some info about the dependency, for instance its APT package name and the name of the library to look up with `pkg-config`. For each dependency, swiftly will first attempt to look up the package by issuing the following command:

```
$ dpkg --status libcurl4
```

If the exit code of the previous command was 0, then we know the dependency exists and can return true. If it wasn't, then we call fall back to attempting to locate the library via `pkg-config`:

```
$ pkg-config --exists libcurl
```

Similarly, if the exit code for this invocation is 0, then we can assume the package is installed. If it returns 1 or `pkg-config` itself is not installed, then we'll return false indicating we couldn't find the dependency.

Once this has been performed for all the dependencies, if all of them are installed swiftly will move on to the next stage. Otherwise, it will print a message akin to the following which includes all the missing packages:

```
Some required system dependencies were not detected. You can install them with the following command:
    
    sudo apt-get install libcurl4 libgcc-9-dev
```

#### Downloading and installing a toolchain

`download` accepts a version string like `5.5` and constructs a URL that looks like the following for released versions and downloads it to a temporary directory:

```
https://download.swift.org/swift-5.5.1-release/ubuntu1604/swift-5.5.1-RELEASE/swift-5.5.1-RELEASE-ubuntu16.04.tar.gz
```

`install` accepts a URL pointing to the downloaded `.tar.gz` file and executes the following to install it:

```
$ tar -xf <URL> --directory ~/.local/share/swiftly/toolchains
```

It also updates `config.json` to include this toolchain as the latest for the provided version. If installing a new patch release toolchain, the now-outdated one can be deleted (e.g. `5.5.0` can be deleted when `5.5.1` is installed).

Finally, the use implementation executes the following to update the link:

```
$ ln -s ~/.local/share/swiftly/toolchains/<toolchain>/usr/bin/swift ~/.local/bin/swift
```

It also updates `config.json` to include this version as the currently selected one.

### Implementation Sketch - macOS

`verifySystemDependencies` will only attempt to detect if Xcode is installed. There are no other required dependencies on macOS.

`download` access a URL that looks like the following for released versions:

```
https://download.swift.org/swift-<version>-RELEASE/xcode/swift-<version>-RELEASE/swift-<version>-RELEASE-osx.pkg
```

`install` accepts the URL pointing to the downloaded `.pkg` file and uses `installer` to install it to the user's home directory.

`config.json` is then updated to include this toolchain as the latest for the provided version.

Finally, the use implementation executes the following to update the link:

```
$ ln -s ~/Library/Developer/Toolchains/<toolchain name> ~/.swiftly/active-toolchain
```

It also updates `config.json` to include this version as the currently selected one.

### `config.json` Schema

```
{
  "platform": {
    "namePretty": <OS name pretty printed>,
    "fullName": <OS name used in toolchain file name>,
    "name": <OS name used in toolchain URL path>
  } 
  "inUse": "version string",
  "installedToolchains": [
     <toolchain name>,
     <toolchain name>
  ]
}
```
