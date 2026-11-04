import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'github_release_update_service.dart';

class DesktopUpdateInstaller {
  String? get _target {
    final executable = Platform.resolvedExecutable;
    final directory = path.dirname(executable);
    if (Platform.isWindows &&
        Abi.current() == Abi.windowsX64 &&
        File(path.join(directory, 'unins000.exe')).existsSync()) {
      return directory;
    }
    if (Platform.isLinux &&
        Abi.current() == Abi.linuxX64 &&
        executable == '/usr/lib/nodeql/nodeql' &&
        File('/usr/bin/pkexec').existsSync() &&
        File('/usr/bin/dpkg').existsSync()) {
      return executable;
    }
    return null;
  }

  bool canInstall(AppUpdate update) {
    final suffix = switch (Abi.current()) {
      Abi.windowsX64 => '-setup.exe',
      Abi.linuxX64 => '_amd64.deb',
      _ => null,
    };
    return suffix != null &&
        update.assetName.endsWith(suffix) &&
        update.installDigest != null &&
        _target != null;
  }

  Future<void> install(AppUpdate update) async {
    final target = _target;
    if (target == null || !canInstall(update)) {
      throw StateError('This installation cannot be updated automatically');
    }
    final directory = await Directory.systemTemp.createTemp('nodeql-update-');
    final client = http.Client();
    var handedOff = false;
    try {
      final extension = path.extension(update.assetName);
      final installer = File(path.join(directory.path, 'update$extension'));
      final request = http.Request('GET', update.downloadUrl);
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('Update download failed: ${response.statusCode}');
      }
      await response.stream
          .timeout(const Duration(seconds: 30))
          .pipe(installer.openWrite());
      final digest = await sha256.bind(installer.openRead()).single;
      if ('sha256:$digest' != update.installDigest) {
        throw const FormatException('Update checksum mismatch');
      }

      final windows = Platform.isWindows;
      final helper = File(
        path.join(directory.path, windows ? 'install.ps1' : 'install.sh'),
      );
      await helper.writeAsString(windows ? _windowsHelper : _unixHelper);
      final arguments = [pid.toString(), target, installer.path];
      if (windows) {
        await File(
          path.join(directory.path, 'update.json'),
        ).writeAsString(jsonEncode(arguments));
        await Process.start(
          path.join(
            Platform.environment['SystemRoot'] ?? r'C:\Windows',
            r'System32\WindowsPowerShell\v1.0\powershell.exe',
          ),
          [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-WindowStyle',
            'Hidden',
            '-File',
            helper.path,
          ],
          mode: ProcessStartMode.detached,
        );
      } else {
        await Process.start('/bin/sh', [
          helper.path,
          ...arguments,
        ], mode: ProcessStartMode.detached);
      }
      handedOff = true;
      try {
        final response = await ServicesBinding.instance.exitApplication(
          AppExitType.cancelable,
        );
        if (response == AppExitResponse.cancel) {
          throw StateError('The application did not close');
        }
      } catch (_) {
        await File(path.join(directory.path, 'cancel')).create();
        rethrow;
      }
    } finally {
      client.close();
      if (!handedOff) {
        await directory.delete(recursive: true);
      }
    }
  }
}

const _windowsHelper = r'''
$ErrorActionPreference = 'Stop'
$parent, $target, $installer = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'update.json') | ConvertFrom-Json
try {
  $process = Get-Process -Id ([int]$parent) -ErrorAction SilentlyContinue
  $cancel = Join-Path $PSScriptRoot 'cancel'
  if ($process) {
    for ($attempt = 0; !$process.WaitForExit(1000); $attempt++) {
      if ($attempt -ge 59 -or (Test-Path -LiteralPath $cancel)) { return }
    }
  }
  if (Test-Path -LiteralPath $cancel) { return }
  try {
    $setup = Start-Process -FilePath $installer -Verb RunAs -PassThru -Wait -ArgumentList @(
      '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NORESTARTAPPLICATIONS',
      '/RESTARTEXITCODE=3010', ('/DIR="' + $target + '"')
    )
    if ($setup.ExitCode -ne 0) { throw "Installer exit code: $($setup.ExitCode)" }
  } catch {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'NodeQL update')
  }
  Start-Process -FilePath (Join-Path $target 'nodeql.exe') -WorkingDirectory $target
} finally {
  Remove-Item -LiteralPath $PSScriptRoot -Recurse -Force -ErrorAction SilentlyContinue
}
''';

const _unixHelper = r'''
parent=$1
target=$2
installer=$3
work=${installer%/*}
trap '/bin/rm -rf "$work"' EXIT

attempt=0
while kill -0 "$parent" 2>/dev/null; do
  [ "$attempt" -lt 60 ] && [ ! -e "$work/cancel" ] || exit 0
  attempt=$((attempt + 1))
  sleep 1
done
[ ! -e "$work/cancel" ] || exit 0

if ! /usr/bin/pkexec /usr/bin/dpkg --install "$installer"; then
  if command -v zenity >/dev/null; then
    zenity --error --title=NodeQL --text='The update could not be installed.'
  elif command -v kdialog >/dev/null; then
    kdialog --title NodeQL --error 'The update could not be installed.'
  fi
fi
"$target" </dev/null >/dev/null 2>&1 &
''';
