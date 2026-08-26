// create_alert_screen.dart
//
// Pantalla donde el usuario arma su alerta. Puntos clave que pediste:
// - Elegir por CIUDAD (no por aeropuerto individual) -> "Buenos Aires"
//   automáticamente incluye EZE y AEP.
// - Fechas puntuales o flexibles.
// - Guardar como favorito para no tener que reconfigurar cada vez
//   (esto se resuelve solo: cada alerta creada YA es un favorito,
//   vive guardada en Firestore ligada al usuario).

import 'package:flutter/material.dart';
import '../widgets_destination_search_sheet.dart';
import '../data/city_airports.dart';
import '../services/alert_service.dart';
import '../services/travelpayouts_service.dart';
import '../models/flight_alert.dart';

enum TripType { oneWay, roundTrip }

class CreateAlertScreen extends StatefulWidget {
  const CreateAlertScreen({super.key});

  @override
  State<CreateAlertScreen> createState() => _CreateAlertScreenState();
}

class _CreateAlertScreenState extends State<CreateAlertScreen> {
  CityGroup? _origin;
  CityGroup? _destination;
  DateTimeRange? _dateRange;
  DateTime? _departureDate; // usado solo cuando _tripType == TripType.oneWay
  TripType _tripType = TripType.roundTrip;
  int _passengers = 1;
  bool _flexibleDates = false;
  double? _maxPrice;
  bool _saving = false;
  final _alertService = AlertService();
  final _travelpayoutsService = TravelpayoutsService();
  bool _searching = false;
  List<FlightDeal>? _searchResults;
  String? _searchError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva alerta de vuelo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCitySelector(
            label: 'Desde',
            selected: _origin,
            onSelect: (city) => setState(() => _origin = city),
          ),
          const SizedBox(height: 16),
          _buildCitySelector(
            label: 'Hasta',
            selected: _destination,
            onSelect: (city) => setState(() => _destination = city),
          ),

          // Acá es donde se le muestra al usuario, de forma transparente,
          // qué aeropuertos va a incluir su búsqueda -- para que entienda
          // por qué puede aparecer una oferta a un aeropuerto que no
          // esperaba.
          if (_destination != null) _buildAirportsPreview(_destination!),

