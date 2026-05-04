# dBMeter

This is a small MacOS app that monitors audio input levels in order to warn the user if they are speaking too quietly or too loudly.

I created it to help me keep an eye on my speaking volume in video meetings.

Disclaimers:

- This app is at least 80% "vibe coded" using GitHub Copilot. It seems to run fine on my computer, but if you use it, you use it at your own risk.
- I have not verified its accuracy. It seems good enough for my purposes, but I probably wouldn't trust it if you need precise measurements.

To use, you'll need to build the app yourself:

- Clone the repository locally (or download it)
- Open it in Xcode on your computer
- Build the app with **Product** / **Build For** / **Running**
- Select **Product** / **Show Build Folder in Finder** to go to the build folder. The app is located in `Products/Debug/dB Meter.app`
- Double-click **dB Meter.app** to run it, or copy it to your **Applications** folder and run it from there