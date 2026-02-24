library fast_ads;

export 'src/app_open_ad.dart';
export 'src/banner_ad.dart';
export 'src/interstitial_ad.dart';
export 'src/rewarded_ad.dart';
export 'src/native_ad.dart';
export 'src/pool/fast_ad_pool.dart';
export 'src/pool/fast_base_ad.dart';
export 'src/config/fast_placement.dart';
export 'src/utils/logger.dart';
export 'src/config/fast_ad_unit_interceptor.dart';
export 'src/utils/UMP.dart';
export 'src/utils/frequency.dart';
import 'package:fast_ads/fast_ads.dart';
import 'package:fast_ads/src/utils/sp_utils.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 广告类型枚举
///
/// 定义 FastAds 库支持的不同广告类型
enum FastAdsType {
  /// 应用启动时展示的开屏广告
  appOpen,

  /// 全屏插屏广告
  interstitial,

  /// 激励视频广告，观看后可获得奖励
  rewarded,

  /// 原生广告，可自定义样式以匹配应用UI
  native,

  /// 横幅广告，在屏幕顶部或底部展示
  banner,

  /// Feed 流广告，用于信息流中展示的原生广告
  feed,
}

/// Fast Ads Manager
///
/// FastAds 库的主入口，提供以下功能：
/// - 初始化广告 SDK
/// - 预加载广告
/// - 按物理广告位展示广告
class FastAds {
  /// 是否全局启用广告
  static bool globalAdEnabled = true;

  /// 广告请求超时时间（毫秒）
  static int adRequestTimeoutMs = 12000;

  /// 按物理广告位名称存储的广告池
  static final pools = <String, FastAdPool>{};

  /// 兜底广告池，当主池无可用广告时使用
  static final fallbackPools = <String, FastAdPool>{};

  /// 高价值广告池，优先展示高价值广告
  static final highValuePools = <String, FastAdPool>{};

  /// 广告位配置缓存
  static final placements = <String, FastPlacement>{};

  /// 初始化 Google Mobile Ads SDK
  ///
  /// 必须在使用任何广告功能之前调用
  ///
  /// [enableUMP] 是否启用 UMP 同意流程（默认 true）
  /// [umpDebug] 是否开启 UMP 调试模式（仅开发环境使用）
  /// [umpTestDeviceIds] UMP 调试时的测试设备 ID 列表
  /// [tagForUnderAgeOfConsent] 是否标记为未成年用户
  /// [umpShowConsentForm] 启动时是否自动弹出同意表单
  static Future<InitializationStatus> initialize({FastAdUnitInterceptor? interceptor}) async {
    await SpUtils.init();
    FastAdsLogger.info('Initializing FastAds SDK');

    // 先处理 UMP 同意流程（如 GDPR），再初始化广告 SDK

    final ad = await MobileAds.instance.initialize();
    FastAdsLogger.info('Mobile Ads SDK initialization complete', ad.adapterStatuses.keys);
    if (interceptor != null) {
      addInterceptor(interceptor);
    }

    return ad;
  }

  /// 主动弹出隐私选项表单（例如设置页里调用）
  static Future<bool> showPrivacyOptionsForm() => UMP.showPrivacyOptionsForm();

  static addInterceptor(FastAdUnitInterceptor interceptor) => interceptors.add(interceptor);

  /// 预加载单个广告位
  ///
  /// 为广告位创建广告池并开始加载广告
  ///
  /// 参数：
  /// - [placement]: 广告位配置
  static FastAdPool? preload(FastPlacement placement) => _preloadToPool(placement, pools);

  /// 预加载兜底广告位
  ///
  /// 参数：
  /// - [placement]: 广告位配置
  static FastAdPool? preloadFallback(FastPlacement placement) =>
      _preloadToPool(placement, fallbackPools, poolType: 'fallback');

  /// 预加载高价值广告位
  ///
  /// 参数：
  /// - [placement]: 广告位配置
  static FastAdPool? preloadHighValue(FastPlacement placement) =>
      _preloadToPool(placement, highValuePools, poolType: 'high value');

  /// 内部方法：预加载广告位到指定池
  static FastAdPool? _preloadToPool(
    FastPlacement placement,
    Map<String, FastAdPool> targetPools, {
    String poolType = 'main',
  }) {
    // 跳过未启用的广告位
    if (!placement.enabled) {
      FastAdsLogger.debug('Skipping disabled $poolType placement: ${placement.name}');
      return null;
    }

    // 跳过没有广告单元的广告位
    if (placement.adUnits.isEmpty) {
      FastAdsLogger.warning('No ad units for $poolType placement: ${placement.name}');
      return null;
    }

    // 缓存广告位配置
    placements[placement.name] = placement;

    // 创建广告池
    final pool = FastAdPool(placement: placement);
    targetPools[placement.name] = pool;

    FastAdsLogger.info(
      'Created $poolType pool for placement: ${placement.name} (adUnits: ${placement.adUnits.length})',
    );
    return pool;
  }

