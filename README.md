# Poise

Poise is a macOS menu bar app that reminds you to check your posture. By default, it sends a reminder every 30 minutes on weekdays from 9 AM to 5 PM.

## Install

Requires macOS 13 or later and Swift 5.9 or later. If you need Apple's Command Line Tools, run `xcode-select --install` first.

```sh
git clone https://github.com/alexstrugacz/poise.git
cd poise
bash scripts/build.sh --install
open ~/Applications/Poise.app
```

## Use

Click **Poise** in the menu bar, choose **Enable Notifications…**, and allow notifications when macOS asks. Use **Send Test Reminder** to try it.

Use **Remind Every** and **Schedule** to change when reminders show up. You can also pause for 30 minutes or turn on **Launch at Login** from the menu.
