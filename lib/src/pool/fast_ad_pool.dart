import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../fast_ads.dart';
import '../app_open_ad.dart';

/// Ad Pool for managing multiple instances of the same ad type
///
/// The pool handles:
/// - Managing multiple ad instances of the same type for rotation
/// - Automatic reloading of ads after display or expiration
/// - Handling pending show requests when ads are not immediately available
/// - Tracking ad statuses and availability
/// - Global ad instance sharing to avoid duplicate loading of the same adUnitId
class FastAdPool<T extends FastBaseAd> {
  /// 全局广告实例池，按 adUnitId 索引，避免重复加载
  static final _adInstances = <String, FastBaseAd>{};

  /// 广告实例引用计数，记录每个广告实例被多少个 FastPlacement 使用
  static final _adRefCounts = <String, int>{};

  /// Internal storage for ad instances
  final List<T> _pool = [];

  List<T> get ads => _pool;

  int get length => _pool.length;

  /// 广告位配置
  final FastPlacement placement;

  /// 记录池使用的所有广告实例的 adUnitId，用于释放引用
  final Set<String> _adUnitIds = {};

  /// 获取或创建广告实例（带引用计数管理）
  ///
  /// 如果广告实例已存在，增加引用计数并返回
  /// 如果不存在，创建新实例并初始化引用计数为 1
  ///
  /// 参数：
  /// - [adUnit]: 广告单元配置
  /// 返回：
  /// - 广告实例
  static FastBaseAd getOrCreateAdInstance(FastAdUnit adUnit) {
    final adUnitId = adUnit.adUnitId;

    if (_adInstances.containsKey(adUnitId)) {
      // 广告实例已存在，增加引用计数
      _adRefCounts[adUnitId] = (_adRefCounts[adUnitId] ?? 0) + 1;
      FastAdsLogger.info('Reusing ad instance: $adUnitId (refCount: ${_adRefCounts[adUnitId]})');
      return _adInstances[adUnitId]!;
    }

    // 创建新广告实例
    final ad = _createAd(adUnit);
    _adInstances[adUnitId] = ad;
    _adRefCounts[adUnitId] = 1;
    FastAdsLogger.info('Created new ad instance: $adUnitId (refCount: 1)');
    return ad;
  }

  /// 释放广告实例的引用（减少引用计数）
  ///
  /// 当引用计数为 0 时，从全局池中移除广告实例
  ///
  /// 参数：
  /// - [adUnitId]: 广告单元ID
  static void releaseAdInstance(String adUnitId) {
    final refCount = _adRefCounts[adUnitId] ?? 0;
    if (refCount <= 1) {
      // 引用计数为 0 或更少，移除广告实例
      _adInstances.remove(adUnitId);
      _adRefCounts.remove(adUnitId);
      FastAdsLogger.debug('Removed ad instance: $adUnitId');
    } else {
      // 减少引用计数
      _adRefCounts[adUnitId] = refCount - 1;
      FastAdsLogger.debug('Released ad instance: $adUnitId (refCount: ${_adRefCounts[adUnitId]})');
    }
  }

  /// 根据广告位类型创建对应的广告实例
  static FastBaseAd _createAd(FastAdUnit unit) {
    switch (unit.adType) {
      case FastAdsType.appOpen:
        return FastAppOpenAd(adUnit: unit);
      case FastAdsType.interstitial:
        return FastInterstitialAd(adUnit: unit);
      case FastAdsType.rewarded:
        return FastRewardedAd(adUnit: unit);
      case FastAdsType.banner:
        return FastBannerAd(adUnit: unit, size: AdSize.banner);
      case FastAdsType.native:
        return FastNativeAd(adUnit: unit);
      case FastAdsType.feed:
        return FastNativeAd(adUnit: unit);
    }
  }

  /// Get an ad from the pool by index
  T ad({int index = 0}) => _pool[index];

  // bool enable = true;

  /// Constructor
  ///
  /// Initializes the pool with placement config and begins loading ads
  /// Uses global ad instance pool to avoid duplicate loading of the same adUnitId
  FastAdPool({required this.placement}) {
    FastAdsLogger.info(
      'Initializing ad pool for placement: ${placement.name} with ${placement.adUnits.length} ads',
    );

    for (final unit in placement.adUnits) {
      FastAdsLogger.debug(
        'Getting or creating ad: ${unit.adUnitId} for placement: ${placement.name}',
      );

      // 检查广告实例是否已存在（在调用 getOrCreateAdInstance 之前）
      final adUnitId = unit.adUnitId;
      final isNewInstance = !_adInstances.containsKey(adUnitId);

      // 从全局池中获取或创建广告实例（带引用计数）
      final ad = getOrCreateAdInstance(unit) as T;
      _adUnitIds.add(adUnitId);

      _pool.add(ad);

      // 只有在广告实例是新创建的时候才加载（避免重复加载）
      if (isNewInstance && ad.value == FastAdStatus.init) {
        FastAdsLogger.info('Loading new ad instance: ${ad.adUnitId}');
        ad.load();
      } else if (!isNewInstance) {
        FastAdsLogger.info(
          'Reusing existing ad instance: ${ad.adUnitId} (status: ${ad.value.name})',
        );
      } else {
        FastAdsLogger.info('Ad instance already loaded: ${ad.adUnitId} (status: ${ad.value.name})');
      }
    }
  }

