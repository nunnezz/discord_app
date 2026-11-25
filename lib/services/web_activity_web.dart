import 'dart:html' as html show document, EventListener;

const _activityEvents = [
  'mousemove',
  'keydown',
  'click',
  'scroll',
  'touchstart'
];

class WebActivityHooks {
  WebActivityHooks({
    required this.onHidden,
    required this.onVisible,
    required this.onActivity,
  });

  final void Function() onHidden;
  final void Function() onVisible;
  final void Function() onActivity;

  html.EventListener? _visibilityListener;
  html.EventListener? _activityListener;

  void attach() {
    _visibilityListener = (event) {
      if (html.document.visibilityState == 'hidden') {
        onHidden();
      } else {
        onVisible();
      }
    };
    html.document.addEventListener('visibilitychange', _visibilityListener);

    _activityListener = (_) => onActivity();
    for (final type in _activityEvents) {
      html.document.addEventListener(type, _activityListener);
    }
  }

  void detach() {
    if (_visibilityListener != null) {
      html.document
          .removeEventListener('visibilitychange', _visibilityListener!);
    }
    if (_activityListener != null) {
      for (final type in _activityEvents) {
        html.document.removeEventListener(type, _activityListener!);
      }
    }
  }
}
