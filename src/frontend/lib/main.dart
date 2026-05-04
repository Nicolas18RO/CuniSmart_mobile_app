import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'services/rabbit_service.dart';
import 'services/sensor_service.dart';
import 'viewmodels/rabbit_viewmodel.dart';
import 'viewmodels/sensor_viewmodel.dart';
import 'views/iot/iot_dashboard_view.dart';
import 'views/rabbits/rabbit_list_view.dart';

void main() {
  runApp(const CuniSmartApp());
}

class CuniSmartApp extends StatelessWidget {
  const CuniSmartApp({super.key});

  @override
  Widget build(BuildContext context) {
    final apiClient = ApiClient();
    final rabbitService = RabbitService(apiClient);
    final sensorService = SensorService(apiClient);

    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        Provider<RabbitService>.value(value: rabbitService),
        Provider<SensorService>.value(value: sensorService),
        ChangeNotifierProvider<RabbitViewModel>(
          create: (_) => RabbitViewModel(rabbitService),
        ),
        ChangeNotifierProvider<SensorViewModel>(
          create: (_) => SensorViewModel(sensorService),
        ),
      ],
      child: MaterialApp(
        title: 'CuniSmart',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
          useMaterial3: true,
        ),
        home: const _MainShell(),
      ),
    );
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell();

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _index == 0 ? const RabbitListView() : const IoTDashboardView(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.pets_outlined),
            label: 'Rabbits',
          ),
          NavigationDestination(
            icon: Icon(Icons.sensors),
            label: 'IoT',
          ),
        ],
      ),
    );
  }
}
