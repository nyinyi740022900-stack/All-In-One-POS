import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';

/// Public website — the one link every build (store or direct-install) can
/// safely show; it carries no commerce content itself.
const String _kWebsiteUrl = 'https://allinonepos.app';

/// Owner-facing community channel (Facebook page/group, Telegram, etc.).
/// Left blank on purpose: fabricating one would ship a broken/wrong link.
/// The row below only renders once this is filled in.
const String _kCommunityUrl = '';

/// Android can deep-link straight to this app's Play Store listing by
/// package id alone. iOS' `apps.apple.com` only resolves by *numeric* app
/// id, which isn't known yet — this falls back to a store search for the
/// app's name until that id is filled in below.
const String _kAndroidPackageId = 'com.allinonepos.app';
const String _kIosAppStoreId = ''; // e.g. '1234567890', once published.

/// App version, links, and a "check for updates" action — the basic legal/
/// support surface a store submission expects (alongside App Guide and
/// Support, already in the Help section) and this app didn't have yet.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  Future<void> _open(Uri uri) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text(l.aboutOpenFailed)));
    }
  }

  Future<void> _checkForUpdates() async {
    if (Platform.isIOS) {
      await _open(
        _kIosAppStoreId.isNotEmpty
            ? Uri.parse('https://apps.apple.com/app/id$_kIosAppStoreId')
            : Uri.https('apps.apple.com', '/sg/search', {
                'term': 'All In One POS',
              }),
      );
    } else {
      await _open(
        Uri.https('play.google.com', '/store/apps/details', {
          'id': _kAndroidPackageId,
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: Text(l.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppTheme.space5),
        children: [
          SettingsGroup(
            children: [
              ListTile(
                leading: const IconAvatar(icon: Icons.info_outline),
                title: Text(l.aboutVersion),
                subtitle: info == null
                    ? null
                    : Text('${info.version} (${info.buildNumber})'),
              ),
              ListTile(
                leading: const IconAvatar(icon: Icons.language),
                title: Text(l.aboutWebsite),
                subtitle: const Text(_kWebsiteUrl),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _open(Uri.parse(_kWebsiteUrl)),
              ),
              if (_kCommunityUrl.isNotEmpty)
                ListTile(
                  leading: const IconAvatar(icon: Icons.groups_outlined),
                  title: Text(l.aboutCommunity),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _open(Uri.parse(_kCommunityUrl)),
                ),
              ListTile(
                leading: const IconAvatar(icon: Icons.system_update_outlined),
                title: Text(l.aboutCheckForUpdates),
                trailing: const Icon(Icons.chevron_right),
                onTap: _checkForUpdates,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
