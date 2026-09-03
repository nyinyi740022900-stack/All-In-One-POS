import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import 'owner_permission.dart';
import 'staff_members_screen.dart';
import 'staff_providers.dart';

export 'owner_permission.dart';

String staffRoleLabel(AppLocalizations l, String role) {
  return role == 'owner' ? l.staffRoleOwner : l.staffRoleStaff;
}

/// Wraps owner-only content. In staff mode it shows a lock placeholder
/// instead of [child].
class OwnerOnlyGate extends ConsumerWidget {
  const OwnerOnlyGate({
    super.key,
    required this.child,
    this.capability = OwnerCapability.branches,
  });
  final Widget child;
  final OwnerCapability capability;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(hasOwnerCapabilityProvider(capability));
    if (allowed) return child;
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space6),
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
            const SizedBox(height: AppTheme.space2),
            Text(l.staffOwnerOnlyDesc, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// A small pill for app bars showing that the device is in staff mode.
class StaffBadge extends ConsumerWidget {
  const StaffBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isEffectiveOwnerProvider)) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final name = ref.watch(activeStaffNameProvider);
    // Neutral/informational, not a status signal — this badge says who's
    // signed in, it isn't reporting that anything is good, bad, or
    // attention-worthy, so it takes the same muted tone the app already
    // reserves for "just informational" states rather than a raw Material
    // scheme colour with no meaning in this app's own palette.
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(right: AppTheme.space3),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space2,
        vertical: AppTheme.space1,
      ),
      decoration: BoxDecoration(
        color: colors.neutralSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.badge_outlined, size: 14, color: colors.muted),
          const SizedBox(width: AppTheme.space1),
          Text(
            name ?? l.staffBadge,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Prompts for a numeric PIN. Returns the entered value or null if cancelled.
Future<String?> promptPin(BuildContext context, String title) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        decoration: InputDecoration(
          hintText: AppLocalizations.of(ctx).staffPinHint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(AppLocalizations.of(ctx).commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
        ),
      ],
    ),
  );
}

/// Extra confirmation for owner-sensitive actions (branch/account/tier
/// changes). If [capability] does not require PIN re-auth, or no owner PIN is
/// set, this returns true immediately.
Future<bool> requireOwnerPinReauth(
  BuildContext context,
  WidgetRef ref, {
  required OwnerCapability capability,
}) async {
  if (!ref.read(hasOwnerCapabilityProvider(capability))) return false;
  if (!ownerPermissionPolicy.requiresPinReauth(capability)) return true;
  // A granted staff member (not the owner) has no owner PIN to re-enter —
  // they already authenticated with their own member PIN when switching
  // into Staff-as-<name> mode, so the re-auth prompt below is only for the
  // actual owner.
  if (!ref.read(isEffectiveOwnerProvider)) return true;

  final l = AppLocalizations.of(context);
  final ctrl = ref.read(staffControllerProvider);
  if (!await ctrl.hasPin()) return true;
  if (!context.mounted) return false;
  final pin = await promptPin(context, l.staffEnterPin);
  if (pin == null || pin.isEmpty || !context.mounted) return false;
  final ok = await ctrl.verifyOwnerPin(pin);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.staffWrongPin)));
  }
  return ok;
}

/// Sentinel returned by [pickStaffMemberId] for "no name — just Staff mode".
const kSkipNamedStaffId = '__skip__';

/// Lets the owner pick which roster member is about to use the device, or
/// fall back to plain (unnamed) Staff mode. Returns the member id, the
/// [kSkipNamedStaffId] sentinel, or null if dismissed without a choice.
/// Shared by [StaffModeCard] and the daily gate's local identity step.
Future<String?> pickStaffMemberId(
  BuildContext context,
  List<StaffMember> members,
) {
  final l = AppLocalizations.of(context);
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l.staffWhoAreYou,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          for (final m in members)
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(m.name),
              onTap: () => Navigator.of(ctx).pop(m.id),
            ),
          ListTile(
            leading: const Icon(Icons.person_off_outlined),
            title: Text(l.staffNoNamedStaff),
            onTap: () => Navigator.of(ctx).pop(kSkipNamedStaffId),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Collects the owner PIN for a switch / daily-gate confirm. If this phone
/// has no owner PIN yet, creates one (enter + confirm) so a shared-phone
/// staff member cannot later open as Owner with an empty PIN.
Future<String?> promptOwnerPinForSwitch(
  BuildContext context,
  WidgetRef ref,
) async {
  final l = AppLocalizations.of(context);
  final ctrl = ref.read(staffControllerProvider);
  final pinSet = await ctrl.hasPin();
  if (!context.mounted) return null;
  if (!pinSet) {
    final role = ref.read(effectiveRoleProvider);
    if (role == 'staff') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.staffOwnerPinRequired)),
      );
      return null;
    }
  }
  if (pinSet) {
    final pin = await promptPin(context, l.staffEnterPin);
    if (pin == null || pin.isEmpty) return null;
    return pin;
  }

  final pin = await promptPin(context, l.staffSetPin);
  if (!context.mounted || pin == null || pin.isEmpty) return null;
  if (!ctrl.isValidOwnerPin(pin)) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.staffPinHint)));
    return null;
  }
  final confirm = await promptPin(context, l.staffConfirmPin);
  if (!context.mounted || confirm == null) return null;
  if (confirm != pin) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.staffPinMismatch)));
    return null;
  }
  try {
    await ctrl.setPin(pin);
    ref.invalidate(ownerPinIsSetProvider);
  } on ArgumentError {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.staffPinHint)));
    }
    return null;
  }
  return pin;
}

