import 'dart:async';

import 'package:fast_ads/fast_ads.dart';
import 'package:flutter/foundation.dart';
import 'package:fast_ads/src/utils/logger.dart';

/// Represents the current status of an ad
enum FastAdStatus {
  /// Initial state, ad is not yet loaded
  init,

  /// Ad has been successfully loaded and is ready to display
  loaded,

  /// Ad was displayed and has been closed by the user
  closed,

  /// Ad failed to load or display
  failed,
}

/// Base abstract class for all ad types
///
/// Provides common functionality for ad loading, status tracking,
/// retry logic, and expiration management
abstract class FastBaseAd<T> extends ChangeNotifier implements ValueListenable<FastAdStatus> {
  /// 广告单元配置
  final FastAdUnit adUnit;

  /// 广告单元ID（便捷属性）
  String get adUnitId => adUnit.adUnitId;

  /// Whether the ad is currently being shown
  // bool isShowing = false;

  /// The actual ad instance from the ad network SDK
  T? ad;

  /// 记录该广告实例“最后一次是被哪个物理广告位展示的”
  ///
  /// 由于 FastAdPool 会在多个 placement 之间复用同一个 adUnitId 的实例，
  /// 所以需要用这个字段来避免“某个广告关闭 → 所有使用该实例的 pool 都触发 reload()”的连锁反应。
  String? lastShownPlacementName;

  @override
  FastAdStatus get value => _value;
  FastAdStatus _value = FastAdStatus.init;

  /// Timestamp when the ad request started
  DateTime? _requestStartTime;

  /// Timestamp when the ad was successfully loaded
  DateTime? _loadedTime;

  /// Timestamp when the ad display started
  DateTime? _displayStartTime;

  /// Completer for waiting for ad load completion
  Completer<void>? _loadCompleter;

  /// 关闭后是否自动刷新（重新发起 load）
  ///
  /// 适用于插屏/激励/开屏等一次性广告：展示后会被 SDK 释放，需要重新 load 才能下一次展示。
  /// Banner/Native 也可用，但通常它们的生命周期由 Widget/页面控制。
  bool autoReloadOnClose = true;

  /// 自动刷新最小间隔，避免极端情况下 close/fail 频繁触发导致刷爆请求
  Duration autoReloadMinInterval = const Duration(seconds: 1);

  DateTime? _lastAutoReloadAt;
  bool _autoReloadScheduled = false;

  void _scheduleAutoReload() {
    if (!autoReloadOnClose) return;
    if (_autoReloadScheduled) return;

    final now = DateTime.now();
    if (_lastAutoReloadAt != null && now.difference(_lastAutoReloadAt!) < autoReloadMinInterval) {
      return;
    }

    _autoReloadScheduled = true;
    _lastAutoReloadAt = now;

    // 用 microtask 让当前状态流转/回调先完成，再触发下一次 load
    scheduleMicrotask(() {
      _autoReloadScheduled = false;
      // 如果此时又被加载成功/正在展示，就不重复 load
      if (isLoaded) return;
      FastAdsLogger.info('Auto reloading ad after close: $adUnitId');
      load();
    });
  }

