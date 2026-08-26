// city_airports.dart
//
// Acá vive el "problema de los aeropuertos cercanos": alguien busca
// vuelos a "Buenos Aires" y eso puede significar aterrizar en Ezeiza
// (EZE, a 35km del centro) o en Aeroparque (AEP, dentro de CABA). Si
// el usuario solo mira EZE, se pierde ofertas que llegan a AEP y
// viceversa.
//
// La solución: agrupamos aeropuertos por "ciudad/área metropolitana".
// Cuando el usuario elige una ciudad, buscamos precios en TODOS los
// aeropuertos de ese grupo y mostramos el más barato, indicando a cuál
// aeropuerto corresponde cada oferta.
//
// Cada aeropuerto también tiene latitud/longitud, que se usan para
// detectar automáticamente la ciudad más cercana a partir de la
// ubicación del celular (ver location_service.dart).

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class Airport {
  final String iataCode; // Código de 3 letras, ej "EZE"
  final String name; // Nombre completo, ej "Ministro Pistarini"
  final String cityGroupId; // A qué grupo/ciudad pertenece
  final bool isPrimary; // Si es el aeropuerto "principal" de esa ciudad
  final double lat;
  final double lng;

  const Airport({
    required this.iataCode,
    required this.name,
    required this.cityGroupId,
    this.isPrimary = false,
    required this.lat,
    required this.lng,
  });
}

class CityGroup {
  final String id; // Identificador único, ej "buenos_aires"
  final String displayName; // Lo que ve el usuario, ej "Buenos Aires"
  final String country;
  final List<String> airportCodes; // IATA codes de todos los aeropuertos del grupo
  final String? imageUrl; // Foto para el carrusel "Explorá destinos"
  // Datos para armar el link de hoteles de Klook para esta ciudad — ver
  // klook.com/es/hoteles, buscar la ciudad, y copiar stype/svalue/city_id
  // de la URL resultante.
  final String? klookSvalue;
  final String klookStype;
  final String? klookCityId;

  const CityGroup({
    required this.id,
    required this.displayName,
    required this.country,
    required this.airportCodes,
    this.imageUrl,
    this.klookSvalue,
    this.klookStype = 'city',
    this.klookCityId,
  });
}

// ---------------------------------------------------------------------
// CATÁLOGO DE DESTINOS
// ---------------------------------------------------------------------
// `allAirports` y `cityGroups` arrancan con este catálogo hardcodeado
// como respaldo (para que la app funcione aunque sea la primerísima vez
// que se abre, sin conexión). Apenas hay internet, `refreshDestinationsFromFirestore()`
// reemplaza el contenido de estas mismas listas con lo que haya cargado
// en Firestore (colección "destinations") — así, para agregar, editar o
// sacar un destino, alcanza con tocar Firestore desde Firebase Console,
// sin volver a compilar ni pedirle a nadie que reinstale la app.
//
// Importante: son `List` normales (no `const`), pero se modifican con
// `.clear()` + `.addAll()` en vez de reasignar la variable — así,
// cualquier código que ya haya guardado una referencia a `cityGroups`
// (como este mismo archivo) sigue viendo los datos actualizados.
List<Airport> allAirports = List.of(_hardcodedAirports);
List<CityGroup> cityGroups = List.of(_buildCityGroups(_hardcodedAirports));

