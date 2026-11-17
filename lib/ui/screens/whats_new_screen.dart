import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/update_service.dart' show releaseNotesLanguages;
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/hero_panel.dart';
import '../../l10n/l10n.dart';

/// Versions of a `changelog/<lang>.md` file in file order: `## X.Y.Z` and its `- ` bullets.
List<({String version, List<String> items})> parseChangelog(String markdown) {
  final versions = <({String version, List<String> items})>[];
  for (final raw in markdown.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.startsWith('## ')) {
      versions.add((version: line.substring(3).trim(), items: []));
    } else if (line.startsWith('- ') && versions.isNotEmpty) {
      versions.last.items.add(line.substring(2).trim());
    }
  }
  return versions;
}

/// The whole release history in the app's language (English when there is no file for it), from the bundled
/// `changelog/` — offline.
class WhatsNewScreen extends StatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  Future<String>? _text;
  String? _language;

  Future<String> _load(String language) {
    final code = releaseNotesLanguages.containsKey(language) ? language : 'en';
    return rootBundle.loadString('changelog/$code.md');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = Localizations.localeOf(context).languageCode;
    if (language != _language) {
      _language = language;
      _text = _load(language);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TeapodTokens>()!;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            BreadcrumbBar(t: t, parent: 'settings', current: 'changelog'),
            HeroPanel(t: t, tagline: context.l10n.whatsNewTagline, title: context.l10n.whatsNewTitle),
            Expanded(
              child: FutureBuilder<String>(
                future: _text,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return Center(child: CircularProgressIndicator(color: t.accent, strokeWidth: 1.5));
                  }
                  final versions = parseChangelog(snap.data!);
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    itemCount: versions.length,
                    itemBuilder: (context, i) => _Version(t: t, version: versions[i].version, items: versions[i].items),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Version extends StatelessWidget {
  final TeapodTokens t;
  final String version;
  final List<String> items;
  const _Version({required this.t, required this.version, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('v$version', style: AppTheme.mono(size: 12, color: t.accent, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('·  ', style: AppTheme.mono(size: 12, color: t.textMuted, height: 1.4)),
                  Expanded(
                    child: Text(item, style: AppTheme.sans(size: 13, color: t.text, height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
