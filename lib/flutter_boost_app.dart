import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_boost/messages.dart';
import 'package:flutter_boost/boost_flutter_router_api.dart';
import 'package:flutter_boost/logger.dart';
import 'package:flutter_boost/boost_navigator.dart';
import 'package:flutter_boost/page_visibility.dart';

import 'page_visibility.dart';

final navigatorKey = GlobalKey<NavigatorState>();

typedef FlutterBoostAppBuilder = Widget Function(Widget home);

typedef FlutterBoostRouteFactory = Route<dynamic> Function(
    RouteSettings settings, String uniqueId);

///
/// 生成UniqueId
///
String getUniqueId(String pageName) {
  return '${DateTime.now().millisecondsSinceEpoch}_$pageName';
}

///
///
///
///
class FlutterBoostApp extends StatefulWidget {
  const FlutterBoostApp(this.routeFactory,
      {FlutterBoostAppBuilder appBuilder, String initialRoute, this.observers})
      : appBuilder = appBuilder ?? _materialAppBuilder,
        initialRoute = initialRoute ?? '/';

  final FlutterBoostRouteFactory routeFactory;
  final FlutterBoostAppBuilder appBuilder;
  final List<NavigatorObserver> observers;
  final String initialRoute;

  static Widget _materialAppBuilder(Widget home) {
    return MaterialApp(home: home);
  }

  @override
  State<StatefulWidget> createState() => FlutterBoostAppState();
}

class FlutterBoostAppState extends State<FlutterBoostApp> {
  List<BoostContainer<dynamic>> get containers => _containers;
  final List<BoostContainer<dynamic>> _containers = [];

  BoostContainer get topContainer => containers.last;

  NativeRouterApi get nativeRouterApi => _nativeRouterApi;
  NativeRouterApi _nativeRouterApi;

  BoostFlutterRouterApi get boostFlutterRouterApi => _boostFlutterRouterApi;
  BoostFlutterRouterApi _boostFlutterRouterApi;

  FlutterBoostRouteFactory get routeFactory => widget.routeFactory;

  @override
  void initState() {
    _containers.add(_createContainer(PageInfo(pageName: widget.initialRoute)));
    _nativeRouterApi = NativeRouterApi();
    _boostFlutterRouterApi = BoostFlutterRouterApi.instance(this);
    super.initState();
  }

  ///     1. onWillPop 先从父层收到事件，再到子层.
  ///     当子层返回 false 时候。父的maybePop 才会true.
  ///     当子层返回 true 时候。父的maybePop 才会false.
  ///
  @override
  Widget build(BuildContext context) {
    return widget.appBuilder(WillPopScope(
        onWillPop: () async {
          bool canPop = topContainer.navigator.canPop();
          if (canPop) {
            topContainer.navigator.pop();
            return true;
          }
          return false;
        },
        child: Navigator(
            key: navigatorKey,
            pages: List.of(_containers),
            onPopPage: _onPopPage)));
  }

  bool _onPopPage(Route<dynamic> route, dynamic result) {
    return false;
  }

  ///
  /// 创建页面
  BoostContainer _createContainer(PageInfo pageInfo) {
    pageInfo.uniqueId ??= getUniqueId(pageInfo.pageName);
    return BoostContainer<dynamic>(
        key: ValueKey(pageInfo.uniqueId),
        pageInfo: pageInfo,
        routeFactory: widget.routeFactory,
        observers: widget.observers);
  }

