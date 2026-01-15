import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_android/geolocator_android.dart';
import '../utils/time_utils.dart';

class LocationService {
  static Position? _lastValidPosition;

  // Global access to last seen position from stream or direct fetch
  static Position? get lastValidPosition => _lastValidPosition;
  static set lastValidPosition(Position? pos) {
    if (pos != null && pos.latitude != 0) {
      _lastValidPosition = pos;
    }
  }

  Future<Position> getCurrentLocation({
    bool requestAlways = false,
    bool allowPermissionDialog = true,
  }) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      if (allowPermissionDialog) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return Future.error('Location permissions are denied');
        }
      } else {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }

    // On Android, we need to request "Always" permission specifically for background tasks
    // after "While In Use" has been granted.
    if (requestAlways &&
        permission == LocationPermission.whileInUse &&
        allowPermissionDialog) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.always) {
        debugPrint(
          'Always location permission not granted, background tasks may fail.',
        );
      }
    }

    try {
      // Try to get last known position first for faster response
      if (!kIsWeb) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          final diff = TimeUtils.nowUtc().difference(
            lastKnown.timestamp.toUtc(),
          );
          if (diff.inMinutes < 1) {
            debugPrint('LocationService: Returning fresh last known position');
            return lastKnown;
          }
        }
      }

      // Android specific settings to improve reliability in background/spoofing
      LocationSettings settings(LocationAccuracy accuracy, int timeoutSeconds) {
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          return AndroidSettings(
            accuracy: accuracy,
            timeLimit: Duration(seconds: timeoutSeconds),
            forceLocationManager:
                false, // Set to false to use Fused Location Provider (better for spoofing)
            intervalDuration: const Duration(seconds: 5),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationText: "FactoryFlow is tracking your location",
              notificationTitle: "Location Service",
              enableWakeLock: true,
            ),
          );
        }
        return LocationSettings(
          accuracy: accuracy,
          timeLimit: Duration(seconds: timeoutSeconds),
        );
      }

      // Multi-stage strategy:
      // 1) Fast attempt
      try {
        debugPrint('LocationService: Stage 1 (Fast)');
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: settings(LocationAccuracy.low, 10),
        );
        lastValidPosition = pos;
        return pos;
      } catch (_) {}

      // 2) Balanced attempt
      try {
        debugPrint('LocationService: Stage 2 (Balanced)');
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: settings(LocationAccuracy.medium, 20),
        );
        lastValidPosition = pos;
        return pos;
      } catch (_) {}

      // 3) High accuracy attempt
      try {
        debugPrint('LocationService: Stage 3 (High)');
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: settings(LocationAccuracy.high, 45),
        );
        lastValidPosition = pos;
        return pos;
      } catch (e) {
        debugPrint('LocationService: Stage 3 failed: $e');
      }

      // 4) Longer fallback with Play Services (forceLocationManager: false)
      try {
        debugPrint('LocationService: Stage 4 (Play Services Fallback)');
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 40),
          ),
        );
        lastValidPosition = pos;
        return pos;
      } catch (e) {
        debugPrint('LocationService: Stage 4 failed: $e');
      }

      // 5) Final desperate attempt: 90 second timeout
      debugPrint('LocationService: Stage 5 (Final Desperate Attempt)');
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: settings(LocationAccuracy.lowest, 90),
      );
      lastValidPosition = pos;
      return pos;
    } catch (e) {
      debugPrint('LocationService: All stages failed: $e');

      // If all GPS attempts fail, try to return our globally cached last position
      if (lastValidPosition != null) {
        debugPrint(
          'LocationService: Returning cached lastValidPosition as fallback',
        );
        // No notification here to avoid spamming, but log is useful
        return lastValidPosition!;
      }

      if (!kIsWeb) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          debugPrint(
            'LocationService: Returning system last known position as absolute final fallback',
          );
          lastValidPosition = lastKnown;
          return lastKnown;
        }
      }
      rethrow;
    }
  }

  bool isInside(
    Position position,
    double targetLat,
    double targetLng,
    double radiusMeters, {
    double bufferMultiplier = 1.0,
    bool useAccuracy = true,
    double marginMeters = 0.0,
  }) {
    double distanceInMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      targetLat,
      targetLng,
    );

    double effectiveRadius = radiusMeters * bufferMultiplier + marginMeters;

    // If using accuracy, we add the position's accuracy to the effective radius.
    // This helps in indoor environments (like factories) where GPS drift is common.
    if (useAccuracy) {
      effectiveRadius += position.accuracy;
    }

    return distanceInMeters <= effectiveRadius;
  }

  Future<Position> getHighAccuracyLocation() async {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }
}
