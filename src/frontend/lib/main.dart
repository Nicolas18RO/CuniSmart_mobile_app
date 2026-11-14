import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app/app_root.dart';
import 'core/network/api_client.dart';
import 'core/theme/cuni_theme.dart';
import 'core/voice/app_voice_form_bridge.dart';
import 'data/local/app_database.dart';
import 'features/r3/application/r3_use_cases.dart';
import 'features/r3/data/local_r3_repository.dart';
import 'features/r3/presentation/r3_view_model.dart';
import 'services/auth_service.dart';
import 'services/chatbot_service.dart';
import 'services/connectivity_plus_gate.dart';
import 'services/r3_hydration_service.dart';
import 'services/offline_authorization.dart';
import 'services/rabbit_local_store.dart';
import 'services/rabbit_service.dart';
import 'services/sensor_service.dart';
import 'services/voice_command_parser.dart';
import 'services/voice_service.dart';
import 'voice/engine/r3_voice_facade.dart';
import 'viewmodels/auth_viewmodel.dart';
import 'viewmodels/chatbot_viewmodel.dart';
import 'viewmodels/rabbit_viewmodel.dart';
import 'viewmodels/sensor_viewmodel.dart';
import 'viewmodels/voice_viewmodel.dart';
import 'views/chatbot/chatbot_view.dart';
import 'views/iot/iot_dashboard_view.dart';
import 'views/rabbits/rabbit_create_route.dart';
import 'views/rabbits/rabbit_list_view.dart';
import 'widgets/voice_mic_fab.dart';

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
  final database = AppDatabase.fromDocuments();
  runApp(CuniSmartApp(database: database));
}

class CuniSmartApp extends StatelessWidget {
  const CuniSmartApp({super.key, required this.database});

  final AppDatabase database;

  @override
  Widget build(BuildContext context) {
    final apiClient = ApiClient();
    final authService = AuthService(
      apiClient: apiClient,
      readBootTime: readAndroidBootTime,
    );
    apiClient.onTokenRefresh = authService.refreshFromStorage;
    apiClient.sessionGeneration = () => authService.generation;
    apiClient.onBackendUnavailable = authService.markDisconnected;

    final connectivity = ConnectivityPlusGate();
    final rabbitService = RabbitService(
      apiClient,
      RabbitLocalStore.accountScopes(database),
      connectivity: connectivity,
      r3PublicationEnabled:
          const bool.fromEnvironment('CUNISMART_R3_PUBLICATION'),
      auth: authService,
    );
    final sensorService = SensorService(apiClient);
    final chatbotService = ChatbotService(apiClient);
    final r3UseCases = R3UseCases(LocalR3Repository(
      database,
      authService,
      onLocalMutation: rabbitService.requestR3Publication,
    ));

    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        Provider<AuthService>.value(value: authService),
        ChangeNotifierProvider<AuthViewModel>(
          create: (_) => AuthViewModel(authService: authService),
        ),
        Provider<RabbitService>.value(value: rabbitService),
        Provider<R3HydrationService>(
          create: (_) => R3HydrationService(database, apiClient, authService,
              onResolution: rabbitService.requestR3Publication),
        ),
        Provider<SensorService>.value(value: sensorService),
        Provider<ChatbotService>.value(value: chatbotService),
        Provider<VoiceService>(create: (_) => VoiceService()),
        Provider<VoiceCommandParser>.value(value: const VoiceCommandParser()),
        ChangeNotifierProvider<RabbitViewModel>(
          create: (_) => RabbitViewModel(
            rabbitService,
            onlineChanges: connectivity.onOnline,
          ),
        ),
        ChangeNotifierProvider<SensorViewModel>(
          create: (_) => SensorViewModel(sensorService),
        ),
        ChangeNotifierProvider<ChatbotViewModel>(
          create: (_) => ChatbotViewModel(chatbotService),
        ),
        ChangeNotifierProvider<R3ViewModel>(
          create: (_) => R3ViewModel(
            r3UseCases,
            sessionGeneration: () => authService.generation,
            sessionUnlocked: () => authService.localDataUnlocked,
            remoteVerified: () => authService.remoteVerified,
          ),
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
            r3VoiceFacade: R3VoiceFacade(r3UseCases,
                sessionGeneration: () => authService.generation,
                sessionUnlocked: () => authService.localDataUnlocked),
            onRequestOpenCreateRabbitScreen: () {
              appNavigatorKey.currentState?.push<bool>(
                MaterialPageRoute(builder: (_) => const RabbitCreateRoute()),
              );
            },
            onRequestPopToRoot: () {
              appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
            },
            onChangeTab: _setMainShellTab,
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
    if (index < 0 || index > 2) return;
    setState(() => _index = index);
    context.read<VoiceViewModel>().updateCurrentTabIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceViewModel>();
    final showBanner = voice.isProcessing || voice.voice.isListening;

    return Scaffold(
      body: Stack(
        children: [
          _index == 0
              ? const RabbitListView()
              : _index == 1
                  ? const IoTDashboardView()
                  : const ChatbotView(),
          if (showBanner) _VoiceStatusChip(voice: voice),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: setTabIndex,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.pets_outlined),
            label: 'Rabbits',
          ),
          NavigationDestination(
            icon: Icon(Icons.sensors),
            label: 'IoT',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'CuniBot',
          ),
        ],
      ),
      floatingActionButton: _index == 0
          ? null
          : const VoiceMicFab(
              heroTag: 'voice_mic_shell',
              debugBypassStt: kVoiceDebugBypassStt,
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

/// Listening vs processing feedback (minimal chip).
class _VoiceStatusChip extends StatelessWidget {
  const _VoiceStatusChip({required this.voice});

  final VoiceViewModel voice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = voice.isProcessing ? 'Procesando…' : 'Escuchando…';

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(999),
            color: scheme.surfaceContainerHighest.withOpacity(0.92),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    voice.isProcessing ? Icons.hourglass_top : Icons.mic,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
