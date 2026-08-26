// location_service.dart
//
// Detecta la ubicación aproximada del celular y encuentra la ciudad
// (de nuestra lista de aeropuertos) más cercana. Esto es lo que
// permite que la app diga "estás cerca de Buenos Aires" sin que el
// usuario tenga que elegir nada a mano.
//
// Usamos precisión BAJA a propósito (LocationAccuracy.low): alcanza
// de sobra para saber en qué ciudad/provincia estás, y consume mucha
// menos batería que pedir la ubicación exacta.

import 'dart:ui' show PlatformDispatcher;
import 'package:geolocator/geolocator.dart';
import '../data/city_airports.dart';

/// Código de país (2 letras, ej "AR", "BR", "UY") según la
/// configuración de idioma/región del celular — no requiere GPS ni
/// ningún permiso, y es bastante confiable: la gente casi nunca
/// cambia la región de su teléfono de la de su propio país. Se usa
/// para decidir qué "destinos populares" mostrar (ver
/// popularDestinationsFor() en city_airports.dart), no para detectar
/// la ciudad de origen exacta — para eso sigue sirviendo el GPS.
String? currentCountryCode() {
  return PlatformDispatcher.instance.locale.countryCode;
}

class LocationService {
  /// Devuelve la ciudad más cercana a la ubicación actual del
  /// celular, o null si no se pudo obtener (sin permiso, GPS
  /// apagado, o ninguna ciudad conocida cerca).
  Future<CityGroup?> detectNearestCity() async {
    final hasPermission = await _ensurePermission();
    if (!hasPermission) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );
      return nearestCityGroup(position.latitude, position.longitude);
    } catch (_) {
      // Falló obtener la ubicación (GPS apagado, timeout, etc). No es
      // grave: el usuario simplemente elige la ciudad a mano.
      return null;
    }
  }

  Future<bool> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }
}
