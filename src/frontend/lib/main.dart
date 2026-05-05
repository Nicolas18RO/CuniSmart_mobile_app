import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app/app_root.dart';
import 'core/network/api_client.dart';
import 'core/theme/cuni_theme.dart';
import 'core/voice/app_voice_form_bridge.dart';
import 'services/auth_service.dart';
import 'services/rabbit_service.dart';
import 'services/sensor_service.dart';
import 'services/voice_command_parser.dart';
import 'services/voice_service.dart';
import 'viewmodels/auth_viewmodel.dart';
import 'viewmodels/rabbit_viewmodel.dart';
import 'viewmodels/sensor_viewmodel.dart';
import 'viewmodels/voice_viewmodel.dart';
import 'views/rabbits/rabbit_create_route.dart';
import 'views/rabbits/rabbit_list_view.dart';
import 'views/iot/iot_dashboard_view.dart';
import 'features/rabbits/presentation/widgets/custom_bottom_bar.dart';
import 'widgets/voice_listening_overlay.dart';

/// Used so [VoiceViewModel] can open routes without a [BuildContext] from a nested rebuild.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Used so [VoiceViewModel] can switch bottom tabs via [_MainShellState.setTabIndex].
final GlobalKey _appMainShellKey = GlobalKey();

void _setMainShellTab(int index) {
  final s = _appMainShellKey.currentState;
  if (s is _MainShellState) s.setTabIndex(index);
}

/// Debug-only: skip STT and run a fixed command (proves parser + ViewModel path).
/// Set to `true` while testing on device, then set back to `false`.
const bool kVoiceDebugBypassStt = false;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CuniSmartApp());
}

class CuniSmartApp extends StatelessWidget {
  const CuniSmartApp({super.key});

  @override
  Widget build(BuildContext context) {
    final apiClient = ApiClient();
    final authService = AuthService(apiClient: apiClient);
    apiClient.onTokenRefresh = authService.refreshFromStorage;

    final rabbitService = RabbitService(apiClient);
    final sensorService = SensorService(apiClient);

    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        Provider<AuthService>.value(value: authService),
        ChangeNotifierProvider<AuthViewModel>(
          create: (_) => AuthViewModel(authService: authService),
        ),
        Provider<RabbitService>.value(value: rabbitService),
        Provider<SensorService>.value(value: sensorService),
        Provider<VoiceService>(create: (_) => VoiceService()),
        Provider<VoiceCommandParser>.value(value: const VoiceCommandParser()),
        ChangeNotifierProvider<RabbitViewModel>(
          create: (_) => RabbitViewModel(rabbitService),
        ),
        ChangeNotifierProvider<SensorViewModel>(
          create: (_) => SensorViewModel(sensorService),
        ),
        ChangeNotifierProvider<AppVoiceFormBridge>(
          create: (_) => AppVoiceFormBridge(),
        ),
        ChangeNotifierProvider<VoiceViewModel>(
          create: (ctx) => VoiceViewModel(
            ctx.read<VoiceService>(),
            ctx.read<VoiceCommandParser>(),
            ctx.read<RabbitViewModel>(),
            ctx.read<SensorViewModel>(),
            ctx.read<AppVoiceFormBridge>(),
            onRequestOpenCreateRabbitScreen: () {
              appNavigatorKey.currentState?.push<bool>(
                MaterialPageRoute(builder: (_) => const RabbitCreateRoute()),
              );
            },
            onRequestPopToRoot: () {
              appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
            },
            onChangeTab: _setMainShellTab,
            onUiFeedback: (message) {
              final ctx2 = appNavigatorKey.currentState?.context;
              if (ctx2 == null) return;
              ScaffoldMessenger.of(ctx2)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(message)));
            },
            currentTabIndex: 0,
          ),
        ),
      ],
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'CuniSmart',
        debugShowCheckedModeBanner: false,
        theme: CuniTheme.light(),
        home: AppRoot(home: _MainShell(key: _appMainShellKey)),
      ),
    );
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell({super.key});

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _index = 0;

  void setTabIndex(int index) {
    if (!mounted) return;
    if (index < 0 || index > 1) return;
    setState(() => _index = index);
    context.read<VoiceViewModel>().updateCurrentTabIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _index == 0 ? const RabbitListView() : const IoTDashboardView(),
          if (context.watch<VoiceViewModel>().isVoiceModeEnabled)
            const VoiceListeningOverlay(),
        ],
      ),
      bottomNavigationBar: CustomBottomBar(
        activeIndex: _index,
        onTap: setTabIndex,
        items: const [
          BottomBarItem(icon: Icons.pets_outlined, label: 'Conejos'),
          BottomBarItem(icon: Icons.sensors, label: 'IoT'),
        ],
      ),
    );
  }
}
