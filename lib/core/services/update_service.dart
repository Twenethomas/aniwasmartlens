import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:app_installer/app_installer.dart'; // Changed import
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import 'package:logger/logger.dart';

class UpdateService {
  final Logger _logger = Logger();

  // Update this with your actual repository details
  static const String GITHUB_API =
      "https://api.github.com/repos/Twenethomas/aniwasmartlens/releases/latest";
  Future<void> checkAndInstallUpdate() async {
    try {
      // Get current version
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;

      _logger.i("Checking for updates. Current version: $currentVersion");

      // Check latest release with minimal headers
      final response = await http.get(
        Uri.parse(GITHUB_API),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'AssistLens-App'
        },
      );

      if (response.statusCode == 404) {
        _logger.e(
          "Repository or release not found. Please check the GitHub URL.",
        );
        throw Exception('Repository or release not found');
      }

      if (response.statusCode != 200) {
        _logger.e("Failed to check updates: ${response.statusCode}");
        throw Exception('Failed to check updates: ${response.statusCode}');
      }

      final releaseData = jsonDecode(response.body);
      String latestVersion = releaseData['tag_name'].replaceAll('v', '');

      _logger.i("Latest version available: $latestVersion");

      if (isNewerVersion(currentVersion, latestVersion)) {
        _logger.i("Update available. Downloading new version...");
        String apkUrl = releaseData['assets'][0]['browser_download_url'];
        await downloadAndInstallUpdate(apkUrl);
      } else {
        _logger.i("App is up to date");
      }
    } catch (e) {
      _logger.e("Update check failed: $e");
      rethrow;
    }
  }

  bool isNewerVersion(String current, String latest) {
    List<int> currentParts = current.split('.').map(int.parse).toList();
    List<int> latestParts = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < currentParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  Future<void> downloadAndInstallUpdate(String apkUrl) async {
    try {
      final apkData = await http.get(Uri.parse(apkUrl));
      final dir = await getExternalStorageDirectory();
      if (dir == null) throw Exception('Failed to get storage directory');

      File apkFile = File('${dir.path}/update.apk');
      await apkFile.writeAsBytes(apkData.bodyBytes);

      _logger.i("APK downloaded. Installing...");
      // Changed to use AppInstaller
      await AppInstaller.installApk(apkFile.path);
    } catch (e) {
      _logger.e("Failed to download/install update: $e");
      rethrow;
    }
  }
}
