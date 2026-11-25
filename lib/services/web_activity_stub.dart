class WebActivityHooks {
  WebActivityHooks({
    required this.onHidden,
    required this.onVisible,
    required this.onActivity,
  });

  final void Function() onHidden;
  final void Function() onVisible;
  final void Function() onActivity;

  void attach() {}
  void detach() {}
}
