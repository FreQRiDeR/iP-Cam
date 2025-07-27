#!/bin/bash

# Build for device
xcodebuild -project iP-Cam.xcodeproj -scheme iP-Cam -configuration Release -destination generic/platform=iOS CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO clean build

# Create payload directory
mkdir -p Payload

# Copy app to payload
cp -r build/Release-iphoneos/iP-Cam.app Payload/

# Create IPA
zip -r iP-Cam-unsigned.ipa Payload/

# Cleanup
rm -rf Payload/