/// Trae el catálogo de destinos desde Firestore y reemplaza el contenido
/// de `allAirports`/`cityGroups`. Se llama una vez al arrancar la app
/// (ver main.dart), sin bloquear el primer frame. Si falla (sin
/// conexión, Firestore caído, etc.) no rompe nada: la app sigue
/// funcionando con el catálogo hardcodeado de respaldo.
Future<void> refreshDestinationsFromFirestore() async {
  final snapshot = await FirebaseFirestore.instance.collection('destinations').get();
  if (snapshot.docs.isEmpty) return; // Colección vacía o sin migrar todavía: seguimos con el respaldo.

  final newAirports = <Airport>[];
  final newCityGroups = <CityGroup>[];

  for (final doc in snapshot.docs) {
    final data = doc.data();
    final airportsData = (data['airports'] as List<dynamic>? ?? []);
    final airportCodes = <String>[];
    for (final a in airportsData) {
      final map = a as Map<String, dynamic>;
      airportCodes.add(map['code'] as String);
      newAirports.add(Airport(
        iataCode: map['code'] as String,
        name: (map['name'] as String?) ?? map['code'] as String,
        cityGroupId: doc.id,
        isPrimary: map['isPrimary'] as bool? ?? false,
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
      ));
    }
    if (airportCodes.isEmpty) continue; // Documento incompleto: lo salteamos.

    newCityGroups.add(CityGroup(
      id: doc.id,
      displayName: (data['displayName'] as String?) ?? doc.id,
      country: (data['country'] as String?) ?? '',
      airportCodes: airportCodes,
      imageUrl: data['imageUrl'] as String?,
      klookSvalue: data['klookSvalue'] as String?,
      klookStype: (data['klookStype'] as String?) ?? 'city',
      klookCityId: data['klookCityId'] as String?,
    ));
  }

  if (newCityGroups.isEmpty) return;
  allAirports
    ..clear()
    ..addAll(newAirports);
  cityGroups
    ..clear()
    ..addAll(newCityGroups);
}

// ---------------------------------------------------------------------
// DESTINOS POPULARES POR PAÍS
// ---------------------------------------------------------------------
// Qué destinos se muestran como "accesos rápidos" al elegir origen o
// destino, según en qué país esté el usuario (ver
// currentCountryCode() en location_service.dart). Arranca con este
// respaldo hardcodeado (Argentina como caso por default, porque es
// donde arrancó el proyecto) y se actualiza con lo que haya en
// Firestore (colección "popular_destinations", un documento por
// código de país de 2 letras + uno "default" para cualquier país sin
// lista propia todavía) — editable desde panel.html o Firebase
// Console, sin volver a compilar.
Map<String, List<String>> popularByCountryCode = {
  'AR': ['buenos_aires', 'cordoba', 'mendoza', 'bariloche', 'sao_paulo', 'rio_de_janeiro', 'santiago', 'montevideo', 'asuncion', 'lima', 'madrid', 'barcelona', 'roma', 'paris', 'londres', 'frankfurt', 'new_york', 'miami', 'ciudad_de_mexico', 'dubai', 'tokio', 'estambul'],
  'default': ['madrid', 'barcelona', 'paris', 'londres', 'roma', 'new_york', 'miami', 'dubai', 'tokio', 'ciudad_de_mexico', 'buenos_aires', 'sao_paulo', 'lisboa', 'amsterdam', 'estambul', 'bangkok'],
};

/// Trae el mapa de destinos populares por país desde Firestore y
/// reemplaza `popularByCountryCode`. Igual que con `refreshDestinationsFromFirestore()`,
/// si falla no rompe nada: sigue con el respaldo hardcodeado de arriba.
Future<void> refreshPopularDestinationsFromFirestore() async {
  final snapshot = await FirebaseFirestore.instance.collection('popular_destinations').get();
  if (snapshot.docs.isEmpty) return;

  final newMap = <String, List<String>>{};
  for (final doc in snapshot.docs) {
    final ids = (doc.data()['cityIds'] as List<dynamic>?)?.cast<String>() ?? [];
    if (ids.isNotEmpty) newMap[doc.id] = ids;
  }
  if (newMap.isEmpty) return;
  popularByCountryCode
    ..clear()
    ..addAll(newMap);
}

