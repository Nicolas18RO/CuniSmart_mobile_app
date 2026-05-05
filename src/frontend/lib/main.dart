import 'package:flutter/foundation.dart';
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
import 'views/iot/iot_dashboard_view.dart';
import 'views/rabbits/rabbit_create_route.dart';
import 'views/rabbits/rabbit_list_view.dart';

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
    final voice = context.watch<VoiceViewModel>();
    final showBanner = voice.isProcessing || voice.voice.isListening;

    return Scaffold(
      body: Stack(
        children: [
          _index == 0 ? const RabbitListView() : const IoTDashboardView(),
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
        ],
      ),
      floatingActionButton: const _VoiceMicButton(heroTag: 'voice_mic_shell'),
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

/// Mic: tap starts listening; tap again stops and runs command / silence handling.
class _VoiceMicButton extends StatefulWidget {
  const _VoiceMicButton({required this.heroTag});

  final Object heroTag;

  @override
  State<_VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends State<_VoiceMicButton> {
  Future<void> _toggle() async {
    final vm = context.read<VoiceViewModel>();
    debugPrint(
      'VoiceMic: tap isListening=${vm.voice.isListening} kVoiceDebugBypassStt=$kVoiceDebugBypassStt',
    );

    if (kDebugMode && kVoiceDebugBypassStt) {
      debugPrint('VoiceMic: debug bypass — applyCommandFromText("ver conejos")');
      await vm.applyCommandFromText('ver conejos');
      if (mounted) setState(() {});
      return;
    }

    await vm.toggleMicrophone();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VoiceViewModel>();
    final listening = vm.isVoiceModeEnabled;
    final scheme = Theme.of(context).colorScheme;

    return FloatingActionButton.small(
      heroTag: widget.heroTag,
      tooltip: listening ? 'Detener y procesar' : 'Voz',
      backgroundColor:
          listening ? scheme.errorContainer : scheme.secondaryContainer,
      foregroundColor:
          listening ? scheme.onErrorContainer : scheme.onSecondaryContainer,
      onPressed: _toggle,
      child: const Icon(Icons.mic),
    );
  }
}
