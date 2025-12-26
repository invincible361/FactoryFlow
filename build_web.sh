#!/bin/bash
set -e

# Install Flutter
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi

export PATH="$PATH:`pwd`/flutter/bin"

# Flutter config
flutter config --enable-web

# Build
cd flutter_application_1
flutter pub get
flutter build web --release
