import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account.dart';

final accountProvider = Provider<AccountController>((ref) {
  final controller = AccountController();
  ref.onDispose(controller.dispose);
  controller.initialize();
  return controller;
});
