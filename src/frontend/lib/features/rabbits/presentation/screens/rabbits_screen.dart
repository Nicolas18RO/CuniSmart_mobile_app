import 'package:flutter/material.dart';

import '../../../../core/theme/cuni_theme.dart';
import '../widgets/custom_bottom_bar.dart';
import '../widgets/floating_actions.dart';
import '../../../../models/rabbit.dart';
import '../widgets/rabbit_card.dart';
import '../widgets/rabbits_header.dart';

class RabbitsScreen extends StatelessWidget {
  const RabbitsScreen({super.key});

  // UI-only showcase screen; not used in navigation (real screen is `views/rabbits/rabbit_list_view.dart`).
  static const List<Rabbit> _mock = [
    Rabbit(
      id: 1,
      name: 'Luna',
      breed: 'Nueva Zelanda',
      sex: 'F',
      birthDate: '2026-01-01',
      weight: 2.4,
      status: 'Saludable',
      notes: '',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
    ),
    Rabbit(
      id: 2,
      name: 'Copito',
      breed: 'Californiano',
      sex: 'M',
      birthDate: '2026-01-01',
      weight: 2.1,
      status: 'En observación',
      notes: '',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
    ),
    Rabbit(
      id: 3,
      name: 'Moka',
      breed: 'Rex',
      sex: 'F',
      birthDate: '2026-01-01',
      weight: 2.8,
      status: 'Saludable',
      notes: '',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
    ),
    Rabbit(
      id: 4,
      name: 'Nube',
      breed: 'Angora',
      sex: 'M',
      birthDate: '2026-01-01',
      weight: 1.9,
      status: 'Vacunación pendiente',
      notes: '',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CuniTheme.rabbitsBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                RabbitsHeader(
                  title: 'Conejos',
                  onChat: () {},
                  onRefresh: () {},
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                    itemCount: _mock.length,
                    itemBuilder: (context, index) {
                      final rabbit = _mock[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: RabbitCard(
                          rabbit: rabbit,
                          onEdit: () {},
                          onDelete: () {},
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const FloatingActions(
              onMic: null,
              onAdd: null,
            ),
          ],
        ),
      ),
      bottomNavigationBar: const CustomBottomBar(
        activeIndex: 0,
        onTap: null,
        items: [
          BottomBarItem(icon: Icons.pets_outlined, label: 'Conejos'),
          BottomBarItem(icon: Icons.sensors, label: 'IoT'),
        ],
      ),
    );
  }
}

