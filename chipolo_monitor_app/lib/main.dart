import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/ble_scanner_service.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChipoloMonitorApp());
}

class ChipoloMonitorApp extends StatelessWidget {
  const ChipoloMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BleScannerService(),
      child: MaterialApp(
        title: 'Kerberos',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00BCD4),
            brightness: Brightness.dark,
            surface: const Color(0xFF0D1117),
            surfaceContainer: const Color(0xFF161B22),
          ),
          scaffoldBackgroundColor: const Color(0xFF0D1117),
          cardTheme: CardThemeData(
            color: const Color(0xFF161B22),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF30363D), width: 1),
            ),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
