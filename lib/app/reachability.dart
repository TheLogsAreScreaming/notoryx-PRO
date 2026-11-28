/// How well the app can communicate with one direct-message contact.
///
/// Derived entirely from stored messages — no transmissions are made.
enum Reachability {
  /// We have received at least one message from this contact, or one of
  /// our messages was explicitly acked (delivered) by them.
  twoWay,

  /// At least one of our messages reached the radio for transmission, but
  /// we have not heard back and have no inbound messages from this contact.
  theyHeardYou,

  /// No messages have been sent yet, or every sent message failed.
  noAnswerYet,
}
