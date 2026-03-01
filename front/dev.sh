#!/bin/bash

echo "Starting Flutter app in development mode..."
echo ""
echo "Available devices:"
flutter devices
echo ""
echo "Starting on Chrome (web)..."
echo "Press 'r' for hot reload, 'R' for hot restart, 'q' to quit"
echo ""

# Let Flutter pick an available port automatically
flutter run -d chrome

