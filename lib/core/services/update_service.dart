import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:app_installer/app_installer.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:logger/logger.dart';
import '../../main.dart';

class UpdateService {
  final Logger _logger = logger;
  static const String owner = 'Twenethomas';
  static const String repo = 'aniwasmartlens';
  static const String apiUrl = 'https://api.github.com/repos/$owner/$repo/releases/latest';

  Future<bool> checkAndInstallUpdate() async {
    try {
      _logger.i('Starting update check...');
      
      // Get current app version
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      _logger.i('Current app version: $currentVersion');

      // Fetch latest release from GitHub
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode != 200) {
        _logger.e('GitHub API response: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to fetch release info: ${response.statusCode}');
      }

      final releaseData = json.decode(response.body);
      final latestVersion = releaseData['tag_name'].toString().replaceAll('v', '');
      _logger.i('Latest version available: $latestVersion');

      // Compare versions
      if (!_isNewerVersion(currentVersion, latestVersion)) {
        _logger.i('App is up to date');
        return false;
      }

      _logger.i('New version found. Current: $currentVersion, Latest: $latestVersion');

      // Get APK download URL from assets
      final assets = releaseData['assets'] as List;
      final apkAsset = assets.firstWhere(
        (asset) => asset['name'].toString().endsWith('.apk'),
        orElse: () => null,
      );

      if (apkAsset == null) {
        throw Exception('No APK found in release assets');
      }

      final downloadUrl = apkAsset['browser_download_url'];
      _logger.i('APK download URL: $downloadUrl');

      // Download and install update
      await _downloadAndInstallUpdate(downloadUrl);
      return true;

    } catch (e, stack) {
      _logger.e('Update check failed', error: e, stackTrace: stack);
      throw Exception('Failed to check for updates: $e');
    }
  }

  bool _isNewerVersion(String currentVersion, String latestVersion) {
    final current = currentVersion.split('.').map(int.parse).toList();
    final latest = latestVersion.split('.').map(int.parse).toList();

    // Ensure both lists have length 3
    while (current.length < 3) {
      current.add(0);
    }
    while (latest.length < 3) {
      latest.add(0);
    }

    for (var i = 0; i < 3; i++) {
      if (latest[i] > current[i]) return true;
      if (latest[i] < current[i]) return false;
    }
    return false;
  }

  Future<void> _downloadAndInstallUpdate(String downloadUrl) async {
    try {
      _logger.i('Downloading update from: $downloadUrl');
      
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download update: ${response.statusCode}');
      }

      // Save the APK file
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/update.apk';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      
      _logger.i('Update downloaded to: $filePath');

      // Install the APK using app_installer
      // Use the static method directly
      _logger.i('Installing APK...');
      await AppInstaller.installApk(filePath);
      
      _logger.i('Update installation initiated successfully');
    } catch (e, stack) {
      _logger.e('Update installation failed', error: e, stackTrace: stack);
      throw Exception('Failed to install update: $e');
    }
  }
}
