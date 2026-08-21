import 'dart:convert';
import 'dart:io';

/// Display name on the Desktop and Start Menu. The exe itself is
/// `AllInOnePOS.exe` (no spaces — CMake/Flutter are happier that way);
/// Windows search and the shortcut use this string.
const kWindowsShortcutName = 'All In One POS';

/// Creates (or refreshes) Desktop + Start Menu shortcuts that point at this
/// install. Unzip-from-Downloads users otherwise only find the app via
/// search for the exe filename. No-op on non-Windows. Overwrites existing
/// `.lnk` files so moving the folder still lands a working icon after the
/// next launch from the new location.
Future<bool> ensureWindowsAppShortcuts({
  String? exePath,
  String? workingDirectory,
}) async {
  if (!Platform.isWindows) return false;
  final exe = exePath ?? Platform.resolvedExecutable;
  final dir = workingDirectory ?? File(exe).parent.path;
  final name = kWindowsShortcutName;
  final script =
      '''
\$ErrorActionPreference = 'Stop'
\$ws = New-Object -ComObject WScript.Shell
function Save-Shortcut([string]\$path) {
  \$s = \$ws.CreateShortcut(\$path)
  \$s.TargetPath = ${jsonEncode(exe)}
  \$s.WorkingDirectory = ${jsonEncode(dir)}
  \$s.IconLocation = ${jsonEncode('$exe,0')}
  \$s.Description = ${jsonEncode(name)}
  \$s.Save()
}
\$desktop = [Environment]::GetFolderPath('Desktop')
\$programs = Join-Path \$env:APPDATA 'Microsoft\\Windows\\Start Menu\\Programs'
if (-not (Test-Path \$programs)) { New-Item -ItemType Directory -Force -Path \$programs | Out-Null }
Save-Shortcut (Join-Path \$desktop '$name.lnk')
Save-Shortcut (Join-Path \$programs '$name.lnk')
''';
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    script,
  ]);
  return result.exitCode == 0;
}
