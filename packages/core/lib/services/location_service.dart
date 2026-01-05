import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> getCurrentLocation({bool requestAlways = false}) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
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
    if (requestAlways && permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.always) {
        debugPrint(
          'Always location permission not granted, background tasks may fail.',
        );
      }
    }

    try {
      // Try to get last known position first for faster response
      // getLastKnownPosition is not supported on web
      if (!kIsWeb) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          // If last known is fresh (less than 1 minute old), return it
          final diff = DateTime.now().difference(lastKnown.timestamp);
          if (diff.inMinutes < 1) {
            return lastKnown;
          }
        }
      }

      // Otherwise get current position with a timeout
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      // Fallback to last known if current position fails
      if (!kIsWeb) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) return lastKnown;
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
  }) {
    double distanceInMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      targetLat,
      targetLng,
    );

    double effectiveRadius = radiusMeters * bufferMultiplier;

    // If using accuracy, we add the position's accuracy to the effective radius.
    // This helps in indoor environments (like factories) where GPS drift is common.
    if (useAccuracy) {
      effectiveRadius += position.accuracy;
    }

    return distanceInMeters <= effectiveRadius;
  }
}
