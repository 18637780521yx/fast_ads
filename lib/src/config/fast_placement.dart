import 'package:fast_ads/fast_ads.dart';
import 'package:fast_ads/src/config/fast_ad_unit_interceptor.dart';

/// 物理广告位配置
///
/// 描述单个广告位的配置信息，包括广告单元列表、控制参数等
class FastPlacement {
  /// 广告位名称，如 "ad_open_cold", "ad_feed_banner"
  final String name;

  /// 是否启用该广告位
  final bool enabled;

  /// 广告单元列表
  final List<FastAdUnit> adUnits;

  /// Feed 流广告缓存数量（每个 adUnit 需要创建的实例数）
  /// 用于信息流场景，确保有足够的广告实例可供使用
  final int? feedCacheCount;

  /// 冷却时间间隔（单位：秒）
  /// 用户关闭广告后，到下一次有资格再次看到广告的最小时间间隔
  /// 例如：1800 表示 30 分钟内不会再次显示
  /// 0 或 null 表示没有冷却时间限制
  final int? cooldown;

  /// 当天频次上限
  /// 单个用户自然日内看到广告的最大次数
  /// 例如：3 表示每日最多展示 3 次，达到后当日不再展示
  /// 0 或 null 表示没有上限
  final int? dailyCap;

  /// 是否有其他广告单元可以获得奖励
  bool canEarnReward(FastAdUnit unit) =>
      adUnits.firstOrNull?.adType == FastAdsType.rewarded && !unit.isMaxHighPriority;

  /// 主广告单元，优先级最高的广告单元
  FastAdUnit get mainAdUnit => adUnits.first;

  /// 是否为横幅广告位
  bool get isBanner => mainAdUnit.adType == FastAdsType.banner;

  /// 是否为 Feed 流广告位
  bool get isFeed => mainAdUnit.adType == FastAdsType.feed;

  /// 获取有效的冷却时间（秒）
  /// 如果 placement 未配置，则根据广告类型返回默认值
  int get effectiveCooldown {
    if (cooldown != null) return cooldown!;
    // 根据广告类型返回默认值
    switch (mainAdUnit.adType) {
      case FastAdsType.appOpen:
        return 1800; // 开屏广告默认 30 分钟
      case FastAdsType.interstitial:
        return 60; // 插屏广告默认 1 分钟
      case FastAdsType.rewarded:
        return 0; // 激励视频默认无冷却
      default:
        return 0; // 其他类型默认无冷却
    }
  }

  /// 获取有效的每日上限
  /// 如果 placement 未配置，则根据广告类型返回默认值
  int get effectiveDailyCap {
    if (dailyCap != null) return dailyCap!;
    // 根据广告类型返回默认值
    switch (mainAdUnit.adType) {
      case FastAdsType.appOpen:
        return 3; // 开屏广告默认每日 3 次
      case FastAdsType.interstitial:
        return 5; // 插屏广告默认每日 5 次
      case FastAdsType.rewarded:
        return 0; // 激励视频默认无上限
      default:
        return 0; // 其他类型默认无上限
    }
  }

  FastPlacement({
    required this.name,
    required this.enabled,
    required this.adUnits,
    this.feedCacheCount,
    this.cooldown,
    this.dailyCap,
  }) {
    /// 按优先级排序，priority 值越小优先级越高
    adUnits.sort((a, b) => a.priority.compareTo(b.priority));

    /// 引用一下父类
    for (var element in adUnits) {
      element.placementReference = WeakReference(this);
    }
  }

  /// 从 JSON 创建广告位配置
  ///
  /// 支持两种格式：
  /// 1. 直接包含 adUnits 数组的格式（新格式）
  /// 2. 通过 type 和 adUnitsByType 获取广告单元的格式（旧格式）
  ///
  /// [json] 广告位 JSON 数据
  /// [adUnitsByType] 按广告类型分组的广告单元映射（可选，用于旧格式）
  factory FastPlacement.fromJson(
    Map<String, dynamic> json, [
    Map<String, List<FastAdUnit>>? adUnitsByType,
  ]) {
    // 优先使用 JSON 中直接包含的 adUnits
    List<FastAdUnit> adUnits;
    if (json['adUnits'] != null) {
      // 新格式：直接包含 adUnits 数组
      final adUnitsJson = json['adUnits'] as List<dynamic>;
      adUnits = adUnitsJson.map((e) => FastAdUnit.fromJson(e as Map<String, dynamic>)).toList();
    } else if (adUnitsByType != null) {
      // 旧格式：通过 type 从 adUnitsByType 获取
      final typeStr = json['type'] as String? ?? '';
      adUnits = adUnitsByType[typeStr] ?? [];
    } else {
      adUnits = [];
    }

    return FastPlacement(
      name: json['name'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      adUnits: adUnits,
      feedCacheCount: json['feed_cache_count'] as int?,
      cooldown: json['cooldown'] as int?,
      dailyCap: json['daily_cap'] as int?,
    );
  }

  @override
  String toString() => 'FastPlacement($name,  enabled: $enabled, adUnits: ${adUnits.length})';
}

/// 广告单元配置
///
/// 描述单个广告单元的详细信息，包括ID、优先级、平台等
class FastAdUnit extends FastAdUnitInterceptor {
  /// 广告位
  WeakReference<FastPlacement>? placementReference;

