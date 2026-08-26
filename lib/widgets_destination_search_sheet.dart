import 'package:flutter/material.dart';
import 'data/city_airports.dart';
import 'services/location_service.dart';

/// Selector de destinos inspirado en los buscadores de vuelos:
/// el usuario escribe ciudad, país, aeropuerto o código IATA y recibe
/// resultados relevantes. Si escribe un país, se muestran las ciudades
/// y aeropuertos disponibles de ese país.
Future<CityGroup?> showDestinationSearchSheet(
  BuildContext context, {
  required String title,
  CityGroup? exclude,
}) {
  return showModalBottomSheet<CityGroup>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => _DestinationSearchSheet(title: title, exclude: exclude),
  );
}

class _DestinationSearchSheet extends StatefulWidget {
  final String title;
  final CityGroup? exclude;

  const _DestinationSearchSheet({required this.title, this.exclude});

  @override
  State<_DestinationSearchSheet> createState() => _DestinationSearchSheetState();
}

class _DestinationSearchSheetState extends State<_DestinationSearchSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _query = _controller.text));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _normalize(String value) {
    const accents = 'áéíóúüñÁÉÍÓÚÜÑ';
    const plain = 'aeiouunAEIOUUN';
    var result = value;
    for (var i = 0; i < accents.length; i++) {
      result = result.replaceAll(accents[i], plain[i]);
    }
    return result.toLowerCase().trim();
  }

  bool _matches(CityGroup city, String q) {
    if (q.isEmpty) return false;
    final nq = _normalize(q);
    if (_normalize(city.displayName).contains(nq)) return true;
    if (_normalize(city.country).contains(nq)) return true;
    for (final code in city.airportCodes) {
      final airport = airportByCode(code);
      if (airport == null) continue;
      if (_normalize(airport.iataCode).contains(nq) || _normalize(airport.name).contains(nq)) {
        return true;
      }
    }
    return false;
  }

  List<CityGroup> get _results {
    if (_query.trim().isEmpty) return const [];
    final list = cityGroups
        .where((c) => widget.exclude?.id != c.id && _matches(c, _query))
        .toList();

    final nq = _normalize(_query);
    list.sort((a, b) {
      int score(CityGroup c) {
        final city = _normalize(c.displayName);
        final country = _normalize(c.country);
        if (city == nq) return 0;
        if (city.startsWith(nq)) return 1;
        if (country == nq) return 2;
        if (country.startsWith(nq)) return 3;
        return 4;
      }
      return score(a).compareTo(score(b));
    });
    return list;
  }

  List<CityGroup> get _popular {
    // Destinos populares según el país del usuario (detectado por el
    // idioma/región del celular, no por GPS) — alguien en Brasil ve
    // los destinos más buscados desde Brasil, alguien en Uruguay ve
    // los de Uruguay, etc. Se puede editar sin tocar código desde
    // Firestore (colección "popular_destinations") o desde panel.html.
    return popularDestinationsFor(currentCountryCode())
        .where((c) => widget.exclude?.id != c.id)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final showCountryHint = _query.trim().length >= 2 && results.isNotEmpty;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .86,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Ciudad, país o aeropuerto (ej. BUE, Alem...)',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(icon: const Icon(Icons.close_rounded), onPressed: _controller.clear),
                  filled: true,
                  fillColor: const Color(0xFFF5F7FA),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),
            ),
            if (_query.trim().isEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Destinos frecuentes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF526173))),
                ),
              ),
              Expanded(child: _buildList(_popular, showAirportDetails: false)),
            ] else ...[
              if (showCountryHint)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Resultados', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF526173))),
                  ),
                ),
              Expanded(child: results.isEmpty ? _empty() : _buildList(results, showAirportDetails: true)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<CityGroup> cities, {required bool showAirportDetails}) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
      itemCount: cities.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 62),
      itemBuilder: (_, index) {
        final city = cities[index];
        final airports = city.airportCodes
            .map(airportByCode)
            .whereType<Airport>()
            .toList();
        final airportText = airports.map((a) => a.iataCode).join(' · ');
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFEAF2FF),
            child: Icon(Icons.flight_rounded, color: const Color(0xFF0B5ED7), size: 21),
          ),
          title: Text(city.displayName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          subtitle: Text(
            showAirportDetails ? '${city.country}  •  $airportText' : '${city.country}  •  $airportText',
            style: const TextStyle(fontSize: 12, color: Color(0xFF697586)),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.pop(context, city),
        );
      },
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.flight_takeoff_rounded, size: 46, color: Color(0xFF98A2B3)),
            SizedBox(height: 12),
            Text('No encontramos ese destino', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            SizedBox(height: 6),
            Text('Probá con una ciudad, país o código IATA.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF697586))),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
