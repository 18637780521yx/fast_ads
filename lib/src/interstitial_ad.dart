import 'package:fast_ads/fast_ads.dart';
import 'package:fast_ads/src/pool/fast_base_ad.dart';
import 'package:fast_ads/src/utils/logger.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Interstitial Ad Implementation
///
/// Interstitial ads are full-screen ads that cover the interface of their host app.
/// They're typically displayed at natural transition points in the flow of an app,
/// such as between activities or during the pause between levels in a game.
class FastInterstitialAd extends FastBaseAd<InterstitialAd> {
  /// Create a new interstitial ad instance
  ///
  /// Parameters:
  /// - [adUnit]: 广告单元配置
  /// - [expireDuration]: 广告缓存过期时间，默认 1 小时
  FastInterstitialAd({required super.adUnit, super.expireDuration = const Duration(hours: 1)});

  @override
  void load() {
    FastAdsLogger.info('Loading interstitial ad: $adUnitId');
    // 每次 load 都需要通知监听方（即使当前已经是 init）
    setStatus(FastAdStatus.init, force: true);
    InterstitialAd.load(
      adUnitId: adUnitId,
      request: AdRequest(httpTimeoutMillis: adUnit.timeoutMs > 0 ? adUnit.timeoutMs : null),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ads) {
          FastAdsLogger.info('Interstitial ad loaded successfully: $adUnitId');
          ad = ads;
          ad?.setImmersiveMode(true);
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
          FastAdsLogger.warning('Interstitial ad failed to load: $adUnitId', error);
          value = FastAdStatus.failed;
          triggerCallback(
            (interceptor, adUnit) => interceptor.onAdFailedToLoad?.call(adUnit, error),
          );
        },
      ),
    );
  }

  @override
  Future<void> show({required FastPlacement placement}) async {
    super.show(placement: placement);
    if (isLoaded && ad != null) {
      FastAdsLogger.info('Showing interstitial ad: $adUnitId (placement: ${placement.name})');
      ad?.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (ad) {
          FastAdsLogger.info('Interstitial ad showed: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdShow?.call(adUnit));
        },
        onAdClicked: (ad) {
          FastAdsLogger.info('Interstitial ad clicked: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdClicked?.call(adUnit));
        },
        onAdImpression: (ad) {
          FastAdsLogger.info('Interstitial ad impression: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdImpression?.call(adUnit));
        },
        onAdWillDismissFullScreenContent: (ad) {
          FastAdsLogger.info('Interstitial ad will dismiss: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdWillDismissScreen?.call(adUnit));
        },
        onAdDismissedFullScreenContent: (ad) {
          FastAdsLogger.info('Interstitial ad dismissed: $adUnitId');
          ad.dispose();
          this.ad = null;
          value = FastAdStatus.closed;

          if (placement.canEarnReward(adUnit)) {
            triggerCallback(
              (interceptor, adUnit) =>
                  interceptor.onUserEarnedReward?.call(adUnit, ad, RewardItem(1, 'reward')),
            );
          }

          triggerCallback((interceptor, adUnit) => interceptor.onAdDismissed?.call(adUnit));
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          FastAdsLogger.warning('Interstitial ad failed to show: $adUnitId', error);
          ad.dispose();
          this.ad = null;
          value = FastAdStatus.failed;

          triggerCallback(
            (interceptor, adUnit) => interceptor.onAdFailedToShow?.call(adUnit, error),
          );
        },
      );
      return ad?.show();
    } else {
      FastAdsLogger.warning('Attempted to show interstitial ad that is not ready: $adUnitId');
      return Future.error('Attempted to show interstitial ad that is not ready: $adUnitId');
    }
  }

  /// 记录广告收入信息
  void _logAdRevenue(double valueMicros, PrecisionType precision, String currencyCode) {
    // valueMicros 是微单位，需要除以 1e6 得到实际金额
    final revenue = valueMicros / 1000000.0;

    FastAdsLogger.info('💰 Interstitial Ad Revenue for $adUnitId:');
    FastAdsLogger.info('  - Revenue: $revenue $currencyCode');
    FastAdsLogger.info('  - Precision: ${precision.name}');
    FastAdsLogger.info('  - Value (micros): $valueMicros');
  }

  @override
  void dispose() {
    FastAdsLogger.debug('Disposing interstitial ad: $adUnitId');
    ad?.dispose();
    super.dispose();
  }
}
