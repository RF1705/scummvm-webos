# Storage on LG webOS TV

## What the TV partitions mean

The root filesystem commonly reports 100% usage because it is a fixed,
read-only system image. Do not modify it.

Homebrew applications and `/media/internal` share a small writable partition.
Large game collections should not be copied there.

## Recommended: NFS network storage

The tested webOS 6.5.3 kernel provides NFS 3 and NFS 4 directly. It does not
provide CIFS/SMB. NFS therefore avoids installing a large userspace filesystem
client and keeps all game data off the TV.

Export the game directory from a NAS or Linux server, preferably read-only.
Then copy `scripts/configure-nfs-games.sh` to the rooted TV and run:

```sh
./configure-nfs-games.sh 192.168.3.20 /volume1/ScummVM 3
```

Replace the example server and export. The helper:

- mounts the share read-only at `/media/internal/scummvm-games`;
- exposes the same path inside ScummVM's native app jail;
- installs a webOSbrew startup hook for future reboots;
- leaves configuration and savegames in local app storage.

Inside ScummVM, use `/media/internal/scummvm-games` and choose **Add Games**.
The NFS server should grant access to the TV's IP address.

## USB alternative

Use a USB drive formatted with a filesystem supported by the TV and create:

```text
ScummVM/Games
ScummVM/Saves
```

The actual mount path changes depending on the connected devices. Typical
examples are:

```text
/tmp/usb/sda/sda1
/tmp/usb/sdb/sdb1
/tmp/usb/sdc/sdc1
```

The authoritative way to find it on webOS is:

```sh
luna-send -n 1 -f luna://com.webos.service.pdm/getAttachedStorageDeviceList \
  '{"subscribe":false}'
```

Look for the `mountName` value.

## Native application jail

Seeing files over SSH does not guarantee that the ScummVM application jail
can see them. On a rooted TV, first launch ScummVM once so webOS creates its
jail. Then bind the mounted USB volume into the jail:

```sh
APP_ID=org.scummvm.scummvm
USB_PATH=/tmp/usb/sda/sda1
JAIL_PATH=/var/palm/jail/$APP_ID/tmp/usb/sda/sda1

mkdir -p "$JAIL_PATH"
mount --bind "$USB_PATH" "$JAIL_PATH"
```

Inside ScummVM, browse to `/tmp/usb/sda/sda1/ScummVM/Games`.

The mount is temporary and disappears after a reboot or USB reconnect. An
automatic webOSbrew startup helper will be added after the package and path
have been verified on hardware. Hard-coding `sda` permanently is avoided
because webOS can assign a different device letter after reconnecting USB
devices.

## Internal fallback

For a small test game, `/media/internal/roms` can be used. Keep enough free
space for application updates and TV services.
