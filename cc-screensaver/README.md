# cc-screensaver (ComputerCraft:Tweaked)

Lua screensaver shuffler for ComputerCraft:Tweaked.

It cycles through `.lua` programs in `/screensavers`, shuffling the order and running each one for **20 seconds** by default.

## Install

### Easy install (recommended)

Host this repo somewhere reachable via raw HTTP (GitHub raw works well), then on the ComputerCraft computer run:

```
wget run <URL_TO_RAW_install.lua>
```

Or if you already have `install.lua` on the computer:

```
install --base https://raw.githubusercontent.com/<owner>/<repo>/main --startup
```

### Manual install

1. Copy [screensaver.lua](screensaver.lua) to the computer root.
2. Create a folder named `screensavers`.
3. Copy any screensaver programs (ending in `.lua`) into `/screensavers`.

Optional (auto-start on boot): copy [startup.lua](startup.lua) to the computer root.

## Usage

List discovered screensavers:

```
screensaver --list
```

Run the shuffle loop (default: 20 seconds):

```
screensaver
```

Change interval (seconds):

```
screensaver --interval 20
```

Use a different directory:

```
screensaver --dir /screensavers
```

## Screensaver contract

This launcher relies on screensavers **yielding** (e.g., using `sleep()` or `os.pullEvent()`) so they can be stopped after the time limit.

If a screensaver runs a tight loop without yielding, it cannot be safely time-sliced.
