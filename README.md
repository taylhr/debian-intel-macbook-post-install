# Debian Linux Post-Installation Setup for Intel MacBooks

## Overview

A one-command post-installation setup for Intel MacBooks (2012–2019 models)
running Debian GNU/Linux 13 (Trixie). It picks up where the Broadcom offline
WiFi install leaves off — a bare terminal — and turns the machine into a
daily-usable laptop: an XFCE desktop, automatic security updates, a hardened
Broadcom WiFi rebuild chain, NetworkManager, macOS-style keyboard remapping via
keyd, working suspend/resume (s2idle plus lid suspend-then-hibernate), a bcm5974
touchpad resume fix, the reverse-engineered FaceTime HD webcam and microphone
drivers, and a curated set of everyday applications. Everything is organised
into 20 groups that can be turned on or off at runtime, so you can install the
whole thing, skip the parts you do not want, or take only the MacBook hardware
enablement and bring your own desktop. An optional theming script
gives XFCE a macOS-style look — the WhiteSur dark theme and a Plank dock — with
Classic, Dock, and Revert modes. Both scripts are idempotent and safe to re-run.
Apple Silicon Macs are not supported; use the Asahi Linux project instead.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [⚠️ Compatibility Notice](#-compatibility-notice)
- [The Story So Far](#the-story-so-far)
- [Why Debian on an Intel MacBook](#why-debian-on-an-intel-macbook)
- [Who This Is For](#who-this-is-for)
- [Choosing What to Install](#choosing-what-to-install)
  - [Group Reference](#group-reference)
  - [Presets](#presets)
  - [Already Have a Desktop?](#already-have-a-desktop)
  - [Dependencies](#dependencies)
- [What This Script Installs and Configures](#what-this-script-installs-and-configures)
  - [wifi-broadcom](#wifi-broadcom)
  - [auto-updates](#auto-updates)
  - [desktop](#desktop)
  - [terminal](#terminal)
  - [apps-essential](#apps-essential)
  - [apps-dev](#apps-dev)
  - [apps-media](#apps-media)
  - [apps-office](#apps-office)
  - [print-scan](#print-scan)
  - [bluetooth](#bluetooth)
  - [monitoring](#monitoring)
  - [network-manager](#network-manager)
  - [keyboard](#keyboard)
  - [touchpad](#touchpad)
  - [webcam](#webcam)
  - [microphone](#microphone)
  - [power](#power)
  - [panel](#panel)
  - [desktop-shortcuts](#desktop-shortcuts)
  - [system-upgrade](#system-upgrade)
- [Prerequisites](#prerequisites)
  - [1. Working internet connection](#1-working-internet-connection)
  - [2. Set up sudo for your user](#2-set-up-sudo-for-your-user)
- [Installation](#installation)
- [Theming (optional)](#theming-optional)
- [Verified Test Environment](#verified-test-environment)
- [Known Limitations](#known-limitations)
- [Related](#related)
- [Version History](#version-history)
- [Contributing](#contributing)
- [License](#license)

## Quick Start

> Make sure you have read [Prerequisites](#prerequisites) first — sudo
> must be configured and you need a working internet connection.

**Setup script** (required):

    bash <(curl -s https://raw.githubusercontent.com/willardcsoriano/debian-intel-macbook-post-install/v1.8.0/setup.sh)

That runs the full install. To install only part of it, pass options through
to the script — see [Choosing What to Install](#choosing-what-to-install):

    # see every group, then preview a run without installing anything
    bash <(curl -s .../setup.sh) --list
    bash <(curl -s .../setup.sh) --dry-run

    # skip the 300MB office suite and the Microsoft VS Code repo
    bash <(curl -s .../setup.sh) --skip apps-office,apps-dev

    # MacBook hardware enablement only — no desktop, no apps
    bash <(curl -s .../setup.sh) --preset hardware

**Theming script** (optional, run after first reboot):

    bash <(curl -s https://raw.githubusercontent.com/willardcsoriano/debian-intel-macbook-post-install/v1.8.0/themes.sh)

---

## ⚠️ Compatibility Notice

**This script is for Intel MacBooks only.**

Apple Silicon Macs (M1, M2, M3, M4 — released 2020 onwards) use ARM
architecture and are not supported. Apple Silicon Linux support is handled
by the separate Asahi Linux project.

**This script targets Debian GNU/Linux 13 (Trixie) only.**

Ubuntu and Linux Mint are not tested and not officially supported. Most
apt-based steps will likely work, but keyd availability varies by Ubuntu
version and may require a PPA. The facetimehd driver is built from upstream
source via DKMS and generally tracks current kernels, but kernel API changes
have broken it before (notably Trixie's 6.12 kernel, which dropped the
`videobuf-dma-sg.h` header) — it relies on the latest upstream master carrying
the fix, which it currently does.
If you test this on Ubuntu or Mint, open an issue with your results.

Tested on MacBook Air 7,2 (2015, 13-inch). Should work on most Intel
MacBooks from 2012–2019 running Debian 13 Trixie.

---

## The Story So Far

If you just came from the [Broadcom offline repo](https://github.com/willardcsoriano/debian-intel-macbook-broadcom-offline), you have accomplished something genuinely difficult — you installed Linux on a MacBook with no internet access and got WiFi working entirely from a USB stick. That is not a beginner task and you should feel good about it.

But right now you are staring at a terminal. No desktop, no browser, no
way to adjust brightness, no GUI tools, no keyboard shortcuts that feel
familiar coming from macOS. The Cmd key does nothing useful. The function
keys do nothing. The FaceTime camera does not work. The mic may not work.

This script fixes all of that in one command.

---

## Why Debian on an Intel MacBook

macOS Monterey — the last macOS version supporting most Intel MacBooks —
reached end of life on September 16, 2024 when Apple released Sequoia.
Security updates have stopped. On top of that, Monterey consumes roughly
4GB of RAM at idle on 8GB hardware, leaving almost nothing available for
actual work.

Debian Trixie at idle uses under 500MB. After running this post-install script, idle RAM rises to approximately 1GB — XFCE, NetworkManager, Bluetooth, and the FaceTime driver all add overhead that a terminal-only install does not have. That is still well under a quarter of what Monterey uses on the same hardware, and you now have a fully functional desktop.

---

## Who This Is For

This script is for users who have:

1. An Intel MacBook with no usable macOS (end of life, or removed)
2. Debian GNU/Linux 13 (Trixie) installed — minimal, no desktop
3. Broadcom WiFi working via the offline repo below
4. Internet connected via wpa_supplicant and dhcpcd
5. A terminal and nothing else

If you have not yet gotten WiFi working, start [here](https://github.com/willardcsoriano/debian-intel-macbook-broadcom-offline) first.

---

## Choosing What to Install

Everything the script does belongs to one of 20 **groups**. By default every
group runs, which is the full install. Options let you narrow that down.

    -p, --preset NAME   Start from a preset instead of the full install
    -o, --only LIST     Run only these groups (comma separated)
    -a, --add LIST      Add these groups on top of a preset (comma separated)
    -s, --skip LIST     Skip these groups (comma separated)
    -l, --list          List every group with what it does, then exit
    -n, --dry-run       Show what would run, install nothing, then exit
    -h, --help          Show help, then exit

Some examples:

    ./setup.sh                                       # everything (the default)
    ./setup.sh --skip apps-office,apps-dev           # no LibreOffice, no VS Code
    ./setup.sh --preset hardware                     # drivers and updates only
    ./setup.sh --only wifi-broadcom,keyboard,webcam  # just these three
    ./setup.sh --preset minimal --skip webcam        # a preset, minus one group
    ./setup.sh --preset existing-desktop --add monitoring   # a preset, plus one

`--dry-run` is the safe way to check a selection before committing to it — it
prints exactly which groups would run and installs nothing.

Pre-flight checks, the APT component setup (contrib, non-free,
non-free-firmware), and the closing summary are not groups. They always run,
because everything else depends on them.

The script stays idempotent: re-running it later with different options adds
the new groups and leaves everything already installed alone. If you skip a
group now, you can add it afterwards with `--only <group>`.

### Group Reference

| Group | What it covers | Notes |
|---|---|---|
| `wifi-broadcom` | DKMS, kernel headers, b43/bcma/ssb blacklist, `wl` on boot | Keeps WiFi alive across kernel updates |
| `auto-updates` | unattended-upgrades, intel-microcode, needrestart, fwupd | |
| `desktop` | Xorg, XFCE, fonts, window tiling, App Finder launcher fix | Required by `panel` and `desktop-shortcuts` |
| `terminal` | GNOME Terminal, bracketed-paste fix | |
| `apps-essential` | Firefox, gedit, File Roller, gdebi, poppler-utils, speech-dispatcher | |
| `apps-dev` | Visual Studio Code | Adds Microsoft's apt repository |
| `apps-media` | VLC, Flameshot (+ Ctrl+Alt+S shortcut), mtPaint | |
| `apps-office` | LibreOffice | Large — roughly 300MB |
| `print-scan` | CUPS, SANE, Simple Scan | |
| `bluetooth` | Blueman | |
| `monitoring` | XFCE Task Manager, htop, fastfetch | |
| `network-manager` | NetworkManager, replacing wpa_supplicant + dhcpcd | Skip if you manage networking yourself |
| `keyboard` | keyd Mac-style remapping, rofi, backlight permissions | |
| `touchpad` | bcm5974 trackpad resume fix | |
| `webcam` | FaceTime HD camera driver | Builds from source; the slowest step |
| `microphone` | ALSA `model=mbp101` quirk | Model-specific — may be wrong on your MacBook |
| `power` | s2idle suspend, lid suspend-then-hibernate, battery plugin | |
| `panel` | Clean XFCE panel layout on first login | Needs `desktop` |
| `desktop-shortcuts` | Desktop launchers, keyboard shortcuts cheat sheet | Needs `desktop` |
| `system-upgrade` | Offers a full `apt full-upgrade` | Already a prompt; skip to suppress it |

### Presets

| Preset | Groups |
|---|---|
| `full` | Everything. The default when no options are given. |
| `minimal` | Hardware fixes, desktop, terminal, essential apps, panel, shortcuts. No office suite, VS Code, media apps, printing, or Bluetooth. |
| `hardware` | MacBook hardware enablement and updates only — no desktop, no applications. For bringing your own desktop environment. |
| `existing-desktop` | For a machine that already has a desktop. Hardware fixes plus the XFCE tweaks, without the groups that would fight a setup you already have. See below. |

A preset is a starting point, not a final answer: `--add` and `--skip` apply on
top of one, in that order.

### Already Have a Desktop?

This script was originally written for the bare terminal you are left with
after the Broadcom offline install. If instead you installed Debian by
selecting **Debian desktop environment + Xfce + standard system utilities** in
the installer, the machine already has xorg, xfce4, xfce4-goodies,
xfce4-power-manager, xfce4-terminal, cups, firefox-esr, NetworkManager, and the
LibreOffice components.

Two things are worth knowing.

**Redundant packages take care of themselves.** Every install checks `dpkg -s`
first, so anything already present is skipped and reported as such. You do not
need to hunt for those.

**One group would otherwise overwrite your setup.** `panel` builds its clean
layout by clearing every existing panel item first — correct on a bare install,
destructive on a desktop whose panel you have arranged yourself. The script now
detects XFCE that predates the run and leaves your panel alone, telling you so.
If you do want the clean layout, ask for it by name:

    ./setup.sh --only panel

The `existing-desktop` preset packages this up:

    ./setup.sh --preset existing-desktop

It keeps every hardware fix and the `desktop` group — worth having even with
XFCE installed, because that is where window tiling and the App Finder launcher
fix live, and its package installs no-op when they are already satisfied. It
leaves out:

| Left out | Why |
|---|---|
| `panel` | Would replace a panel layout you may have customised |
| `desktop-shortcuts` | Would add 17 launchers to a Desktop you have already arranged |
| `terminal` | gnome-terminal duplicates the xfce4-terminal you already have |
| `apps-essential`, `apps-media` | The desktop task ships a browser, editor, and media player |
| `apps-office` | Installs the `libreoffice` metapackage, which adds Base, Draw, and Math on top of the writer/calc/impress you already have |
| `print-scan` | The desktop task ships cups and xsane |

Add back whatever you do want — `--add terminal` for the bracketed-paste fix,
`--add apps-dev` for VS Code, and so on.

### Dependencies

Only two groups have hard prerequisites — `panel` and `desktop-shortcuts` both
need `desktop`. Unmet dependencies are resolved before anything is installed,
never partway through:

- **Skipping a dependency carries its dependents with it.** `--skip desktop`
  plainly means "no GUI", so `panel` and `desktop-shortcuts` are dropped too
  and the script tells you it did that.
- **Naming a group on `--only` without its dependency is an error.**
  `--only panel` stops immediately rather than silently doing nothing, or
  quietly pulling in all of XFCE and defeating the point of `--only`.

Desktop shortcuts are only created for applications that are actually
installed, so the Desktop never ends up with a launcher that does nothing.
The panel is built the same way — skipped plugins leave no gap.

---

## What This Script Installs and Configures

Headings below match the group names from `--list`, so you can map anything
here to the option that controls it.

### wifi-broadcom
The Broadcom `wl` driver is a kernel module, and a kernel update silently
invalidates it — leaving you with no WiFi and no obvious cause. This group locks
in the rebuild chain so that cannot happen.

- dkms + linux-headers-amd64 — rebuilds the driver automatically for every new
  kernel. Without these the driver vanishes on the next kernel update.
- b43, bcma, and ssb blacklisted — the open-source Broadcom modules fight the
  proprietary `wl` driver and win, causing random WiFi drops
- `wl` added to `/etc/modules-load.d` so it loads on every boot
- Warns if no swap is configured (8GB with no swap hard-freezes on OOM)

### auto-updates
Skip this group with `--skip auto-updates` to opt out of automatic patching
entirely — it is the single switch for everything in this section.

**Skipping never removes anything.** Every step here only installs what is
missing, so anything already on the machine stays exactly as it is. What you
give up is whatever was not there already:

- **unattended-upgrades** is the real loss. Debian does not install it by
  default, so skipping this group means nothing patches the machine in the
  background — security updates wait until you run `apt upgrade` yourself.
- **fwupd** and **needrestart** are likewise not installed by default: no
  firmware updates via LVFS, and no notification when a reboot is needed.
- **intel-microcode** may or may not already be present depending on how the
  installer handled non-free firmware. Where it is missing, you are without the
  Spectre/Meltdown-class CPU mitigations.
- **VS Code will not auto-update** — the origins file whitelisting Microsoft's
  repository is written by this group.
- **linux-image-amd64** is almost certainly already installed, since the Debian
  installer includes it, in which case skipping changes nothing. Confirm with
  `dpkg -s linux-image-amd64`. It matters only on an unusual install that lacks
  it, and there it matters more than it looks — Trixie ships each kernel update
  as a *new* binary package (`linux-image-6.12.95+deb13-amd64`) and drops the
  previous name from the archive, so `apt upgrade` cannot follow the change on
  its own. The metapackage's moving dependency is what pulls the new kernel in;
  without it the kernel is frozen at whatever is installed.
- the DKMS drivers are **not** affected — `wifi-broadcom` and `webcam` install
  the kernel headers they need themselves, independently of this group

Contents:

- linux-image-amd64 — kernel meta-package, ensures the kernel actually updates
  automatically rather than staying pinned to the version installed at setup
- intel-microcode — CPU microcode updates for Spectre/Meltdown-class mitigations
- unattended-upgrades — daily auto-install of Debian security patches and kernel
  updates. Extended to also cover the stable -updates pocket and the VS Code
  Microsoft repo (third-party origins are excluded by default)
- needrestart — notifies you when a kernel or library update requires a reboot
  to take effect. No auto-reboot; you decide when to restart.
- fwupd + fwupd-refresh.timer — UEFI and firmware updates via LVFS, refreshed
  automatically on a timer
- AppArmor verified active (ships enabled on Debian 13, warns if disabled)

### desktop
- xorg — display server
- xfce4 + xfce4-goodies — lightweight desktop, chosen specifically because
  it is fast and low on RAM — consistent with the reason you switched to
  Linux in the first place. Brings along xfce4-screenshooter (Print key) and
  xfce4-clipman-plugin (clipboard history).
- fonts-liberation — Arial, Times New Roman, Courier New replacements
- fonts-noto — broad Unicode coverage
- Window tiling — drag a window to a screen edge to snap it to that half
- App Finder launcher fix — some `.desktop` files declare `Exec=...%F` or `%U`,
  telling the launcher to pass a file argument. Launched from the XFCE App
  Finder with no file selected, those apps silently fail. This writes cleaned
  copies into `~/.local/share/applications` (per-user overrides; system files
  are left untouched) so every app starts cleanly.

Required by `panel` and `desktop-shortcuts`.

### terminal
- gnome-terminal — modern terminal with proper copy-paste, right-click menu,
  and mouse support. The default xterm that ships with Debian minimal is
  essentially unusable for everyday work.
- Bracketed paste mode disabled system-wide so pasting commands into the
  terminal works without escape code artifacts

### apps-essential
- firefox-esr — Mozilla Firefox
- gedit — simple text editor, similar feel to TextEdit on macOS
- file-roller — archive manager for zip, tar, and other formats
- gdebi — GUI installer for standalone .deb packages
- poppler-utils — command-line PDF tools (pdftotext, pdfinfo, pdfimages)
- speech-dispatcher — text-to-speech backend for accessibility tools

### apps-dev
- code (Visual Studio Code) — installed from Microsoft's official apt
  repository so it stays current via normal apt updates

Skip this group if you would rather not add a Microsoft apt repository to the
machine. Note that `auto-updates` configures unattended-upgrades to cover that
repository, but only if it exists.

### apps-media
- vlc — media player for video and audio
- flameshot — screenshot tool with annotation support, bound to Ctrl+Alt+S
- mtpaint — simple image editor similar to Microsoft Paint

### apps-office
- libreoffice — full office suite (Writer, Calc, Impress)

By far the largest single download in the script, around 300MB. The most
worthwhile group to skip on a slow connection or a small SSD.

### print-scan
- cups — printing system, works with most USB and network printers, enabled
  and started as a service
- sane-utils + simple-scan — scanner support for USB and all-in-one printers

### bluetooth
- blueman — Bluetooth manager with GUI tray applet

### monitoring
- xfce4-taskmanager — GUI task manager, similar to Activity Monitor
- htop — terminal process viewer
- fastfetch — system info tool. Run with: fastfetch

### network-manager
- network-manager + network-manager-gnome — replaces the manual
  wpa_supplicant + dhcpcd workflow permanently. After this you will never
  type ip link or wpa_passphrase again. WiFi connects automatically on boot
  and a tray icon lets you switch networks from the desktop.

Skip this group if you manage networking yourself — it disables
`wpa_supplicant` and `dhcpcd` and hands all interfaces to NetworkManager.

### keyboard
This is one of the most important parts of the script. Out of the box on
Linux, the Mac keyboard feels completely wrong — the Cmd key does nothing,
F keys behave unexpectedly, and text navigation shortcuts from macOS do not
work. This script fixes all of it.

- keyd — kernel-level key remapping, works before the desktop even loads
- brightness-udev — backlight write permissions without sudo
- rofi — window switcher used as an F3 Mission Control equivalent

Full key mapping applied:

| Key | Action |
|-----|--------|
| Cmd | Ctrl (preserves Mac muscle memory) |
| Cmd+Space / F4 | App finder (like Spotlight / Launchpad) |
| F1 / F2 | Brightness down / up |
| F3 | Window switcher (like Mission Control) |
| F5 / F6 | Keyboard backlight down / up |
| F7 / F8 / F9 | Previous / Play-Pause / Next track |
| F10 / F11 / F12 | Mute / Volume down / Volume up |
| Fn+F1–F12 | Standard F1–F12 keys |
| Cmd+Left / Right | Jump to start / end of line |
| Cmd+Up / Down | Jump to start / end of document |
| Cmd+Shift+Left / Right | Select to start / end of line |
| Cmd+Shift+Up / Down | Select to start / end of document |
| Cmd+Backspace | Delete entire line left of cursor |

### touchpad
The bcm5974 trackpad re-enumerates as a USB device every time the lid opens
after suspend. When it reconnects, XFCE's settings daemon (xfsettingsd) replays
its stored input properties — and if it has a stale `Device_Enabled=0`, it
disables the trackpad before anything can turn it back on, leaving a dead pad
until reboot. This script clears that stored state and installs a systemd sleep
hook that force-enables the trackpad after each resume.

This covers only re-enabling the trackpad. For personal touchpad *preferences*
(tap-to-click, natural scrolling, cursor acceleration), see the
[dotfiles](https://github.com/willardcsoriano/dotfiles) repo below.

### webcam
The FaceTime HD camera in Intel MacBooks connects via PCIe, not USB. It
requires a reverse-engineered driver that is not included in the Linux
kernel. This script builds and installs it automatically via DKMS, which
means it survives kernel updates without any manual intervention.

- facetimehd — FaceTime HD webcam driver (compiled from source, DKMS managed)
- Firmware extracted and installed, module set to load on boot

This is the slowest group in the script — it clones and compiles two upstream
repositories, which takes several minutes. It is also the most likely to fail
on a kernel the upstream driver has not caught up with yet, so it is a
reasonable one to skip if you never use the camera.

### microphone
- Microphone configured via ALSA (`options snd-hda-intel model=mbp101`)
- alsa-utils — `alsamixer` and `amixer`, for unmuting and checking the mic once
  the quirk is applied

Kept separate from `webcam` because it is unrelated hardware and this quirk is
model-specific — it is the setting for a MacBook Pro 10,1 codec layout, applied
because it also happens to work on the MacBook Air 7,2. On a different Intel
MacBook it may be wrong, so it can be skipped without losing the camera.

### power
- xfce4-battery-plugin — battery level and charging status in taskbar
- xfce4-power-manager — lid close triggers suspend and screen lock.
  Password required on wake.
- s2idle forced via kernel parameter and systemd — Intel MacBooks default to
  deep/S3 suspend, which enters fine but never resumes, leaving the machine
  dead on lid-open until a hard power-off
- logind owns the lid: suspend-then-hibernate, so an overnight close hibernates
  to swap instead of draining the battery flat

The two XFCE packages are only installed when the `desktop` group is also part
of the run — a hardware-only install gets the kernel, systemd, and logind
layers without pulling in XFCE.

### panel
- xfce4-pulseaudio-plugin — volume control in the panel with scroll-wheel
  adjustment
- A clean panel layout — app menu, open windows, system tray, volume, battery,
  clock — applied once on first login

Plugins whose packages are not installed are left out rather than registered
as dead slots, so the panel stays correct whichever groups you selected.
Needs `desktop`.

The layout is built by clearing the existing panel first, so on a machine where
XFCE predates this run it is skipped by default to avoid discarding a layout you
arranged yourself — see [Already Have a Desktop?](#already-have-a-desktop).
Request it by name with `--only panel` to rebuild anyway.

### desktop-shortcuts
Shortcuts for installed apps are placed on your Desktop so you can find
everything without memorizing commands. Apps that were not installed are
skipped, so you never get a launcher that does nothing. First time you click a
shortcut XFCE will show "Untrusted application launcher" — click Launch to
confirm. It will not ask again.

A plain text file called KEYBOARD SHORTCUTS.txt is placed alongside them with a
complete reference of every shortcut configured by this script. Needs `desktop`.

### system-upgrade
Near the end, the script offers to run a full `apt full-upgrade` to bring every
package up to the latest Debian 13 point release. It first simulates the upgrade
and, when nothing is pending, reports the system as up to date and skips the
prompt entirely. When updates are available it is still **off by default** —
security updates normally install automatically via unattended-upgrades, so
skipping it is safe, and pressing Enter (or a non-interactive run) skips it.
(If you skipped `auto-updates`, unattended-upgrades is not installed and the
prompt says so instead — nothing is patching the machine in the background, so
skipping the upgrade leaves it behind.) If
you accept and a new kernel is installed, the Broadcom and FaceTime HD DKMS
drivers rebuild for it automatically and the script flags a reboot — verify WiFi
and the webcam after rebooting. The summary closes with a **System status** line
reporting one of: fully up to date, upgraded, or — if you declined pending
updates — a warning with the `sudo apt full-upgrade` command to catch up later.

This group runs last by design: every DKMS driver is registered by then, so a
new kernel pulled in here rebuilds them automatically. Skip the group entirely
with `--skip system-upgrade` to suppress the prompt on an unattended run.

---

## Prerequisites

### 1. Working internet connection

Confirm with:

    ping -c 3 google.com

### 2. Set up sudo for your user

Debian does not configure sudo for regular users by default. This must be
done once before running the script. Do it while you are still in the
terminal from the Broadcom install.

Switch to root:

    su -

Add your user to the sudo group (replace yourusername with your actual
username, for example willard):

    usermod -aG sudo yourusername

Exit root and log out:

    exit
    logout

Log back in as your regular user. Confirm sudo works:

    sudo echo "sudo is working"

If you see "sudo is working" you are ready.

---

## Installation

Run this single command as your regular user, not as root:

    bash <(curl -s https://raw.githubusercontent.com/willardcsoriano/debian-intel-macbook-post-install/v1.8.0/setup.sh)

The script prints progress for every step. Estimated time for the full install:
20–40 minutes depending on internet speed. LibreOffice alone is ~300MB, and the
webcam driver compiles from source.

To install only part of it, append the options described in
[Choosing What to Install](#choosing-what-to-install) — for example
`--skip apps-office,apps-dev` or `--preset hardware`. Use `--dry-run` first to
see exactly what a selection would do. Any group you skip can be added later by
re-running with `--only <group>`.

When finished it will tell you whether a reboot is required and prompt you. The
summary lists what was installed, what was already present, anything that
failed, and any groups you chose not to run.

---

## Theming (optional)

Vanilla XFCE is functional but plain. If you want a macOS-style look — the
WhiteSur dark GTK theme, macOS-style window controls on the left, and a
Plank dock at the bottom — run this after the setup script completes and
you have rebooted into the desktop:

    bash <(curl -s https://raw.githubusercontent.com/willardcsoriano/debian-intel-macbook-post-install/v1.8.0/themes.sh)

You will be prompted to choose a mode:

- **Classic** — desktop icons visible, Plank shows open apps only
- **Dock** — clean empty desktop, all apps pinned in Plank
- **Revert** — removes all themes and restores vanilla XFCE

The mode can also be given up front, matching the option style of `setup.sh`:

    ./themes.sh --mode dock
    ./themes.sh --mode revert --yes    # skip the revert confirmation

Revert removes packages and deletes generated launchers, so it asks for
confirmation unless you pass `--yes`.

If you change your mind later, just run the script again and pick a
different mode or choose Revert.

---

## Verified Test Environment

| Component | Details |
|---|---|
| **Machine** | Apple MacBookAir7,2 (Mid-2015, 13-inch) |
| **OS** | Debian GNU/Linux 13 (Trixie) 13.5 |
| **Kernel** | 6.12.73+deb13-amd64 |
| **CPU** | Intel Core i5-5350U @ 1.80GHz (2 cores, 4 threads, up to 2.9GHz) |
| **RAM** | 8GB |
| **Storage** | 221GB SSD |
| **Architecture** | amd64 (64-bit) |

---

## Known Limitations

- F3 (Mission Control) uses rofi as an approximation. It shows open windows
  with icons and supports arrow key navigation. A closer equivalent
  (skippy-xd) is not currently in Debian Trixie repos.
- The FaceTime HD webcam driver is a community reverse-engineered driver.
  It works well but is not officially supported by Apple or the Linux kernel.
- Ctrl+Alt+S screenshot shortcut requires XFCE session to be running. It
  will not work from a pure terminal before first boot into the desktop.

---

## Related

Step 1 — get WiFi working before running this script:
https://github.com/willardcsoriano/debian-intel-macbook-broadcom-offline

Optional — personal touchpad preferences (tap-to-click, natural scrolling,
cursor acceleration) on top of the resume fix this script installs:
https://github.com/willardcsoriano/dotfiles

---

## Version History

- **v1.8.0** — Make the install configurable: every step now belongs to one of 20 named groups selectable at runtime via `--preset`, `--only`, `--add`, and `--skip`, with `--list` and `--dry-run` to inspect a selection before committing to it. Supports machines that did not start from a bare terminal: an `existing-desktop` preset for Debian installed with the desktop + Xfce task, and — importantly — the `panel` group no longer discards an existing panel layout. It builds its clean layout by clearing every current panel item, which is correct on a bare install and destructive on a desktop the user has arranged, so it is now skipped when XFCE predates the run unless requested by name. Running with no options is unchanged and still installs everything. Splits the microphone quirk out of the webcam group (unrelated hardware, and the `mbp101` model quirk can be wrong on MacBooks the camera driver handles fine); moves the volume plugin from the media apps to `panel` where it belongs; builds the first-login panel from the plugins actually installed instead of a fixed eight-slot layout; creates Desktop shortcuts only for apps that are present; installs the XFCE power packages only when the desktop is part of the run. Documents `wifi-broadcom` and `panel`, which were undocumented, and corrects the media list — `xfce4-screenshooter` and `xfce4-clipman-plugin` arrive via `xfce4-goodies` and were never installed explicitly
- **v1.7.7** — Remove the Google Antigravity CLI (`agy`) install: it was personal tooling rather than MacBook/Debian enablement, and dropping it also removes a third-party `curl | bash` installer from the run
- **v1.7.6** — Add the Google Antigravity CLI (`agy`), installed user-space via the official upstream installer (no root, checksum-verified, idempotent); render the optional system upgrade as its own three-state **System status** line (fully up to date / upgraded / declined) instead of a mislabeled package skip, warning with a catch-up command when pending updates are declined
- **v1.7.5** — Fix the contradictory closing message (the final banner no longer says "just reboot when ready" on a run that also reports "no reboot needed"); skip the optional system-upgrade prompt entirely when every package is already current, instead of always asking then doing nothing
- **v1.7.4** — Add an optional, off-by-default `apt full-upgrade` step (runs last so a new kernel triggers automatic DKMS driver rebuilds; flags a reboot when the running kernel is superseded)
- **v1.7.3** — Correct the stale post-install repo name in `setup.sh` branding and comments; restore the README intro as an Overview and drop the duplicate contents list; document the facetimehd kernel 6.12 build caveat; bump the verified environment to Debian 13.5
- **v1.7.2** — Fix suspend/resume on Intel MacBooks: force `s2idle` (deep/S3 never resumes on this hardware, leaving the machine dead on lid-open until a hard power-off) via the `mem_sleep_default=s2idle` kernel parameter and `MemorySleepMode=s2idle`; delegate the lid to logind for `suspend-then-hibernate` so a long/overnight close hibernates instead of draining the battery flat
- **v1.7.1** — Fix App Finder launches for apps whose `.desktop` files declare `Exec=...%F/%U` file-argument placeholders; writes cleaned per-user copies to `~/.local/share/applications`
- **v1.7.0** — Add automatic security updates section: linux-image-amd64, intel-microcode, unattended-upgrades (extended to -updates pocket and VS Code repo), needrestart, fwupd with timer, AppArmor check
- **v1.6.3** — Align window title to the left for macOS style in themes.sh
- **v1.6.2** — Fix FaceTime HD webcam driver re-installing on every run; replace unreliable modinfo check with direct find on module path
- **v1.6.1** — Fix conflicting VS Code apt sources (vscode.sources vs vscode.list breaks all apt installs); use full path for swapon
- **v1.6.0** — Harden themes.sh: fix plugin ID collision, unconditional panel restart after plugin changes, --force-array for wallpaper rgba1, poll-based plank seed replacing fixed sleep, explicit Sort= ordering for dock items, Mode 3 confirmation prompt, curl-based connectivity check, dual metadata::trusted+checksum for XFCE compat; harden setup.sh connectivity check
- **v1.5.0** — Automate panel setup (battery, volume, WiFi icons added on first login — no manual steps); fix themes.sh plugin ID collision
- **v1.4.0** — Add optional theming script (WhiteSur dark theme, Plank dock, macOS-style layout)
- **v1.3.0** — Add VS Code, poppler-utils, and speech-dispatcher; drop rhythmbox
- **v1.2.0** — Harden Broadcom WiFi rebuild chain, add swap warning, refactor for readability
- **v1.1.0** — Add gdebi package installer utility
- **v1.0** — Initial release

For full release details and downloads, see [GitHub Releases](https://github.com/willardcsoriano/debian-intel-macbook-post-install/releases).

---

## Contributing

Pull requests welcome. If you test this on a different Intel MacBook model
please open an issue with your model (run: sudo dmidecode -s
system-product-name) and whether it worked, so the tested hardware list
can be updated.

---

## License

MIT
