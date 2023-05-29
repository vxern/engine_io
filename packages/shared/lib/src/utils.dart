/// Verifies that two [Set]s are equal by checking they contain the same
/// elements.
bool setsEqual(Set a, Set b) {
  if (a.length != b.length) {
    return false;
  }

  for (final element in a) {
    if (!b.contains(element)) {
      return false;
    }
  }

  return true;
}
