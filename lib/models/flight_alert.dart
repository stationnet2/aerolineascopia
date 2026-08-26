// flight_alert.dart
//
// Representa una alerta configurada por el usuario: "avisame si baja
// el precio de Córdoba a Buenos Aires en agosto, por debajo de $80.000".

class FlightAlert {
  final String id;
  final String userId;
  final String originCityId; // ej "cordoba"
  final String destinationCityId; // ej "buenos_aires"
  final DateTime? dateFrom; // null = fechas flexibles
  final DateTime? dateTo;
  final bool flexibleDates;
  final double? maxPrice; // null = "avisame de cualquier baja significativa"
  final double alertThresholdPercent; // ej 20.0 = avisar si baja 20% o más
  final bool isActive;
  final DateTime createdAt;
  final double? lastKnownPrice; // para comparar y detectar bajas
  final int passengers; // cantidad de pasajeros (siempre >= 1)

  const FlightAlert({
    required this.id,
    required this.userId,
    required this.originCityId,
    required this.destinationCityId,
    this.dateFrom,
    this.dateTo,
    this.flexibleDates = false,
    this.maxPrice,
    this.alertThresholdPercent = 15.0,
    this.isActive = true,
    required this.createdAt,
    this.lastKnownPrice,
    this.passengers = 1,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'originCityId': originCityId,
      'destinationCityId': destinationCityId,
      'dateFrom': dateFrom?.toIso8601String(),
      'dateTo': dateTo?.toIso8601String(),
      'flexibleDates': flexibleDates,
      'maxPrice': maxPrice,
      'alertThresholdPercent': alertThresholdPercent,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'lastKnownPrice': lastKnownPrice,
      'passengers': passengers,
    };
  }

  factory FlightAlert.fromFirestore(String id, Map<String, dynamic> data) {
    return FlightAlert(
      id: id,
      userId: data['userId'],
      originCityId: data['originCityId'],
      destinationCityId: data['destinationCityId'],
      dateFrom: data['dateFrom'] != null ? DateTime.parse(data['dateFrom']) : null,
      dateTo: data['dateTo'] != null ? DateTime.parse(data['dateTo']) : null,
      flexibleDates: data['flexibleDates'] ?? false,
      maxPrice: data['maxPrice']?.toDouble(),
      alertThresholdPercent: (data['alertThresholdPercent'] ?? 15.0).toDouble(),
      isActive: data['isActive'] ?? true,
      createdAt: DateTime.parse(data['createdAt']),
      lastKnownPrice: data['lastKnownPrice']?.toDouble(),
      passengers: data['passengers'] ?? 1,
    );
  }
}

// Una oferta puntual encontrada, lista para mostrar y para generar
// el link de afiliado.
class FlightDeal {
  final String originAirportCode; // ej "COR"
  final String destinationAirportCode; // ej "AEP" (puede no ser el que el usuario esperaba)
  final double price;
  final String currency; // Código real devuelto por la API (ej "USD"), no un valor fijo
  final DateTime departureDate;
  final DateTime? returnDate; // null = solo ida
  final String airline;
  final String affiliateLink;
  final int transfers; // cantidad de escalas de ida (0 = vuelo directo)
  final int? durationMinutes; // duración total del viaje en minutos, si está disponible

  const FlightDeal({
    required this.originAirportCode,
    required this.destinationAirportCode,
    required this.price,
    required this.currency,
    required this.departureDate,
    this.returnDate,
    required this.airline,
    required this.affiliateLink,
    this.transfers = 0,
    this.durationMinutes,
  });

  bool get isRoundTrip => returnDate != null;
}
