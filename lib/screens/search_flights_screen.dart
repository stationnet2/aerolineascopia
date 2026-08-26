import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/city_airports.dart';
import '../models/flight_alert.dart';
import '../services/travelpayouts_service.dart';
import '../services/location_service.dart';
import '../services/alert_service.dart';
import 'create_alert_screen.dart';
import 'my_alerts_screen.dart';
import '../widgets_destination_search_sheet.dart';

enum TripType { oneWay, roundTrip }

class SearchFlightsScreen extends StatefulWidget {
  const SearchFlightsScreen({super.key});

  @override
  State<SearchFlightsScreen> createState() => _SearchFlightsScreenState();
}

class _SearchFlightsScreenState extends State<SearchFlightsScreen>
    with SingleTickerProviderStateMixin {
  final _travelpayoutsService = TravelpayoutsService();
  final _locationService = LocationService();
  final _alertService = AlertService();
  late final AnimationController _notificationController;

  CityGroup? _origin;
  CityGroup? _destination;
  DateTimeRange? _dateRange;
  DateTime? _departureDate;
  TripType _tripType = TripType.roundTrip;
  int _passengers = 1;
  bool _anyDate = true;
  bool _usedDefaultRoundTripDates = false;
  bool _searching = false;
  List<FlightDeal>? _results;
  List<NearbyDateDeal> _nearbyDateDeals = [];
  DateTime? _searchedDepartureDate;
  String? _error;
  bool _detectingLocation = true;
  CityGroup? _detectedCity;
  List<FlightDeal>? _nearbyOffers;

  @override
  void initState() {
    super.initState();
    _notificationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: -0.08,
      upperBound: 0.08,
    );
    _detectLocationAndLoadOffers();
  }

  @override
  void dispose() {
    _notificationController.dispose();
    super.dispose();
  }

  Future<void> _detectLocationAndLoadOffers() async {
    CityGroup? city;
    try {
      city = await _locationService
          .detectNearestCity()
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      print('[Location] no se pudo detectar la ciudad: $e');
      city = null;
    }

    if (!mounted) return;
    setState(() {
      _detectedCity = city;
      _detectingLocation = false;
      _origin ??= city;
    });

    if (city == null) {
      city = cityGroups.firstWhere(
        (c) => c.id == 'buenos_aires',
        orElse: () => cityGroups.first,
      );
      if (mounted) setState(() => _origin ??= city);
    }

    try {
      final offers = await _travelpayoutsService
          .fetchSpecialOffers(city.id)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() => _nearbyOffers = offers);
    } catch (e) {
      print('[TP] fetchSpecialOffers fallo: $e');
      if (mounted) setState(() => _nearbyOffers = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: _buildAppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            _buildHero(),
            _buildDestinationCarousel(),
            _buildSearchCard(),
            _buildHotelsAndActivitiesCard(),
            if (_error != null) _buildError(),
            if (_results != null) _buildResults(),
            if (_nearbyDateDeals.isNotEmpty) _buildNearbyDateAlternatives(),
            if (_results == null && !_searching) _buildNearbySection(),
            _buildAlertBanner(),
            _buildTrustSection(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: const Color(0xFFF5F7FB),
      foregroundColor: const Color(0xFF172033),
      titleSpacing: 20,
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 44,
              height: 44,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          const Text('AlertaTrip',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        ],
      ),
      actions: [
        StreamBuilder<List<FlightNotification>>(
          stream: _alertService.watchMyNotifications(),
          builder: (context, snapshot) {
            final unreadCount = snapshot.data
                    ?.where((n) => !n.read && !n.isTest)
                    .length ??
                0;
            if (unreadCount > 0 && !_notificationController.isAnimating) {
              _notificationController.repeat(reverse: true);
            } else if (unreadCount == 0 &&
                _notificationController.isAnimating) {
              _notificationController.stop();
              _notificationController.reset();
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedBuilder(
                  animation: _notificationController,
                  builder: (_, child) => Transform.rotate(
                    angle: unreadCount > 0 ? _notificationController.value : 0,
                    child: child,
                  ),
                  child: IconButton(
                    tooltip: unreadCount > 0
                        ? 'Tenes $unreadCount alerta${unreadCount == 1 ? '' : 's'} nueva${unreadCount == 1 ? '' : 's'}'
                        : 'Mis alertas',
                    icon: Icon(
                      unreadCount > 0
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                      color: unreadCount > 0
                          ? const Color(0xFFD92D20)
                          : const Color(0xFF172033),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MyAlertsScreen()),
                    ),
                  ),
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 4,
                    top: 5,
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFD92D20),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildHero() {
    return Container(
      height: 310,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF0F9D8D),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
            child: Image.network(
              'https://images.unsplash.com/photo-1500534623283-312aade485b7?auto=format&fit=crop&w=1400&q=85',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFF071A2B).withOpacity(.94),
                  const Color(0xFF0F9D8D).withOpacity(.62),
                  Colors.transparent,
                ],
                stops: const [0, .56, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 28, 150, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(.24)),
                  ),
                  child: const Text(
                    '✈  Alertas inteligentes',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12),
                  ),
                ),
                const Spacer(),
                const Text(
                  'Viaja mas,\npaga menos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    height: 1.02,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Buscamos oportunidades y te avisamos cuando aparece un mejor precio.',
                  style: TextStyle(
                      color: Color(0xFFDBF2EC),
                      fontSize: 13,
                      height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  CityGroup? _cityGroupForAirportCode(String code) {
    final airport = airportByCode(code);
    if (airport == null) return null;
    try {
      return cityGroups.firstWhere((c) => c.id == airport.cityGroupId);
    } catch (_) {
      return null;
    }
  }

  Widget _buildDestinationCarousel() {
    if (_nearbyOffers == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 16),
        child: SizedBox(
            height: 166,
            child: Center(
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final byCity = <String, FlightDeal>{};
    final rawByCode = <String, FlightDeal>{};
    for (final deal in _nearbyOffers!) {
      final city = _cityGroupForAirportCode(deal.destinationAirportCode);
      if (city != null) {
        final current = byCity[city.id];
        if (current == null || deal.price < current.price)
          byCity[city.id] = deal;
      } else {
        final current = rawByCode[deal.destinationAirportCode];
        if (current == null || deal.price < current.price)
          rawByCode[deal.destinationAirportCode] = deal;
      }
    }

    if (byCity.isEmpty && rawByCode.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
        child: Row(children: [
          const Expanded(
              child: Text(
                  'No pudimos cargar destinos sugeridos ahora.',
                  style: TextStyle(
                      fontSize: 12, color: Color(0xFF667085)))),
          TextButton(
            onPressed: () {
              setState(() => _nearbyOffers = null);
              _detectLocationAndLoadOffers();
            },
            child: const Text('Reintentar'),
          ),
        ]),
      );
    }

    final cityEntries = byCity.entries.toList()
      ..sort((a, b) => a.value.price.compareTo(b.value.price));
    final rawEntries = rawByCode.entries.toList()
      ..sort((a, b) => a.value.price.compareTo(b.value.price));

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 2),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Icon(Icons.explore_rounded, color: Color(0xFF0F9D8D)),
                SizedBox(width: 8),
                Text('Explora destinos',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF172033))),
              ]),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                  'Precios reales encontrados hoy desde tu ciudad.',
                  style:
                      TextStyle(fontSize: 12, color: Color(0xFF667085))),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 166,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: cityEntries.length + rawEntries.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, index) {
                  if (index < cityEntries.length) {
                    final cityId = cityEntries[index].key;
                    final deal = cityEntries[index].value;
                    final city =
                        cityGroups.firstWhere((c) => c.id == cityId);
                    final imageUrl = city.imageUrl;
                    return _buildExploreCard(
                      title: city.displayName,
                      price: deal.price,
                      currency: deal.currency,
                      imageUrl: imageUrl,
                      onTap: () => _openDestinationOffers(city),
                    );
                  }
                  final deal =
                      rawEntries[index - cityEntries.length].value;
                  final airportName = airportByCode(
                              deal.destinationAirportCode)
                          ?.name ??
                      deal.destinationAirportCode;
                  return _buildExploreCard(
                    title: airportName,
                    price: deal.price,
                    currency: deal.currency,
                    imageUrl: null,
                    onTap: () => _openBookingLink(deal),
                  );
                },
              ),
            ),
          ]),
    );
  }

  Widget _buildExploreCard({
    required String title,
    required double price,
    required String currency,
    required String? imageUrl,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 140,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Ink(
            decoration:
                BoxDecoration(borderRadius: BorderRadius.circular(20)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl != null)
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: const Color(0xFF0F9D8D)),
                    )
                  else
                    Container(color: const Color(0xFF0F9D8D)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0xD0000000)
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 11,
                    top: 11,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.35),
                          borderRadius: BorderRadius.circular(14)),
                      child: Text(
                          '$currency ${price.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Row(children: [
                      Expanded(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14))),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 18),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openDestinationOffers(CityGroup city) async {
    final origin = _origin ?? _detectedCity;
    if (origin == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Primero elegi tu ciudad de origen para buscar ofertas.')),
      );
      return;
    }
    if (origin.id == city.id) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Elegi un destino diferente al origen.')),
      );
      return;
    }

    setState(() {
      _origin = origin;
      _destination = city;
      _anyDate = true;
      _departureDate = null;
      _dateRange = null;
    });
    await _search();
  }

  // ================================================================
  // SEARCH CARD - CON BOTON SWAP Y MEJORAS ESTETICAS
  // ================================================================
  Widget _buildSearchCard() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F9D8D).withOpacity(.06),
              blurRadius: 24,
              offset: const Offset(0, 8),
              spreadRadius: -4,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            children: [
              Container(
                height: 4,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F9D8D), Color(0xFF4ECDC0)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3F5F1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.flight_rounded,
                            color: Color(0xFF0F9D8D),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Buscar vuelos',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                                color: const Color(0xFF172033),
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildRouteField(
                      label: 'Origen',
                      value: _origin,
                      icon: Icons.flight_takeoff_rounded,
                      color: const Color(0xFF0F9D8D),
                      onTap: () async {
                        final city = await showDestinationSearchSheet(
                          context,
                          title: '¿Desde donde viajas?',
                          exclude: _destination,
                        );
                        if (city != null) setState(() => _origin = city);
                      },
                    ),
                    _buildSwapButton(),
                    _buildRouteField(
                      label: 'Destino',
                      value: _destination,
                      icon: Icons.flight_land_rounded,
                      color: const Color(0xFF0F766E),
                      onTap: () async {
                        final city = await showDestinationSearchSheet(
                          context,
                          title: '¿A donde queres ir?',
                          exclude: _origin,
                        );
                        if (city != null) setState(() => _destination = city);
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildTripTypeSelector(),
                    const SizedBox(height: 14),
                    _buildPassengerField(),
                    const SizedBox(height: 14),
                    _buildDateField(),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF7A45),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shadowColor: const Color(0xFFFF7A45).withOpacity(.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: (_canSearch() && !_searching) ? _search : null,
                        child: _searching
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Buscando las mejores opciones...',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_rounded, size: 22),
                                  SizedBox(width: 10),
                                  Text(
                                    'Buscar vuelos',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Center(
                        child: Text(
                          'Los precios se muestran en dólares estadounidenses (USD)',
                          style: TextStyle(fontSize: 11, color: Color(0xFF98A2B3)),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwapButton() {
    final canSwap = _origin != null || _destination != null;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: canSwap ? _swapCities : null,
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: canSwap ? const Color(0xFFE3F5F1) : const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: canSwap ? const Color(0xFF0F9D8D).withOpacity(.2) : const Color(0xFFE0E6EF),
                ),
              ),
              child: Icon(
                Icons.swap_vert_rounded,
                size: 20,
                color: canSwap ? const Color(0xFF0F9D8D) : const Color(0xFF98A2B3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _swapCities() {
    if (_origin == null && _destination == null) return;
    setState(() {
      final temp = _origin;
      _origin = _destination;
      _destination = temp;
    });
  }

  Widget _buildTripTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        border: Border.all(color: const Color(0xFFE8ECF2)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(child: _buildTripTypeOption('Solo ida', TripType.oneWay)),
          Expanded(child: _buildTripTypeOption('Ida y vuelta', TripType.roundTrip)),
        ],
      ),
    );
  }

  Widget _buildTripTypeOption(String label, TripType type) {
    final selected = _tripType == type;
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () => setState(() {
        _tripType = type;
        _dateRange = null;
        _departureDate = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0F9D8D) : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF526173),
          ),
        ),
      ),
    );
  }

  Widget _buildPassengerField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        border: Border.all(color: const Color(0xFFE8ECF2)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline_rounded, color: Color(0xFF526173), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _passengers == 1 ? '1 pasajero' : '$_passengers pasajeros',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF172033)),
            ),
          ),
          _buildPassengerButton(
            icon: Icons.remove_rounded,
            onTap: _passengers > 1 ? () => setState(() => _passengers--) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '$_passengers',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF172033)),
            ),
          ),
          _buildPassengerButton(
            icon: Icons.add_rounded,
            onTap: _passengers < 9 ? () => setState(() => _passengers++) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerButton({required IconData icon, required VoidCallback? onTap}) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFFE3F5F1) : const Color(0xFFF5F7FA),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? const Color(0xFF0F9D8D) : const Color(0xFF98A2B3),
          ),
        ),
      ),
    );
  }

  Widget _buildRouteField({required String label, required CityGroup? value, required IconData icon, required Color color, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFBFC),
            border: Border.all(
              color: value != null ? color.withOpacity(.25) : const Color(0xFFE8ECF2),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withOpacity(.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF98A2B3),
                        letterSpacing: .3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value?.displayName ?? 'Elegir ciudad',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: value == null ? const Color(0xFF98A2B3) : const Color(0xFF172033),
                      ),
                    ),
                    if (value != null)
                      Text(
                        value.country,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF98A2B3),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF98A2B3),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateField() {
    final isOneWay = _tripType == TripType.oneWay;
    final text = isOneWay
        ? (_departureDate == null ? 'Fecha de viaje' : _formatDate(_departureDate!))
        : (_dateRange == null
            ? 'Fechas de viaje'
            : '${_formatDate(_dateRange!.start)}  —  ${_formatDate(_dateRange!.end)}');

    return Material(
      color: const Color(0xFFFAFBFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8ECF2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.calendar_month_rounded, color: Color(0xFF526173), size: 22),
              title: const Text(
                'Cualquier fecha',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF172033)),
              ),
              subtitle: const Text(
                'Buscar las mejores opciones sin fijar fechas',
                style: TextStyle(fontSize: 12, color: Color(0xFF98A2B3)),
              ),
              value: _anyDate,
              onChanged: (value) {
                setState(() {
                  _anyDate = value;
                  if (value) {
                    _dateRange = null;
                    _departureDate = null;
                  }
                });
              },
            ),
            if (!_anyDate)
              InkWell(
                onTap: isOneWay ? _pickSingleDate : _pickDateRange,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10, top: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range_rounded, size: 22, color: Color(0xFF526173)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          (isOneWay ? _departureDate == null : _dateRange == null)
                              ? (isOneWay ? 'Elegir fecha de ida' : 'Elegir fechas de viaje')
                              : text,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: (isOneWay ? _departureDate == null : _dateRange == null)
                                ? const Color(0xFF98A2B3)
                                : const Color(0xFF172033),
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Color(0xFF98A2B3)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: const Color(0xFFFFF1F0), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.error_outline, color: Color(0xFFD92D20)),
          const SizedBox(width: 10),
          Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFB42318))))
        ]),
      ),
    );
  }

  Widget _buildResults() {
    final results = _results!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: Color(0xFF0F9D8D), size: 20),
          const SizedBox(width: 7),
          Text(results.isEmpty ? 'No encontramos vuelos' : 'Mejores opciones', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
        if (_usedDefaultRoundTripDates && results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Pusiste "cualquier fecha" con ida y vuelta: te mostramos precios de referencia saliendo el ${_formatDate(_searchedDepartureDate!)} y volviendo una semana despues.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
            ),
          ),
        const SizedBox(height: 10),
        if (results.isEmpty)
          const Text('Proba con otras fechas o ciudades. Tambien podes crear una alerta y te avisamos cuando aparezca una buena oportunidad.', style: TextStyle(color: Color(0xFF667085)))
        else
          ...results.map(_buildDealCard),
      ]),
    );
  }

  Widget _buildNearbyDateAlternatives() {
    final selectedBest = _results != null && _results!.isNotEmpty ? _results!.first : null;
    final alternatives = _nearbyDateDeals;
    FlightDeal? bestAlternative;
    for (final alternative in alternatives) {
      final deal = alternative.cheapest;
      if (deal != null && (bestAlternative == null || deal.price < bestAlternative.price)) {
        bestAlternative = deal;
      }
    }
    final hasSaving = selectedBest != null && bestAlternative != null && bestAlternative.price < selectedBest.price;
    final saving = hasSaving ? selectedBest.price - bestAlternative!.price : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fechas cercanas disponibles', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(
            _searchedDepartureDate == null
                ? 'Buscamos las 2 fechas con vuelos anteriores y las 2 posteriores.'
                : 'Alrededor de ${_formatDate(_searchedDepartureDate!)} buscamos resultados reales, no solamente +/-2 dias.',
            style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
          ),
          if (hasSaving) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF8EE),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFB7E0C0)),
              ),
              child: Row(children: [
                const Icon(Icons.savings_outlined, color: Color(0xFF18864B)),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'Podes ahorrar ${selectedBest.currency} ${(saving * _passengers).toStringAsFixed(0)} con una fecha cercana.',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF146C3A)),
                )),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          ...alternatives.map((alternative) {
            final deal = alternative.cheapest!;
            final isBest = bestAlternative != null && identical(deal, bestAlternative);
            return Container(
              margin: const EdgeInsets.only(bottom: 9),
              decoration: BoxDecoration(
                color: isBest ? const Color(0xFFF0FAF7) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isBest ? const Color(0xFF6FC2B4) : const Color(0xFFE7EBF2)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _openBookingLink(deal),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_formatDate(alternative.requestedDate), style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        deal.returnDate == null ? 'Solo ida' : '${_formatDate(alternative.requestedDate)} -> ${_formatDate(deal.returnDate!)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
                      ),
                      const SizedBox(height: 9),
                      const Row(children: [
                        Icon(Icons.open_in_new_rounded, size: 15, color: Color(0xFF0F9D58)),
                        SizedBox(width: 5),
                        Text('Ver y reservar esta fecha', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F9D58))),
                      ]),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${deal.currency} ${(deal.price * _passengers).toStringAsFixed(0)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF0F9D8D))),
                      if (isBest) const Text('MEJOR PRECIO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF18864B))),
                    ]),
                  ]),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildNearbySection() {
    if (_detectingLocation || _detectedCity == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.local_fire_department_rounded, color: Color(0xFFF79009), size: 21),
          const SizedBox(width: 7),
          Expanded(child: Text('Ofertas desde ${_detectedCity!.displayName}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 5),
        const Text('Toca cualquiera para ver la oferta completa.', style: TextStyle(color: Color(0xFF667085))),
        const SizedBox(height: 12),
        if (_nearbyOffers == null)
          const Center(child: Padding(padding: EdgeInsets.all(15), child: CircularProgressIndicator(strokeWidth: 2)))
        else if (_nearbyOffers!.isEmpty)
          const Text('No hay ofertas destacadas en este momento.', style: TextStyle(color: Color(0xFF667085)))
        else
          ..._nearbyOffers!.take(3).map(_buildCompactDealCard),
      ]),
    );
  }

  Widget _buildCompactDealCard(FlightDeal deal) {
    // Buscar la ciudad destino, no solo el aeropuerto
    final destCity = _cityGroupForAirportCode(deal.destinationAirportCode);
    final destName = destCity?.displayName ?? airportByCode(deal.destinationAirportCode)?.name ?? deal.destinationAirportCode;
    final destCountry = destCity?.country ?? '';

    return InkWell(
      onTap: () => _openBookingLink(deal),
      borderRadius: BorderRadius.circular(17),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFE7EBF2)),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE3F5F1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.flight_rounded, color: Color(0xFF0F9D8D)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                if (destCountry.isNotEmpty)
                  Text(
                    destCountry,
                    style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 11),
                  ),
                Text(
                  '${deal.airline} · ${_formatDate(deal.departureDate)}',
                  style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${deal.currency} ${deal.price.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Color(0xFF0F9D8D),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Ver oferta →',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F9D58),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _buildDealCard(FlightDeal deal) {
    final originAirport = airportByCode(deal.originAirportCode);
    final destAirport = airportByCode(deal.destinationAirportCode);
    final originName = originAirport?.name ?? deal.originAirportCode;
    final destName = destAirport?.name ?? deal.destinationAirportCode;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFE7EBF2)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${deal.currency} ${(deal.price * _passengers).toStringAsFixed(0)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F9D8D)))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(color: const Color(0xFFEAF7EE), borderRadius: BorderRadius.circular(20)),
            child: Text(deal.transfers == 0 ? 'Directo' : '${deal.transfers} escala(s)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF217A3E))),
          ),
        ]),
        if (_passengers > 1)
          Padding(padding: const EdgeInsets.only(top: 2), child: Text('Total estimado para $_passengers pasajeros (${deal.currency} ${deal.price.toStringAsFixed(0)} c/u) · se confirma al comprar', style: const TextStyle(fontSize: 11, color: Color(0xFFB54708)))),
        const SizedBox(height: 10),
        _buildLegRow(icon: Icons.flight_takeoff_rounded, label: 'Ida', route: '$originName -> $destName', date: _formatDate(deal.departureDate)),
        if (deal.returnDate != null) ...[
          const SizedBox(height: 8),
          _buildLegRow(icon: Icons.flight_land_rounded, label: 'Vuelta', route: '$destName -> $originName', date: _formatDate(deal.returnDate!)),
        ],
        const SizedBox(height: 8),
        Text(deal.airline, style: const TextStyle(color: Color(0xFF667085), fontSize: 12)),
        if (deal.durationMinutes != null) Text('Duracion ${_formatDuration(deal.durationMinutes!)}', style: const TextStyle(color: Color(0xFF667085), fontSize: 12)),
        const SizedBox(height: 13),
        SizedBox(width: double.infinity, height: 45, child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF7A45)),
          onPressed: () => _openBookingLink(deal),
          child: const Text('Ver oferta'),
        )),
      ]),
    );
  }

  Widget _buildLegRow({required IconData icon, required String label, required String route, required String date}) {
    return Row(children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(color: const Color(0xFFE3F5F1), borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, size: 16, color: const Color(0xFF0F9D8D)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label · $date', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF667085))),
          Text(route, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      ),
    ]);
  }

  Widget _buildAlertBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF172B4D), Color(0xFF0F9D8D)]), borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: Colors.white.withOpacity(.14), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.notifications_active_rounded, color: Colors.white)),
        const SizedBox(width: 13),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('¿Queres pagar menos?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          SizedBox(height: 4),
          Text('Crea una alerta y te avisamos cuando encontremos una baja de precio.', style: TextStyle(color: Color(0xFFD3EEE8), fontSize: 12, height: 1.35)),
        ])),
        const SizedBox(width: 8),
        IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateAlertScreen())), icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white)),
      ]),
    );
  }

  Widget _buildTrustSection() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(22, 0, 22, 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.verified_outlined, size: 17, color: Color(0xFF667085)),
        SizedBox(width: 6),
        Flexible(child: Text('Compara precios · Sin costo para buscar · Sin publicidad invasiva', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF667085), fontSize: 11))),
      ]),
    );
  }

  Widget _buildBottomNavigationBar() {
    return NavigationBar(
      selectedIndex: 0,
      height: 68,
      onDestinationSelected: (index) {
        if (index == 1) Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAlertsScreen()));
        if (index == 2) Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateAlertScreen()));
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.search_rounded), selectedIcon: Icon(Icons.search_rounded), label: 'Buscar'),
        NavigationDestination(icon: Icon(Icons.notifications_none_rounded), selectedIcon: Icon(Icons.notifications_active_rounded), label: 'Mis alertas'),
        NavigationDestination(icon: Icon(Icons.add_alert_rounded), selectedIcon: Icon(Icons.add_alert_rounded), label: 'Crear alerta'),
      ],
    );
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), helpText: 'Elegi tus fechas de viaje');
    if (range != null) setState(() { _dateRange = range; _anyDate = false; });
  }

  Future<void> _pickSingleDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: DateTime.now().add(const Duration(days: 7)),
      helpText: 'Elegi tu fecha de ida',
    );
    if (date != null) setState(() { _departureDate = date; _anyDate = false; });
  }

  bool _canSearch() => _origin != null && _destination != null && _origin != _destination;

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _error = null;
      _results = null;
      _nearbyDateDeals = [];
      _searchedDepartureDate = null;
      _usedDefaultRoundTripDates = false;
    });
    try {
      final isOneWay = _tripType == TripType.oneWay;
      DateTime? departure = isOneWay ? _departureDate : _dateRange?.start;
      DateTime? returnDate = isOneWay ? null : _dateRange?.end;

      final usedDefaultDates = !isOneWay && _anyDate && departure == null;
      if (usedDefaultDates) {
        departure = DateTime.now().add(const Duration(days: 7));
        returnDate = departure.add(const Duration(days: 7));
      }

      final results = await _travelpayoutsService.searchDeals(
        originCityId: _origin!.id,
        destinationCityId: _destination!.id,
        dateFrom: departure,
        dateTo: returnDate,
      );

      List<NearbyDateDeal> nearby = [];
      if (!_anyDate && departure != null) {
        nearby = await _travelpayoutsService.searchNearestAvailableDates(
          originCityId: _origin!.id,
          destinationCityId: _destination!.id,
          departureDate: departure,
          returnDate: returnDate,
          previousCount: 2,
          nextCount: 2,
          maxDaysEachSide: 60,
        );
      }

      if (!mounted) return;
      setState(() {
        _results = results;
        _nearbyDateDeals = nearby;
        _searchedDepartureDate = departure;
        _usedDefaultRoundTripDates = usedDefaultDates;
      });
    } catch (e) {
      print('[Search] Error: $e');
      if (!mounted) return;
      setState(() => _error = 'No pudimos buscar precios ahora. Proba de nuevo en un momento.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openBookingLink(FlightDeal deal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vas a salir de la app'),
        content: const Text('Te vamos a llevar al sitio de venta para completar la compra. El precio no cambia para vos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar')),
        ],
      ),
    );
    if (confirmed != true) return;

    final uri = Uri.tryParse(deal.affiliateLink.trim());
    if (uri == null || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El link de compra no es valido.')));
      return;
    }

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No pudimos abrir el link de compra.')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No pudimos abrir el link de compra.')));
    }
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  String _formatDuration(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';

  static const _tpMarker = '761958';
  static const _tpTrs = '560037';

  String _affiliateDeepLink({required int campaignId, required int promoId, required String targetUrl}) {
    final encodedTarget = Uri.encodeComponent(targetUrl);
    return 'https://tp.media/r?campaign_id=$campaignId&marker=$_tpMarker&p=$promoId&trs=$_tpTrs&u=$encodedTarget';
  }

  String get _klookLink {
    const klookHotelsHome = 'https://www.klook.com/es/hotels/';
    final destination = _destination;
    if (destination == null) {
      return _affiliateDeepLink(campaignId: 137, promoId: 4110, targetUrl: klookHotelsHome);
    }
    final klookSvalue = destination.klookSvalue;
    if (klookSvalue == null || klookSvalue.isEmpty) {
      return _affiliateDeepLink(campaignId: 137, promoId: 4110, targetUrl: klookHotelsHome);
    }
    final checkIn = _searchedDepartureDate ?? DateTime.now().add(const Duration(days: 14));
    final checkOut = _results?.first.returnDate ?? checkIn.add(const Duration(days: 5));
    String fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final searchUrl = Uri.parse('https://www.klook.com/es/hotels/searchresult/').replace(queryParameters: {
      'check_in': fmt(checkIn),
      'check_out': fmt(checkOut),
      'room_num': '1',
      'adult_num': '$_passengers',
      'child_num': '0',
      'age': '',
      'stype': destination.klookStype,
      'svalue': klookSvalue,
      'override': '${destination.displayName}, ${destination.displayName}, ${destination.country}',
      'title': destination.displayName,
      'city_id': destination.klookCityId ?? klookSvalue,
      'latlng': '',
    }).toString();

    return _affiliateDeepLink(campaignId: 137, promoId: 4110, targetUrl: searchUrl);
  }

  String get _kkdayLink => _affiliateDeepLink(campaignId: 633, promoId: 9074, targetUrl: 'https://www.kkday.com/es/');

  Future<void> _openAffiliateLink(String rawUrl, String providerName) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.host.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No pudimos abrir $providerName.')));
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No pudimos abrir $providerName.')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No pudimos abrir $providerName.')));
    }
  }

  Widget _buildHotelsAndActivitiesCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1FAF7),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFD9EFE8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.hotel_rounded, color: Color(0xFF0F9D8D)),
          SizedBox(width: 8),
          Text('¿Necesitas hotel o excursiones?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        const Text('Alojamiento con Klook y actividades con KKday para tu viaje.', style: TextStyle(fontSize: 12, color: Color(0xFF667085))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _openAffiliateLink(_klookLink, 'Klook'),
              icon: const Icon(Icons.hotel_rounded, size: 16),
              label: const Text('Hoteles (Klook)'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _openAffiliateLink(_kkdayLink, 'KKday'),
              icon: const Icon(Icons.tour_rounded, size: 16),
              label: const Text('Excursiones (KKday)'),
            ),
          ),
        ]),
      ]),
    );
  }
}