  /// Update ad status and trigger appropriate actions
  ///
  /// When [force] is true, listeners will be notified even if the status didn't change.
  void setStatus(FastAdStatus newValue, {bool force = false}) {
    if (!force && _value == newValue) {
      return;
    }

    final oldStatus = _value;
    _value = newValue;

    FastAdsLogger.debug(
      'Ad status changed: $adUnitId - ${oldStatus.name} → ${newValue.name} (force: $force)',
    );

    switch (newValue) {
      case FastAdStatus.init:
        // Initial state
        // 如果还没有 Completer 或已经完成，创建新的
        if (_loadCompleter == null || _loadCompleter!.isCompleted) {
          _loadCompleter = Completer<void>();
        }
        // 记录请求开始时间
        _requestStartTime = DateTime.now();
        // 触发广告开始请求回调
        triggerCallback((interceptor, adUnit) => interceptor.onAdRequest?.call(adUnit));
        break;
      case FastAdStatus.loaded:
        isLoaded = true;
        _loadedTime = DateTime.now();
        // 计算请求时长
        if (_requestStartTime != null) {
          adUnit.requestDuration = DateTime.now().difference(_requestStartTime!).inMilliseconds;
        }
        resetRetry();
        // FastAdsLogger.info('Ad loaded successfully: $adUnitId');
        // 完成等待加载的 Completer
        if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
          _loadCompleter!.complete();
        }
        break;
      case FastAdStatus.closed:
        // 计算展示时长
        if (_displayStartTime != null) {
          adUnit.displayDuration = DateTime.now().difference(_displayStartTime!).inMilliseconds;
          _displayStartTime = null;
        }

        // 完成等待加载的 Completer
        if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
          _loadCompleter!.complete();
        }
        _loadCompleter = null;

        // 清理广告状态和资源
        clear();

        FastAdsLogger.info('Ad closed: $adUnitId');
        _scheduleAutoReload();
        break;
      case FastAdStatus.failed:
        // 计算请求时长（即使失败也记录）
        if (_requestStartTime != null) {
          adUnit.requestDuration = DateTime.now().difference(_requestStartTime!).inMilliseconds;
        }

