---
layout: post
title: FreeBSD for your laptop 
author: Hywel
date:   2024-03-03 11:13:42 
---

The last time I ran FreeBSD on a personal system was with version 4 and in the intervening years I have spent most of my time on \*nix using Debian based distros. I was inspired to return to running FreeBSD on bare metal for everyday use by posts on [c0ffee.net](https://c0ffee.net), in particular [this](https://www.c0ffee.net/blog/freebsd-on-a-laptop) and [this](https://www.c0ffee.net/blog/openbsd-on-a-laptop). Before starting, it's important to note that one of the overriding success factors in getting a pleasant FreeBSD experience will be your choice of hardware. Essentially you purchase a laptop after deciding to use FreeBSD. I went with a Lenovo Carbon X1 Gen 7, it's an Intel i7 with 8GB ram and Intel integrated graphics, it's very light and the battery lasts for a good 5 hours. The cost as a refurbished model was $200. The laptops original origin was Japan so I have stickers to cover all the Kanji, but its a small price to pay for an otherwise excellent machine. 

The main outstanding issue after the full FreeBSD installation is the WiFi stack does not support 802.11ac/ax networks, one option for faster mobile internet speeds has been to configure tethering between my iPhone and FreeBSD via USB.   

Why not explore one of the desktop ready BSD distributions? Well TrueOS, the most prominent, has ceased regular maintenance, and although there is a case for [DragonFly](https://www.dragonflybsd.org/), [Ghost](https://ghostbsd.org/) or [Nomad](https://nomadbsd.org/), I was far more excited to be able to configure the OS from the base install. This led to a deeper understanding of the internals, the configuration, some of the subtleties with Linux and also some of my own assumptions as to what to invest time into and when.

---

So where do we start? I recommend downloading the FreeBSD 14 RELEASE memstick image and running 

```zsh 
sudo dd if=/path/to/FreeBSD14-RELEASE of=/dev/r(IDENTIFIER) bs=1m
```

As mentioned above the installation is self explanatory, but I did chose to use an encrypted root ZFS partition. Ensure your user belongs to the wheel, video and operator groups, otherwise you will be unable to elevate privileges or use an X Server. Log in as your user, and we can begin configuration.

If you have not headed the above advise and finished the installation with a user unable to elevate privileges; reboot the system and enter in Single user mode, ensure you mount the file system in read-write mode `mount -u /` and then run `pw usermod [user_name] -G wheel video operator`.   
 
Power
=====

You can check the current battery level with `apm`. First, following along with c0ffee.net we can enable CPU frequency scaling by editing `/etc/rc.conf`.

```zsh
performance_cx_lowest="Cmax"
economy_cx_lowest="Cmax"
```

I was also able to enable power saving using 

```zsh
ifconfig_wlan0="WPA DHCP powersave"
```

Next is to ensure the following exists in `/boot/loader.conf` to enable power saving kernel settings.

```zsh
hw.pci.do_power_nodriver="3"
hw.snd.latency="7"
hint.p4tcc.0.disabled="1"
hint.acpi_throttle.0.disabled="1"
hint.ahcich.0.pm_level="5"
hint.ahcich.1.pm_level="5"
hint.ahcich.2.pm_level="5"
hint.ahcich.3.pm_level="5"
hint.ahcich.4.pm_level="5"
hint.ahcich.5.pm_level="5"

# for intel cards only
drm.i915.enable_rc6="7"
drm.i915.semaphores="1"
drm.i915.intel_iommu_enabled="1"
```

The final aspect of power saving lies with the embedded usb devices, although from experimentation it seems there is no effect from setting some of the onboard usb devices into power saving mode. To find your usb devices run `usbconfig list`, you can find their current power usage listed at the end and their current `pwr` mode. To change the power mode of for example the Integrated Camera we can run `usbconfig -d ugen0.3 power_save` but notice that even after the mode is changed its power consumption remains the same. This may be due to the hub already switching to power saving mode although I'm not sure how to confirm.

----

Networking
=========

iwm comes configured for the kernel in base, and the below addition to `/etc/rc.conf` is all that is required.

```zsh
# wireless config
wlans_iwm0="wlan0"
ifconfig_wlan0="WPA DHCP powersave"
ifconfig_wlan0_ipv6="inet6 accept_rtadv"
```

And then in `/etc/wpa_supplicant.conf`

```zsh
ctrl_interface=/var/run/wpa_supplicant
eapol_version=2
ap_scan=1
fast_reauth=1

network={
  ssid="PrettyFlyForAWiFi"
  psk="secret"
  priority=5
}
```

`doas service NETWORKING restart` to bring our wifi stack up, later I use `wifimgr` a GUI application to manage the multitude of WiFi hotspots I connect to. 

----

Configuration for the desktop
============================

First lets edit `/boot/loader.conf` for some quality of life changes when using FreeBSD as a desktop system

```zsh
autoboot_delay="2"

# these values need to be bumped up a bit for desktop usage
kern.maxproc="100000"
kern.ipc.shmseg="1024"
kern.ipc.shmmni="1024"

# increase default framebuffer to max resolution  
kern.vt.fb.default_mode="2560x1440"

# enable the nub and the touchpad
hw.psm.trackpoint_support="1"
hw.psm.synaptics_support="1"

# Enables a faster but possibly buggy implementation of soreceive
net.inet.tcp.soreceive_stream="1"

# increase the network interface queue link
net.link.ifqmaxlen="2048"

# enable hardware accelerated AES (can speed up TLS)
aesni_load="YES"

# Load the H-TCP algorithm. It has a more aggressive ramp-up to max
# bandwidth, and is optimized for high-speed, high-latency connections.
cc_htcp_load="YES"

# enable CPU firmware updates
cpuctl_load="YES"

# enable CPU temperature monitoring
coretemp_load="YES"

# enable LCD backlight control, ThinkPad buttons, etc
acpi_ibm_load="YES"

# load firmware for wireless card - (Intel 8265) 
if_iwm_load="YES"
iwm8265fw_load="YES"

# filesystems, webcam driver, sound etc
snd_hda_load="YES":
cuse4bsd_load="YES"
fuse_load="YES"
libiconv_load="YES"
cd9660_iconv_load="YES"
msdosfs_iconv_load="YES"
tmpfs_load="YES"
```

Next we make the following changes in `/etc/rc.conf`

```zsh
# My machines folllow the Beverly Hills Cop nomenclature
hostname="foley.local"

# Zeroconf DNS enable
avahi_daemon_enable="YES"
avahi_dnsconfig_enable="YES"

# disable moused for now, there is native support in X and Wayland
moused_nondefault_enable="NO"

# clear tmp on boot 
clear_tmp_enable="YES"

# don't let syslog open network sockets
syslogd_flags="-ss"

# disable sendmail daemon
sendmail_enable="NONE"

# disable kernal crash dumps
dumpdev="NO"

# sync clock on boot
ntpd_enable="YES" 
ntpd_flags="-g"

# enable dbus
dbus_enable="YES"

# enable bluetooth
hcsecd_enable="YES"
sdpd_enable="YES"

# enable printing
cupsd_enable="YES"

# enable ZFS fs
zfs_enable="YES"

# enable webcam (works fine in chrome)
webcamd_enable="YES"

# enable drm-next-kmd for video
kld_list="i915kms"
seatd_enable="YES"

# enable wireguard for vpn
wireguard_enable="YES"
wireguard_interfaces="wg0"
```

The above configuration assumes the following packages have been installed for various daemons:

```
graphics/drm-kmod
print/cups
multimedia/webcamd
net/avahi-app
net/nss_mdns
net/wireguard-tools
```

Next append UTF-8 as our default encoding to the default profile in `/etc/login.conf`

```zsh
default:\
  :charset=UTF-8:\
  :lang=en_GB.UTF-8:
```

Rebuild the login database after editing the above file

```
cap_mkdb /etc/login.conf
```   

Finally we further tune some sysctl variables to enhance the experience of FreeBSD on the desktop, expanding the amount of shared memory, increasing the process schedule threshold and also increasing the amount of simultaneous files which can be open to something sane.

```zsh
vfs.zfs.min_auto_ashift=12

# allow users to mount disks without root permissions
vfs.usermount=1

# make the desktop retain responsiveness under heavy load
kern.sched.preempt_thresh=224

# shared memory needed for chromium
kern.ipc.shm_allow_removed=1

# bump up maximum number of open files
kern.maxfiles=200000

# enable IPv6 autoconfiguration
net.inet6.ip6.accept_rtadv=1

# suspend on lid close
hw.acpi.lid_switch_state=S3

# tweeks to boost network performance over longer pipes
net.inet.tcp.cc.algorithm=htcp
net.inet.tcp.cc.htcp.adaptive_backoff=1
net.inet.tcp.cc.htcp.rtt_scaling=1
net.inet.tcp.rfc6675_pipe=1
net.inet.tcp.syncookies=0
net.inet.tcp.nolocaltimewait=1
kern.ipc.soacceptqueue=1024
kern.ipc.maxsockbuf=8388608
kern.ipc.maxsockbuf=2097152
net.inet.tcp.sendspace=262144
net.inet.tcp.recvspace=262144
net.inet.tcp.sendbuf_max=16777216
net.inet.tcp.recvbuf_max=16777216
net.inet.tcp.sendbuf_inc=32768
net.inet.tcp.recvbuf_inc=65536
net.local.stream.sendspace=16384
net.local.stream.recvspace=16384
net.inet.raw.maxdgram=16384
net.inet.raw.recvspace=16384
net.inet.tcp.abc_l_var=44
net.inet.tcp.initcwnd_segments=44
net.inet.tcp.mssdflt=1448
net.inet.tcp.minmss=524
net.inet.ip.intr_queue_maxlen=2048
net.route.netisr_maxqlen=2048
```

Rebooting your system will allow for the kernel changes made to take effect, in addition ensure you have TPM disabled in your BIOS if you find suspend on lid close does not work.

---

Display servers
===============

My original workflow for this machine was just to live with X11 and launch GUI applications into separate sessions, this only requires installing `pkg install xorg` and as mentioned above ensuring your user is part of the video group. This setup lasted for a couple of weeks; the ultimate need for a proper window manager became apparent as the configurations for them to work in a vanilla X Server always felt fragile. 

There are a limited number of fonts included with a base FreeBSD install, and just like suggested in [c0ffee.net](https://www.c0ffee.net/blog/freebsd-on-a-laptop) terminus is a good monospaced addition, along with these other fonts

```
x11-fonts/bitstream-vera
x11-fonts/droid-fonts-ttf
x11-fonts/ubuntu-font
x11-fonts/inconsolata-ttf
x11-fonts/liberation-fonts-ttf
x11-fonts/webfonts
x11-fonts/terminus-font
x11-fonts/terminus-ttf
x11-fonts/tlwg-ttf
x11-fonts/powerline-fonts
```

After installing X11 and our fonts  we can move onto installing wayland, a new display protocol which will be using as the base for our window manager sway. A significant difference with wayland is that as it is just a protocol, it will be the compositor which will provide the display server. Install with `pkg install wayland seatd` we need to include `seatd` here as this will allow non-root access to certain devices.

Lastly we need to ensure we have the correct environment variables set for wayland

```zsh
XDG_RUNTIME_DIR=/tmp
XDG_SESSION_TYPE=wayland
```

---

Window Managers
===============

Sway is a new compositor for wayland using the same window tiling philosophy as i3. First we install the following packages for a pleasant experience `pkg install sway swayidle swaylock-effects alacritty dmenu-wayland dmenu`. I've included alacritty here as I think its one of the better terminal emulators, but replace this with your preference.

Create a new config at `~/.config/sway/config`, my configuration has no significant changes from the default provided by sway. I add bindings to control the audio mixer from the specific Lenovo media keys along with the separation of the status bar to it's own config file. 

```zsh
xwayland force

### Variables
# Logo key. Use Mod1 for Alt.
input * xkb_rules evdev
set $mod Mod4
# Home row direction keys, like vim
set $left h
set $down j
set $up k
set $right l
# Your preferred terminal emulator
set $term alacritty
set $lock swaylock -f -c 000000 --clock
# Your preferred application launcher
# Note: pass the final command to swaymsg so that the resulting 
# window can be opened on the original workspace that the command 
# was run on.
set $menu dmenu_path | dmenu | xargs swaymsg exec --

# Remove all borders from applications
default_border none

# Stablish gaps between windows and from the screen edge
gaps inner 5
gaps outer 1

### Output configuration
output "OwlStation" mode 1920x1080@60hz position 1920,0
output * bg /home/hywel/freebsd-desktop-background.jpg fill

# This will lock your screen after 300 seconds of inactivity,
# then turn off your displays after another 300 seconds, and 
# turn your screens back on when resumed. It will also lock your 
# screen before your computer goes to sleep.
exec swayidle -w \
    timeout 300 'swaylock -f -c 000000 --clock' \
    timeout 600 'swaymsg "output * dpms off"' resume 'swaymsg "output * dpms on"' \
  before-sleep 'swaylock -f -c 000000'

# Custom
bindsym XF86AudioRaiseVolume exec mixer -f /dev/mixer0 vol=+0.10
bindsym XF86AudioLowerVolume exec mixer -f /dev/mixer0 vol=-0.10

# Lock the screen
bindsym $mod+Shift+z exec $lock

# Start a terminal
bindsym $mod+Return exec $term

# Kill focused window
bindsym $mod+Shift+q kill

# Start your launcher
bindsym $mod+d exec $menu

# mouse button for dragging.
floating_modifier $mod normal

# Reload the configuration file
bindsym $mod+Shift+c reload

# Lock the screen manually 
bindsym $mod+Shift+Return exec $lock

# Exit sway (logs you out of your Wayland session)
bindsym $mod+Shift+e exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit sway? This will end your Wayland session.' -B 'Yes, exit sway' 'swaymsg exit'
  
# Move your focus around
bindsym $mod+$left focus left
bindsym $mod+$down focus down
bindsym $mod+$up focus up
bindsym $mod+$right focus right
# Or use $mod+[up|down|left|right]
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

# Move the focused window with the same, but add Shift
bindsym $mod+Shift+$left move left
bindsym $mod+Shift+$down move down
bindsym $mod+Shift+$up move up
bindsym $mod+Shift+$right move right
# Ditto, with arrow keys
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right
    
# Switch to workspace
bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5
bindsym $mod+6 workspace number 6
bindsym $mod+7 workspace number 7
bindsym $mod+8 workspace number 8
bindsym $mod+9 workspace number 9
bindsym $mod+0 workspace number 10
# Move focused container to workspace
bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4
bindsym $mod+Shift+5 move container to workspace number 5
bindsym $mod+Shift+6 move container to workspace number 6
bindsym $mod+Shift+7 move container to workspace number 7
bindsym $mod+Shift+8 move container to workspace number 8
bindsym $mod+Shift+9 move container to workspace number 9
bindsym $mod+Shift+0 move container to workspace number 10
    
# You can "split" the current object of your focus with
# $mod+b or $mod+v, for horizontal and vertical splits
# respectively.
bindsym $mod+b splith
bindsym $mod+v splitv

# Switch the current container between different layout styles
bindsym $mod+s layout stacking
bindsym $mod+w layout tabbed
bindsym $mod+e layout toggle split

# Make the current focus fullscreen
bindsym $mod+f fullscreen

# Toggle the current focus between tiling and floating mode
bindsym $mod+Shift+space floating toggle

# Swap focus between the tiling area and the floating area
bindsym $mod+space focus mode_toggle

# Move focus to the parent container
bindsym $mod+a focus parent
    
# Move the currently focused window to the scratchpad
bindsym $mod+Shift+minus move scratchpad

bindsym $mod+minus scratchpad show

mode "resize" {
    bindsym $left resize shrink width 10px
    bindsym $down resize grow height 10px
    bindsym $up resize shrink height 10px
    bindsym $right resize grow width 10px

    bindsym Left resize shrink width 10px
    bindsym Down resize grow height 10px
    bindsym Up resize shrink height 10px
    bindsym Right resize grow width 10px

    # Return to default mode
    bindsym Return mode "default"
    bindsym Escape mode "default"
}
bindsym $mod+r mode "resize"

# Read `man 5 sway-bar` for more information about this section.
bar {
    position top

    status_command while $HOME/.config/sway/status; do sleep 1; done
    colors {
        statusline #ffffff
        background #323232
        inactive_workspace #32323200 #32323200 #5c5c5c
    }
}


include /usr/local/etc/sway/config.d/*
```

My status bar is configured to show language, network, volume, battery, CPU temperature and time, it's formatted using `$HOME/.config/sway/status`, and also requires installing `x11-fonts/noto-emoji` for the icons.

```bash

#!/usr/bin/env bash

# Language
language=$(swaymsg -r -t get_inputs | awk '/1:1:AT_Translated_Set_2_keyboard/;/xkb_active_layout_name/' | grep "xkb_active_layout_name" | awk -F '"' '{print $4}' | head -1)

# Network
network=$(ifconfig wlan0 | grep "status" -i | grep "associated" -i | tr -d "[:blank:]" )

if [ "$network" == "status:associated" ]; then
    network_ssid=$(ifconfig wlan0 | grep ssid -i | cut -d " " -f 2,2)
else
    network_ssid="Disconnected"
fi

# Master volume
volume=$(mixer vol | sed 's/.*s*\t*s* *s*://' | head -1 | xargs -n 1 bash -c 'echo "$1 * 100.00" | bc' args | cut -d . -f 1,3)

# Battery
battery=$(apm | grep "Remaining battery life: " | cut -f 2 -d ":" | head -1)

# CPU temp
cpu=$(hwstat | grep "tz0" | cut -c 10,13)

# Date
date=$(date +'%Y-%m-%d %I:%M:%S %p')

# Status bar
echo ⌨️ $language 📡 $network_ssid 🔊 $volume% ⚡ $battery 🌡️ $cpu°C "|" $date
```

Login Managers (or my struggle with them)
========================================

I was unable to get a login manager to work with FreeBSD + sway, I attempted to use sddm and [ly](https://github.com/fairyglade/ly) but both failed to integrate correctly, and for the time being I've fallen back to launching immediately from the shell using the below from my `.zshrc`.

```zsh
if tty | grep -q '/dev/ttyv0'; then
	sway -c ~/.config/sway/config
fi
```

One final note is the lack of a lockscreen on opening the laptop lid. The default sway config shared above does contain a line for triggering `swaylock` on the `before-sleep` event, but this does not take effect for me, and I have to ensure to use my lock shortcut `$mod + Shift + z` instead. 

Applications
===========

Below is the list of applications I run on my machine, it's predominately used for writing (Vim), programming (VSCode, gcc, rust), publishing this blog (Ruby) and consuming an unhealthy amount of internet (chromium). 

```
www/chromium
security/doas
graphics/freeimage
lang/gawk
lang/gcc
devel/git
devel/gmake
textproc/gsed
misc/help2man
sysutils/hwstat
textproc/jq
www/npm
shells/ohmyzsh
dns/p5-Net-Bonjour
devel/patch
misc/py-powerline-status
sysutils/py-zfs-autobackup
lang/python
lang/ruby31
devel/ruby-gems
lang/rust
sysutils/tmux
converters/unix2dos
editors/vim
editors/vscode
ftp/wget
net-mgmt/wifimgr
sysutils/yadm
shells/zsh
```
