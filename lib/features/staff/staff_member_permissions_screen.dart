import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import 'owner_permission.dart';
import 'staff_providers.dart';

/// Every [OwnerCapability] the owner can grant a named staff member from
/// this screen. `analytics` is included since the router redirect guard and
/// the bottom-nav destination list (`core/router.dart`) are both
/// capability-aware via `hasResolvedOwnerCapabilityProvider`/
/// `hasOwnerCapabilityProvider` — granting it here now actually unlocks the
/// tab and the route, not a switch with no effect.
const _grantableCapabilities = <OwnerCapability>[
  OwnerCapability.analytics,
  OwnerCapability.inventoryEdit,
  OwnerCapability.staffAccounts,
  OwnerCapability.branches,
  OwnerCapability.storefront,
  OwnerCapability.license,
  OwnerCapability.settingsSensitive,
];

String _capabilityLabel(AppLocalizations l, OwnerCapability c) {
  return switch (c) {
    OwnerCapability.analytics => l.navAnalytics,
    OwnerCapability.branches => l.branchesTitle,
    OwnerCapability.staffAccounts => l.staffAccountsTitle,
    OwnerCapability.license => l.settingsLicense,
    OwnerCapability.storefront => l.storefrontTitle,
    OwnerCapability.inventoryEdit => l.staffCapabilityInventoryEdit,
    OwnerCapability.settingsSensitive => l.staffCapabilitySettingsSensitive,
  };
}

/// Owner-only screen (see the hard rule below) letting the owner grant or
/// revoke individual [OwnerCapability]s for one named staff member.
///
/// **Hard rule — do not relax this gate.** This screen's own access check
/// must stay a raw [isEffectiveOwnerProvider] read, never routed through
/// [hasOwnerCapabilityProvider]. Letting a granted staff member reach this
/// screen would let them grant themselves (or another staff member) further
/// capabilities — a privilege-escalation hole no single capability grant
/// should ever be able to open.
class StaffMemberPermissionsScreen extends ConsumerWidget {
  const StaffMemberPermissionsScreen({super.key, required this.member});

  final StaffMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // Deliberately a raw owner check, not `hasOwnerCapabilityProvider` — see
    // the hard rule in this class's doc comment.
    if (!ref.watch(isEffectiveOwnerProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.staffPermissionsTooltip)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.space5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 56,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                const SizedBox(height: AppTheme.space3),
                Text(
                  l.staffOwnerOnly,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppTheme.space1),
                Text(l.staffOwnerOnlyDesc, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }
    final granted =
        ref.watch(staffGrantedCapabilitiesProvider(member.id)).valueOrNull ??
        const <OwnerCapability>{};

    return Scaffold(
      appBar: AppBar(title: Text(l.staffPermissionsTitle(member.name))),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space4,
              AppTheme.space3,
              AppTheme.space4,
              AppTheme.space2,
            ),
            child: Text(
              l.staffPermissionsIntro(member.name),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          for (final capability in _grantableCapabilities)
            SwitchListTile(
              title: Text(_capabilityLabel(l, capability)),
              value: granted.contains(capability),
              onChanged: (value) => ref
                  .read(staffRepositoryProvider)
                  .setCapabilityGranted(member.id, capability, value),
            ),
        ],
      ),
    );
  }
}
