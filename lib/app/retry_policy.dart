/// How hard the app tries to deliver a direct message.
///
/// MeshCore: [directAttempts] along the known route, then the route is
/// reset and [floodAttempts] more go by flood, as the official MeshCore app
/// does. Each attempt waits for the radio's suggested timeout (at least
/// [minWait]) plus [extraWait]. Meshtastic retries in the firmware; the app
/// adds [meshtasticResends] fresh sends after a "no acknowledgement" failure
/// and gives up after [meshtasticTimeout] without any news.
class RetryPolicy {
  const RetryPolicy({
    this.directAttempts = 3,
    this.floodAttempts = 2,
    this.minWait = const Duration(seconds: 5),
    this.extraWait = const Duration(seconds: 2),
    this.meshtasticResends = 1,
    this.meshtasticTimeout = const Duration(seconds: 90),
  });

  final int directAttempts;
  final int floodAttempts;
  final Duration minWait;
  final Duration extraWait;
  final int meshtasticResends;
  final Duration meshtasticTimeout;

  /// How long to wait for an acknowledgement after one MeshCore attempt.
  Duration waitFor(int radioTimeoutMs) {
    final radio = Duration(milliseconds: radioTimeoutMs);
    return (radio > minWait ? radio : minWait) + extraWait;
  }
}
