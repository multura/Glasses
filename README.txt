GLASSES
=======

An open-source SwiftUI companion app for compatible AIBuds smart glasses.

The project was created with full participation from GPT-5.6-Sol. It is
provided as a community source release and may require adaptation for other
devices, firmware versions, or development environments.

Features
--------

- Discover and connect to compatible glasses over Bluetooth.
- Save devices and reconnect to previously used glasses.
- Take photos and start or stop video recording.
- Start or stop audio recording.
- Basic music playback control.
- View the media count reported by the glasses.
- Experimentally import photos and videos through the glasses hotspot.
- Automatically save imported photos and videos to Apple Photos.
- English, Russian, Ukrainian, Belarusian, and Kazakh localization.
- Light, dark, and system appearance modes.

Requirements
------------

- macOS with Xcode installed.
- A physical iPhone for Bluetooth, hotspot, camera, and media testing.
- iOS 15.0 or later.
- CocoaPods.
- Compatible glasses supported by the AIBuds SDK.

The app has not been tested with every glasses model or firmware version.
Hardware features depend on the connected device and its firmware.

Getting Started
---------------

1. Clone this repository.
2. Install CocoaPods dependencies:

       pod install

3. Open the workspace, not the project:

       open Glasses.xcworkspace

4. Select the Glasses target, a development team, and a physical iPhone.
5. Build and run the app from Xcode.

SDK
---

This project uses AIBudsSDK/ABMate from the official AIBuds SDK repository,
version 1.0.0, through CocoaPods. See Podfile for the exact dependency.

The SDK is responsible for Bluetooth device discovery and connection. The app
does not create its own CBCentralManager or implement a private Bluetooth
protocol.

Media Import
------------

Media import is experimental. It uses the glasses hotspot and the iPhone local
network rather than downloading files directly over Bluetooth.

The feature may temporarily interrupt the Bluetooth connection and may fail
depending on iOS network permissions, hotspot state, device firmware, or SDK
behavior. The app displays a disclaimer before importing unless the user turns
it off in Settings.

Required permissions include Bluetooth, local network access, and permission
to add media to Photos. The relevant descriptions are in Glasses-Info.plist.

Signing and IPA Files
--------------------

An unsigned IPA is not installable by itself. It must be signed with a valid
Apple provisioning profile before it can be installed on an iPhone.

The app also uses Hotspot Configuration and Access Wi-Fi Information
entitlements for experimental media import. A provisioning profile must allow
these capabilities for the signed build. If a profile does not contain them,
media import may fail even though the app builds successfully.

Source Release Notes
--------------------

Please do not commit:

- Apple signing certificates or private keys;
- provisioning profiles containing sensitive information;
- personal device identifiers;
- generated build archives and IPA files;
- Pods or other generated dependency directories, unless you intentionally
  choose to vendor them.

This release is published for reading, learning, experimentation, and
personal use. The maintainer is not currently accepting issue reports or pull
requests, and no support response or maintenance activity is promised.

If you make a private modification, keep your own copy of the project and
review the licenses of the AIBuds SDK and all other dependencies.

License
-------

Add the project license that you want to use before publishing the repository.
The AIBuds SDK and its dependencies may have separate licenses; review their
license terms independently.