  /// 实际广告位
  WeakReference<FastPlacement>? realPlacementReference;

  FastPlacement? get realPlacement => realPlacementReference?.target;
  FastPlacement? get placement => placementReference?.target;

  /// 广告单元ID
  final String adUnitId;

  /// 优先级，数值越小优先级越高
  final int priority;

  /// 广告单元名称，用于标识和日志
  final String name;

  /// 目标平台：ios / android
  final String platform;

  /// 聚合平台：admob / max / topon 等
  final String mediation;

  /// 广告类型：app_open / interstitial / rewarded / banner / native
  final FastAdsType adType;

  /// 原始广告类型字符串（解析前的值）
  final String rawAdType;

  /// 底价，用于 waterfall 竞价
  final double floorPrice;

  /// 请求超时时间（毫秒）
  final int timeoutMs;

  /// 请求时长（毫秒）- 从开始请求到加载完成/失败的时间
  int? requestDuration;

  /// 重试次数 - 从 FastBaseAd 中计算得出
  int retryCount;

  /// 广告展示时长（毫秒）- 从开始展示到关闭的时间
  int? displayDuration;

  bool get isMaxHighPriority => priority == 1;

  FastAdUnit({
    required this.adUnitId,
    this.priority = 0,
    this.name = '',
    this.platform = '',
    this.mediation = 'admob',
    this.adType = FastAdsType.banner,
    this.rawAdType = '',
    this.floorPrice = 0.0,
    this.timeoutMs = 5000,
    this.requestDuration,
    this.displayDuration,
    this.retryCount = 0,
  });

  /// 从字符串解析广告类型
  static FastAdsType? parseAdType(String? type) {
    switch (type) {
      case 'app_open':
      case 'open':
        return FastAdsType.appOpen;
      case 'interstitial':
      case 'rewarded_interstitial':
        return FastAdsType.interstitial;
      case 'rewarded':
        return FastAdsType.rewarded;
      case 'native':
        return FastAdsType.native;
      case 'banner':
      case 'banner_adaptive':
      case 'banner_fixed':
        return FastAdsType.banner;
      case 'feed':
      case 'feed_ad':
        return FastAdsType.feed;
      default:
        return null;
    }
  }

  /// 从 JSON 创建广告单元
  factory FastAdUnit.fromJson(Map<String, dynamic> json) {
    final rawAdType = json['ad_type'] as String? ?? json['name'] as String? ?? '';
    return FastAdUnit(
      adUnitId: json['ad_unit_id'] as String? ?? json['id'] as String? ?? '',
      priority: json['priority'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      mediation: json['mediation'] as String? ?? 'admob',
      adType: parseAdType(rawAdType) ?? FastAdsType.banner,
      rawAdType: rawAdType,
      floorPrice: (json['floor_price'] as num?)?.toDouble() ?? 0.0,
      timeoutMs: json['timeout_ms'] as int? ?? 5000,
      requestDuration: json['request_duration'] as int?,
      displayDuration: json['display_duration'] as int?,
      retryCount: json['retry_count'] as int? ?? 0,
    );
  }

  /// 复制一个 FastAdUnit 并可选地覆盖回调
  FastAdUnit copyWith({int? requestDuration, int? displayDuration, int? retryCount}) {
    return FastAdUnit(
      adUnitId: adUnitId,
      priority: priority,
      name: name,
      platform: platform,
      mediation: mediation,
      adType: adType,
      rawAdType: rawAdType,
      floorPrice: floorPrice,
      timeoutMs: timeoutMs,
      requestDuration: requestDuration ?? this.requestDuration,
      displayDuration: displayDuration ?? this.displayDuration,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  @override
  String toString() => 'FastAdUnit($name: $adUnitId, priority: $priority)';
}
