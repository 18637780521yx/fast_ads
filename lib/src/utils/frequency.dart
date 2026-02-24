import 'package:fast_ads/fast_ads.dart';
import 'package:fast_ads/src/utils/sp_utils.dart';

/// FastBaseAd 的频次控制扩展
///
/// 用于控制广告的显示频次，包括：
/// - 冷却时间：两次显示之间的最小时间间隔
/// - 每日上限：单个用户自然日内看到广告的最大次数
extension AdFrequency on FastBaseAd {
  /// 获取上次显示时间的存储键
  String _getLastShownTimeKey(String storagePrefix, String placementName) =>
      '${storagePrefix}_${placementName}_last_shown_time';

  /// 获取今日显示次数的存储键
  String _getTodayShowCountKey(String storagePrefix, String placementName) =>
      '${storagePrefix}_${placementName}_today_show_count';

  /// 获取今日显示日期（用于判断是否跨天）的存储键
  String _getTodayDateKey(String storagePrefix, String placementName) =>
      '${storagePrefix}_${placementName}_today_date';

  /// 检查是否满足显示条件（冷却时间和每日上限）
  ///
  /// [placement] 广告位配置（包含 cooldown 和 dailyCap 配置）
  /// [storagePrefix] 存储键前缀，用于区分不同类型的广告（如 'fast_app_open_ad', 'fast_interstitial_ad'）
  /// [checkMaxHighPriority] 是否检查最高优先级（如果为 false，则跳过所有限制）
  ///
  /// 返回 true 表示可以展示，false 表示被限制
  bool canShowFrequency(
    FastPlacement placement, {
    required String storagePrefix,
    bool checkMaxHighPriority = true,
  }) {
    // 如果不检查最高优先级，直接返回 true
    if (!checkMaxHighPriority) {
      FastAdsLogger.info(
        'Skipping frequency check (not max high priority) for $adUnitId (placement: ${placement.name})',
      );
      return true;
    }

    final cooldown = placement.effectiveCooldown;
    final dailyCap = placement.effectiveDailyCap;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final todayDateKey = _getTodayDateKey(storagePrefix, placement.name);
    final todayShowCountKey = _getTodayShowCountKey(storagePrefix, placement.name);
    final lastShownTimeKey = _getLastShownTimeKey(storagePrefix, placement.name);

    // 检查每日上限
    if (dailyCap > 0) {
      final lastDateStr = SpUtils.getString(todayDateKey);
      final todayStr = today.toIso8601String();
      int todayCount = SpUtils.getInt(todayShowCountKey);

      // 如果跨天了，重置计数
      if (lastDateStr != todayStr) {
        todayCount = 0;
        SpUtils.setString(todayDateKey, todayStr);
        SpUtils.setInt(todayShowCountKey, 0);
      }

      // 检查是否达到每日上限
      if (todayCount >= dailyCap) {
        FastAdsLogger.info(
          'Ad daily cap reached: $todayCount/$dailyCap for $adUnitId (placement: ${placement.name})',
        );
        return false;
      }
    }

    // 检查冷却时间
    if (cooldown > 0) {
      final lastShownTimeStr = SpUtils.getString(lastShownTimeKey);
      if (lastShownTimeStr.isNotEmpty) {
        final lastShownTime = DateTime.parse(lastShownTimeStr);
        final elapsedSeconds = now.difference(lastShownTime).inSeconds;

        if (elapsedSeconds < cooldown) {
          final remainingSeconds = cooldown - elapsedSeconds;
          FastAdsLogger.info(
            'Ad in cooldown: ${remainingSeconds}s remaining for $adUnitId (placement: ${placement.name})',
          );
          return false;
        }
      }
    }

    return true;
  }

  /// 记录广告显示
  ///
  /// [placement] 广告位配置
  /// [storagePrefix] 存储键前缀，用于区分不同类型的广告
  Future<void> recordShowFrequency(FastPlacement placement, {required String storagePrefix}) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayStr = today.toIso8601String();

      final todayDateKey = _getTodayDateKey(storagePrefix, placement.name);
      final todayShowCountKey = _getTodayShowCountKey(storagePrefix, placement.name);
      final lastShownTimeKey = _getLastShownTimeKey(storagePrefix, placement.name);

      // 记录显示时间
      await SpUtils.setString(lastShownTimeKey, now.toIso8601String());

      // 更新今日显示次数
      final lastDateStr = SpUtils.getString(todayDateKey);
      int todayCount = SpUtils.getInt(todayShowCountKey);

      // 如果跨天了，重置计数
      if (lastDateStr != todayStr) {
        todayCount = 0;
        await SpUtils.setString(todayDateKey, todayStr);
      }

      todayCount++;
      await SpUtils.setInt(todayShowCountKey, todayCount);

      FastAdsLogger.info(
        'Ad show recorded: count=$todayCount for $adUnitId (placement: ${placement.name})',
      );
    } catch (e) {
      FastAdsLogger.warning('Error recording ad show: $e');
    }
  }

  /// 获取今日已显示次数
  ///
  /// [placement] 广告位配置
  /// [storagePrefix] 存储键前缀
  int getTodayShowCount(FastPlacement placement, {required String storagePrefix}) {
    final todayDateKey = _getTodayDateKey(storagePrefix, placement.name);
    final todayShowCountKey = _getTodayShowCountKey(storagePrefix, placement.name);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayStr = today.toIso8601String();

    final lastDateStr = SpUtils.getString(todayDateKey);
    int todayCount = SpUtils.getInt(todayShowCountKey);

    // 如果跨天了，返回 0
    if (lastDateStr != todayStr) {
      return 0;
    }

    return todayCount;
  }

  /// 获取距离下次可显示还剩余的时间（秒）
  ///
  /// [placement] 广告位配置（包含 cooldown 配置）
  /// [storagePrefix] 存储键前缀
  /// 返回剩余秒数，如果不在冷却中则返回 0
  int getRemainingCooldownSeconds(FastPlacement placement, {required String storagePrefix}) {
    final cooldown = placement.effectiveCooldown;
    if (cooldown <= 0) {
      return 0;
    }

    final lastShownTimeKey = _getLastShownTimeKey(storagePrefix, placement.name);
    final lastShownTimeStr = SpUtils.getString(lastShownTimeKey);

    if (lastShownTimeStr.isEmpty) {
      return 0;
    }

    try {
      final lastShownTime = DateTime.parse(lastShownTimeStr);
      final now = DateTime.now();
      final elapsedSeconds = now.difference(lastShownTime).inSeconds;

      if (elapsedSeconds < cooldown) {
        return cooldown - elapsedSeconds;
      }
    } catch (e) {
      FastAdsLogger.warning('Error parsing last shown time: $e');
    }

    return 0;
  }

  /// 重置指定广告位的显示记录
  ///
  /// [placement] 广告位配置
  /// [storagePrefix] 存储键前缀
  Future<void> resetFrequency(FastPlacement placement, {required String storagePrefix}) async {
    final todayDateKey = _getTodayDateKey(storagePrefix, placement.name);
    final todayShowCountKey = _getTodayShowCountKey(storagePrefix, placement.name);
    final lastShownTimeKey = _getLastShownTimeKey(storagePrefix, placement.name);

    await SpUtils.remove(todayDateKey);
    await SpUtils.remove(todayShowCountKey);
    await SpUtils.remove(lastShownTimeKey);

    FastAdsLogger.info('Ad frequency records reset for placement: ${placement.name}');
  }
}
