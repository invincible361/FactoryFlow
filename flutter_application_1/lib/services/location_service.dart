import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> getCurrentLocation() async {
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

    // For background tasks, we ideally want "always" permission.
    // However, on some platforms, we can only request "always" after "whileInUse".
    // This is a simplified check.
    if (permission == LocationPermission.whileInUse) {
      // In a real app, you might want to explain WHY you need background access
      // before calling requestPermission() again to get "always".
      debugPrint(
        'Location permission is whileInUse, background tasks might be limited.',
      );
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  bool isInside(
    Position position,
    double targetLat,
    double targetLng,
    double radiusMeters,
  ) {
    double distanceInMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      targetLat,
      targetLng,
    );
    return distanceInMeters <= radiusMeters;
  }
}
