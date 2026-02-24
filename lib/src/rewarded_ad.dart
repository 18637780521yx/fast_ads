import 'package:fast_ads/fast_ads.dart';
import 'package:fast_ads/src/pool/fast_base_ad.dart';
import 'package:fast_ads/src/utils/logger.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Rewarded Ad Implementation
///
/// Rewarded ads are a type of full-screen ad that users have the option to watch
/// in exchange for in-app rewards. These ads are designed to enhance the user experience
/// by providing a clear value exchange: watch an ad and receive in-app benefits.
class FastRewardedAd extends FastBaseAd<RewardedAd> {
  /// Create a new rewarded ad instance
  ///
  /// Parameters:
  /// - [adUnit]: 广告单元配置
  /// - [expireDuration]: 广告缓存过期时间，默认 1 小时
  FastRewardedAd({required super.adUnit, super.expireDuration = const Duration(hours: 1)});

  @override
  void load() {
    FastAdsLogger.info('Loading rewarded ad: $adUnitId');
    super.load();
    // 每次 load 都需要通知监听方（即使当前已经是 init）
    setStatus(FastAdStatus.init, force: true);
    RewardedAd.load(
      adUnitId: adUnitId,
      request: AdRequest(httpTimeoutMillis: adUnit.timeoutMs > 0 ? adUnit.timeoutMs : null),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ads) {
          FastAdsLogger.info('Rewarded ad loaded successfully: $adUnitId');
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
          FastAdsLogger.warning('Rewarded ad failed to load: $adUnitId', error);
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
    FastAdsLogger.debug('Rewarded ad show() called: $adUnitId');

    if (isLoaded && ad != null) {
      FastAdsLogger.info('Showing rewarded ad: $adUnitId (placement: ${placement.name})');
      ad!.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (ad) {
          FastAdsLogger.info('Rewarded ad showed: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdShow?.call(adUnit));
        },
        onAdClicked: (ad) {
          FastAdsLogger.info('Rewarded ad clicked: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdClicked?.call(adUnit));
        },
        onAdImpression: (ad) {
          FastAdsLogger.info('Rewarded ad impression: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdImpression?.call(adUnit));
        },
        onAdWillDismissFullScreenContent: (ad) {
          FastAdsLogger.info('Rewarded ad will dismiss: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdWillDismissScreen?.call(adUnit));
        },
        onAdDismissedFullScreenContent: (ad) {
          FastAdsLogger.info('Rewarded ad dismissed: $adUnitId');
          ad.dispose();
          this.ad = null;
          value = FastAdStatus.closed;
          triggerCallback((interceptor, adUnit) => interceptor.onAdDismissed?.call(adUnit));
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          FastAdsLogger.warning('Rewarded ad failed to show: $adUnitId', error);
          ad.dispose();
          this.ad = null;
          value = FastAdStatus.failed;
          triggerCallback(
            (interceptor, adUnit) => interceptor.onAdFailedToShow?.call(adUnit, error),
          );
        },
      );
      return ad!.show(
        onUserEarnedReward: (ad, reward) {
          FastAdsLogger.info(
            'User earned reward: ${reward.amount} ${reward.type} from ad: $adUnitId',
          );
          triggerCallback(
            (interceptor, adUnit) => interceptor.onUserEarnedReward?.call(adUnit, ad, reward),
          );
        },
      );
    } else {
      FastAdsLogger.warning('Attempted to show rewarded ad that is not ready: $adUnitId');
      return Future.error('Attempted to show rewarded ad that is not ready: $adUnitId');
    }
  }

  /// 记录广告收入信息
  void _logAdRevenue(double valueMicros, PrecisionType precision, String currencyCode) {
    // valueMicros 是微单位，需要除以 1e6 得到实际金额
    final revenue = valueMicros / 1000000.0;

    FastAdsLogger.info('💰 Rewarded Ad Revenue for $adUnitId:');
    FastAdsLogger.info('  - Revenue: $revenue $currencyCode');
    FastAdsLogger.info('  - Precision: ${precision.name}');
    FastAdsLogger.info('  - Value (micros): $valueMicros');
  }

  @override
  void dispose() {
    FastAdsLogger.debug('Disposing rewarded ad: $adUnitId');
    ad?.dispose();
    super.dispose();
  }
}
