part of 'admin_dashboard_screen.dart';

/// Owner decision (2026-10-17): lapsed shops' cloud data is kept, and the
/// question is reopened once the database passes this size. The page flags
/// it so nobody has to remember to look.
const int _kRetentionReviewBytes = 300 * 1024 * 1024;

/// Cloud cost per shop, and the photos the nightly clean-up would delete.
/// Fetches its own data on open (and on the app bar's Reload) instead of in
/// the dashboard's `_reload`, so the rest of the console doesn't wait on it.
class _StoragePage extends StatefulWidget {
  const _StoragePage({
    required this.api,
    required this.shops,
    required this.reloadToken,
  });

  final AdminApi api;
  final List<Map<String, dynamic>> shops;
  final int reloadToken;

  @override
  State<_StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<_StoragePage> {
  late Future<(StorageReport, OrphanPhotos)> _data = _fetch();

  Future<(StorageReport, OrphanPhotos)> _fetch() async {
    final r = await Future.wait<Object>([
      widget.api.storageReport(),
      widget.api.photoOrphans(),
    ]);
    return (r[0] as StorageReport, r[1] as OrphanPhotos);
  }

  void _refetch() {
    // Block body: an arrow would hand setState the Future, which it rejects.
    setState(() {
      _data = _fetch();
    });
  }

  @override
  void didUpdateWidget(_StoragePage old) {
    super.didUpdateWidget(old);
    // A rebuild follows didUpdateWidget anyway, so no setState here.
    if (old.reloadToken != widget.reloadToken) _data = _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(StorageReport, OrphanPhotos)>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorRetryView(
            message: _adminErrorMessage(snap.error!),
            onRetry: _refetch,
          );
        }
        if (!snap.hasData) return const AppLoadingView();
        final (report, orphans) = snap.data!;
        return _StorageBody(
          report: report,
          orphans: orphans,
          integrity: _IntegrityCard(
            api: widget.api,
            reloadToken: widget.reloadToken,
          ),
          names: {
            for (final s in widget.shops)
              '${s['shop_id']}': '${s['shop_name'] ?? s['shop_id']}',
          },
        );
      },
    );
  }
}

class _StorageBody extends StatelessWidget {
  const _StorageBody({
    required this.report,
    required this.orphans,
    required this.names,
    this.integrity,
  });

  final Widget? integrity;
  final StorageReport report;
  final OrphanPhotos orphans;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final width = MediaQuery.sizeOf(context).width;
    final review = report.databaseBytes >= _kRetentionReviewBytes;
    return ListView(
      padding: const EdgeInsets.all(AppTheme.space4),
      children: [
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: width >= 1100 ? 3 : 2,
            mainAxisSpacing: AppTheme.space3,
            crossAxisSpacing: AppTheme.space3,
            mainAxisExtent: StatCard.gridExtent(context),
          ),
          children: [
            StatCard(
              label: 'Database',
              value: formatBytes(report.databaseBytes),
              icon: Icons.storage_outlined,
              tone: review ? StatusTone.attention : null,
            ),
            StatCard(
              label: 'Product photos',
              value: '${report.photos} · ${formatBytes(report.photoBytes)}',
              icon: Icons.photo_library_outlined,
            ),
            StatCard(
              label: 'Unused photos',
              value: '${orphans.files} · ${formatBytes(orphans.bytes)}',
              icon: Icons.delete_sweep_outlined,
            ),
          ],
        ),
        const SizedBox(height: AppTheme.space2),
        Text(
          review
              ? 'The database has passed 300 MB — time to decide what happens '
                    "to lapsed shops' cloud data. It is all kept today."
              : "Lapsed shops' cloud data is kept. Revisit that once the "
                    'database passes 300 MB.',
          style: muted,
        ),
        const SizedBox(height: AppTheme.space4),
        Card(
          // Flush with the stat tiles above (Card's default margin is 4).
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'By shop'),
                Text(
                  'Row data excludes indexes, so it reads low against disk '
                  'use — use it to compare shops.',
                  style: muted,
                ),
                const SizedBox(height: AppTheme.space2),
                if (report.shops.isEmpty)
                  const Text('No shop data in the cloud yet.')
                else
                  for (final s in report.shops)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      // Some rows carry an empty shop_id (written before a
                      // shop existed); a blank title read as a broken row.
                      title: Text(
                        s.shopId.isEmpty
                            ? 'Not tied to a shop'
                            : names[s.shopId] ?? s.shopId,
                      ),
                      subtitle: Text(
                        '${s.rows} rows · ${formatBytes(s.bytes)} data · '
                        '${s.photos} photos · ${formatBytes(s.photoBytes)}',
                      ),
                      trailing: Text(
                        formatBytes(s.totalBytes),
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                if (report.unfolderedPhotos > 0)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Older uploads (no shop folder)'),
                    subtitle: Text(
                      '${report.unfolderedPhotos} photos · uploaded before '
                      'photos were filed per shop',
                    ),
                    trailing: Text(formatBytes(report.unfolderedPhotoBytes)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTheme.space3),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Unused photos'),
                Text(
                  'Replaced product photos and the like, 30+ days old, in a '
                  'shop folder, that no product or storefront uses. The '
                  'nightly clean-up deletes exactly this list. Receipt logos '
                  'and older uploads with no shop folder are never on it.',
                  style: muted,
                ),
                const SizedBox(height: AppTheme.space2),
                if (orphans.names.isEmpty)
                  const Text('Nothing to clean up.')
                else
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text(
                      '${orphans.files} file${orphans.files == 1 ? '' : 's'}'
                      ' · ${formatBytes(orphans.bytes)}',
                    ),
                    children: [
                      for (final n in orphans.names.take(200))
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(n, style: muted),
                        ),
                      if (orphans.names.length > 200)
                        Text(
                          '…and ${orphans.names.length - 200} more',
                          style: muted,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (integrity != null) ...[
          const SizedBox(height: AppTheme.space3),
          integrity!,
        ],
      ],
    );
  }
}

