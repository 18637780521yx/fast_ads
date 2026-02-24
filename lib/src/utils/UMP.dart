import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class UMP {
  static const _defaultDebugGeography = DebugGeography.debugGeographyEea;

  /// 在应用启动时检查用户同意状态，处理调试参数并可选地展示同意表单。
  static Future<bool> checkConsentOnLaunch({
    bool isDebug = false,
    List<String>? testDeviceIds,
    bool tagForUnderAgeOfConsent = false,
    bool showConsentForm = true,
  }) async {
    final params = ConsentRequestParameters(
      tagForUnderAgeOfConsent: tagForUnderAgeOfConsent,
      consentDebugSettings:
          isDebug
              ? ConsentDebugSettings(
                debugGeography: _defaultDebugGeography,
                testIdentifiers: testDeviceIds,
              )
              : null,
    );

    final completer = Completer<bool>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        final status = await consentStatus();
        final available = await isConsentFormAvailable();
        if (status == ConsentStatus.required && available && showConsentForm) {
          try {
            await loadAndShowConsentFormIfRequired();
          } catch (e) {
            completer.completeError('Failed to show consent form: $e');
            return;
          }
        }
        completer.complete(true);
      },
      (error) {
        completer.completeError('Failed to update consent info: ${error.message}');
      },
    );
    return completer.future;
  }

  /// 如果需要，自动加载并展示同意表单。
  static Future<void> loadAndShowConsentFormIfRequired() async {
    final completer = Completer<void>();
    await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
      if (formError != null) {
        completer.completeError('Failed to load/show consent form: ${formError.message}');
      } else {
        completer.complete();
      }
    });
    return completer.future;
  }

  /// 仅加载同意表单，不展示。
  static Future<ConsentForm> loadConsentForm() async {
    final completer = Completer<ConsentForm>();
    ConsentForm.loadConsentForm(
      (form) => completer.complete(form),
      (error) => completer.completeError('Failed to load consent form: ${error.message}'),
    );
    return completer.future;
  }

  /// 展示已加载的同意表单。
  static Future<void> showConsentForm(ConsentForm form) async {
    final completer = Completer<void>();
    form.show((formError) {
      if (formError != null) {
        completer.completeError('Failed to show consent form: ${formError.message}');
      } else {
        completer.complete();
      }
    });
    return completer.future;
  }

  /// 展示隐私选项表单（例如用于隐私设置入口）。
  static Future<bool> showPrivacyOptionsForm() async {
    final completer = Completer<bool>();
    try {
      await ConsentForm.showPrivacyOptionsForm((error) {
        completer.completeError('Failed to show privacy options form: ${error.toString()}');
      });
      completer.complete(true);
    } catch (e) {
      completer.completeError('Failed to show privacy options form: ${e.toString()}');
    }
    return completer.future;
  }

  /// 获取当前同意状态。
  static Future<ConsentStatus> consentStatus() {
    return ConsentInformation.instance.getConsentStatus();
  }

  /// 检查同意表单是否可用。
  static Future<bool> isConsentFormAvailable() =>
      ConsentInformation.instance.isConsentFormAvailable();

  /// 检查是否可以请求广告。
  static Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  /// 检查是否需要隐私选项。
  static Future<bool> isRequirementPrivacyOptions() async {
    return await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
  }

  /// 重置同意信息（例如用于重新触发同意表单）。
  static Future<void> reset() async {
    await ConsentInformation.instance.reset();
  }
}
