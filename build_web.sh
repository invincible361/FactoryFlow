#!/bin/bash
set -e

# Use the current directory for Flutter
FLUTTER_PATH="$(pwd)/flutter"

if [ ! -d "$FLUTTER_PATH" ]; then
  echo "Cloning Flutter stable..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_PATH"
fi

export PATH="$PATH:$FLUTTER_PATH/bin"

echo "Flutter version:"
flutter --version

echo "Enabling web..."
flutter config --enable-web

echo "Pre-caching web artifacts..."
flutter precache --web

# Navigate to app directory if not already there
if [ -d "flutter_application_1" ]; then
  cd flutter_application_1
fi

echo "Getting dependencies..."
flutter pub get

echo "Building web release..."
flutter build web --release

echo "Build complete."
