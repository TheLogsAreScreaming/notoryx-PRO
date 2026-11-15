import 'package:flutter/widgets.dart';

/// [padding] plus the system's bottom inset (navigation bar, gesture bar).
///
/// A list that sets its own padding loses the inset Flutter would otherwise
/// add, so with Android drawing edge to edge its last rows end up behind the
/// navigation bar and can't be scrolled into view.
EdgeInsets withBottomInset(BuildContext context, EdgeInsets padding) =>
    padding + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom);