/// Devuelve la lista de ciudades populares para mostrar como accesos
/// rápidos, según el país del usuario. Si no hay lista propia para ese
/// país, usa la lista "default" (destinos internacionales genéricos)
/// en vez de mostrar la lista de otro país al azar.
List<CityGroup> popularDestinationsFor(String? countryCode) {
  final ids = popularByCountryCode[countryCode] ?? popularByCountryCode['default'] ?? [];
  return ids.map((id) => cityGroups.where((c) => c.id == id).firstOrNull).whereType<CityGroup>().toList();
}

 //(solo se usa si Firestore no)
// responde a tiempo — normalmente los datos reales vienen de ahí)
// ---------------------------------------------------------------------
const List<Airport> _hardcodedAirports = [
  // ===================== ARGENTINA =====================

  // --- Buenos Aires (el caso de los 2 aeropuertos) ---
  Airport(iataCode: 'EZE', name: 'Ministro Pistarini (Ezeiza)', cityGroupId: 'buenos_aires', isPrimary: true, lat: -34.8222, lng: -58.5358),
  Airport(iataCode: 'AEP', name: 'Aeroparque Jorge Newbery', cityGroupId: 'buenos_aires', lat: -34.5592, lng: -58.4156),

  Airport(iataCode: 'COR', name: 'Ingeniero Ambrosio Taravella', cityGroupId: 'cordoba', isPrimary: true, lat: -31.3236, lng: -64.2080),
  Airport(iataCode: 'ROS', name: 'Islas Malvinas', cityGroupId: 'rosario', isPrimary: true, lat: -32.9036, lng: -60.7850),
  Airport(iataCode: 'MDZ', name: 'El Plumerillo', cityGroupId: 'mendoza', isPrimary: true, lat: -32.8317, lng: -68.7929),
  Airport(iataCode: 'BRC', name: 'Teniente Luis Candelaria', cityGroupId: 'bariloche', isPrimary: true, lat: -41.1512, lng: -71.1575),
  Airport(iataCode: 'MDQ', name: 'Astor Piazzolla', cityGroupId: 'mar_del_plata', isPrimary: true, lat: -37.9342, lng: -57.5733),
  Airport(iataCode: 'SLA', name: 'Martín Miguel de Güemes', cityGroupId: 'salta', isPrimary: true, lat: -24.8425, lng: -65.4861),
  Airport(iataCode: 'IGR', name: 'Cataratas del Iguazú', cityGroupId: 'iguazu', isPrimary: true, lat: -25.7373, lng: -54.4734),
  Airport(iataCode: 'USH', name: 'Malvinas Argentinas', cityGroupId: 'ushuaia', isPrimary: true, lat: -54.8433, lng: -68.2958),
  Airport(iataCode: 'NQN', name: 'Presidente Perón', cityGroupId: 'neuquen', isPrimary: true, lat: -38.9490, lng: -68.1557),
  Airport(iataCode: 'TUC', name: 'Teniente General Benjamín Matienzo', cityGroupId: 'tucuman', isPrimary: true, lat: -26.8409, lng: -65.1048),
  Airport(iataCode: 'CRD', name: 'General Enrique Mosconi', cityGroupId: 'comodoro_rivadavia', isPrimary: true, lat: -45.7853, lng: -67.4655),
  Airport(iataCode: 'BHI', name: 'Comandante Espora', cityGroupId: 'bahia_blanca', isPrimary: true, lat: -38.7247, lng: -62.1693),
  Airport(iataCode: 'PSS', name: 'Libertador General José de San Martín', cityGroupId: 'posadas', isPrimary: true, lat: -27.3858, lng: -55.9707),
  Airport(iataCode: 'RES', name: 'Resistencia', cityGroupId: 'resistencia', isPrimary: true, lat: -27.4500, lng: -59.0561),
  Airport(iataCode: 'FTE', name: 'Comandante Armando Tola', cityGroupId: 'el_calafate', isPrimary: true, lat: -50.2803, lng: -72.0531),
  Airport(iataCode: 'JUJ', name: 'Gobernador Horacio Guzmán', cityGroupId: 'jujuy', isPrimary: true, lat: -24.3928, lng: -65.0978),

  // --- Nuevas: resto de provincias con aeropuerto comercial ---
  Airport(iataCode: 'UAQ', name: 'Domingo Faustino Sarmiento', cityGroupId: 'san_juan', isPrimary: true, lat: -31.5717, lng: -68.4183),
  Airport(iataCode: 'LUQ', name: 'Brigadier Mayor César Raúl Ojeda', cityGroupId: 'san_luis', isPrimary: true, lat: -33.2731, lng: -66.3567),
  Airport(iataCode: 'RSA', name: 'Santa Rosa', cityGroupId: 'santa_rosa', isPrimary: true, lat: -36.5883, lng: -64.2757),
  Airport(iataCode: 'SDE', name: 'Santiago del Estero', cityGroupId: 'santiago_del_estero', isPrimary: true, lat: -27.7658, lng: -64.3097),
  Airport(iataCode: 'CTC', name: 'Catamarca', cityGroupId: 'catamarca', isPrimary: true, lat: -28.5958, lng: -65.7514),
  Airport(iataCode: 'IRJ', name: 'Capitán Vicente Almandos Almonacid', cityGroupId: 'la_rioja', isPrimary: true, lat: -29.3816, lng: -66.7959),
  Airport(iataCode: 'PRA', name: 'General Justo José de Urquiza', cityGroupId: 'parana', isPrimary: true, lat: -31.7948, lng: -60.4805),
  Airport(iataCode: 'CNQ', name: 'Doctor Fernando Piragine Niveyro', cityGroupId: 'corrientes', isPrimary: true, lat: -27.4455, lng: -58.7619),
  Airport(iataCode: 'FMA', name: 'Formosa', cityGroupId: 'formosa', isPrimary: true, lat: -26.2127, lng: -58.2281),
  Airport(iataCode: 'REL', name: 'Almirante Marcos A. Zar (Trelew / Puerto Madryn)', cityGroupId: 'trelew', isPrimary: true, lat: -43.2105, lng: -65.2703),
  Airport(iataCode: 'EQS', name: 'Brigadier Antonio Parodi', cityGroupId: 'esquel', isPrimary: true, lat: -42.9080, lng: -71.1395),
  Airport(iataCode: 'VDM', name: 'Gobernador Edgardo Castello', cityGroupId: 'viedma', isPrimary: true, lat: -40.8692, lng: -63.0000),
  Airport(iataCode: 'RGL', name: 'Piloto Civil Norberto Fernández', cityGroupId: 'rio_gallegos', isPrimary: true, lat: -51.6089, lng: -69.3126),
  Airport(iataCode: 'RGA', name: 'Río Grande', cityGroupId: 'rio_grande', isPrimary: true, lat: -53.7777, lng: -67.7494),

  // ===================== BRASIL =====================
  Airport(iataCode: 'GRU', name: 'Guarulhos', cityGroupId: 'sao_paulo', isPrimary: true, lat: -23.4356, lng: -46.4731),
  Airport(iataCode: 'CGH', name: 'Congonhas', cityGroupId: 'sao_paulo', lat: -23.6266, lng: -46.6558),
  Airport(iataCode: 'GIG', name: 'Galeão', cityGroupId: 'rio_de_janeiro', isPrimary: true, lat: -22.8090, lng: -43.2506),
  Airport(iataCode: 'SDU', name: 'Santos Dumont', cityGroupId: 'rio_de_janeiro', lat: -22.9105, lng: -43.1634),
  Airport(iataCode: 'FLN', name: 'Hercílio Luz', cityGroupId: 'florianopolis', isPrimary: true, lat: -27.6705, lng: -48.5477),
  Airport(iataCode: 'SSA', name: 'Deputado Luís Eduardo Magalhães', cityGroupId: 'salvador_bahia', isPrimary: true, lat: -12.9086, lng: -38.3225),

  // ===================== RESTO DE SUDAMÉRICA =====================
  Airport(iataCode: 'SCL', name: 'Arturo Merino Benítez', cityGroupId: 'santiago', isPrimary: true, lat: -33.3930, lng: -70.7858),
  Airport(iataCode: 'MVD', name: 'Carrasco', cityGroupId: 'montevideo', isPrimary: true, lat: -34.8384, lng: -56.0308),
  Airport(iataCode: 'PDP', name: 'Capitán de Corbeta Carlos A. Curbelo', cityGroupId: 'punta_del_este', isPrimary: true, lat: -34.8556, lng: -55.0956),
  Airport(iataCode: 'ASU', name: 'Silvio Pettirossi', cityGroupId: 'asuncion', isPrimary: true, lat: -25.2400, lng: -57.5200),
  Airport(iataCode: 'LIM', name: 'Jorge Chávez', cityGroupId: 'lima', isPrimary: true, lat: -12.0219, lng: -77.1143),
  Airport(iataCode: 'CUZ', name: 'Alejandro Velasco Astete', cityGroupId: 'cusco', isPrimary: true, lat: -13.5357, lng: -71.9388),
  Airport(iataCode: 'BOG', name: 'El Dorado', cityGroupId: 'bogota', isPrimary: true, lat: 4.7016, lng: -74.1469),
  Airport(iataCode: 'CTG', name: 'Rafael Núñez', cityGroupId: 'cartagena', isPrimary: true, lat: 10.4424, lng: -75.5130),
  Airport(iataCode: 'LPB', name: 'El Alto', cityGroupId: 'la_paz', isPrimary: true, lat: -16.5133, lng: -68.1925),

  // ===================== NORTE Y CENTROAMÉRICA / CARIBE =====================
  Airport(iataCode: 'MEX', name: 'Ciudad de México (AICM)', cityGroupId: 'ciudad_de_mexico', isPrimary: true, lat: 19.4363, lng: -99.0721),
  Airport(iataCode: 'CUN', name: 'Cancún', cityGroupId: 'cancun', isPrimary: true, lat: 21.0365, lng: -86.8771),
  Airport(iataCode: 'PUJ', name: 'Punta Cana', cityGroupId: 'punta_cana', isPrimary: true, lat: 18.5674, lng: -68.3634),
  Airport(iataCode: 'AUA', name: 'Reina Beatrix', cityGroupId: 'aruba', isPrimary: true, lat: 12.5014, lng: -70.0152),
  Airport(iataCode: 'MIA', name: 'Miami International', cityGroupId: 'miami', isPrimary: true, lat: 25.7959, lng: -80.2870),
  Airport(iataCode: 'FLL', name: 'Fort Lauderdale-Hollywood', cityGroupId: 'fort_lauderdale', isPrimary: true, lat: 26.0726, lng: -80.1527),
  Airport(iataCode: 'MCO', name: 'Orlando International', cityGroupId: 'orlando', isPrimary: true, lat: 28.4312, lng: -81.3081),
  Airport(iataCode: 'JFK', name: 'John F. Kennedy', cityGroupId: 'new_york', isPrimary: true, lat: 40.6413, lng: -73.7781),
  Airport(iataCode: 'EWR', name: 'Newark Liberty', cityGroupId: 'new_york', lat: 40.6895, lng: -74.1745),
  Airport(iataCode: 'LGA', name: 'LaGuardia', cityGroupId: 'new_york', lat: 40.7769, lng: -73.8740),
  Airport(iataCode: 'LAX', name: 'Los Angeles International', cityGroupId: 'los_angeles', isPrimary: true, lat: 33.9416, lng: -118.4085),
  Airport(iataCode: 'LAS', name: 'Harry Reid International', cityGroupId: 'las_vegas', isPrimary: true, lat: 36.0840, lng: -115.1537),

  // ===================== EUROPA =====================
  Airport(iataCode: 'MAD', name: 'Adolfo Suárez Barajas', cityGroupId: 'madrid', isPrimary: true, lat: 40.4936, lng: -3.5668),
  Airport(iataCode: 'BCN', name: 'El Prat', cityGroupId: 'barcelona', isPrimary: true, lat: 41.2971, lng: 2.0785),
  Airport(iataCode: 'LIS', name: 'Humberto Delgado', cityGroupId: 'lisboa', isPrimary: true, lat: 38.7813, lng: -9.1359),
  Airport(iataCode: 'FCO', name: 'Fiumicino', cityGroupId: 'roma', isPrimary: true, lat: 41.8003, lng: 12.2389),
  Airport(iataCode: 'CIA', name: 'Ciampino', cityGroupId: 'roma', lat: 41.7994, lng: 12.5949),
  Airport(iataCode: 'CDG', name: 'Charles de Gaulle', cityGroupId: 'paris', isPrimary: true, lat: 49.0097, lng: 2.5479),
  Airport(iataCode: 'ORY', name: 'Orly', cityGroupId: 'paris', lat: 48.7233, lng: 2.3794),
  Airport(iataCode: 'LHR', name: 'Heathrow', cityGroupId: 'londres', isPrimary: true, lat: 51.4700, lng: -0.4543),
  Airport(iataCode: 'LGW', name: 'Gatwick', cityGroupId: 'londres', lat: 51.1537, lng: -0.1821),
  Airport(iataCode: 'STN', name: 'Stansted', cityGroupId: 'londres', lat: 51.8860, lng: 0.2389),
  Airport(iataCode: 'AMS', name: 'Schiphol', cityGroupId: 'amsterdam', isPrimary: true, lat: 52.3105, lng: 4.7683),
  Airport(iataCode: 'FRA', name: 'Frankfurt am Main', cityGroupId: 'frankfurt', isPrimary: true, lat: 50.0379, lng: 8.5622),
  Airport(iataCode: 'MUC', name: 'Munich International', cityGroupId: 'munich', isPrimary: true, lat: 48.3538, lng: 11.7861),
  Airport(iataCode: 'BER', name: 'Berlin Brandenburg', cityGroupId: 'berlin', isPrimary: true, lat: 52.3667, lng: 13.5033),
  Airport(iataCode: 'DUS', name: 'Düsseldorf International', cityGroupId: 'dusseldorf', isPrimary: true, lat: 51.2895, lng: 6.7668),
  Airport(iataCode: 'HAM', name: 'Hamburg Airport', cityGroupId: 'hamburg', isPrimary: true, lat: 53.6304, lng: 9.9882),
  Airport(iataCode: 'CGN', name: 'Cologne Bonn Airport', cityGroupId: 'cologne', isPrimary: true, lat: 50.8659, lng: 7.1427),


  // ===================== MEDIO ORIENTE =====================
  Airport(iataCode: 'DXB', name: 'Dubai International', cityGroupId: 'dubai', isPrimary: true, lat: 25.2532, lng: 55.3657),

  // ===================== TURQUÍA =====================
  Airport(iataCode: 'IST', name: 'Estambul (Aeropuerto de Estambul)', cityGroupId: 'estambul', isPrimary: true, lat: 41.2753, lng: 28.7519),

  // ===================== EGIPTO =====================
  Airport(iataCode: 'CAI', name: 'El Cairo Internacional', cityGroupId: 'el_cairo', isPrimary: true, lat: 30.1219, lng: 31.4056),

  // ===================== ASIA =====================
  Airport(iataCode: 'BKK', name: 'Suvarnabhumi', cityGroupId: 'bangkok', isPrimary: true, lat: 13.6900, lng: 100.7501),
  Airport(iataCode: 'HND', name: 'Haneda', cityGroupId: 'tokio', isPrimary: true, lat: 35.5494, lng: 139.7798),
  Airport(iataCode: 'NRT', name: 'Narita', cityGroupId: 'tokio', lat: 35.7719, lng: 140.3929),
  Airport(iataCode: 'SIN', name: 'Changi', cityGroupId: 'singapur', isPrimary: true, lat: 1.3644, lng: 103.9915),
  Airport(iataCode: 'DPS', name: 'Ngurah Rai (Bali)', cityGroupId: 'bali', isPrimary: true, lat: -8.7482, lng: 115.1672),
  Airport(iataCode: 'ICN', name: 'Incheon', cityGroupId: 'seul', isPrimary: true, lat: 37.4602, lng: 126.4407),
  Airport(iataCode: 'GMP', name: 'Gimpo', cityGroupId: 'seul', lat: 37.5583, lng: 126.7906),
  Airport(iataCode: 'HKT', name: 'Phuket Internacional', cityGroupId: 'phuket', isPrimary: true, lat: 8.1132, lng: 98.3169),
];

