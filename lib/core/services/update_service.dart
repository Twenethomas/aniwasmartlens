import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:app_installer/app_installer.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import 'package:logging/logging.dart';

class UpdateService {
  final _logger = Logger('UpdateService');
  static const String GITHUB_API =
      "https://api.github.com/repos/Twenethomas/aniwasmartlens/releases/latest";

  bool isNewerVersion(String current, String latest) {
    List<int> currentParts = current.split('.').map(int.parse).toList();
    List<int> latestParts = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < currentParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  Future<void> checkAndInstallUpdate() async {
    try {
      // Get current version
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;

      // Check latest release
      final response = await http.get(
        Uri.parse(GITHUB_API),
        headers: {
          'Authorization': 'token ',
          'Accept': 'application/vnd.github.v3+json',
        },
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to check updates: ${response.statusCode}');
      }

      final releaseData = jsonDecode(response.body);
      String latestVersion = releaseData['tag_name'].replaceAll('v', '');

      if (isNewerVersion(currentVersion, latestVersion)) {
        _logger.info('New version available: $latestVersion');

        // Get APK download URL
        String apkUrl = releaseData['assets'][0]['browser_download_url'];

        // Download APK
        final apkData = await http.get(Uri.parse(apkUrl));
        final dir = await getExternalStorageDirectory();
        if (dir == null) throw Exception('Failed to get storage directory');

        File apkFile = File('${dir.path}/update.apk');
        await apkFile.writeAsBytes(apkData.bodyBytes);

        // Install APK using app_installer
        await AppInstaller.installApk(apkFile.path);
      } else {
        _logger.info('App is up to date');
      }
    } catch (e) {
      _logger.severe('Update failed: $e');
      rethrow;
    }
  }
}
