import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/flight_alert.dart';
import '../data/city_airports.dart';
import '../services/alert_service.dart';
import '../services/travelpayouts_service.dart';
import 'create_alert_screen.dart';
import 'search_flights_screen.dart';

class MyAlertsScreen extends StatefulWidget {
  const MyAlertsScreen({super.key});

  @override
  State<MyAlertsScreen> createState() => _MyAlertsScreenState();
}

class _MyAlertsScreenState extends State<MyAlertsScreen> with SingleTickerProviderStateMixin {
  final _alertService = AlertService();
  final _travelpayoutsService = TravelpayoutsService();
  late final AnimationController _bellController;

  @override
  void initState() {
    super.initState();
    _alertService.setupNotifications();
    _bellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
      lowerBound: -0.07,
      upperBound: 0.07,
    );
  }

  @override
  void dispose() {
    _bellController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Mis alertas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Probar notificación',
            onPressed: _requestNotificationTest,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Buscar vuelos',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchFlightsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateAlertScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nueva alerta'),
      ),
      body: StreamBuilder<List<FlightNotification>>(
        stream: _alertService.watchMyNotifications(),
        builder: (context, notificationSnapshot) {
          if (notificationSnapshot.hasError) {
            return _buildLoadError(
              'No pudimos cargar las alertas encontradas',
              notificationSnapshot.error,
            );
          }
          if (!notificationSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = notificationSnapshot.data!;
          final unreadCount = notifications.where((n) => !n.read && !n.isTest).length;
          if (unreadCount > 0 && !_bellController.isAnimating) {
            _bellController.repeat(reverse: true);
          } else if (unreadCount == 0 && _bellController.isAnimating) {
            _bellController.stop();
            _bellController.reset();
          }

          return StreamBuilder<List<FlightAlert>>(
            stream: _alertService.watchMyAlerts(),
            builder: (context, alertSnapshot) {
              if (alertSnapshot.hasError) {
                return _buildLoadError('No pudimos cargar tus alertas', alertSnapshot.error);
              }
              if (!alertSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final alerts = alertSnapshot.data!;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  if (unreadCount > 0) ...[
                    _buildFoundAlertBanner(unreadCount),
                    const SizedBox(height: 12),
                  ],
                  _buildIntro(alerts.length, unreadCount),
                  const SizedBox(height: 18),
                  _buildNotificationSection(notifications),
                  const SizedBox(height: 22),
                  _buildSectionTitle('Tus alertas activas', Icons.flight_takeoff_rounded),
                  const SizedBox(height: 10),
                  if (alerts.isEmpty) _buildEmptyState(context),
                  ...alerts.map(_buildAlertCard),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _requestNotificationTest() async {
    try {
      await _alertService.requestTestNotification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prueba solicitada. Ejecutá ahora el workflow de GitHub Actions.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pudimos preparar la prueba: $e')),
      );
    }
  }

  Widget _buildLoadError(String title, Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFD92D20)),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 8),
          Text('$error', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF667085), fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _buildFoundAlertBanner(int unreadCount) {
    final label = unreadCount == 1 ? '¡TENÉS 1 ALERTA ENCONTRADA!' : '¡TENÉS $unreadCount ALERTAS ENCONTRADAS!';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFD92D20), Color(0xFFFF6B35)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Row(children: [
        AnimatedBuilder(
          animation: _bellController,
          builder: (_, child) => Transform.rotate(angle: _bellController.value, child: child),
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: Colors.white.withOpacity(.18), shape: BoxShape.circle),
            child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 33),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          const Text('Abrí la oferta de abajo para ver el precio y reservar antes de que cambie.', style: TextStyle(color: Colors.white, height: 1.3, fontSize: 12)),
        ])),
      ]),
    );
  }

  Widget _buildIntro(int alertCount, int unreadCount) {
    final hasNews = unreadCount > 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasNews
              ? const [Color(0xFF7A271A), Color(0xFFD92D20)]
              : const [Color(0xFF172B4D), Color(0xFF0B5ED7)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: Colors.white.withOpacity(.16), borderRadius: BorderRadius.circular(18)),
              child: AnimatedBuilder(
                animation: _bellController,
                builder: (_, child) => Transform.rotate(angle: hasNews ? _bellController.value : 0, child: child),
                child: Icon(hasNews ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, color: Colors.white, size: 29),
              ),
            ),
            if (hasNews) Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Text('$unreadCount', style: const TextStyle(color: Color(0xFFD92D20), fontWeight: FontWeight.w900, fontSize: 11)),
              ),
            ),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                hasNews ? 'Hay una oportunidad esperándote' : 'Tus alertas están trabajando',
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                hasNews
                    ? 'Mirá la sección ALERTA ENCONTRADA debajo.'
                    : '$alertCount alerta${alertCount == 1 ? '' : 's'} guardada${alertCount == 1 ? '' : 's'} y monitoreándose.',
                style: const TextStyle(color: Color(0xFFE1EEFF), fontSize: 12, height: 1.35),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationSection(List<FlightNotification> notifications) {
    final priceNotifications = notifications.where((n) => !n.isTest).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          priceNotifications.isEmpty ? 'Novedades de precio' : '🚨 ALERTAS ENCONTRADAS',
          priceNotifications.isEmpty ? Icons.bolt_rounded : Icons.notifications_active_rounded,
          color: priceNotifications.isEmpty ? const Color(0xFF0B5ED7) : const Color(0xFFD92D20),
        ),
        const SizedBox(height: 10),
        if (priceNotifications.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: const Row(children: [
              Icon(Icons.hourglass_empty_rounded, color: Color(0xFF667085)),
              SizedBox(width: 12),
              Expanded(child: Text('Todavía no encontramos una baja que cumpla las condiciones de tus alertas. Cuando ocurra, la vas a ver acá.', style: TextStyle(color: Color(0xFF667085), height: 1.35))),
            ]),
          )
        else
          ...priceNotifications.take(8).map(_buildNotificationCard),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, {Color color = const Color(0xFF0B5ED7)}) {
    return Row(children: [
      Icon(icon, color: color, size: 21),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF172033))),
    ]);
  }

  Widget _buildNotificationCard(FlightNotification notification) {
    final isUnread = !notification.read;
    final dates = notification.departureDate == null
        ? ''
        : '${_formatDate(notification.departureDate!)}${notification.returnDate != null ? ' → ${_formatDate(notification.returnDate!)}' : ''}';

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(color: const Color(0xFFD92D20), borderRadius: BorderRadius.circular(22)),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
      ),
      confirmDismiss: (_) => _confirmDeleteNotification(),
      onDismissed: (_) => _alertService.deleteNotification(notification.id),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isUnread ? const Color(0xFFD92D20) : const Color(0xFFE7EBF2), width: isUnread ? 2 : 1),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: isUnread ? () => _alertService.markNotificationRead(notification.id) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(color: isUnread ? const Color(0xFFFFE4E1) : const Color(0xFFE8F7EF), borderRadius: BorderRadius.circular(20)),
            child: Text(isUnread ? '🚨 ALERTA NUEVA' : 'PRECIO DETECTADO', style: TextStyle(color: isUnread ? const Color(0xFFD92D20) : const Color(0xFF167B45), fontSize: 10, fontWeight: FontWeight.w900)),
          ),
          const Spacer(),
          if (isUnread) const Icon(Icons.notifications_active_rounded, color: Color(0xFFD92D20), size: 22),
        ]),
        const SizedBox(height: 12),
        Text(
          '${notification.originCityId.isNotEmpty ? _cityName(notification.originCityId) : notification.origin} → ${notification.destinationCityId.isNotEmpty ? _cityName(notification.destinationCityId) : notification.destination}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        if (notification.originCityId.isNotEmpty && notification.origin.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text('${notification.origin}${notification.destination.isNotEmpty ? ' → ${notification.destination}' : ''}', style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 11)),
        ],
        if (dates.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(dates, style: const TextStyle(color: Color(0xFF667085), fontSize: 12)),
        ],
        const SizedBox(height: 10),
        Text(notification.body, style: const TextStyle(color: Color(0xFF475467), height: 1.35)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFF1F8FF), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            const Icon(Icons.sell_rounded, color: Color(0xFF0B5ED7)),
            const SizedBox(width: 10),
            const Text('Precio encontrado', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475467))),
            const Spacer(),
            Text('${notification.currency} ${notification.price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0B5ED7))),
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F9D58)),
            onPressed: () => _openReservation(notification),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Ver y reservar este vuelo', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 7),
        Text('Detectado ${_formatRelative(notification.createdAt)} · El precio final se confirma en el sitio de reserva.', style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 10)),
          ]),
        ),
      ),
      ),
    );
  }

  Future<bool> _confirmDeleteNotification() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar esta alerta?'),
        content: const Text('No la vas a ver más en esta lista. Esto no afecta la alerta de búsqueda que la generó.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.flight_takeoff_rounded, size: 56, color: Color(0xFF0B5ED7)),
        const SizedBox(height: 14),
        const Text('Todavía no tenés alertas guardadas', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        const Text('Creá una para que te avisemos cuando encontremos una baja de precio.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFF667085))),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateAlertScreen())), icon: const Icon(Icons.add_alert_rounded), label: const Text('Crear mi primera alerta')),
      ]),
    );
  }

  Widget _buildAlertCard(FlightAlert alert) {
    final origin = _cityName(alert.originCityId);
    final destination = _cityName(alert.destinationCityId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE7EBF2))),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: alert.isActive ? const Color(0xFFEAF3FF) : Colors.grey.shade200,
          child: Icon(Icons.flight, color: alert.isActive ? const Color(0xFF0B5ED7) : Colors.grey),
        ),
        title: Text('$origin → $destination', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(_buildSubtitle(alert))),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(value: alert.isActive, onChanged: (v) => _alertService.setActive(alert.id, v)),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _confirmDelete(alert)),
        ]),
      ),
    );
  }

  String _buildSubtitle(FlightAlert alert) {
    final parts = <String>[];
    if (alert.flexibleDates) {
      parts.add('Fechas flexibles');
    } else if (alert.dateFrom != null && alert.dateTo != null) {
      parts.add('${_formatDate(alert.dateFrom!)} - ${_formatDate(alert.dateTo!)}');
    } else if (alert.dateFrom != null) {
      parts.add(_formatDate(alert.dateFrom!));
    }
    if (alert.maxPrice != null) parts.add('Tope: USD ${alert.maxPrice!.toStringAsFixed(0)}');
    if (alert.lastKnownPrice != null) parts.add('Último precio: USD ${alert.lastKnownPrice!.toStringAsFixed(0)}');
    return parts.join(' · ');
  }

  Future<void> _openReservation(FlightNotification notification) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reservar vuelo'),
        content: const Text('Vas a salir de la app para continuar en el sitio de reserva. El precio final se confirma allí.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar')),
        ],
      ),
    );
    if (confirmed != true) return;

    // La notificación puede venir de una versión anterior del robot con
    // un link .ru. Si tenemos ruta y fechas, regeneramos el enlace con el
    // dominio internacional, español y el marker actual.
    final link = _bookingLinkForNotification(notification);
    final uri = Uri.tryParse(link);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El enlace de reserva no es válido.')),
        );
      }
      return;
    }

    // Al continuar, el usuario ya vio la alerta. Recién ahora la marcamos
    // como leída; cancelar no la descarta.
    await _alertService.markNotificationRead(notification.id);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos abrir el sitio de reserva.')),
      );
    }
  }

  String _bookingLinkForNotification(FlightNotification notification) {
    // El link ya viene armado (y guardado) desde el momento en que se
    // encontró la oferta —ya sea por la app o por el robot de GitHub
    // Actions— usando el campo `link` real que devuelve Travelpayouts.
    // No lo reconstruimos acá para no volver a caer en el link genérico
    // de `search.aviasales.com` que redirigía a la versión en ruso.
    return notification.affiliateLink.trim();
  }

  String _cityName(String cityId) {
    try {
      return cityGroups.firstWhere((c) => c.id == cityId).displayName;
    } catch (_) {
      return cityId;
    }
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatRelative(DateTime date) {
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return 'recién';
    if (difference.inMinutes < 60) return 'hace ${difference.inMinutes} min';
    if (difference.inHours < 24) return 'hace ${difference.inHours} h';
    return 'el ${_formatDate(date)}';
  }

  Future<void> _confirmDelete(FlightAlert alert) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar esta alerta?'),
        content: Text('${_cityName(alert.originCityId)} → ${_cityName(alert.destinationCityId)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (confirmed == true) await _alertService.deleteAlert(alert.id);
  }
}
