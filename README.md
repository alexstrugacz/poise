# Poise

Poise reminds you to check your posture from the macOS menu bar. The default is every 30 minutes on weekdays from 9 AM to 5 PM.

## Install

Requires macOS 13 or later and Swift 5.9 or later. If you need Apple's Command Line Tools, run `xcode-select --install` first.

```sh
git clone https://github.com/alexstrugacz/poise.git
cd poise
bash scripts/update.sh
open ~/Applications/Poise.app
```

## Use

Click **Poise** in the menu bar and choose **Enable Notifications…**, then try **Send Test Reminder**. Change the timing under **Remind Every** or **Schedule**.

## Update

Quit Poise, then run `bash scripts/update.sh` again from the cloned folder. It builds the latest tagged [GitHub release](https://github.com/alexstrugacz/poise/releases/latest) and installs it over your current copy. Open Poise again when it finishes.

If you cloned Poise before v1.0.2, run `git pull --ff-only` once to get the update script.
