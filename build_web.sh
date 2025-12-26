#!/bin/bash
set -e

# Use a local directory for Flutter to ensure persistence within the build environment
FLUTTER_PATH="$(pwd)/.flutter"

if [ ! -d "$FLUTTER_PATH" ]; then
  echo "Cloning Flutter stable..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_PATH"
fi

export PATH="$FLUTTER_PATH/bin:$PATH"

echo "Flutter version:"
flutter --version

echo "Enabling web..."
flutter config --enable-web

# Navigate to app directory
cd flutter_application_1

echo "Getting dependencies..."
flutter pub get

echo "Building web release..."
flutter build web --release --base-href "/"

echo "Build complete."