  /// 获取指定广告位的配置
  static FastPlacement? getPlacement(String placementName) {
    return placements[placementName];
  }

  /// 获取指定广告位的广告池
  static FastAdPool? getPool(String placementName) {
    return pools[placementName];
  }

  static FastBannerAd showBanner(FastPlacement placement, {int index = 0}) {
    final pool = pools[placement.name];
    return pool?.ad(index: index) as FastBannerAd;
  }

  /// 展示 Feed 流广告（使用 NativeAd）
  ///
  /// [placement] 广告位配置
  /// [index] 广告索引，用于获取池中指定位置的广告实例
  /// 返回 Native 广告实例，如果不是 Feed/Native 类型则返回 null
  static FastNativeAd showFeed(FastPlacement placement, {int index = 0}) {
    final pool = pools[placement.name];
    return pool?.ad(index: index) as FastNativeAd;
  }

  /// 展示广告
  ///
  /// 展示优先级：
  /// 1. 高价值广告池（如果 preferHighValue 为 true）
  /// 2. 主广告池
  /// 3. 兜底广告池
  ///
  /// 参数：
  /// - [placement]: 广告位配置
  /// - [preferHighValue]: 是否优先使用高价值广告池，默认 true
  static Future<FastBaseAd?> show(FastPlacement placement, {bool preferHighValue = true}) async {
    if (!globalAdEnabled) {
      FastAdsLogger.info('Ad is disabled globally, skipping show: ${placement.name}');
      return null;
    }

    if (!placement.enabled) {
      FastAdsLogger.info('Placement is disabled: ${placement.name}');
      return null;
    }

    FastAdsLogger.info('Attempting to show ad for placement: ${placement.name}');

    final pool = pools[placement.name];
    final highValuePool = highValuePools[placement.name];
    final fallbackPool = fallbackPools[placement.name];

    // 1. 优先尝试高价值广告池
    if (preferHighValue && highValuePool != null && highValuePool.hasReadyAd) {
      FastAdsLogger.info('Found ready high value ad for placement: ${placement.name}');
      return highValuePool.show(placement);
    }

    // 2. 尝试主广告池
    if (pool != null && pool.hasReadyAd) {
      FastAdsLogger.info('Found ready ad for placement: ${placement.name}');
      return pool.show(placement);
    }

    // 3. 尝试兜底广告池
    if (fallbackPool != null && fallbackPool.hasReadyAd) {
      FastAdsLogger.info('Found ready fallback ad for placement: ${placement.name}');
      return fallbackPool.show(placement);
    }

    FastAdsLogger.info('No ready ads available for placement: ${placement.name}');
    return showDirect(placement);
  }

  /// 直接加载并展示广告
  ///
  /// 不从缓存中读取，直接创建新广告实例并加载展示
  ///
  /// 参数：
  /// - [placement]: 广告位配置
  static Future<FastBaseAd?> showDirect(FastPlacement placement) async {
    if (!globalAdEnabled) {
      FastAdsLogger.info('Ad is disabled globally, skipping showDirect: ${placement.name}');
      return null;
    }

    if (!placement.enabled) {
      FastAdsLogger.info('Placement is disabled: ${placement.name}');
      return null;
    }

    final pool = pools[placement.name];
    if (pool != null) {
      FastAdsLogger.info('Direct loading ad for placement: ${placement.name}');
      return await pool.showDirect(placement);
    }

    FastAdsLogger.warning('No pool found for placement: ${placement.name}');
    return null;
  }

  /// 检查广告位是否有可用广告（检查所有池子）
  static bool hasReadyAd(String placementName) {
    return (pools[placementName]?.hasReadyAd ?? false) ||
        (highValuePools[placementName]?.hasReadyAd ?? false) ||
        (fallbackPools[placementName]?.hasReadyAd ?? false);
  }

  /// 检查主广告池是否有可用广告
  static bool hasReadyAdInMain(String placementName) {
    return pools[placementName]?.hasReadyAd ?? false;
  }

  /// 检查高价值广告池是否有可用广告
  static bool hasReadyAdInHighValue(String placementName) {
    return highValuePools[placementName]?.hasReadyAd ?? false;
  }

  /// 检查兜底广告池是否有可用广告
  static bool hasReadyAdInFallback(String placementName) {
    return fallbackPools[placementName]?.hasReadyAd ?? false;
  }

  /// 获取兜底广告池
  static FastAdPool? getFallbackPool(String placementName) {
    return fallbackPools[placementName];
  }

  /// 获取高价值广告池
  static FastAdPool? getHighValuePool(String placementName) {
    return highValuePools[placementName];
  }

  /// 重新加载指定广告位（所有池子）
  static void reload(String placementName) {
    pools[placementName]?.reload();
    highValuePools[placementName]?.reload();
    fallbackPools[placementName]?.reload();
  }

  /// 重新加载所有广告位
  static void reloadAll() {
    for (final pool in pools.values) {
      pool.reload();
    }
    for (final pool in highValuePools.values) {
      pool.reload();
    }
    for (final pool in fallbackPools.values) {
      pool.reload();
    }
  }
}
