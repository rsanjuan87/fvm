import 'dart:io';

import 'package:fvm/exceptions.dart';
import 'package:io/io.dart';
import 'package:path/path.dart';

import '../models/cache_version_model.dart';
import '../models/valid_version_model.dart';
import '../utils/helpers.dart';
import 'context.dart';
import 'git_tools.dart';

enum CacheIntegrity {
  valid,
  invalid,
  versionMismatch,
}

/// Service to interact with FVM Cache
class CacheService {
  CacheService._();

  /// Directory where local versions are cached

  /// Returns a [CacheVersion] from a [versionName]
  static Future<CacheVersion?> getByVersionName(String versionName) async {
    final versionDir = versionCacheDir(versionName);
    // Return null if version does not exist
    if (!await versionDir.exists()) return null;

    return CacheVersion(versionName);
  }

  /// Lists Installed Flutter SDK Version
  static Future<List<CacheVersion>> getAllVersions() async {
    // Returns empty array if directory does not exist
    if (!await ctx.fvmVersionsDir.exists()) return [];

    final versions = await ctx.fvmVersionsDir.list().toList();

    final cacheVersions = <CacheVersion>[];

    for (var version in versions) {
      if (isDirectory(version.path)) {
        final name = basename(version.path);
        final cacheVersion = await getByVersionName(name);

        if (cacheVersion != null) {
          cacheVersions.add(cacheVersion);
        }
      }
    }

    cacheVersions.sort((a, b) => a.compareTo(b));

    return cacheVersions.reversed.toList();
  }

  /// Removes a Version of Flutter SDK
  static void remove(CacheVersion version) {
    if (version.dir.existsSync()) {
      version.dir.deleteSync(recursive: true);
    }
  }

  /// Verifies that cache is correct
  /// returns 'true' if cache is correct 'false' if its not
  static Future<bool> _verifyIsExecutable(CacheVersion version) async {
    final binExists = File(version.flutterExec).existsSync();

    return binExists && await isExecutable(version.flutterExec);
  }

  // Verifies that the cache version name matches the flutter version
  static Future<bool> _verifyVersionMatch(CacheVersion version) async {
    // If its a channel return true
    if (version.isChannel) return true;
    // If sdkVersion is not available return true
    if (version.sdkVersion == null) return true;
    return version.sdkVersion == version.name;
  }

  /// Caches version a [validVersion] and returns [CacheVersion]
  static Future<void> cacheVersion(ValidVersion validVersion) async {
    await GitTools.cloneVersion(validVersion);
  }

  /// Checks if a [validVersion] is cached correctly, and cleans up if its not
  /// Returns the cache version if its valid
  static Future<CacheVersion?> getVersionCache(
    ValidVersion validVersion,
  ) async {
    return CacheService.getByVersionName(
      validVersion.name,
    );
  }

  /// Sets a [CacheVersion] as global
  static void setGlobal(CacheVersion version) {
    final versionDir = versionCacheDir(version.name);

    createLink(ctx.globalCacheLink, versionDir);
  }

  // Verifies that cache can be executed and matches version
  static Future<CacheIntegrity> verifyCacheIntegrity(
      CacheVersion version) async {
    final isExecutable = await _verifyIsExecutable(version);
    final versionsMatch = await _verifyVersionMatch(version);

    if (!isExecutable) return CacheIntegrity.invalid;
    if (!versionsMatch) return CacheIntegrity.versionMismatch;

    return CacheIntegrity.valid;
  }

  /// Moves a [CacheVersion] to the cache of [sdkVersion]
  static void moveToSdkVersionDiretory(CacheVersion version) {
    final sdkVersion = version.sdkVersion;
    if (sdkVersion == null) {
      throw FvmError(
        'Cannot move to SDK version directory without a valid version',
      );
    }
    final newDir = versionCacheDir(sdkVersion);
    print('Moving to $newDir');
    if (newDir.existsSync()) {
      newDir.deleteSync(recursive: true);
    }

    version.dir.renameSync(newDir.path);
  }

  /// Returns a global [CacheVersion] if exists
  static Future<CacheVersion?> getGlobal() async {
    if (await ctx.globalCacheLink.exists()) {
      // Get directory name
      final version = basename(await ctx.globalCacheLink.target());
      // Make sure its a valid version
      final validVersion = ValidVersion(version);
      // Verify version is cached
      return CacheService.getVersionCache(validVersion);
    } else {
      return null;
    }
  }

  /// Checks if a cached [version] is configured as global
  static Future<bool> isGlobal(CacheVersion version) async {
    if (await ctx.globalCacheLink.exists()) {
      return await ctx.globalCacheLink.target() == version.dir.path;
    } else {
      return false;
    }
  }

  /// Returns a global version name if exists
  static String? getGlobalVersionSync() {
    if (ctx.globalCacheLink.existsSync()) {
      // Get directory name
      return basename(ctx.globalCacheLink.targetSync());
    } else {
      return null;
    }
  }
}
