import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'firebase_options.dart';
import 'screens/search_flights_screen.dart';
import 'services/alert_service.dart';
import 'data/city_airports.dart';

void main() async {
  // Necesario antes de usar cualquier plugin nativo (Firebase incluido).
  WidgetsFlutterBinding.ensureInitialized();

  // Conecta la app con el proyecto de Firebase que configuramos con
  // flutterfire configure (ese comando generó firebase_options.dart).
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // runApp() se llama de inmediato: el resto (login anónimo, notificaciones,
  // catálogo de destinos) corre en paralelo, en segundo plano, con timeout.
  // Si algo tarda o falla (sin red, Play Services desactualizado, etc.) la
  // app arranca igual en vez de quedarse en pantalla negra para siempre.
  _initBackgroundTasks();

  runApp(const VuelosApp());
}

void _initBackgroundTasks() async {
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously().timeout(const Duration(seconds: 10));
    }
  } catch (e) {
    // ignore: avoid_print
    print('No se pudo iniciar sesión anónima: $e');
  }

  try {
    await AlertService().setupNotifications().timeout(const Duration(seconds: 10));
  } catch (e) {
    // ignore: avoid_print
    print('No se pudieron configurar las notificaciones: $e');
  }

  try {
    // Trae el catálogo de destinos actualizado desde Firestore (ver
    // city_airports.dart). Si falla, la app sigue con el catálogo
    // hardcodeado de respaldo, sin romper nada.
    await refreshDestinationsFromFirestore().timeout(const Duration(seconds: 10));
  } catch (e) {
    // ignore: avoid_print
    print('No se pudo actualizar el catálogo de destinos: $e');
  }

  try {
    await refreshPopularDestinationsFromFirestore().timeout(const Duration(seconds: 10));
  } catch (e) {
    // ignore: avoid_print
    print('No se pudieron actualizar los destinos populares: $e');
  }
}

class VuelosApp extends StatelessWidget {
  const VuelosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlertaTrip',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0F9D8D),
        useMaterial3: true,
      ),
      home: const ConnectivityGate(child: SearchFlightsScreen()),
    );
  }
}

/// Envuelve la pantalla principal y muestra un banner fijo arriba cuando
/// el celular se queda sin internet, sin tapar el resto de la app.
class ConnectivityGate extends StatelessWidget {
  final Widget child;
  const ConnectivityGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      builder: (context, snapshot) {
        final offline = snapshot.hasData &&
            snapshot.data!.every((r) => r == ConnectivityResult.none);
        return Column(
          children: [
            if (offline)
              Container(
                width: double.infinity,
                color: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: const SafeArea(
                  bottom: false,
                  child: Text(
                    'Sin conexión a internet. Algunas funciones no van a estar disponibles.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}