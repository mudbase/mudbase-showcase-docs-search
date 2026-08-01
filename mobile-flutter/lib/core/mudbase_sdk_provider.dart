import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mudbase_sdk/mudbase_sdk.dart';

import '../config/env_config.dart';

/// The single shared [MudbaseSdk] instance for the app - one `Dio` client,
/// one `Serializers` registry.
///
/// Every Mudbase call in this app (auth, documents/search_log) goes through
/// `sdk.dio` directly rather than the generated per-domain `*Api` wrapper
/// classes (`AuthenticationApi`, `MultiRoleFeatureApi`, `DataApi`). That is a
/// deliberate, documented choice ported from the sibling kanban/social/
/// ecommerce Flutter apps - see `auth_service.dart` and
/// `mudbase_data_service.dart` for exactly why each wrapper's typed response
/// model is inadequate for this real deployment.
final mudbaseSdkProvider = Provider<MudbaseSdk>((ref) {
  return MudbaseSdk(basePathOverride: EnvConfig.mudbaseBaseUrl);
});
