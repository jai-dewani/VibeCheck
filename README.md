# VibeCheck

VibeCheck is a lightweight native iOS app to record and analyze vibrations transmitted to an iPhone mounted on a motorcycle handlebar. It polls the accelerometer at 100 Hz and logs the data to CSV files that you can export.

## Setup Instructions

Since you are setting this up manually via Xcode (to use a free personal Apple ID without requiring paid developer certificates), please follow these instructions carefully:

1. **Open Xcode** and select **Create a new Xcode project**.
2. Select **App** under the iOS tab and click **Next**.
3. Fill in the details:
   - **Product Name:** VibeCheck
   - **Team:** Select your Personal Team (or add your Apple ID if you haven't already).
   - **Organization Identifier:** (e.g., `com.yourname`)
   - **Interface:** SwiftUI
   - **Language:** Swift
4. Click **Next** and choose the directory `/Users/jaikumardewani/Projects/VibeCheck` to save it (it's okay to overwrite or place it next to these files).
   *(Alternatively, save it anywhere, and then drag-and-drop the provided `.swift` files into your new project).*

5. **Replace the generated files** in your Xcode project with the ones I've provided in the `VibeCheck/` folder:
   - `VibeCheckApp.swift`
   - `ContentView.swift`
   - `MotionManager.swift`
   - `Info.plist` (To add `Info.plist` values in modern Xcode 14+, go to your Project Target -> Info tab, and add the row for `Privacy - Motion Usage Description` with the value `VibeCheck needs accelerometer access to record handlebar vibrations.`. Also add `Supports opening documents in place` and set it to `YES`).

6. **Connect your iPhone 13** via USB.
7. Select your iPhone as the run destination at the top of the Xcode window.
8. Press **Cmd + R** to Build and Run.

### Note on First Launch
If this is the first time running an app from your free developer account on your iPhone:
- You will get an "Untrusted Developer" error.
- Go to your iPhone's **Settings -> General -> VPN & Device Management**.
- Tap your Apple ID email and tap **Trust**.
- You can now open the app on your phone.

The app uses `UIApplication.shared.isIdleTimerDisabled` to keep the screen alive during recording. You can dim the screen, but do not lock the phone, as iOS suspends accelerometer polling in the background without active GPS or audio sessions.
