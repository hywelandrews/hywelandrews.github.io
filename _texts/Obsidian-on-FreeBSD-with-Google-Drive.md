---
layout: post 
title: "Obsidian on FreeBSD with Google Drive"
author: Hywel
date: 2025-06-28 11:19:42
share: "true"
---
FreeBSD provides a repository for user-space application binaries, which can be managed with [pkg](https://docs.freebsd.org/en/books/handbook/ports/#pkgng-intro) tools. It's a fantastic base of software, and one of the main reasons I choose FreeBSD over say OpenBSD (along with its speed), but there are some caveats; mostly to allow you, the user, the most customisation and to align with the FreeBSD release process.

If you followed [Freebsd for your laptop](/texts/FreeBSD-for-your-laptop) you will have installed the STABLE quarterly release version (as opposed to CURRENT) and therefore are tacked to the quarterly ports repository. This is great for stability, this branch only receives security and hot-fixes and is then sync'd to latest before the release in the next quarter. A desktop system may have essential applications which depend on some of the heaviest and therefore flakiest dependencies in the ports tree however, namely electron. For my development machine, I rely on `sway`, `vscode`, `chromium`, `wifimgr`, `darktable` and `Qalculate`. There have been multiple times when `vscode` has fallen out of the ports tree, and on the last upgrade to FreeBSD 14.2, with it once again gone (and this time for three months until the next cut from latest) it was time to [switch](https://docs.freebsd.org/en/books/handbook/ports/#pkgng-intro) to the latest branch. The updates will come thick and fast, but with careful locking, you can be in a similar position as with quarterly, but always able to fetch fixes and resolutions to fallouts, along with being closer to the latest versions.

The repository configuration file pointing to quarterly is located in `/etc/pkg/FreeBSD.conf`. Copy this file to `/usr/local/etc/pkg/repos/FreeBSD.conf` then edit so that it reflects 

```config
FreeBSD: {
	url: "pkg+http://pkg.FreeBSD.org/${ABI}/latest",
}
```

Creating our own FreeBSD.conf means future OS upgrades won't reset changes made there, as opposed to `/etc/FreeBSD.conf`. Now update the `pkg` repository 

`doas pkg update -f` 

and then upgrade your packages 

`doas pkg upgrade` 

----
##### Gunpowder

But we want to go a step further. We can provide a `pkg` like experience to ports that are not built into the `pkg` binaries repository. For example, there is currently a port of [Obsidian](https://www.freshports.org/textproc/obsidian/), but it's excluded from `pkg` builds due to a EULA; FreeBSD is much stricter than Linux about what it's users are signing up for (but maybe the use of different repositories in the Linux world serves exactly this purpose, and FreeBSD could follow). First lets install `poudriere`, a tool used as part of the ports `pkg` tree infrastructure, handling, build, management and visibility. For our use case, we simply want to provide a local repository with one binary application, `obsidian`.

`doas pkg install poudriere`

We are using ZFS, so configure the pool name in `/usr/local/etc/poudriere.conf` 

Next we need a jail to run our builds, they are typically created per major release per architecture: 

`poudriere jail -c -j 14amd64 -v 14.3-RELEASE`

Finally we setup a ports tree 

`poudriere ports -c -p HEAD -m svn+https`

Now we can build our missing port 

`poudriere bulk -j 14amd64 -p HEAD -b latest -S textproc/obsidian`

Here we are building obsidian in our 14.3 jail for amd64 `-j 14amd64`, using the ports tree attached to the tip of the default branch `-p HEAD`, and using binary packages from the latest branch `-b latest -S` and without rebuilding on dependency changes. These last flags are important to build our package on top of binary instead of from source. Although it is preferred to build from source, as the HEAD of ports and latest branch can still differ, in our case building electron34 and rust dependencies would take 2 days and would not succeed (due to resource constraints).

Finally we need to add our local poudriere repo to our local `pkg` manager

Create the file `/usr/local/etc/pkg/repos/poudriere.conf` with the below contents (assuming the same jail name)

```config
local: {
  url: "file:///usr/local/poudriere/data/packages/14amd64-HEAD",
  enabled: yes
}
```

Finally update your repositories

`pkg update -u`

And you should find obsidien

```bash
$ pkg search obsidian
obsidian-1.8.10_4              Powerful and extensible knowledge base application
```

--- 

#### Where are my files?

I use google drive to sync my obsidian notes between devices (except iOS *\*shakes fist at the clouds*\*) so we need a way to have this mounted after login. Our tool of choice is `rclone` so lets

`pkg install rclone`

Now we need to configure our google drive api keys, using the conveniently supplied `rclone config` command, follow the steps as instructed.

Lets now confirm we can connect to our gdrive instance, I choose to place mounts in `/media/`

`mkdir -p /media/gdrive`

`doas rclone cmount -vvv gdrive: /media/gdrive --allow-other --direct-io --config ~/.config/rclone/rclone.conf --daemon`

Here we are using `cmount` instead of `mount` as we need to go through user-land FUSE drivers. We increase verbosity in case of errors (`-vvv`) tell rclone to use the google drive endpoints (`gdrive:`) and the location of our mount (`/media/gdrive`), ensure users other than root can access files (`--allow-others`) and remove any filesystem caching (`--direct-io`). Finally we specify the config (`--config`) and run rclone as a background process (`--daemon`).

Hopefully you have a working gdrive connection and we can move this into a service to be available after login, just like other platforms. 

In `/usr/local/etc/rc.d` create the script `rclone_gdrive` with the below contents

```bash
#!/bin/sh

# PROVIDE: rclone_gdrive
# REQUIRE: LOGIN
# KEYWORD: shutdown

. /etc/rc.subr

name="rclone_gdrive"
rcvar="rclone_gdrive_enable"

load_rc_config $name

: ${rclone_gdrive_enable:="NO"}
: ${rclone_gdrive_config:="/usr/local/etc/rclone/rclone.conf"}
: ${rclone_gdrive_mount_point:="/media/gdrive"}

pidfile="/var/run/${name}.pid"

start_cmd="${name}_start"
stop_cmd="${name}_stop"
status_cmd="${name}_status"

rclone_gdrive_start()
{
    echo "Starting ${name}."

    command="/usr/local/bin/rclone"
    command_args="cmount -vv gdrive: ${rclone_gdrive_mount_point} --allow-other --direct-io --config ${rclone_gdrive_config} --daemon"

    # Create mount point if it doesn't exist
    if [ ! -d "${rclone_gdrive_mount_point}" ]; then
        mkdir -p "${rclone_gdrive_mount_point}"
    fi

    # Check if already mounted
    if mount | grep -q "${rclone_gdrive_mount_point}"; then
        echo "${name} is already mounted at ${rclone_gdrive_mount_point}"
        return 1
    fi

    # Start rclone mount
    ${command} ${command_args}
    # Save pid from child daemon process (instead of parent process using $>!)
    echo $(pgrep -f "rclone.*${rclone_gdrive_mount_point}") > ${pidfile}

    # Wait a moment and check if mount succeeded
    sleep 2
    if mount | grep -q "${rclone_gdrive_mount_point}"; then
        echo "${name} started successfully."
        return 0
    else
        echo "Failed to start ${name}."
        rm -f ${pidfile}
        return 1
    fi
}

rclone_gdrive_stop()
{
    echo "Stopping ${name}."

    # Unmount the filesystem
    if mount | grep -q "${rclone_gdrive_mount_point}"; then
        umount "${rclone_gdrive_mount_point}"
        if [ $? -eq 0 ]; then
            echo "Unmounted ${rclone_gdrive_mount_point}"
        else
            echo "Failed to unmount ${rclone_gdrive_mount_point}, trying force unmount"
            umount -f "${rclone_gdrive_mount_point}"
        fi
    fi

    # Kill the process if it's still running
    if [ -f ${pidfile} ]; then
        pid=$(cat ${pidfile})
        if kill -0 ${pid} 2>/dev/null; then
            kill ${pid}
            sleep 2
            if kill -0 ${pid} 2>/dev/null; then
                kill -9 ${pid}
            fi
        fi
        rm -f ${pidfile}
    fi

    # Kill any remaining rclone processes for this mount
    pkill -f "rclone.*${rclone_gdrive_mount_point}"

    echo "${name} stopped."
}

rclone_gdrive_status()
{
    if [ -f ${pidfile} ]; then
        pid=$(cat ${pidfile})
        if kill -0 ${pid} 2>/dev/null; then
            echo "${name} is running as pid ${pid}."
        else
            echo "${name} is not running but pidfile exists."
            return 1
        fi
    else
        echo "${name} is not running."
        return 1
    fi

    if mount | grep -q "${rclone_gdrive_mount_point}"; then
        echo "Mount point ${rclone_gdrive_mount_point} is active."
    else
        echo "Mount point ${rclone_gdrive_mount_point} is not mounted."
        return 1
    fi
}

run_rc_command "$1"
```

Add the above service to your `rc.conf`, along with any parameters that need configuring

`sysrc rclone_gdrive_enable=YES`

Next we can start our new service

`service rclone_gdrive start`

Launch obsidian and find our notes.

---

##### Keeping our local repository updated

To provide updates to `pkg` we will need to update our poudriere ports tree

`poudriere ports -u -p HEAD`

And rebuild from our jail as before 

`poudriere bulk -j 14amd64 -p HEAD -b latest -S textproc/obsidian`

At this stage I'm happy with the ease at adding further ports to install alongside regular binaries from latest; moving this to my FreeBSD home server and setting up weekly poudriere repository updates will be the next stage.