/// Switches the device to [target] ('owner' or 'staff'), prompting for
/// whichever PIN is needed along the way (owner PIN, or a named staff
/// member's own PIN if a roster is configured). Returns true on a
/// confirmed switch, false on cancel/wrong PIN/cooldown. Entirely local —
/// no network required — so it doubles as an offline identity-confirm step
/// (used by both [StaffModeCard] and the universal daily gate).
Future<bool> switchStaffRole(
  BuildContext context,
  WidgetRef ref,
  String target,
) async {
  final l = AppLocalizations.of(context);
  final ctrl = ref.read(staffControllerProvider);
  if (target == 'owner') {
    final cooldown = ctrl.ownerPinCooldownRemainingSeconds();
    if (cooldown > 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.staffPinTryAgainIn(cooldown))));
      return false;
    }
  }

  // Switching to Staff with a named roster set up: ask who's using the
  // device (each name has its own PIN) instead of a single shared PIN.
  if (target == 'staff') {
    final members = ref.read(staffMembersProvider).valueOrNull ?? const [];
    if (members.isNotEmpty) {
      final pickedId = await pickStaffMemberId(context, members);
      if (pickedId == null || !context.mounted) return false; // cancelled
      if (pickedId == kSkipNamedStaffId) {
        final ok = await ctrl.switchRole('staff');
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.staffWrongPin)));
        }
        return ok;
      }
      final pin = await promptPin(context, l.staffEnterPin);
      if (pin == null || !context.mounted) return false;
      final ok = await ctrl.switchToStaffMember(pickedId, pin);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.staffWrongPin)));
      }
      return ok;
    }
  }

  String? pin;
  if (target == 'owner') {
    pin = await promptOwnerPinForSwitch(context, ref);
    if (pin == null) return false; // cancelled / invalid new PIN
  }
  if (!context.mounted) return false;
  final ok = await ctrl.switchRole(target, pin: pin);
  if (!ok && context.mounted) {
    final remaining = ctrl.ownerPinCooldownRemainingSeconds();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          remaining > 0 ? l.staffPinTryAgainIn(remaining) : l.staffWrongPin,
        ),
      ),
    );
  }
  return ok;
}

/// Settings section to switch between Owner and Staff mode, and manage the
/// owner PIN. Switching to Staff is free; switching to Owner prompts for the
/// PIN. Deliberately just two modes — a finer-grained role tier was tried and
/// folded back into this for simplicity.
class StaffModeCard extends ConsumerWidget {
  const StaffModeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final ctrl = ref.watch(staffControllerProvider);
    final ownerCooldown =
        ref.watch(ownerPinCooldownSecondsProvider).valueOrNull ??
        ctrl.ownerPinCooldownRemainingSeconds();
    final role = ref.watch(staffRoleProvider).valueOrNull ?? 'owner';
    final isLocalOwner = role == 'owner';
    final pinIsSet = ref.watch(ownerPinIsSetProvider).valueOrNull ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(
            isLocalOwner ? Icons.verified_user : Icons.badge_outlined,
          ),
          title: Text(l.staffMode),
          subtitle: Text(
            '${l.staffModeSubtitle}\n${l.staffCurrentRole(staffRoleLabel(l, role))}',
          ),
          isThreeLine: true,
        ),
        for (final target in staffRoles)
          if (target != role)
            ListTile(
              leading: Icon(
                target == 'owner'
                    ? Icons.lock_open_outlined
                    : Icons.badge_outlined,
              ),
              title: Text(l.staffSwitchTo(staffRoleLabel(l, target))),
              subtitle: target == 'owner' && ownerCooldown > 0
                  ? Text(l.staffPinTryAgainIn(ownerCooldown))
                  : null,
              enabled: !(target == 'owner' && ownerCooldown > 0),
              onTap: (target == 'owner' && ownerCooldown > 0)
                  ? null
                  : () => switchStaffRole(context, ref, target),
            ),
        if (isLocalOwner)
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: Text(pinIsSet ? l.staffChangePin : l.staffSetPin),
            onTap: () async {
              final pin = await promptPin(
                context,
                pinIsSet ? l.staffChangePin : l.staffSetPin,
              );
              if (pin == null || pin.isEmpty) return;
              try {
                await ref.read(staffControllerProvider).setPin(pin);
                ref.invalidate(ownerPinIsSetProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l.staffPinSaved)));
                }
              } on ArgumentError {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l.staffWrongPin)));
                }
              }
            },
          ),
        if (isLocalOwner)
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: Text(l.staffManageMembers),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StaffMembersScreen()),
            ),
          ),
      ],
    );
  }
}