        // 完成等待加载的 Completer（失败情况，需要在 clear 之前处理）
        if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
          _loadCompleter!.completeError('Ad failed to load: $adUnitId');
        }
        _loadCompleter = null;

        // 清理广告状态和资源
        clear();

        FastAdsLogger.warning('Ad failed: $adUnitId, attempting retry');
        retry();
        break;
    }

    notifyListeners();
  }

  set value(FastAdStatus newValue) => setStatus(newValue);

  /// Whether the ad is loaded and ready to display
  bool isLoaded = false;

  /// Time period after which a loaded ad is considered expired
  final Duration expireDuration;

  /// Check if the ad has expired based on load time
  bool get isExpired =>
      _loadedTime == null || DateTime.now().difference(_loadedTime!) > expireDuration;

  /// Check if the ad cache has expired
  ///
  /// Each type of ad cache has a time limit, and if it exceeds the expiration time, it needs to be reloaded
  /// Returns true if the cache has expired and needs to be reloaded
  /// Returns false if the cache is still valid and can be used directly
  ///
  /// Note: Only checks expiration if the ad is already loaded.
  /// If the ad hasn't finished loading yet, it's not considered expired.
  bool get isCacheExpired {
    // 只有已加载的广告才检查是否过期
    // 如果广告还没加载完成，不算过期
    if (!isLoaded || _loadedTime == null) {
      return false;
    }
    return DateTime.now().difference(_loadedTime!) > expireDuration;
  }

  /// Load the ad from the ad network
  void load() {
    FastAdsLogger.debug('Base load called for: $adUnitId');
  }

  /// Display the ad to the user
  ///
  /// Parameters:
  /// - [placement]: 广告位配置，包含广告位名称、类型、控制参数等
  Future<dynamic> show({required FastPlacement placement}) async {
    lastShownPlacementName = placement.name;

    adUnit.realPlacementReference = WeakReference(placement);

    // 记录展示开始时间
    _displayStartTime = DateTime.now();
    FastAdsLogger.debug('Base show called for: $adUnitId (placement: ${placement.name})');
  }

  /// 直接展示广告，等待加载完成后展示
  ///
  /// 如果广告已加载完成，立即展示
  /// 如果广告还在加载中，等待加载完成后再展示
  ///
  /// Parameters:
  /// - [placement]: 广告位配置，包含广告位名称、类型、控制参数等
  /// - [timeout]: 等待超时时间，默认 30 秒
  Future<dynamic> showDirect({
    required FastPlacement placement,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    adUnit.realPlacementReference = WeakReference(placement);

    // 如果已经加载完成，直接展示
    if (isLoaded) {
      FastAdsLogger.debug('Ad already loaded, showing directly: $adUnitId');
      return show(placement: placement);
    }

    // 确保有 Completer 可以等待（如果已经完成，创建新的）
    if (_loadCompleter == null || _loadCompleter!.isCompleted) {
      _loadCompleter = Completer<void>();
    }

    // 等待广告加载完成
    FastAdsLogger.info('Waiting for ad to load: $adUnitId');
    try {
      await _loadCompleter!.future.timeout(
        timeout,
        onTimeout: () {
          FastAdsLogger.warning('Ad load timeout: $adUnitId');
          throw TimeoutException('Ad load timeout: $adUnitId', timeout);
        },
      );

      // 加载完成，检查状态并展示广告
      if (isLoaded && value == FastAdStatus.loaded) {
        FastAdsLogger.info('Ad loaded, showing: $adUnitId');
        return show(placement: placement);
      } else {
        FastAdsLogger.warning(
          'Ad load completed but not loaded: $adUnitId (status: ${value.name})',
        );
        throw Exception('Ad load completed but not loaded: $adUnitId');
      }
    } catch (e) {
      FastAdsLogger.warning('Error waiting for ad load: $adUnitId, error: $e');
      rethrow;
    }
  }

  /// Delay before the next retry attempt
  Duration retryDelay = Duration(seconds: 2);

  /// 清理广告状态和资源
  ///
  /// 在广告关闭或失败后调用，清理：
  /// - 广告实例引用
  /// - 加载状态
  /// - adUnit 上的回调函数
  ///
  /// 注意：Completer 需要在调用此方法之前单独处理，
  /// 因为 closed 和 failed 的处理方式不同（complete vs completeError）
  void clear() {
    isLoaded = false;
    _loadedTime = null;
    ad = null;
    // 清理 adUnit 上的回调函数，避免内存泄漏和复用时触发旧回调
    adUnit.clearCallbacks();
    FastAdsLogger.debug('Ad cleared: $adUnitId');
  }

  /// Constructor
  ///
  /// Parameters:
  /// - [adUnit]: 广告单元配置
  /// - [expireDuration]: 广告过期时间
  FastBaseAd({required this.adUnit, this.expireDuration = const Duration(minutes: 30)}) {
    // 初始化拦截器集合，并将 adUnit 本身加入
    interceptors.add(adUnit);
    FastAdsLogger.debug('Creating ad: $adUnitId');
  }

  /// 统一触发所有拦截器的回调（包含 adUnit）
  void triggerCallback(void Function(FastAdUnitInterceptor, FastAdUnit) callback) {
    for (var element in interceptors) {
      try {
        callback(element, adUnit);
      } catch (e) {
        FastAdsLogger.warning('Error in interceptor callback for $adUnitId: $e');
      }
    }
  }
}

/// Extension providing retry functionality for ads
extension Retry on FastBaseAd {
  /// Maximum number of retry attempts
  static const int maxRetryCount = 3;

  /// Reset the retry counter and delay
  resetRetry() {
    adUnit.retryCount = 0;
    retryDelay = Duration(seconds: 2);
    FastAdsLogger.debug('Reset retry counter for: ${adUnitId}');
  }

  /// Implement exponential backoff retry logic
  retry() async {
    final retryCount = adUnit.retryCount;
    if (retryCount < maxRetryCount) {
      FastAdsLogger.info(
        'Retrying ad load (${retryCount + 1}/$maxRetryCount) for ${adUnitId} after ${retryDelay.inSeconds}s',
      );
      await Future.delayed(retryDelay);
      adUnit.retryCount = retryCount + 1;
      retryDelay *= 2; // Exponential backoff
      load();
    } else {
      FastAdsLogger.warning('Maximum retry count reached for: ${adUnitId}');
      // Maximum retry count reached, logging the issue
    }
  }
}
