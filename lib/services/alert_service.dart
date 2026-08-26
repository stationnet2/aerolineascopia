// alert_service.dart
//
// Se encarga de guardar y leer las alertas del usuario en Firestore.
// Por ahora usamos "login anónimo" de Firebase: cada celular que instala
// la app recibe automáticamente un ID único, sin que el usuario tenga
// que crear cuenta ni poner contraseña. Sus alertas quedan ligadas a
// ese ID. Más adelante, si querés que el usuario recupere sus alertas
// en otro celular, ahí sí conviene sumar login con email real.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/flight_alert.dart';



/// Notificación persistente mostrada dentro de la app.
/// Se guarda en Firestore además del push, para que el usuario no pierda
/// una oportunidad aunque haya descartado la notificación del teléfono.
class FlightNotification {
  final String id;
  final String userId;
  final String alertId;
  final String title;
  final String body;
  final String origin;
  final String destination;
  final String originCityId;
  final String destinationCityId;
  final double price;
  final String currency;
  final String affiliateLink;
  final DateTime? departureDate;
  final DateTime? returnDate;
  final DateTime createdAt;
  final bool read;
  final bool isTest;

  const FlightNotification({
    required this.id,
    required this.userId,
    required this.alertId,
    required this.title,
    required this.body,
    required this.origin,
    required this.destination,
    required this.originCityId,
    required this.destinationCityId,
    required this.price,
    required this.currency,
    required this.affiliateLink,
    required this.departureDate,
    required this.returnDate,
    required this.createdAt,
    required this.read,
    required this.isTest,
  });

  factory FlightNotification.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    DateTime? parseNullableDate(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return FlightNotification(
      id: id,
      userId: (data['userId'] ?? '').toString(),
      alertId: (data['alertId'] ?? '').toString(),
      title: (data['title'] ?? 'Alerta de vuelo').toString(),
      body: (data['body'] ?? '').toString(),
      origin: (data['origin'] ?? '').toString(),
      destination: (data['destination'] ?? '').toString(),
      originCityId: (data['originCityId'] ?? '').toString(),
      destinationCityId: (data['destinationCityId'] ?? '').toString(),
      price: (data['price'] as num?)?.toDouble() ?? 0,
      currency: (data['currency'] ?? 'USD').toString(),
      affiliateLink: (data['affiliateLink'] ?? '').toString(),
      departureDate: parseNullableDate(data['departureDate']),
      returnDate: parseNullableDate(data['returnDate']),
      createdAt: parseDate(data['createdAt']),
      read: data['read'] == true,
      isTest: data['isTest'] == true,
    );
  }
}

class AlertService {
  final _db = FirebaseFirestore.instance;

  String get _userId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No hay usuario logueado. Revisá que Firebase.initializeApp y signInAnonymously se hayan ejecutado en main.dart');
    }
    return user.uid;
  }

  /// Pide permiso de notificaciones y guarda el token del celular en
  /// Firestore, para que el robot (GitHub Actions) sepa a qué
  /// dispositivo avisarle cuando encuentre una oferta.
  Future<void> setupNotifications() async {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      // El usuario no dio permiso. No podemos mandarle notificaciones,
      // pero la app sigue funcionando igual para crear/ver alertas.
      return;
    }

    final token = await messaging.getToken(
      vapidKey: 'BMtfOU3U44zywoRAZFQDTW8sTl5l3S7FvqNbh4A9lGYgs8tdqrTeNAkRlRPARjIHIzWJDkSGaeScCvcLhFfwHHk',
    );
    if (token == null) return;

    await _db.collection('users').doc(_userId).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );

    // Si el token cambia (pasa a veces, por ejemplo si el usuario
    // reinstala la app), lo volvemos a guardar automáticamente.
    messaging.onTokenRefresh.listen((newToken) {
      _db.collection('users').doc(_userId).set(
        {'fcmToken': newToken},
        SetOptions(merge: true),
      );
    });
  }

  /// Solicita una notificación de prueba. El robot de GitHub Actions la
  /// detecta en su siguiente ejecución y confirma el circuito completo FCM.
  Future<void> requestTestNotification() async {
    await setupNotifications();
    await _db.collection('users').doc(_userId).set({
      'testNotificationRequested': true,
      'testNotificationRequestedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Guarda una alerta nueva. Devuelve el ID que le asignó Firestore.
  Future<String> saveAlert({
    required String originCityId,
    required String destinationCityId,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool flexibleDates = false,
    double? maxPrice,
    double? initialPrice,
    int passengers = 1,
  }) async {
    final alert = FlightAlert(
      id: '', // Firestore genera el id, este campo no se usa al guardar
      userId: _userId,
      originCityId: originCityId,
      destinationCityId: destinationCityId,
      dateFrom: dateFrom,
      dateTo: dateTo,
      flexibleDates: flexibleDates,
      maxPrice: maxPrice,
      createdAt: DateTime.now(),
      lastKnownPrice: initialPrice,
      passengers: passengers,
    );

    final docRef = await _db.collection('flightAlerts').add(alert.toFirestore());
    return docRef.id;
  }

  /// Devuelve todas las alertas del usuario actual, en tiempo real
  /// (el Stream se actualiza solo si se agrega o borra una alerta).
  Stream<List<FlightAlert>> watchMyAlerts() {
    // Ordenamos en el cliente para que la app no dependa de un índice
    // compuesto de Firestore durante esta etapa del proyecto.
    return _db
        .collection('flightAlerts')
        .where('userId', isEqualTo: _userId)
        .snapshots()
        .map((snapshot) {
          final alerts = snapshot.docs
              .map((doc) => FlightAlert.fromFirestore(doc.id, doc.data()))
              .toList();
          alerts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return alerts;
        });
  }

  Future<void> deleteAlert(String alertId) {
    return _db.collection('flightAlerts').doc(alertId).delete();
  }

  Future<void> setActive(String alertId, bool isActive) {
    return _db.collection('flightAlerts').doc(alertId).update({'isActive': isActive});
  }

  /// Novedades persistentes de precio. A diferencia del push, permanecen
  /// visibles dentro de "Mis alertas" hasta que el usuario las abre.
  Stream<List<FlightNotification>> watchMyNotifications({int limit = 30}) {
    // Importante: antes se usaba where(userId) + orderBy(createdAt).
    // Si el índice compuesto todavía no estaba creado, el Stream podía
    // fallar y la pantalla mostraba silenciosamente una lista vacía.
    // Para estas novedades personales (máximo unas decenas), leemos las
    // del usuario y ordenamos localmente.
    return _db
        .collection('flightNotifications')
        .where('userId', isEqualTo: _userId)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          final notifications = snapshot.docs
              .map((doc) => FlightNotification.fromFirestore(doc.id, doc.data()))
              .toList();
          notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return notifications.take(limit).toList();
        });
  }

  Future<void> markNotificationRead(String notificationId) {
    return _db.collection('flightNotifications').doc(notificationId).update({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteNotification(String notificationId) {
    return _db.collection('flightNotifications').doc(notificationId).delete();
  }
}