/// Play Integrity verdicts, last 7 days — what decides whether
/// `integrity.android_mode` (Config) can move from monitor to enforce.
/// Fetches on its own so a slow or failing read never holds up the storage
/// figures above it.
class _IntegrityCard extends StatefulWidget {
  const _IntegrityCard({required this.api, required this.reloadToken});

  final AdminApi api;
  final int reloadToken;

  @override
  State<_IntegrityCard> createState() => _IntegrityCardState();
}

class _IntegrityCardState extends State<_IntegrityCard> {
  late Future<IntegritySummary> _data = widget.api.integritySummary();

  @override
  void didUpdateWidget(_IntegrityCard old) {
    super.didUpdateWidget(old);
    if (old.reloadToken != widget.reloadToken) {
      _data = widget.api.integritySummary();
    }
  }

  static const _labels = {
    'pass': 'From Play',
    'pass_sideload': 'Our APK, not from Play',
    'fail': 'Failed',
    'unavailable': 'No Play services / no token',
    'missing': 'Sent nothing',
    'not_configured': 'Server not set up',
    'error': 'Google check errored',
    'not_android': 'iPhone / web / desktop',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: FutureBuilder<IntegritySummary>(
          future: _data,
          builder: (context, snap) {
            final s = snap.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'App integrity (last 7 days)'),
                if (snap.hasError)
                  Text('Could not load: ${_adminErrorMessage(snap.error!)}')
                else if (s == null)
                  const LinearProgressIndicator()
                else ...[
                  Text(
                    s.mode == 'enforce'
                        ? 'Enforcing: Android trials and Premium receipts are '
                              'refused to copies that fail Play Integrity.'
                        : 'Monitoring only: every verdict is recorded, nothing '
                              'is blocked. Switch integrity.android_mode to '
                              'enforce in Config once real shops pass.',
                    style: muted,
                  ),
                  const SizedBox(height: AppTheme.space2),
                  if (s.total == 0)
                    const Text('No checks recorded yet.')
                  else
                    for (final e in s.counts.entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(_labels[e.key] ?? e.key),
                        trailing: Text(
                          '${e.value}',
                          style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  if (s.recentFailures.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text(
                        'Latest failures (${s.recentFailures.length})',
                      ),
                      children: [
                        for (final f in s.recentFailures)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                              '${f['created_at']} · ${f['action']} · '
                              '${f['reason'] ?? f['app_verdict'] ?? ''} · '
                              'shop ${f['shop_id']} · build ${f['app_build']}',
                              style: muted,
                            ),
                          ),
                      ],
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
