import 'package:fast_ads/fast_ads.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:fast_ads/src/pool/fast_base_ad.dart';
import 'package:fast_ads/src/utils/logger.dart';

/// Banner Ad Implementation
///
/// Banner ads are typically displayed at the top or bottom of the screen
/// and remain visible while users are interacting with the app.
class FastBannerAd extends FastBaseAd<BannerAd> {
  /// Size of the banner ad
  final AdSize size;

  /// Create a new banner ad instance
  ///
  /// Parameters:
  /// - [adUnit]: 广告单元配置
  /// - [size]: 广告尺寸，默认 AdSize.banner
  /// 注意：插入频率由业务层控制，不在广告类内部处理
  FastBannerAd({required super.adUnit, this.size = AdSize.banner});

  /// Get a widget that displays this banner ad
  ///
  /// Returns a widget that can be inserted directly into the widget tree.
  /// The widget will automatically handle showing/hiding based on ad state.
  late Widget widget;

  @override
  void load() {
    FastAdsLogger.info('Loading banner ad: $adUnitId');
    // 每次 load 都需要通知监听方（即使当前已经是 init）
    setStatus(FastAdStatus.init, force: true);
    ad = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: AdRequest(httpTimeoutMillis: adUnit.timeoutMs > 0 ? adUnit.timeoutMs : null),
      listener: BannerAdListener(
        onAdOpened: (ad) {
          FastAdsLogger.info('Banner ad opened: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdOpen?.call(adUnit));
        },
        onAdLoaded: (ad) {
          FastAdsLogger.info('Banner ad loaded successfully: $adUnitId');
          value = FastAdStatus.loaded;
          triggerCallback((interceptor, adUnit) => interceptor.onAdLoaded?.call(adUnit));
        },
        onAdFailedToLoad: (ad, error) {
          FastAdsLogger.warning('Banner ad failed to load: $adUnitId', error);
          ad.dispose();
          value = FastAdStatus.failed;
          triggerCallback(
            (interceptor, adUnit) => interceptor.onAdFailedToLoad?.call(adUnit, error),
          );
        },
        onAdClicked: (ad) {
          FastAdsLogger.info('Banner ad clicked: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdClicked?.call(adUnit));
        },
        onAdClosed: (ad) {
          FastAdsLogger.info('Banner ad closed: $adUnitId');
          ad.dispose();
          this.ad = null;
          value = FastAdStatus.closed;
          triggerCallback((interceptor, adUnit) => interceptor.onAdDismissed?.call(adUnit));
        },
        onAdImpression: (ad) {
          FastAdsLogger.info('Banner ad impression: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdImpression?.call(adUnit));
        },
        onAdWillDismissScreen: (ad) {
          FastAdsLogger.info('Banner ad will dismiss screen: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdWillDismissScreen?.call(adUnit));
        },
        onPaidEvent: (ad, valueMicros, precision, currencyCode) {
          // 这是真正的广告收入信息！
          // valueMicros 是微单位，需要除以 1e6 得到实际金额
          final revenue = valueMicros / 1000000.0;

          FastAdsLogger.info('💰 Ad Revenue for $adUnitId:');
          FastAdsLogger.info('  - Revenue: $revenue $currencyCode');
          FastAdsLogger.info('  - Precision: ${precision.name}');
          FastAdsLogger.info('  - Value (micros): $valueMicros');
          triggerCallback(
            (interceptor, adUnit) =>
                interceptor.onAdPaid?.call(adUnit, valueMicros, precision, currencyCode),
          );
        },
      ),
    )..load();

    widget = ValueListenableBuilder<FastAdStatus>(
      valueListenable: this,
      builder: (context, status, child) {
        if (status == FastAdStatus.loaded) {
          FastAdsLogger.debug('Rendering banner ad widget: $adUnitId');
          return AdWidget(ad: ad!);
        }
        FastAdsLogger.debug('Banner ad not ready, showing empty space: $adUnitId');
        return SizedBox.shrink();
      },
    );
  }

  @override
  Future<Widget?> show({required FastPlacement placement}) async {
    super.show(placement: placement);
    return widget;
  }

  @override
  void dispose() {
    FastAdsLogger.debug('Disposing banner ad: $adUnitId');
    ad?.dispose();
    super.dispose();
  }
}