          const SizedBox(height: 24),
          const Text('Tipo de viaje', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          SegmentedButton<TripType>(
            segments: const [
              ButtonSegment(value: TripType.oneWay, label: Text('Solo ida')),
              ButtonSegment(value: TripType.roundTrip, label: Text('Ida y vuelta')),
            ],
            selected: {_tripType},
            onSelectionChanged: (selection) => setState(() {
              _tripType = selection.first;
              _dateRange = null;
              _departureDate = null;
            }),
          ),

          const SizedBox(height: 20),
          const Text('Pasajeros', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_passengers == 1 ? '1 pasajero' : '$_passengers pasajeros'),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _passengers > 1 ? () => setState(() => _passengers--) : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _passengers < 9 ? () => setState(() => _passengers++) : null,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          SwitchListTile(
            title: const Text('Fechas flexibles'),
            subtitle: const Text('Avisame de la mejor oferta en cualquier fecha'),
            value: _flexibleDates,
            onChanged: (v) => setState(() => _flexibleDates = v),
          ),
          if (!_flexibleDates && _tripType == TripType.oneWay)
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(_departureDate == null ? 'Elegir fecha de ida' : _formatDate(_departureDate!)),
              onTap: _pickSingleDate,
            ),
          if (!_flexibleDates && _tripType == TripType.roundTrip)
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(_dateRange == null
                  ? 'Elegir fechas'
                  : '${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}'),
              onTap: _pickDateRange,
            ),

          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Avisame si el precio baja de (opcional)',
              prefixText: '\$ ',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) => _maxPrice = double.tryParse(v),
          ),

          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: (_canSave() && !_searching) ? _searchCurrentPrice : null,
            icon: _searching
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(_searching ? 'Buscando...' : 'Ver precio actual'),
          ),
          if (_searchResults != null) _buildSearchResults(),
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_searchError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),

          const SizedBox(height: 32),
          FilledButton(
            onPressed: (_canSave() && !_saving) ? _saveAlert : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Guardar alerta'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCitySelector({
    required String label,
    required CityGroup? selected,
    required ValueChanged<CityGroup> onSelect,
  }) {
    return InkWell(
      onTap: () async {
        final city = await _showCityPicker(context);
        if (city != null) onSelect(city);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        child: Text(selected?.displayName ?? 'Elegir ciudad'),
      ),
    );
  }

  Widget _buildAirportsPreview(CityGroup city) {
    final airports = city.airportCodes.map((code) => airportByCode(code)).whereType<Airport>();
    if (airports.length <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 18, color: Colors.blueGrey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Vamos a buscar en los ${airports.length} aeropuertos de la zona: '
                '${airports.map((a) => '${a.name} (${a.iataCode})').join(', ')}.',
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<CityGroup?> _showCityPicker(BuildContext context) {
    return showDestinationSearchSheet(context, title: 'Elegí una ciudad de destino');
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (range != null) setState(() => _dateRange = range);
  }

  Future<void> _pickSingleDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (date != null) setState(() => _departureDate = date);
  }

  bool _canSave() {
    final hasDates = _flexibleDates ||
        (_tripType == TripType.oneWay ? _departureDate != null : _dateRange != null);
    return _origin != null && _destination != null && _origin != _destination && hasDates;
  }

  DateTime? get _effectiveDateFrom =>
      _tripType == TripType.oneWay ? _departureDate : _dateRange?.start;

  DateTime? get _effectiveDateTo =>
      _tripType == TripType.roundTrip ? _dateRange?.end : null;

  Widget _buildSearchResults() {
    final results = _searchResults!;
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          'No encontramos precios disponibles para esta ruta ahora mismo. '
          'La alerta se puede guardar igual, te avisamos apenas aparezca algo.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Precios encontrados ahora:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          ...results.take(5).map((deal) {
            final originAirport = airportByCode(deal.originAirportCode);
            final destAirport = airportByCode(deal.destinationAirportCode);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.flight, color: Colors.blue),
                title: Text('${deal.currency} \$${(deal.price * _passengers).toStringAsFixed(0)}${_passengers > 1 ? " total" : ""} · ${deal.airline}'),
                subtitle: Text(
                  '${originAirport?.iataCode ?? deal.originAirportCode} → ${destAirport?.iataCode ?? deal.destinationAirportCode} · '
                  '${_formatDate(deal.departureDate)} · '
                  '${deal.isRoundTrip ? "Ida y vuelta" : "Solo ida"} · '
                  '${deal.transfers == 0 ? "Directo" : "${deal.transfers} escala(s)"}'
                  '${_passengers > 1 ? "\n${deal.currency} \$${deal.price.toStringAsFixed(0)} c/u · precio estimado, se confirma al comprar" : ""}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _searchCurrentPrice() async {
    setState(() {
      _searching = true;
      _searchError = null;
      _searchResults = null;
    });

    try {
      final results = await _travelpayoutsService.searchDeals(
        originCityId: _origin!.id,
        destinationCityId: _destination!.id,
        dateFrom: _effectiveDateFrom,
        dateTo: _effectiveDateTo,
      );
      if (!mounted) return;
      setState(() => _searchResults = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _searchError = 'No pudimos buscar el precio ahora. Podés guardar la alerta igual.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _saveAlert() async {
    setState(() => _saving = true);
    try {
      await _alertService.saveAlert(
        originCityId: _origin!.id,
        destinationCityId: _destination!.id,
        dateFrom: _effectiveDateFrom,
        dateTo: _effectiveDateTo,
        flexibleDates: _flexibleDates,
        maxPrice: _maxPrice,
        passengers: _passengers,
        initialPrice: (_searchResults != null && _searchResults!.isNotEmpty) ? _searchResults!.first.price : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Alerta guardada! Te avisamos cuando encontremos una oferta.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
