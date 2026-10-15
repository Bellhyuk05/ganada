import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/team_features.dart';
import 'ride_chat_page.dart';
import 'ride_flow_repository.dart';
import 'ride_manage_page.dart';

/// Connects F-04 참여 신청·승인, F-05 그룹 채팅, F-06 출발·도착 확인 to the shared app.
///
/// Bindings already supplied by other features in [base] are kept, so teammates can chain:
/// `attachRideFlow(client, TeamFeatureBindings(onCreateRide: ...))`.
TeamFeatureBindings attachRideFlow(
  SupabaseClient client, [
  TeamFeatureBindings base = const TeamFeatureBindings(),
]) {
  final repository = RideFlowRepository(client);
  return TeamFeatureBindings(
    authenticationBuilder: base.authenticationBuilder,
    accountBuilder: base.accountBuilder,
    onCreateRide: base.onCreateRide,
    onSearchNearby: base.onSearchNearby,
    onRequestJoin: repository.requestJoin,
    applicantsBuilder: (context, ride) => RideManagePage(
      key: ValueKey('manage-${ride.ride.id}'),
      repository: repository,
      rideContext: ride,
    ),
    chatBuilder: (context, ride) => RideChatPage(
      key: ValueKey('chat-${ride.ride.id}'),
      repository: repository,
      rideContext: ride,
    ),
    onConfirmBoarding: repository.confirmBoarding,
    onConfirmArrival: repository.confirmArrival,
  );
}
