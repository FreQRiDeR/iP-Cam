#!/bin/bash

# Build for device
cd Documents/iP-Cam

xcodebuild -project iP-Cam.xcodeproj -scheme iP-Cam -configuration Release -destination generic/platform=iOS CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO clean build

# Create payload directory
mkdir -p Payload

# Copy app to payload
cp -r /Users/terramoda/Library/Developer/Xcode/DerivedData/iP-Cam-dpmgliqnrrqdczbdlsvhushynnex/Build/Products/Release-iphoneos/iP-Cam.app /Users/terramoda/Documents/iP-Cam/Payload 


# Create IPA
zip -r iP-Cam.ipa Payload/

# Cleanup
rm -rf Payload/