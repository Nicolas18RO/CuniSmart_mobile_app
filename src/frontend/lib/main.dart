import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'services/rabbit_service.dart';
import 'viewmodels/rabbit_viewmodel.dart';
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

    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        Provider<RabbitService>.value(value: rabbitService),
        ChangeNotifierProvider<RabbitViewModel>(
          create: (_) => RabbitViewModel(rabbitService),
        ),
      ],
      child: MaterialApp(
        title: 'CuniSmart',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
          useMaterial3: true,
        ),
        home: const RabbitListView(),
      ),
    );
  }
}
