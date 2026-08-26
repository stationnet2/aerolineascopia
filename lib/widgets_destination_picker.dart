import 'package:flutter/material.dart';
import 'data/city_airports.dart';

/// Selector jerárquico para evitar un listado interminable:
/// continente -> país -> ciudad/aeropuertos.
Future<CityGroup?> showDestinationPicker(
  BuildContext context, {
  required String title,
}) async {
  await ensureAirportCatalogLoaded();
  if (!context.mounted) return null;

  return showModalBottomSheet<CityGroup>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (ctx) => const _DestinationPickerSheet(),
  );
}

class _DestinationPickerSheet extends StatefulWidget {
  const _DestinationPickerSheet();

  @override
  State<_DestinationPickerSheet> createState() => _DestinationPickerSheetState();
}

class _DestinationPickerSheetState extends State<_DestinationPickerSheet> {
  ContinentGroup? _continent;
  CountryGroup? _country;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final title = _country != null
        ? _country!.name
        : (_continent != null ? _continent!.name : 'Elegí el destino');

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .84,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Row(
                children: [
                  if (_continent != null)
                    IconButton(
                      onPressed: () => setState(() {
                        if (_country != null) {
                          _country = null;
                        } else {
                          _continent = null;
                        }
                        _query = '';
                      }),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  Expanded(
                    child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            if (_continent != null || _country != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: _country == null ? 'Buscar país...' : 'Buscar ciudad o aeropuerto...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: const Color(0xFFF5F7FB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
                ),
              ),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_country != null) return _buildCitiesAndAirports(_country!);
    if (_continent != null) return _buildCountries(_continent!);
    return _buildContinents();
  }

  Widget _buildContinents() {
    return ListView.builder(
      itemCount: continentGroups.length,
      itemBuilder: (_, index) {
        final continent = continentGroups[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 3),
          leading: _iconForContinent(continent.code),
          title: Text(continent.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          subtitle: Text('${continent.countries.length} países'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => setState(() => _continent = continent),
        );
      },
    );
  }

  Widget _buildCountries(ContinentGroup continent) {
    final countries = continent.countries.where((country) {
      if (_query.isEmpty) return true;
      return country.name.toLowerCase().contains(_query) || country.code.toLowerCase().contains(_query);
    }).toList();

    return ListView.builder(
      itemCount: countries.length,
      itemBuilder: (_, index) {
        final country = countries[index];
        final airportCount = country.cities.fold<int>(0, (sum, city) => sum + city.airportCodes.length);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 2),
          leading: const Icon(Icons.public_rounded, color: Color(0xFF526173)),
          title: Text(country.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('$airportCount aeropuertos'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => setState(() {
            _country = country;
            _query = '';
          }),
        );
      },
    );
  }

  Widget _buildCitiesAndAirports(CountryGroup country) {
    final cities = country.cities.where((city) {
      if (_query.isEmpty) return true;
      final airportText = city.airportCodes.join(' ').toLowerCase();
      return city.displayName.toLowerCase().contains(_query) || airportText.contains(_query);
    }).toList();

    return ListView.builder(
      itemCount: cities.length,
      itemBuilder: (_, index) {
        final city = cities[index];
        final airports = city.airportCodes.map(airportByCode).whereType<Airport>().toList();
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          elevation: 0,
          color: const Color(0xFFF7F9FC),
          child: ListTile(
            leading: const Icon(Icons.flight_rounded, color: Color(0xFF0B5ED7)),
            title: Text(city.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              airports.map((airport) => '${airport.iataCode} · ${airport.name}').join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.check_circle_outline_rounded),
            onTap: () => Navigator.pop(context, city),
          ),
        );
      },
    );
  }

  Icon _iconForContinent(String code) {
    switch (code) {
      case 'SA': return const Icon(Icons.public_rounded, color: Color(0xFF0B5ED7));
      case 'NA': return const Icon(Icons.public_rounded, color: Color(0xFF0B5ED7));
      case 'EU': return const Icon(Icons.euro_rounded, color: Color(0xFF0B5ED7));
      case 'AS': return const Icon(Icons.public_rounded, color: Color(0xFF0B5ED7));
      case 'OC': return const Icon(Icons.waves_rounded, color: Color(0xFF0B5ED7));
      case 'AF': return const Icon(Icons.terrain_rounded, color: Color(0xFF0B5ED7));
      default: return const Icon(Icons.public_rounded, color: Color(0xFF0B5ED7));
    }
  }
}