// ---------------------------------------------------------------------
// GRUPOS DE CIUDADES (a partir del catálogo de respaldo de arriba)
// ---------------------------------------------------------------------
List<CityGroup> _buildCityGroups(List<Airport> airports) {
  final Map<String, List<Airport>> grouped = {};
  for (final airport in airports) {
    grouped.putIfAbsent(airport.cityGroupId, () => []).add(airport);
  }

  const Map<String, (String, String)> displayInfo = {
    'buenos_aires': ('Buenos Aires', 'Argentina'),
    'cordoba': ('Córdoba', 'Argentina'),
    'rosario': ('Rosario', 'Argentina'),
    'mendoza': ('Mendoza', 'Argentina'),
    'bariloche': ('Bariloche', 'Argentina'),
    'mar_del_plata': ('Mar del Plata', 'Argentina'),
    'salta': ('Salta', 'Argentina'),
    'iguazu': ('Puerto Iguazú', 'Argentina'),
    'ushuaia': ('Ushuaia', 'Argentina'),
    'neuquen': ('Neuquén', 'Argentina'),
    'tucuman': ('San Miguel de Tucumán', 'Argentina'),
    'comodoro_rivadavia': ('Comodoro Rivadavia', 'Argentina'),
    'bahia_blanca': ('Bahía Blanca', 'Argentina'),
    'posadas': ('Posadas', 'Argentina'),
    'resistencia': ('Resistencia', 'Argentina'),
    'el_calafate': ('El Calafate', 'Argentina'),
    'jujuy': ('San Salvador de Jujuy', 'Argentina'),
    'san_juan': ('San Juan', 'Argentina'),
    'san_luis': ('San Luis', 'Argentina'),
    'santa_rosa': ('Santa Rosa', 'Argentina'),
    'santiago_del_estero': ('Santiago del Estero', 'Argentina'),
    'catamarca': ('Catamarca', 'Argentina'),
    'la_rioja': ('La Rioja', 'Argentina'),
    'parana': ('Paraná', 'Argentina'),
    'corrientes': ('Corrientes', 'Argentina'),
    'formosa': ('Formosa', 'Argentina'),
    'trelew': ('Trelew / Puerto Madryn', 'Argentina'),
    'esquel': ('Esquel', 'Argentina'),
    'viedma': ('Viedma', 'Argentina'),
    'rio_gallegos': ('Río Gallegos', 'Argentina'),
    'rio_grande': ('Río Grande (Tierra del Fuego)', 'Argentina'),
    'sao_paulo': ('San Pablo', 'Brasil'),
    'rio_de_janeiro': ('Río de Janeiro', 'Brasil'),
    'florianopolis': ('Florianópolis', 'Brasil'),
    'salvador_bahia': ('Salvador de Bahía', 'Brasil'),
    'santiago': ('Santiago', 'Chile'),
    'montevideo': ('Montevideo', 'Uruguay'),
    'punta_del_este': ('Punta del Este', 'Uruguay'),
    'asuncion': ('Asunción', 'Paraguay'),
    'lima': ('Lima', 'Perú'),
    'cusco': ('Cusco', 'Perú'),
    'bogota': ('Bogotá', 'Colombia'),
    'cartagena': ('Cartagena', 'Colombia'),
    'la_paz': ('La Paz', 'Bolivia'),
    'ciudad_de_mexico': ('Ciudad de México', 'México'),
    'cancun': ('Cancún', 'México'),
    'punta_cana': ('Punta Cana', 'República Dominicana'),
    'aruba': ('Aruba', 'Aruba'),
    'miami': ('Miami', 'Estados Unidos'),
    'fort_lauderdale': ('Fort Lauderdale', 'Estados Unidos'),
    'orlando': ('Orlando', 'Estados Unidos'),
    'new_york': ('Nueva York', 'Estados Unidos'),
    'los_angeles': ('Los Ángeles', 'Estados Unidos'),
    'las_vegas': ('Las Vegas', 'Estados Unidos'),
    'madrid': ('Madrid', 'España'),
    'barcelona': ('Barcelona', 'España'),
    'lisboa': ('Lisboa', 'Portugal'),
    'roma': ('Roma', 'Italia'),
    'paris': ('París', 'Francia'),
    'londres': ('Londres', 'Reino Unido'),
    'amsterdam': ('Ámsterdam', 'Países Bajos'),
    'frankfurt': ('Fráncfort', 'Alemania'),
    'munich': ('Múnich', 'Alemania'),
    'berlin': ('Berlín', 'Alemania'),
    'dusseldorf': ('Düsseldorf', 'Alemania'),
    'hamburg': ('Hamburgo', 'Alemania'),
    'cologne': ('Colonia', 'Alemania'),

    'dubai': ('Dubái', 'Emiratos Árabes Unidos'),

    'estambul': ('Estambul', 'Turquía'),
    'el_cairo': ('El Cairo', 'Egipto'),
    'bangkok': ('Bangkok', 'Tailandia'),
    'tokio': ('Tokio', 'Japón'),
    'singapur': ('Singapur', 'Singapur'),
    'bali': ('Bali (Denpasar)', 'Indonesia'),
    'seul': ('Seúl', 'Corea del Sur'),
    'phuket': ('Phuket', 'Tailandia'),
  };

  return grouped.entries.map((entry) {
    final info = displayInfo[entry.key]!;
    return CityGroup(
      id: entry.key,
      displayName: info.$1,
      country: info.$2,
      airportCodes: entry.value.map((a) => a.iataCode).toList(),
    );
  }).toList();
}

List<String> airportsForCity(String cityGroupId) {
  return cityGroups.firstWhere((g) => g.id == cityGroupId).airportCodes;
}

Airport? airportByCode(String iataCode) {
  try {
    return allAirports.firstWhere((a) => a.iataCode == iataCode);
  } catch (_) {
    return null;
  }
}

CityGroup? nearestCityGroup(double lat, double lng) {
  Airport? closest;
  double closestDistance = double.infinity;

  for (final airport in allAirports) {
    if (!airport.isPrimary) continue;
    final distance = _haversineDistanceKm(lat, lng, airport.lat, airport.lng);
    if (distance < closestDistance) {
      closestDistance = distance;
      closest = airport;
    }
  }

  if (closest == null) return null;
  return cityGroups.firstWhere((g) => g.id == closest!.cityGroupId);
}

double _haversineDistanceKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLng = _degToRad(lng2 - lng1);
  final a = (sin(dLat / 2) * sin(dLat / 2)) +
      cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * (sin(dLng / 2) * sin(dLng / 2));
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusKm * c;
}

double _degToRad(double deg) => deg * (3.141592653589793 / 180);