  void push(String pageName,
      {String uniqueId, Map arguments, bool withContainer}) {
    final BoostContainer existed = _findContainerByUniqueId(uniqueId);
    Logger.log(
        'push page, uniqueId=$uniqueId, existed=$existed, withContainer=$withContainer, arguments:$arguments, $containers');
    if (existed != null) {
      if (topContainer?.pageInfo?.uniqueId != uniqueId) {
        setState(() {
          containers.remove(existed);
          containers.add(existed);
        });
        PageVisibilityBinding.instance
            .onAppear(_getCurrentPage(), ChangeReason.routeReorder);
        if (containers.length > 1) {
          String prevPage = containers[containers.length - 2]
              ?.pages
              ?.last
              ?.pageInfo
              ?.uniqueId;
          PageVisibilityBinding.instance
              .onDisappear(prevPage, ChangeReason.routeReorder);
        }
      }
    } else {
      PageInfo pageInfo = PageInfo(
          pageName: pageName,
          uniqueId: uniqueId ?? getUniqueId(pageName),
          arguments: arguments,
          withContainer: withContainer);
      if (withContainer) {
        setState(() {
          containers.add(_createContainer(pageInfo));
        });
        PageVisibilityBinding.instance
            .onAppear(_getCurrentPage(), ChangeReason.routePushed);
        if (containers.length > 1) {
          String prevPage = containers[containers.length - 2]
              ?.pages
              ?.last
              ?.pageInfo
              ?.uniqueId;
          PageVisibilityBinding.instance
              .onDisappear(prevPage, ChangeReason.routePushed);
        }
      } else {
        setState(() {
          topContainer.pages
              .add(BoostPage.create(pageInfo, topContainer.routeFactory));
        });
      }
    }
  }

  ///
  /// 关闭操作
  ///
  void pop({String uniqueId, Map arguments}) async {
    BoostContainer container;
    if (uniqueId != null) {
      container = _findContainerByUniqueId(uniqueId);
      if (container == null) {
        Logger.error('uniqueId=$uniqueId not find');
        return;
      }
      if (container != topContainer) {
        _removeContainer(container);
        return;
      }
    } else {
      container = topContainer;
    }

    final bool handled = await container?.navigator?.maybePop();
    if (handled != null && !handled) {
      if (_getCurrentPage() == container?.pageInfo?.uniqueId) {
        PageVisibilityBinding.instance
            .onDisappear(_getCurrentPage(), ChangeReason.routePopped);
        if (containers.length > 1) {
          String prevPage = containers[containers.length - 2]
              ?.pages
              ?.last
              ?.pageInfo
              ?.uniqueId;
          PageVisibilityBinding.instance
              .onAppear(prevPage, ChangeReason.routePushed);
        }
      }
      assert(container.pageInfo.withContainer);
      CommonParams params = CommonParams()
        ..pageName = container.pageInfo.pageName
        ..uniqueId = container.pageInfo.uniqueId
        ..arguments = arguments;
      _nativeRouterApi.popRoute(params);
    }
    Logger.log(
        'pop container, uniqueId=$uniqueId, arguments:$arguments, $container');
  }

  void _removeContainer(BoostPage page) {
    containers.remove(page);
    if (page.pageInfo.withContainer) {
      Logger.log('pop container ,  uniqueId=${page.pageInfo.uniqueId}');
      CommonParams params = CommonParams()
        ..pageName = page.pageInfo.pageName
        ..uniqueId = page.pageInfo.uniqueId
        ..arguments = page.pageInfo.arguments;
      _nativeRouterApi.popRoute(params);
    }
  }

  void onForeground() {
    PageVisibilityBinding.instance.onForeground(_getCurrentPage());
  }

  void onBackground() {
    PageVisibilityBinding.instance.onBackground(_getCurrentPage());
  }

  String _getCurrentPage() {
    return topContainer?.pages.last?.pageInfo?.uniqueId;
  }

  bool _isCurrentPage(String uniqueId) {
    return topContainer?.pageInfo?.uniqueId == uniqueId;
  }

  BoostContainer _findContainerByUniqueId(String uniqueId) {
    return containers.singleWhere(
        (BoostContainer element) => element.pageInfo.uniqueId == uniqueId,
        orElse: () {});
  }

  void remove(String uniqueId) {
    if (uniqueId == null) return;
    final BoostContainer container = _findContainerByUniqueId(uniqueId);
    if (container != null) {
      setState(() {
        containers.removeWhere((entry) => entry.pageInfo?.uniqueId == uniqueId);
      });
    } else {
      setState(() {
        containers.forEach((container) {
          container.pages
              .removeWhere((entry) => entry.pageInfo?.uniqueId == uniqueId);
        });
      });
    }
    Logger.log('remove,  uniqueId=$uniqueId, $containers');
  }

