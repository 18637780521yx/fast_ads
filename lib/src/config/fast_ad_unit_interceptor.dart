import 'package:fast_ads/src/config/fast_placement.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 广告回调函数类型定义
typedef OnAdRequest = void Function(FastAdUnit adUnit);
typedef OnAdLoaded = void Function(FastAdUnit adUnit);
typedef OnAdFailedToLoad = void Function(FastAdUnit adUnit, Object error);
typedef OnAdShow = void Function(FastAdUnit adUnit);
typedef OnAdClicked = void Function(FastAdUnit adUnit);
typedef OnAdImpression = void Function(FastAdUnit adUnit);
typedef OnAdDismissed = void Function(FastAdUnit adUnit);
typedef OnAdFailedToShow = void Function(FastAdUnit adUnit, Object error);
typedef OnAdOpen = void Function(FastAdUnit adUnit);
typedef OnAdWillDismissScreen = void Function(FastAdUnit adUnit);
typedef OnAdBlockedByLimit = void Function(FastAdUnit adUnit, String reason);
typedef OnAdTechnicalError = void Function(FastAdUnit adUnit, String error);
typedef OnAdCacheStatus = void Function(FastAdUnit adUnit, String status);
typedef OnAdPaid =
    void Function(
      FastAdUnit adUnit,
      double valueMicros,
      PrecisionType precision,
      String currencyCode,
    );
typedef OnUserEarnedReward = void Function(FastAdUnit adUnit, AdWithoutView ad, RewardItem reward);

abstract class FastAdUnitInterceptor {
  // ============ 广告回调函数 ============

  /// 广告开始请求回调
  OnAdRequest? onAdRequest;

  /// 广告加载成功回调
  OnAdLoaded? onAdLoaded;

  /// 广告加载失败回调
  OnAdFailedToLoad? onAdFailedToLoad;

  /// 广告开始展示回调（全屏广告开始显示）
  OnAdShow? onAdShow;

  /// 广告被点击回调
  OnAdClicked? onAdClicked;

  /// 广告曝光回调（impression）
  OnAdImpression? onAdImpression;

  /// 广告关闭回调
  OnAdDismissed? onAdDismissed;

  /// 广告展示失败回调
  OnAdFailedToShow? onAdFailedToShow;

  /// 广告收入回调
  OnAdPaid? onAdPaid;

  /// 用户获得奖励回调（仅激励广告）
  OnUserEarnedReward? onUserEarnedReward;

  /// 广告即将关闭屏幕回调
  OnAdWillDismissScreen? onAdWillDismissScreen;

  /// 广告打开回调
  OnAdOpen? onAdOpen;

  /// 因频控限制未展示回调
  OnAdBlockedByLimit? onAdBlockedByLimit;

  /// 技术错误回调
  OnAdTechnicalError? onAdTechnicalError;

  /// 广告缓存状态变化回调
  OnAdCacheStatus? onAdCacheStatus;

  /// 清理所有回调函数
  ///
  /// 在广告关闭后调用，避免：
  /// 1. 内存泄漏（回调闭包可能持有外部对象引用）
  /// 2. 下次复用时触发旧回调
  void clearCallbacks() {
    onAdRequest = null;
    onAdLoaded = null;
    onAdFailedToLoad = null;
    onAdShow = null;
    onAdClicked = null;
    onAdImpression = null;
    onAdDismissed = null;
    onAdFailedToShow = null;
    onAdPaid = null;
    onUserEarnedReward = null;
    onAdWillDismissScreen = null;
    onAdOpen = null;
    onAdBlockedByLimit = null;
    onAdTechnicalError = null;
    onAdCacheStatus = null;
  }
}

final Set<FastAdUnitInterceptor> interceptors = {};
