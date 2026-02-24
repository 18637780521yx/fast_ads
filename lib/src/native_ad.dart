import 'package:fast_ads/fast_ads.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:fast_ads/src/pool/fast_base_ad.dart';
import 'package:fast_ads/src/utils/logger.dart';

/// Native Ad Implementation
///
/// Native ads are ad assets that are presented to users via UI components that
/// are native to the platform. They're shown using the same UI components as
/// the rest of the app, which can provide a more consistent user experience.
class FastNativeAd extends FastBaseAd<NativeAd> {
  /// Size of the native ad
  final AdSize size;

  /// Factory ID for the native ad
  final String? factoryId;

  /// Optional margin for the ad container
  final EdgeInsetsGeometry? margin;

  /// Optional custom builder for the ad widget
  final Widget Function(BuildContext, NativeAd)? builder;

  /// Create a new native ad instance
  FastNativeAd({
    required super.adUnit,
    this.size = const AdSize(width: 320, height: 150),
    this.factoryId,
    this.margin,
    this.builder,
  });

  /// Get a widget that displays this native ad
  ///
  /// Returns a widget that can be inserted directly into the widget tree.
  /// The widget will automatically handle showing/hiding based on ad state.
  Widget get widget {
    return ValueListenableBuilder<FastAdStatus>(
      valueListenable: this,
      builder: (context, status, child) {
        if (status == FastAdStatus.loaded && ad != null) {
          FastAdsLogger.info(
            'Native ad Rendering widget: $adUnitId  ad: ${ad.hashCode} code: ${hashCode}',
          );
          if (builder != null) {
            return builder!(context, ad!);
          }
          return Container(
            margin: margin,
            width: size.width.toDouble(),
            height: size.height.toDouble(),
            child: AdWidget(ad: ad!),
          );
        }
        FastAdsLogger.info('Native ad not ready, showing empty space: $adUnitId');
        return const SizedBox.shrink();
      },
    );
  }

  @override
  void load() {
    FastAdsLogger.info('Native ad Loading : $adUnitId');
    // 每次 load 都需要通知监听方（即使当前已经是 init）
    setStatus(FastAdStatus.init, force: true);
    ad = NativeAd(
      adUnitId: adUnitId,
      factoryId: factoryId,
      request: AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(templateType: TemplateType.medium),
      nativeAdOptions: NativeAdOptions(),
      listener: NativeAdListener(
        onAdOpened: (ad) {
          FastAdsLogger.info('Native ad opened: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdOpen?.call(adUnit));
        },
        onAdLoaded: (ad) {
          FastAdsLogger.info('Native ad loaded successfully: $adUnitId');
          value = FastAdStatus.loaded;
          triggerCallback((interceptor, adUnit) => interceptor.onAdLoaded?.call(adUnit));
        },
        onAdFailedToLoad: (ad, error) {
          FastAdsLogger.warning('Native ad failed to load: $adUnitId', error);
          ad.dispose();
          value = FastAdStatus.failed;
          triggerCallback(
            (interceptor, adUnit) => interceptor.onAdFailedToLoad?.call(adUnit, error),
          );
        },
        onAdClicked: (ad) {
          FastAdsLogger.info('Native ad clicked: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdClicked?.call(adUnit));
          load(); // Refresh the ad after it's clicked
        },
        onAdClosed: (ad) {
          FastAdsLogger.info('Native ad closed: $adUnitId');
          ad.dispose();
          this.ad = null;
          value = FastAdStatus.closed;
          triggerCallback((interceptor, adUnit) => interceptor.onAdDismissed?.call(adUnit));
        },
        onAdImpression: (ad) {
          FastAdsLogger.info('Native ad impression: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdImpression?.call(adUnit));
        },
        onAdWillDismissScreen: (ad) {
          FastAdsLogger.info('Native ad onAdWillDismissScreen: $adUnitId');
          triggerCallback((interceptor, adUnit) => interceptor.onAdWillDismissScreen?.call(adUnit));
        },
        onPaidEvent: (ad, valueMicros, precision, currencyCode) {
          FastAdsLogger.info('Native ad onPaidEvent: $adUnitId');
          _logAdRevenue(valueMicros, precision, currencyCode);
          triggerCallback(
            (interceptor, adUnit) =>
                interceptor.onAdPaid?.call(adUnit, valueMicros, precision, currencyCode),
          );
        },
      ),
    )..load();
  }

  @override
  Future<void> show({required FastPlacement placement}) async {
    super.show(placement: placement);
    FastAdsLogger.debug(
      'Native show() called - native requires widget placement: $adUnitId (placement: ${placement.name})',
    );
    // Native ads are embedded widgets, so show() doesn't have a direct action
    // The ad is displayed when the native widget is added to the widget tree
  }

  /// 记录广告收入信息
  void _logAdRevenue(double valueMicros, PrecisionType precision, String currencyCode) {
    // valueMicros 是微单位，需要除以 1e6 得到实际金额
    final revenue = valueMicros / 1000000.0;

    FastAdsLogger.info('💰 Native Ad Revenue for $adUnitId:');
    FastAdsLogger.info('  - Revenue: $revenue $currencyCode');
    FastAdsLogger.info('  - Precision: ${precision.name}');
    FastAdsLogger.info('  - Value (micros): $valueMicros');
  }

  @override
  void dispose() {
    FastAdsLogger.debug('Disposing native ad: $adUnitId');

    ad?.dispose();
    super.dispose();
  }
}
