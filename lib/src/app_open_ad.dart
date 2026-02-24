import 'dart:async';

import 'package:fast_ads/fast_ads.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// App Open Ad Implementation
///
/// App open ads are a special ad format that can be shown when users bring
/// your app to the foreground (cold start, warm start, or from background).
/// They help monetize the loading or splash screen experience.
class FastAppOpenAd extends FastBaseAd<AppOpenAd> {
  /// 存储键前缀
  static const String _storagePrefix = 'fast_app_open_ad';

  /// 标记当前广告是否已记录显示（防止重复记录）
  bool _hasRecordedCurrentShow = false;

  /// Create a new app open ad instance
  ///
  /// Parameters:
  /// - [adUnit]: 广告单元配置
  /// - [expireDuration]: 广告缓存过期时间，默认 4 小时
  FastAppOpenAd({required super.adUnit, super.expireDuration = const Duration(hours: 4)});

  @override
  void load() {
    FastAdsLogger.info('Loading app open ad: $adUnitId');
    // 每次 load 都需要通知监听方（即使当前已经是 init）
    setStatus(FastAdStatus.init, force: true);
    AppOpenAd.load(
      adUnitId: adUnitId,
      request: AdRequest(httpTimeoutMillis: adUnit.timeoutMs > 0 ? adUnit.timeoutMs : null),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ads) {
          FastAdsLogger.info('App open ad loaded successfully: $adUnitId');
          ad = ads;
          // 设置收入回调
          ad?.onPaidEvent = (ad, valueMicros, precision, currencyCode) {
            _logAdRevenue(valueMicros, precision, currencyCode);
            triggerCallback(
              (interceptor, adUnit) =>
                  interceptor.onAdPaid?.call(adUnit, valueMicros, precision, currencyCode),
            );
          };
          value = FastAdStatus.loaded;
          triggerCallback((interceptor, adUnit) => interceptor.onAdLoaded?.call(adUnit));
        },
        onAdFailedToLoad: (error) {
          FastAdsLogger.warning('App open ad failed to load: $adUnitId', error);
          value = FastAdStatus.failed;
          triggerCallback(
            (interceptor, adUnit) => interceptor.onAdFailedToLoad?.call(adUnit, error),
          );
        },
      ),
    );
  }

  /// 检查是否满足显示条件（冷却时间和每日上限）
  bool _canShow(FastPlacement placement) {
    return canShowFrequency(
      placement,
      storagePrefix: _storagePrefix,
      checkMaxHighPriority: adUnit.isMaxHighPriority,
    );
  }

  /// 记录广告显示
  Future<void> _recordShow(FastPlacement placement) async {
    await recordShowFrequency(placement, storagePrefix: _storagePrefix);
  }

  @override
  Future<void> show({required FastPlacement placement}) async {
    super.show(placement: placement);

    if (!isLoaded || ad == null) {
      FastAdsLogger.warning('Attempted to show app open ad that is not ready: $adUnitId');
      return Future.error('Attempted to show app open ad that is not ready: $adUnitId');
    }

    // 检查是否满足显示条件
    final canShow = _canShow(placement);
    if (!canShow) {
      FastAdsLogger.info(
        'App open ad blocked by cooldown or daily cap: $adUnitId (placement: ${placement.name})',
      );
      return;
    }

    FastAdsLogger.info('Showing app open ad: $adUnitId (placement: ${placement.name})');
    _hasRecordedCurrentShow = false; // 重置标记
    ad!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        FastAdsLogger.info('App open ad showed: $adUnitId');
        // 只记录一次
        if (!_hasRecordedCurrentShow) {
          _hasRecordedCurrentShow = true;
          _recordShow(placement);
          triggerCallback((interceptor, adUnit) => interceptor.onAdShow?.call(adUnit));
        }
      },
      onAdClicked: (ad) {
        FastAdsLogger.info('App open ad clicked: $adUnitId');
        triggerCallback((interceptor, adUnit) => interceptor.onAdClicked?.call(adUnit));
      },
      onAdImpression: (ad) {
        FastAdsLogger.info('App open ad impression: $adUnitId');
        triggerCallback((interceptor, adUnit) => interceptor.onAdImpression?.call(adUnit));
      },
      onAdWillDismissFullScreenContent: (ad) {
        FastAdsLogger.info('App open ad will dismiss: $adUnitId');
        triggerCallback((interceptor, adUnit) => interceptor.onAdWillDismissScreen?.call(adUnit));
      },
      onAdDismissedFullScreenContent: (_ad) {
        FastAdsLogger.info('App open ad dismissed: $adUnitId');
        _ad.dispose();
        ad = null;
        value = FastAdStatus.closed;
        if (placement.canEarnReward(adUnit)) {
          triggerCallback(
            (interceptor, adUnit) =>
                interceptor.onUserEarnedReward?.call(adUnit, _ad, RewardItem(1, 'reward')),
          );
        }
        triggerCallback((interceptor, adUnit) => interceptor.onAdDismissed?.call(adUnit));
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        FastAdsLogger.warning('App open ad failed to show: $adUnitId', error);
        ad.dispose();
        this.ad = null;
        value = FastAdStatus.failed;
        triggerCallback((interceptor, adUnit) => interceptor.onAdFailedToShow?.call(adUnit, error));
      },
    );
    return ad!.show();
  }

  /// 记录广告收入信息
  void _logAdRevenue(double valueMicros, PrecisionType precision, String currencyCode) {
    // valueMicros 是微单位，需要除以 1e6 得到实际金额
    final revenue = valueMicros / 1000000.0;

    FastAdsLogger.info('💰 App Open Ad Revenue for $adUnitId:');
    FastAdsLogger.info('  - Revenue: $revenue $currencyCode');
    FastAdsLogger.info('  - Precision: ${precision.name}');
    FastAdsLogger.info('  - Value (micros): $valueMicros');
  }

  @override
  void dispose() {
    FastAdsLogger.debug('Disposing app open ad: $adUnitId');
    ad?.dispose();
    super.dispose();
  }
}
