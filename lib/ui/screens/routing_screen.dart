import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/routing_settings.dart';
import '../../providers/settings_provider.dart';
import '../../providers/vpn_provider.dart';
import '../theme/app_colors.dart';

class RoutingScreen extends ConsumerWidget {
  const RoutingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final isConnected = ref.watch(vpnProvider).isConnected;

    return Scaffold(
      appBar: AppBar(title: const Text('Маршрутизация')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (settings) => _RoutingBody(
          routing: settings.routing,
          isConnected: isConnected,
          onUpdate: (r) => ref
              .read(settingsProvider.notifier)
              .save(settings.copyWith(routing: r)),
        ),
      ),
    );
  }
}

class _RoutingBody extends StatelessWidget {
  final RoutingSettings routing;
  final bool isConnected;
  final void Function(RoutingSettings) onUpdate;

  const _RoutingBody({
    required this.routing,
    required this.isConnected,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isConnected) _connectedBanner(),
        _label('РЕЖИМ'),
        const SizedBox(height: 8),
        _card([
          _radioTile(
            RoutingDirection.global,
            'Глобальный',
            'Весь трафик через VPN',
          ),
          _divider(),
          _radioTile(
            RoutingDirection.bypass,
            'Обход',
            'Выбранные адреса — напрямую, остальное через VPN',
          ),
          _divider(),
          _radioTile(
            RoutingDirection.onlySelected,
            'Только выбранное',
            'Только выбранные адреса — через VPN, остальное напрямую',
          ),
        ]),
        if (routing.isActive) ...[
          const SizedBox(height: 20),
          _label('ПАРАМЕТРЫ'),
          const SizedBox(height: 8),
          _card([
            SwitchListTile(
              title: const Text('Локальные сети',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
              subtitle: const Text('192.168.x.x, 10.x.x.x — напрямую',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              value: routing.bypassLocal,
              onChanged: isConnected
                  ? null
                  : (v) => onUpdate(routing.copyWith(bypassLocal: v)),
            ),
          ]),
          const SizedBox(height: 12),
          _card([
            SwitchListTile(
              title: const Text('По стране (Geo IP)',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
              subtitle: const Text('IP-диапазоны по стране из базы geoip.dat',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              value: routing.geoEnabled,
              onChanged: isConnected
                  ? null
                  : (v) => onUpdate(routing.copyWith(geoEnabled: v)),
            ),
            if (routing.geoEnabled) ...[
              _divider(),
              _chipSection(
                context,
                chips: routing.geoCodes
                    .map((code) => _Chip(
                          label: code,
                          onDelete: isConnected
                              ? null
                              : () => onUpdate(routing.copyWith(
                                    geoCodes: routing.geoCodes
                                        .where((c) => c != code)
                                        .toList(),
                                  )),
                        ))
                    .toList(),
                onAdd: isConnected
                    ? null
                    : () => _showCountryPicker(context),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          _card([
            SwitchListTile(
              title: const Text('По домену',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
              subtitle: const Text('Маршрутизация по доменным зонам (.ru, .cn…)',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              value: routing.domainEnabled,
              onChanged: isConnected
                  ? null
                  : (v) => onUpdate(routing.copyWith(domainEnabled: v)),
            ),
            if (routing.domainEnabled) ...[
              _divider(),
              _chipSection(
                context,
                chips: routing.domainZones
                    .map((zone) => _Chip(
                          label: '.${zone == 'xn--p1ai' ? 'рф' : zone}',
                          onDelete: isConnected
                              ? null
                              : () => onUpdate(routing.copyWith(
                                    domainZones: routing.domainZones
                                        .where((z) => z != zone)
                                        .toList(),
                                  )),
                        ))
                    .toList(),
                onAdd: isConnected
                    ? null
                    : () => _showDomainPicker(context),
              ),
            ],
          ]),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _connectedBanner() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.connecting.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.connecting, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Настройки нельзя изменить во время подключения',
                style: TextStyle(color: AppColors.connecting, fontSize: 13),
              ),
            ),
          ],
        ),
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: children),
      );

  Widget _divider() => const Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: AppColors.border,
      );

  Widget _radioTile(RoutingDirection value, String title, String subtitle) =>
      RadioListTile<RoutingDirection>(
        value: value,
        groupValue: routing.direction,
        title: Text(
          title,
          style: TextStyle(
            color: isConnected ? AppColors.textDisabled : AppColors.textPrimary,
            fontSize: 15,
          ),
        ),
        subtitle: Text(subtitle,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        onChanged: isConnected
            ? null
            : (v) => v != null ? onUpdate(routing.copyWith(direction: v)) : null,
      );

  Widget _chipSection(
    BuildContext context, {
    required List<_Chip> chips,
    required VoidCallback? onAdd,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...chips.map((c) => _buildChip(c)),
            if (onAdd != null)
              ActionChip(
                label: const Text(
                  '+ Добавить',
                  style: TextStyle(color: AppColors.primary, fontSize: 13),
                ),
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: AppColors.primary),
                onPressed: onAdd,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
          ],
        ),
      );

  Widget _buildChip(_Chip chip) => Chip(
        label: Text(chip.label,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 13)),
        backgroundColor: AppColors.surfaceElevated,
        side: const BorderSide(color: AppColors.border),
        deleteIcon: chip.onDelete != null
            ? const Icon(Icons.close, size: 14, color: AppColors.textSecondary)
            : null,
        onDeleted: chip.onDelete,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      );

  // ─── Country picker ───────────────────────────────────────────────────────

  static const _popularCountries = [
    ('RU', 'Россия'),
    ('BY', 'Беларусь'),
    ('KZ', 'Казахстан'),
    ('UA', 'Украина'),
    ('CN', 'Китай'),
    ('US', 'США'),
    ('DE', 'Германия'),
    ('GB', 'Великобритания'),
    ('FR', 'Франция'),
    ('NL', 'Нидерланды'),
    ('TR', 'Турция'),
    ('JP', 'Япония'),
    ('SE', 'Швеция'),
    ('FI', 'Финляндия'),
    ('PL', 'Польша'),
  ];

  Future<void> _showCountryPicker(BuildContext context) async {
    final selected = Set<String>.from(routing.geoCodes);
    final customCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              _sheetHandle(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Выберите страны',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  children: [
                    for (final (code, name) in _popularCountries)
                      CheckboxListTile(
                        title: Text(
                          '$name  ($code)',
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 14),
                        ),
                        value: selected.contains(code),
                        onChanged: (v) => setState(() {
                          if (v == true) selected.add(code);
                          else selected.remove(code);
                        }),
                        checkColor: AppColors.surface,
                        activeColor: AppColors.primary,
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: customCtrl,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Другая страна (код ISO, напр. IT)',
                          labelStyle: const TextStyle(
                              color: AppColors.textSecondary),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.add,
                                color: AppColors.primary),
                            onPressed: () {
                              final code =
                                  customCtrl.text.toUpperCase().trim();
                              if (code.isNotEmpty) {
                                setState(() => selected.add(code));
                                customCtrl.clear();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _doneButton(ctx, () {
                onUpdate(routing.copyWith(geoCodes: selected.toList()));
              }),
            ],
          ),
        ),
      ),
    );
    customCtrl.dispose();
  }

  // ─── Domain picker ────────────────────────────────────────────────────────

  static const _popularDomains = [
    ('ru', '.ru'),
    ('xn--p1ai', '.рф'),
    ('by', '.by'),
    ('kz', '.kz'),
    ('ua', '.ua'),
    ('cn', '.cn'),
    ('com.cn', '.com.cn'),
    ('de', '.de'),
    ('fr', '.fr'),
    ('uk', '.uk'),
    ('jp', '.jp'),
    ('nl', '.nl'),
    ('pl', '.pl'),
    ('fi', '.fi'),
  ];

  Future<void> _showDomainPicker(BuildContext context) async {
    final selected = Set<String>.from(routing.domainZones);
    final customCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              _sheetHandle(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Выберите домены',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  children: [
                    for (final (zone, label) in _popularDomains)
                      CheckboxListTile(
                        title: Text(
                          label,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 14),
                        ),
                        value: selected.contains(zone),
                        onChanged: (v) => setState(() {
                          if (v == true) selected.add(zone);
                          else selected.remove(zone);
                        }),
                        checkColor: AppColors.surface,
                        activeColor: AppColors.primary,
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: customCtrl,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Свой домен или зона (напр. example.com)',
                          labelStyle: const TextStyle(
                              color: AppColors.textSecondary),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.add,
                                color: AppColors.primary),
                            onPressed: () {
                              final zone = customCtrl.text
                                  .toLowerCase()
                                  .trim()
                                  .replaceAll(RegExp(r'^\.+'), '');
                              if (zone.isNotEmpty) {
                                setState(() => selected.add(zone));
                                customCtrl.clear();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _doneButton(ctx, () {
                onUpdate(routing.copyWith(domainZones: selected.toList()));
              }),
            ],
          ),
        ),
      ),
    );
    customCtrl.dispose();
  }

  // ─── Shared sheet widgets ─────────────────────────────────────────────────

  Widget _sheetHandle() => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _doneButton(BuildContext ctx, VoidCallback onDone) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              onDone();
              Navigator.pop(ctx);
            },
            child: const Text('Готово'),
          ),
        ),
      );
}

class _Chip {
  final String label;
  final VoidCallback? onDelete;
  const _Chip({required this.label, this.onDelete});
}
