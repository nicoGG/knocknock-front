import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:nocknock/core/config/app_config.dart';
import 'package:nocknock/features/auth/data/auth_repository.dart';
import 'package:nocknock/features/auth/domain/app_user.dart';

class PlusStatus {
  const PlusStatus({
    required this.active,
    required this.purchasesEnabled,
    this.limitsEnforced = false,
    this.ownedLists = 0,
    this.storageBytes = 0,
    this.listLimit = 5,
    this.storageLimit = 104857600,
    this.termsUrl = '',
    this.privacyUrl = '',
  });
  factory PlusStatus.fromJson(Map<String, dynamic> data) {
    final usage = data['usage'] as Map? ?? const {};
    final limits = data['limits'] as Map? ?? const {};
    return PlusStatus(
      active: data['plan'] == 'plus',
      purchasesEnabled: data['purchasesEnabled'] == true,
      limitsEnforced: data['limitsEnforced'] == true,
      ownedLists: (usage['ownedLists'] as num?)?.toInt() ?? 0,
      storageBytes: (usage['storageBytes'] as num?)?.toInt() ?? 0,
      listLimit: (limits['ownedLists'] as num?)?.toInt() ?? 5,
      storageLimit: (limits['storageBytes'] as num?)?.toInt() ?? 104857600,
      termsUrl: data['termsUrl'] as String? ?? '',
      privacyUrl: data['privacyUrl'] as String? ?? '',
    );
  }
  final bool active, purchasesEnabled, limitsEnforced;
  final int ownedLists, storageBytes, listLimit, storageLimit;
  final String termsUrl, privacyUrl;
}

class PlusPackage {
  const PlusPackage(this.product, this.basePlanId, this.offerToken);
  final ProductDetails product;
  final String basePlanId, offerToken;
  bool get annual => basePlanId == 'yearly';
}

/// One listener per authenticated app session, alive even when PlusPage closes.
class PlusService extends ChangeNotifier with WidgetsBindingObserver {
  PlusService._(this.auth);
  static final _instances = Expando<PlusService>();
  factory PlusService(AuthRepository auth) =>
      _instances[auth] ??= PlusService._(auth);
  final AuthRepository auth;
  static const productId = 'nocknock_plus';
  static const _billingEnabled = bool.fromEnvironment(
    'GOOGLE_PLAY_BILLING_ENABLED',
  );
  bool get storeAvailable =>
      _billingEnabled &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;
  StreamSubscription<List<PurchaseDetails>>? _purchases;
  StreamSubscription<AppUser?>? _auth;
  Future<void> _queue = Future.value();
  PlusStatus? latestStatus;
  String? message;

  void start() {
    if (!storeAvailable || _purchases != null) return;
    WidgetsBinding.instance.addObserver(this);
    _purchases = InAppPurchase.instance.purchaseStream.listen(
      (updates) {
        _queue = _queue.then((_) => _handle(updates)).catchError((Object _) {
          message = 'No pudimos verificar la compra. Usa Restaurar compras para volver a intentarlo.';
          notifyListeners();
        });
      },
      onError: (Object _) {
        message =
            'Google Play no pudo completar la operación. Inténtalo de nuevo.';
        notifyListeners();
      },
    );
    _auth = auth.authStateChanges.listen((_) {
      latestStatus = null;
      if (auth.currentUser != null) unawaited(_recover());
    });
    if (auth.currentUser != null) unawaited(_recover());
  }

