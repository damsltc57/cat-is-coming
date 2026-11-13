# Cat Is Coming

<img src="Sources/Assets.xcassets/AppIcon.appiconset/icon-256.png" alt="A cat sitting on a keyboard" width="128">

Your cat has found the warmest seat in the house. It has 79 buttons.

**Cat Is Coming** is a small macOS menu bar app that locks your keyboard, mouse, or both while your cat settles in. Mouse lock freezes the pointer and blocks clicks, drags, and scrolling from your mouse or trackpad.

## Build and run

You’ll need **macOS 13 or later** and **Xcode 26** to build from source. Open `CatIsComing.xcodeproj` and run the **CatIsComing** scheme with **⌘R**, or use Terminal.

```sh
xcodebuild -project CatIsComing.xcodeproj -scheme CatIsComing -configuration Debug -derivedDataPath build build
open "build/Build/Products/Debug/Cat Is Coming.app"
```

Click the cat in the menu bar and choose **Allow Input Locking…**. Enable **Cat Is Coming** under **System Settings › Privacy & Security › Accessibility**. The app detects the change automatically. If macOS asks you to reopen the app, follow its prompt. The cat will handle its own access to the keyboard.

## When the cat arrives

| Action | Default shortcut |
| --- | --- |
| Lock or unlock the keyboard | ⌃⇧K |
| Lock or unlock the mouse | ⌃⇧P |
| Unlock everything | **⌃⇧Esc** |

**⌃** is Control and **⇧** is Shift. You can change the first two shortcuts in **Settings…**. The emergency shortcut is fixed.

The lock card shows what’s locked and how to get your desk back. It stays up for four seconds, or until you unlock everything. The cat is quiet by default. Turn on **Meows** in **Settings… › Notifications** to hear a different meow for locking and unlocking. You can also enable macOS banners for unlock shortcuts there.

Locks stay on until you turn them off, put your Mac to sleep, or switch sessions. During secure keyboard entry, macOS can prevent the app from receiving keyboard shortcuts.

## The paw report

Unlock the keyboard and click **View Paw Activity**, or reopen the latest report from the menu bar. Switch between **Presses** and **Held Time**, then select any key for its totals. Holding a key counts as one press, even if macOS repeats it. The app keeps only the latest session’s per-key totals in memory and collects them while the keyboard is locked.

Click **Share the Paw Prints…** to preview a PNG of the current heatmap, then save it or use the macOS share menu. The keyboard nap is the time the keyboard stayed locked. The cat may dispute the timesheet.

Enable **Open at Login** in the menu to have Cat Is Coming ready when you sign in. Keep the `.app` in a stable location so macOS can find it. The app follows your preferred language in macOS and comes in English and French.

## Quick smoke test

1. Open TextEdit, press **⌃⇧K**, and try typing. Press it again to restore the keyboard.
2. On a scrollable page, press **⌃⇧P** and try moving, clicking, and scrolling with your mouse and trackpad. The keyboard should still work.
3. Lock both inputs and check the card. Wait more than a minute to check that both inputs stay locked, then press **⌃⇧Esc** to release them.
4. Change a shortcut and reopen the app to check that it was saved. Enable notifications and check for a banner when unlocking.
5. Turn on **Open at Login** and sign out and back in. Look for the cat in the menu bar and check that both inputs are available.

## Sound credits

Both recordings are by skymary and available under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). The app uses Freesound’s high-quality previews converted to WAV, with the unlock sound reduced in volume.

- Lock meow. [cat meow short](https://freesound.org/people/skymary/sounds/412017/)
- Unlock meow. [cat purring and meow](https://freesound.org/people/skymary/sounds/412016/)
