import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/chatbot_viewmodel.dart';

class ChatbotView extends StatefulWidget {
  const ChatbotView({super.key});

  @override
  State<ChatbotView> createState() => _ChatbotViewState();
}

class _ChatbotViewState extends State<ChatbotView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  static const double _maxBubbleWidthFactor = 0.82;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _confirmClear(ChatbotViewModel vm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Limpiar conversación?'),
        content: const Text('Se borrarán todos los mensajes de este chat.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
    if (ok == true) vm.clearChat();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(ChatbotViewModel vm) async {
    final text = _controller.text;
    _controller.clear();
    await vm.sendMessage(text);
    _scrollToBottom();
  }

  Widget _emptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 56,
              color: scheme.onSurface.withOpacity(0.45),
              semanticLabel: 'Chat',
            ),
            const SizedBox(height: 16),
            Text(
              'CuniBot',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Haz una pregunta sobre cunicultura, salud, agua, temperatura o registros.',
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface.withOpacity(0.75),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                _QuickChip(
                  text: '¿Cuánta agua necesita un conejo al día?',
                  onTap: () => _controller.text =
                      '¿Cuánta agua necesita un conejo al día?',
                ),
                _QuickChip(
                  text: '¿Qué temperatura es ideal en el galpón?',
                  onTap: () =>
                      _controller.text = '¿Qué temperatura es ideal en el galpón?',
                ),
                _QuickChip(
                  text: 'Síntomas comunes de enfermedad',
                  onTap: () =>
                      _controller.text = '¿Cuáles son síntomas comunes de enfermedad?',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChatbotViewModel>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CuniBot'),
        actions: [
          IconButton(
            tooltip: 'Limpiar conversación',
            onPressed: vm.isLoading || vm.messages.isEmpty
                ? null
                : () => _confirmClear(vm),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: vm.messages.isEmpty
                ? _emptyState(context)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: vm.messages.length,
                    itemBuilder: (_, i) {
                      final msg = vm.messages[i];
                      final label = msg.isUser
                          ? 'Tú dijiste: ${msg.text}'
                          : 'CuniBot dijo: ${msg.text}';
                      return Semantics(
                        label: label,
                        child: Align(
                          alignment: msg.isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width *
                                  _maxBubbleWidthFactor,
                            ),
                            decoration: BoxDecoration(
                              color: msg.isUser
                                  ? scheme.primary
                                  : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              msg.text,
                              style: TextStyle(
                                color: msg.isUser
                                    ? scheme.onPrimary
                                    : scheme.onSurface,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (vm.isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'CuniBot está respondiendo…',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface.withOpacity(0.75),
                        ),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Pregúntale a CuniBot…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(vm),
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    label: 'Enviar mensaje',
                    child: IconButton.filled(
                      tooltip: 'Enviar',
                      onPressed: vm.isLoading ? null : () => _send(vm),
                      icon: const Icon(Icons.send),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(text),
      onPressed: onTap,
    );
  }
}

