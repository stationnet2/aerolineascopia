// travelpayouts_service.dart
//
// FIX IDA Y VUELTA + LINKS CORREGIDOS
//
// Cambios:
// 1. Ya no manda "one_way" al proxy (la API no lo usa).
// 2. Para ida y vuelta manda departure_at + return_at.
// 3. Max 2 aeropuertos por ciudad para no saturar el proxy.
// 4. Links: preservamos los query params originales de la API,
//    solo agregamos locale=es y nuestro marker. NO forzamos /es/ en el path.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../data/city_airports.dart';
import '../models/flight_alert.dart';

class NearbyDateDeal {
  final DateTime requestedDate;
  final List<FlightDeal> deals;

  const NearbyDateDeal({required this.requestedDate, required this.deals});

  FlightDeal? get cheapest => deals.isEmpty ? null : deals.first;
}

class TravelpayoutsService {
  static const String _affiliateMarker = '761958';
  static const String _proxyBaseUrl = 'https://alertatrip.com/.netlify/functions';
  static const String _currency = 'usd';

  /// Busca ofertas destacadas desde una ciudad (para el carrusel de inicio).
  Future<List<FlightDeal>> fetchSpecialOffers(String originCityId) async {
    final originAirports = airportsForCity(originCityId);
    if (originAirports.isEmpty) return [];

    final primaryAirport = originAirports.first;

    final uri = Uri.parse('$_proxyBaseUrl/special-offers').replace(queryParameters: {
      'origin': primaryAirport,
      'currency': _currency,
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      print('[TP Special] HTTP ${response.statusCode}: ${response.body}');
      return [];
    }

    final json = jsonDecode(response.body);
    if (json['success'] != true) return [];

    final actualCurrency = (json['currency'] as String? ?? _currency).toUpperCase();
    final data = json['data'] as List<dynamic>? ?? [];

    return data.map((entry) {
      final flightInfo = entry as Map<String, dynamic>;
      return FlightDeal(
        originAirportCode: flightInfo['origin_airport'] ?? primaryAirport,
        destinationAirportCode: flightInfo['destination_airport'] ?? flightInfo['destination'] ?? '',
        price: (flightInfo['price'] as num).toDouble(),
        currency: actualCurrency,
        departureDate: DateTime.parse(flightInfo['departure_at']),
        returnDate: (flightInfo['return_at'] as String?)?.isNotEmpty == true
            ? DateTime.parse(flightInfo['return_at']!)
            : null,
        airline: flightInfo['airline'] ?? '',
        affiliateLink: _buildAffiliateLinkFromApi(flightInfo),
      );
    }).toList();
  }

  /// Busca vuelos entre dos ciudades.
  Future<List<FlightDeal>> searchDeals({
    required String originCityId,
    required String destinationCityId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final originAirports = airportsForCity(originCityId);
    final destAirports = airportsForCity(destinationCityId);
    final isRoundTrip = dateFrom != null && dateTo != null;

    print('[TP] Buscando $originCityId -> $destinationCityId | '
        'ida: ${dateFrom?.toIso8601String().substring(0, 10)} | '
        'vuelta: ${dateTo?.toIso8601String().substring(0, 10)} | '
        'roundTrip=$isRoundTrip');

    // Limitamos a max 2 aeropuertos por ciudad para no saturar el proxy.
    final limitedOrigins = originAirports.take(2).toList();
    final limitedDests = destAirports.take(2).toList();

    final futures = <Future<List<FlightDeal>>>[];
    for (final origin in limitedOrigins) {
      for (final dest in limitedDests) {
        futures.add(_fetchPricesForPair(
          origin,
          dest,
          dateFrom,
          isRoundTrip ? dateTo : null,
        ));
      }
    }

    final results = await Future.wait(futures);
    final allDeals = results.expand((deals) => deals).toList();
    print('[TP] Combinada: ${allDeals.length} resultados.');

    // Fallback: si ida y vuelta no devolvio nada, buscamos por separado.
    if (isRoundTrip && allDeals.isEmpty) {
      print('[TP] Combinada vacia, probando fallback de dos tramos...');
      final fallback = await _searchRoundTripAsTwoLegs(
        originAirports: limitedOrigins,
        destAirports: limitedDests,
        departureDate: dateFrom!,
        returnDate: dateTo!,
      );
      print('[TP] Fallback: ${fallback.length} resultados.');
      return fallback;
    }

    allDeals.sort((a, b) => a.price.compareTo(b.price));
    return allDeals;
  }

  Future<List<FlightDeal>> _searchRoundTripAsTwoLegs({
    required List<String> originAirports,
    required List<String> destAirports,
    required DateTime departureDate,
    required DateTime returnDate,
  }) async {
    final outboundFutures = <Future<List<FlightDeal>>>[];
    final inboundFutures = <Future<List<FlightDeal>>>[];

    for (final origin in originAirports) {
      for (final dest in destAirports) {
        outboundFutures.add(_fetchPricesForPair(origin, dest, departureDate, null));
        inboundFutures.add(_fetchPricesForPair(dest, origin, returnDate, null));
      }
    }

    final outboundResults = (await Future.wait(outboundFutures)).expand((d) => d).toList();
    final inboundResults = (await Future.wait(inboundFutures)).expand((d) => d).toList();

    print('[TP] Fallback - ida: ${outboundResults.length} | vuelta: ${inboundResults.length}');

    if (outboundResults.isEmpty || inboundResults.isEmpty) return [];

    outboundResults.sort((a, b) => a.price.compareTo(b.price));
    inboundResults.sort((a, b) => a.price.compareTo(b.price));

    final cheapestOutbound = outboundResults.first;
    final cheapestInbound = inboundResults.first;

    final combinedPrice = cheapestOutbound.price + cheapestInbound.price;
    final combinedLink = _buildTwoLegRoundTripLink(
      origin: cheapestOutbound.originAirportCode,
      destination: cheapestOutbound.destinationAirportCode,
      departureDate: departureDate,
      returnDate: returnDate,
    );

    return [
      FlightDeal(
        originAirportCode: cheapestOutbound.originAirportCode,
        destinationAirportCode: cheapestOutbound.destinationAirportCode,
        price: combinedPrice,
        currency: cheapestOutbound.currency,
        departureDate: cheapestOutbound.departureDate,
        returnDate: cheapestInbound.departureDate,
        airline: cheapestOutbound.airline,
        affiliateLink: combinedLink,
        transfers: cheapestOutbound.transfers,
        durationMinutes: null,
      ),
    ];
  }

  Future<List<FlightDeal>> _fetchPricesForPair(
    String originCode,
    String destCode,
    DateTime? dateFrom,
    DateTime? dateTo,
  ) async {
    final queryParams = <String, String>{
      'origin': originCode,
      'destination': destCode,
      'currency': _currency,
      if (dateFrom != null) 'departure_at': _formatApiDate(dateFrom),
      if (dateTo != null) 'return_at': _formatApiDate(dateTo),
    };

    final uri = Uri.parse('$_proxyBaseUrl/search-flights').replace(queryParameters: queryParams);

    print('[TP] GET $uri');

    final response = await http.get(uri);
    print('[TP] Response HTTP ${response.statusCode}');

    if (response.statusCode != 200) {
      print('[TP] Error body: ${response.body}');
      return [];
    }

    final json = jsonDecode(response.body);
    if (json['success'] != true) {
      print('[TP] success=false: ${response.body}');
      return [];
    }

    final actualCurrency = (json['currency'] as String? ?? _currency).toUpperCase();
    final data = json['data'] as List<dynamic>? ?? [];
    print('[TP] $originCode -> $destCode: ${data.length} resultados');

    return data.map((entry) {
      final flightInfo = entry as Map<String, dynamic>;
      return FlightDeal(
        originAirportCode: flightInfo['origin_airport'] ?? originCode,
        destinationAirportCode: flightInfo['destination_airport'] ?? destCode,
        price: (flightInfo['price'] as num).toDouble(),
        currency: actualCurrency,
        departureDate: DateTime.parse(flightInfo['departure_at']),
        returnDate: flightInfo['return_at'] != null && (flightInfo['return_at'] as String).isNotEmpty
            ? DateTime.parse(flightInfo['return_at'])
            : null,
        airline: flightInfo['airline'] ?? '',
        affiliateLink: _buildAffiliateLinkFromApi(flightInfo),
        transfers: flightInfo['transfers'] ?? 0,
        durationMinutes: flightInfo['duration'],
      );
    }).toList();
  }

  /// >>> FIX DEL LINK <<<
  /// Usa el campo "link" que devuelve la API de Travelpayouts.
  /// Preserva TODOS los query params originales y solo agrega/sobrescribe
  /// locale=es y nuestro marker. NO forzamos /es/ en el path porque
  /// Aviasales maneja el idioma por query param, no por path.
  String _buildAffiliateLinkFromApi(Map<String, dynamic> flightInfo) {
    final rawLink = (flightInfo['link'] ?? '').toString().trim();
    if (rawLink.isEmpty) return '';

    final source = Uri.tryParse(rawLink);
    if (source == null || source.path.isEmpty) return '';

    // Preservamos los query params originales del link de la API
    // (pueden incluir parametros de tracking importantes)
    final params = Map<String, String>.from(source.queryParameters);
    params['marker'] = _affiliateMarker;
    params['locale'] = 'es';

    return Uri.parse('https://www.aviasales.com')
        .replace(path: source.path, queryParameters: params)
        .toString();
  }

  /// Link manual para el fallback de dos tramos (cuando la API no tiene
  /// ida y vuelta combinado). Mismo formato que el link de la API.
  String _buildTwoLegRoundTripLink({
    required String origin,
    required String destination,
    required DateTime departureDate,
    required DateTime returnDate,
  }) {
    final path = '/search/${origin.toUpperCase()}${_ddmmFromDate(departureDate)}'
        '${destination.toUpperCase()}${_ddmmFromDate(returnDate)}1';
    return Uri.parse('https://www.aviasales.com')
        .replace(path: path, queryParameters: {
          'marker': _affiliateMarker,
          'locale': 'es',
        })
        .toString();
  }

  String _ddmmFromDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}${d.month.toString().padLeft(2, '0')}';

  String _formatApiDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Busca fechas disponibles cercanas a la fecha elegida.
  Future<List<NearbyDateDeal>> searchNearestAvailableDates({
    required String originCityId,
    required String destinationCityId,
    required DateTime departureDate,
    DateTime? returnDate,
    int previousCount = 2,
    int nextCount = 2,
    int maxDaysEachSide = 60,
  }) async {
    final previous = <NearbyDateDeal>[];
    final next = <NearbyDateDeal>[];
    final tripLength = returnDate == null
        ? null
        : returnDate.difference(departureDate).inDays;

    Future<NearbyDateDeal?> searchAt(DateTime date) async {
      final shiftedReturn = tripLength == null
          ? null
          : date.add(Duration(days: tripLength));
      final deals = await searchDeals(
        originCityId: originCityId,
        destinationCityId: destinationCityId,
        dateFrom: date,
        dateTo: shiftedReturn,
      );
      if (deals.isEmpty) return null;
      return NearbyDateDeal(requestedDate: date, deals: deals);
    }

    for (var offset = 1;
        offset <= maxDaysEachSide &&
            (previous.length < previousCount || next.length < nextCount);
        offset++) {
      if (previous.length < previousCount) {
        final date = departureDate.subtract(Duration(days: offset));
        if (!date.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
          final result = await searchAt(date);
          if (result != null) previous.add(result);
        }
      }
      if (next.length < nextCount) {
        final date = departureDate.add(Duration(days: offset));
        final result = await searchAt(date);
        if (result != null) next.add(result);
      }
    }

    previous.sort((a, b) => a.requestedDate.compareTo(b.requestedDate));
    next.sort((a, b) => a.requestedDate.compareTo(b.requestedDate));
    return [...previous, ...next];
  }
}