  /// 释放池使用的所有广告实例的引用
  ///
  /// 当池被销毁时调用，减少广告实例的引用计数
  void dispose() {
    for (final adUnitId in _adUnitIds) {
      releaseAdInstance(adUnitId);
    }
    _adUnitIds.clear();
    _pool.clear();
  }

  /// Get the highest priority ad that's ready to show
  ///
  /// Returns null if no ads are ready
  /// Automatically reloads expired ads
  /// Selects the ad with lowest priority value (highest priority)
  T? get readyAd {
    final readyAds = <T>[];

    for (final ad in _pool) {
      // 检查广告是否过期，如果过期则自动重新加载
      if (ad.isCacheExpired) {
        final expireDurationStr = _formatDuration(ad.expireDuration);
        FastAdsLogger.info(
          'Ad cache expired, reloading: ${ad.adUnitId} (expired after $expireDurationStr)',
        );
        ad.load();
        continue; // 跳过过期的广告
      }

      if (ad.isLoaded) {
        readyAds.add(ad);
      }
    }

    if (readyAds.isEmpty) {
      FastAdsLogger.debug('No ready ads available in pool');
      return null;
    }

    // 按优先级排序，priority 值越小优先级越高
    readyAds.sort((a, b) => a.adUnit.priority.compareTo(b.adUnit.priority));

    final selectedAd = readyAds.first;
    FastAdsLogger.debug(
      'Found ready ad: ${selectedAd.adUnitId} (priority: ${selectedAd.adUnit.priority})',
    );
    return selectedAd;
  }

  /// Check if any ad in the pool is ready to display
  bool get hasReadyAd => readyAd != null;

  /// 展示已就绪的广告
  ///
  /// 只从 readyAd 读取，没有可用广告则返回 null，不等待
  /// 自动重新加载过期的广告
  ///
  /// Parameters:
  /// - [placement]: 广告位配置
  T? show(FastPlacement placement) {
    if (!placement.enabled) {
      return null;
    }

    // 先检查并重新加载所有过期的广告
    _reloadExpiredAds();

    final ad = readyAd;
    if (ad != null) {
      FastAdsLogger.info('Showing ad: ${ad.adUnitId} (placement: ${placement.name})');
      ad.show(placement: placement);
      return ad;
    }

    FastAdsLogger.debug('No ready ads available for placement: ${placement.name}');
    return null;
  }

  /// 直接展示广告
  ///
  /// 从池中按优先级选择广告，如果已加载则直接展示，否则等待加载完成后展示
  ///
  /// Parameters:
  /// - [placement]: 广告位配置
  Future<T?> showDirect(FastPlacement placement) async {
    if (!placement.enabled) {
      return null;
    }

    if (_pool.isEmpty) {
      FastAdsLogger.warning('No ads in pool for placement: ${placement.name}');
      return null;
    }

    // 按优先级排序，选择优先级最高的广告
    final sortedAds = List.of(_pool)
      ..sort((a, b) => a.adUnit.priority.compareTo(b.adUnit.priority));

    final ad = sortedAds.first;
    FastAdsLogger.info(
      'Direct show ad: ${ad.adUnitId} (placement: ${placement.name}, priority: ${ad.adUnit.priority})',
    );
    // if (ad.isShowing) {
    //   FastAdsLogger.warning('Ad is already showing: ${ad.adUnitId}');
    //   return null;
    // } else {

    // }

    ad.showDirect(placement: placement);
    return ad;
  }

  /// 重新加载所有过期的广告
  void _reloadExpiredAds() {
    for (final ad in _pool) {
      if (ad.isCacheExpired) {
        final expireDurationStr = _formatDuration(ad.expireDuration);
        FastAdsLogger.info(
          'Reloading expired ad: ${ad.adUnitId} (expired after $expireDurationStr)',
        );
        ad.load();
      }
    }
  }

  /// 格式化 Duration 为可读字符串
  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays} days';
    } else if (duration.inHours > 0) {
      return '${duration.inHours} hours';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes} minutes';
    } else {
      return '${duration.inSeconds} seconds';
    }
  }

  /// Check all ads in the pool and reload any that are expired or not loaded
  void reload() {
    FastAdsLogger.debug('Reloading expired or unloaded ads in pool');
    for (final ad in _pool) {
      if (ad.isExpired || !ad.isLoaded) {
        FastAdsLogger.debug('Reloading ad: ${ad.adUnitId}');
        ad.load();
      }
    }
  }

  T loadNativeAd() {
    if (placement.adUnits.isEmpty) {
      FastAdsLogger.warning('Ad pool for placement ${placement.name} has no ad units to load.');
      throw "no ad units to load";
    }

    // 轮询使用不同的广告单元，确保广告内容多样化
    // 使用当前池的长度作为索引，循环选择广告单元
    final adUnitIndex = _pool.length % placement.adUnits.length;
    final adUnit = placement.adUnits[adUnitIndex];

    final ad = FastNativeAd(adUnit: adUnit) as T;
    ad.load();
    _pool.add(ad);

    FastAdsLogger.debug(
      'Loaded new native ad instance for placement: ${placement.name}, using adUnit[$adUnitIndex]: ${adUnit.adUnitId}, pool length: ${_pool.length}',
    );

    return ad;
  }
}
