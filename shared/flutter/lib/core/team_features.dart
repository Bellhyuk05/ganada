import 'package:flutter/material.dart';

import '../features/companion/models.dart';

enum RideCategory { taxi, carpool }

/// User-entered values only. The team's server creates the ID and host membership.
class RideDraft {
  const RideDraft({
    required this.category,
    required this.originName,
    required this.destinationName,
    required this.departureAt,
    required this.capacity,
    required this.conditionText,
  });

  // The team's creation API must store or reject the selected category explicitly.
  // The shared baseline has no category column, so this app never writes it directly.
  final RideCategory category;
  final String originName;
  final String destinationName;
  final DateTime departureAt;
  final int capacity;
  final String conditionText;
}

/// Context for team-owned screens. Keep authorization and writes on their server.
class TeamRideContext {
  const TeamRideContext({
    required this.ride,
    required this.userId,
    required this.onBack,
    required this.onRefresh,
    required this.onRatings,
  });

  final RideRecord ride;
  final String userId;
  final VoidCallback onBack;
  final Future<void> Function() onRefresh;
  final VoidCallback onRatings;
}

typedef TeamRideScreenBuilder = Widget Function(
  BuildContext context,
  TeamRideContext rideContext,
);

/// Connect these in main() when a teammate's implementation is available.
/// Null means unavailable; the app never substitutes fake success or data.
class TeamFeatureBindings {
  const TeamFeatureBindings({
    this.authenticationBuilder,
    this.accountBuilder,
    this.onCreateRide,
    this.onRequestJoin,
    this.chatBuilder,
    this.applicantsBuilder,
    this.onConfirmBoarding,
    this.onConfirmArrival,
    this.onSearchNearby,
  });

  /// F-01 can replace the login screen with signup and school verification.
  final WidgetBuilder? authenticationBuilder;
  final WidgetBuilder? accountBuilder;

  /// Return the actual server-created ride ID. No local ride is inserted.
  final Future<String> Function(RideDraft draft)? onCreateRide;
  final Future<void> Function(String rideId)? onRequestJoin;

  /// The team owns message loading, realtime subscriptions and sending.
  final TeamRideScreenBuilder? chatBuilder;
  final TeamRideScreenBuilder? applicantsBuilder;
  final Future<void> Function(String rideId)? onConfirmBoarding;
  final Future<void> Function(String rideId)? onConfirmArrival;

  /// Return IDs from real location search; null means the selection was canceled.
  final Future<Set<String>?> Function(BuildContext context)? onSearchNearby;
}