  Future<void> _recover() async {
    try {
      await restore();
    } catch (_) {
      /* Keep the receipt pending until retry. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && auth.currentUser != null) {
      unawaited(_recover());
    }
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uid = auth.currentUser?.id;
    final token = await auth.getIdToken();
    if (uid == null || token == null || auth.currentUser?.id != uid) {
      throw StateError('Inicia sesión con la cuenta que usaste al comprar.');
    }
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    try {
      final response = body == null
          ? await dio.get<Map<String, dynamic>>(path)
          : await dio.post<Map<String, dynamic>>(path, data: body);
      if (auth.currentUser?.id != uid) throw StateError('Tu sesión cambió.');
      return response.data!;
    } finally {
      dio.close();
    }
  }

  Future<PlusStatus> status() async {
    final result = PlusStatus.fromJson(await _request('/subscriptions/me'));
    latestStatus = result;
    return result;
  }

  Future<List<PlusPackage>> packages() async {
    if (!storeAvailable || !await InAppPurchase.instance.isAvailable()) {
      return [];
    }
    final response = await InAppPurchase.instance.queryProductDetails({
      productId,
    });
    if (response.error != null) {
      throw StateError('No pudimos cargar los precios de Google Play.');
    }
    final packages = <PlusPackage>[];
    for (final product
        in response.productDetails.whereType<GooglePlayProductDetails>()) {
      final index = product.subscriptionIndex;
      final offers = product.productDetails.subscriptionOfferDetails;
      if (index == null || offers == null) continue;
      final offer = offers[index];
      if (offer.offerId != null ||
          !{'monthly', 'yearly'}.contains(offer.basePlanId)) {
        continue;
      }
      packages.add(PlusPackage(product, offer.basePlanId, offer.offerIdToken));
    }
    packages.sort((a, b) => a.annual ? -1 : (b.annual ? 1 : 0));
    return packages;
  }

  Future<void> purchase(PlusPackage package) async {
    start();
    final current = await status();
    if (!current.purchasesEnabled || current.active || !storeAvailable) {
      throw StateError(
        'La compra de Plus no está disponible para esta cuenta.',
      );
    }
    final uid = auth.currentUser!.id;
    final hash = await Sha256().hash(utf8.encode(uid));
    if (auth.currentUser?.id != uid) throw StateError('Tu sesión cambió.');
    final started = await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: GooglePlayPurchaseParam(
        productDetails: package.product,
        offerToken: package.offerToken,
        applicationUserName: hash.bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(),
      ),
    );
    if (!started) throw StateError('Google Play no pudo iniciar la compra.');
  }

  Future<void> _handle(List<PurchaseDetails> updates) async {
    for (final purchase in updates) {
      try {
        await _handlePurchase(purchase);
      } catch (error) {
        final data = error is DioException ? error.response?.data : null;
        message = data is Map && data['message'] is String
            ? data['message'] as String
            : 'No pudimos verificar la compra. Usa Restaurar compras para volver a intentarlo.';
      }
      notifyListeners();
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    if (purchase.productID != productId) return;
    if (purchase.status == PurchaseStatus.pending) {
      message = 'El pago está pendiente de confirmación en Google Play.';
    } else if (purchase.status == PurchaseStatus.canceled) {
      message = 'La compra fue cancelada.';
    } else if (purchase.status == PurchaseStatus.error) {
      message = 'Google Play no pudo completar la compra. Inténtalo de nuevo.';
    } else if (auth.currentUser != null) {
      // The server verifies Play state, product, expiry and hashed Firebase UID.
      // Never acknowledge an unverified receipt or a receipt for another account.
      final data = await _request(
        '/subscriptions/google-play/verify',
        body: {
          'purchaseToken': purchase.verificationData.serverVerificationData,
        },
      );
      if (data['plan'] != 'plus') throw StateError('Compra sin verificar.');
      // The backend acknowledges with Google before returning Plus. Do not
      // acknowledge the same receipt twice through BillingClient here.
      await status();
      message = 'Tu suscripción NockNock Plus está activa.';
    }
  }

  Future<void> restore() async {
    start();
    if (!storeAvailable || auth.currentUser == null) return;
    if (!await InAppPurchase.instance.isAvailable()) return;
    final uid = auth.currentUser!.id;
    final hash = await Sha256().hash(utf8.encode(uid));
    if (auth.currentUser?.id != uid) return;
    await InAppPurchase.instance.restorePurchases(
      applicationUserName: hash.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(),
    );
  }

  Future<Uri?> managementUrl() async => Uri.https(
    'play.google.com',
    '/store/account/subscriptions',
    {'sku': productId, 'package': 'cl.nocknock.app'},
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_purchases?.cancel());
    unawaited(_auth?.cancel());
    super.dispose();
  }
}