  PageInfo getTopPageInfo() {
    return topContainer?.pages.last?.pageInfo;
  }

  int pageSize() {
    int count = 0;
    containers.forEach((entry) {
      count += entry.pages.length;
    });
    return count;
  }
}

///
/// boost定义的page
///
class BoostPage<T> extends Page<T> {
  BoostPage({LocalKey key, this.routeFactory, this.pageInfo})
      : super(key: key, name: pageInfo.pageName, arguments: pageInfo.arguments);

  final FlutterBoostRouteFactory routeFactory;
  final PageInfo pageInfo;

  static BoostPage create(
      PageInfo pageInfo, FlutterBoostRouteFactory routeFactory) {
    return BoostPage<dynamic>(
        key: UniqueKey(), pageInfo: pageInfo, routeFactory: routeFactory);
  }

  @override
  String toString() =>
      '${objectRuntimeType(this, 'BoostPage')}(name:$name, uniqueId:${pageInfo.uniqueId}, arguments:$arguments)';

  @override
  Route<T> createRoute(BuildContext context) {
    return routeFactory(this, pageInfo.uniqueId);
  }
}

class _BoostNavigatorObserver extends NavigatorObserver {
  final List<NavigatorObserver> observers;
  _BoostNavigatorObserver(this.observers);

  @override
  void didPush(Route<dynamic> route, Route<dynamic> previousRoute) {
    observers?.forEach((element) {
      element.didPush(route, previousRoute);
    });

    //handle internal route
    if (previousRoute != null) {
      PageVisibilityBinding.instance
          .onAppearWithRoute(route, ChangeReason.routePushed);
      PageVisibilityBinding.instance
          .onDisappearWithRoute(previousRoute, ChangeReason.routePushed);
    }
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic> previousRoute) {
    observers?.forEach((element) {
      element.didPop(route, previousRoute);
    });

    if (previousRoute != null) {
      PageVisibilityBinding.instance
          .onDisappearWithRoute(route, ChangeReason.routePopped);
      PageVisibilityBinding.instance
          .onAppearWithRoute(previousRoute, ChangeReason.routePopped);
    }
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic> previousRoute) {
    observers?.forEach((element) {
      element.didRemove(route, previousRoute);
    });
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic> newRoute, Route<dynamic> oldRoute}) {
    observers?.forEach((element) {
      element.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    });
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didStartUserGesture(Route<dynamic> route, Route<dynamic> previousRoute) {
    observers?.forEach((element) {
      element.didStartUserGesture(route, previousRoute);
    });
    super.didStartUserGesture(route, previousRoute);
  }

  @override
  void didStopUserGesture() {
    observers?.forEach((element) {
      element.didStopUserGesture();
    });
    super.didStopUserGesture();
  }
}

class BoostContainer<T> extends BoostPage<T> {
  BoostContainer(
      {LocalKey key,
      FlutterBoostRouteFactory routeFactory,
      PageInfo pageInfo,
      this.observers})
      : super(key: key, routeFactory: routeFactory, pageInfo: pageInfo) {
    pages.add(BoostPage.create(pageInfo, routeFactory));
  }

  List<BoostPage<dynamic>> get pages => _pages;
  final List<BoostPage<dynamic>> _pages = <BoostPage<dynamic>>[];
  final List<NavigatorObserver> observers;

  NavigatorState get navigator => _navKey.currentState;
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  void _updatePagesList() {
    pages.removeLast();
    Logger.log('_updatePagesList,  $pages');
  }

  @override
  String toString() {
    return '${objectRuntimeType(this, 'BoostContainer')}(size:${_pages.length}, pages:$_pages';
  }

  @override
  Route<T> createRoute(BuildContext context) {
    return PageRouteBuilder<T>(
        settings: this,
        pageBuilder: (_, __, ___) {
          return Navigator(
            key: _navKey,
            pages: List.of(_pages),
            onPopPage: (route, dynamic result) {
              if (route.didPop(result)) {
                _updatePagesList();
                return true;
              }
              return false;
            },
            observers: [
              _BoostNavigatorObserver(observers),
            ],
          );
        });
  }
}
