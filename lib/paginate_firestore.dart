library paginate_firestore;

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'bloc/pagination_cubit.dart';
import 'bloc/pagination_listeners.dart';
import 'widgets/bottom_loader.dart';
import 'widgets/empty_display.dart';
import 'widgets/empty_separator.dart';
import 'widgets/error_display.dart';
import 'widgets/initial_loader.dart';

class PaginateFirestore extends StatefulWidget {
  const PaginateFirestore({
    Key? key,
    required this.itemBuilder,
    required this.query,
    required this.itemBuilderType,
    this.gridDelegate = const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
    this.startAfterDocument,
    this.itemsPerPage = 15,
    this.onError,
    this.onReachedEnd,
    this.onLoaded,
    this.onEmpty = const EmptyDisplay(),
    this.separator = const EmptySeparator(),
    this.initialLoader = const InitialLoader(),
    this.bottomLoader = const BottomLoader(),
    this.shrinkWrap = false,
    this.reverse = false,
    this.scrollDirection = Axis.vertical,
    this.padding = const EdgeInsets.all(0),
    this.physics,
    this.listeners,
    this.scrollController,
    this.allowImplicitScrolling = false,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.pageController,
    this.onPageChanged,
    this.header,
    this.footer,
    this.statesTransitionAnimationDuration,
    this.isLive = false,
    this.includeMetadataChanges = false,
    this.options,
  }) : super(key: key);

  final Widget bottomLoader;
  final Widget onEmpty;
  final SliverGridDelegate gridDelegate;
  final Widget initialLoader;
  final PaginateBuilderType itemBuilderType;
  final int itemsPerPage;
  final List<ChangeNotifier>? listeners;
  final EdgeInsets padding;
  final ScrollPhysics? physics;
  final Query query;
  final bool reverse;
  final bool allowImplicitScrolling;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;
  final ScrollController? scrollController;
  final PageController? pageController;
  final Axis scrollDirection;
  final Widget separator;
  final bool shrinkWrap;
  final bool isLive;
  final DocumentSnapshot? startAfterDocument;
  final Widget? header;
  final Widget? footer;

  final Duration? statesTransitionAnimationDuration;

  /// Use this only if `isLive = false`
  final GetOptions? options;

  /// Use this only if `isLive = true`
  final bool includeMetadataChanges;

  @override
  State<PaginateFirestore> createState() => _PaginateFirestoreState();

  final Widget Function(Exception)? onError;

  final Widget Function(BuildContext, List<DocumentSnapshot>, int) itemBuilder;

  final void Function(PaginationLoaded)? onReachedEnd;

  final void Function(PaginationLoaded)? onLoaded;

  final void Function(int)? onPageChanged;
}

class _PaginateFirestoreState extends State<PaginateFirestore> {
  PaginationCubit? _cubit;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PaginationCubit, PaginationState>(
      bloc: _cubit,
      builder: (context, state) {
        if (widget.statesTransitionAnimationDuration != null) {
          return AnimatedSwitcher(
            duration: widget.statesTransitionAnimationDuration!,
            child: _buildBody(state),
          );
        } else {
          return _buildBody(state);
        }
      },
    );
  }

  Widget _buildBody(PaginationState state) {
    if (state is PaginationInitial) {
      return Center(
        key: const ValueKey('pagination-initial'),
        child: widget.initialLoader,
      );
    } else if (state is PaginationError) {
      return _buildWithScrollView(
        context,
        (widget.onError != null) ? widget.onError!(state.error) : ErrorDisplay(key: const ValueKey('pagination-error'), exception: state.error),
      );
    } else {
      final loadedState = state as PaginationLoaded;
      if (widget.onLoaded != null) {
        widget.onLoaded!(loadedState);
      }
      if (loadedState.hasReachedEnd && widget.onReachedEnd != null) {
        widget.onReachedEnd!(loadedState);
      }

      if (loadedState.documentSnapshots.isEmpty) {
        return widget.onEmpty;
      }
      return widget.itemBuilderType == PaginateBuilderType.listView
          ? _buildListView(loadedState)
          : widget.itemBuilderType == PaginateBuilderType.gridView
              ? _buildGridView(loadedState)
              : _buildPageView(loadedState);
    }
  }

  Widget _buildWithScrollView(BuildContext context, Widget child) {
    return SingleChildScrollView(
      child: Container(
        alignment: Alignment.center,
        height: MediaQuery.of(context).size.height,
        child: child,
      ),
    );
  }

  @override
  void dispose() {
    widget.scrollController?.dispose();
    _cubit?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    if (widget.listeners != null) {
      for (var listener in widget.listeners!) {
        if (listener is PaginateRefreshedChangeListener) {
          listener.addListener(() {
            if (listener.refreshed) {
              _cubit!.refreshPaginatedList();
            }
          });
        } else if (listener is PaginateFilterChangeListener) {
          listener.addListener(() {
            if (listener.searchTerm.isNotEmpty) {
              _cubit!.filterPaginatedList(listener.searchTerm);
            }
          });
        }
      }
    }

    _cubit = PaginationCubit(
      widget.query,
      widget.itemsPerPage,
      widget.startAfterDocument,
      isLive: widget.isLive,
    )..fetchPaginatedList();
    super.initState();
  }

  Widget _buildGridView(PaginationLoaded loadedState) {
    var gridView = CustomScrollView(
      key: const ValueKey('pagination-custom-grid-view'),
      reverse: widget.reverse,
      controller: widget.scrollController,
      shrinkWrap: widget.shrinkWrap,
      scrollDirection: widget.scrollDirection,
      physics: widget.physics,
      keyboardDismissBehavior: widget.keyboardDismissBehavior,
      slivers: [
        if (widget.header != null) widget.header!,
        SliverPadding(
          padding: widget.padding,
          sliver: SliverGrid(
            gridDelegate: widget.gridDelegate,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= loadedState.documentSnapshots.length) {
                  _cubit!.fetchPaginatedList();
                  return widget.bottomLoader;
                }
                return widget.itemBuilder(
                  context,
                  loadedState.documentSnapshots,
                  index,
                );
              },
              childCount: loadedState.hasReachedEnd ? loadedState.documentSnapshots.length : loadedState.documentSnapshots.length + 1,
            ),
          ),
        ),
        if (widget.footer != null) widget.footer!,
      ],
    );

    if (widget.listeners != null && widget.listeners!.isNotEmpty) {
      return MultiProvider(
        key: const ValueKey('multi-provider-grid-view'),
        providers: widget.listeners!
            .map((listener) => ChangeNotifierProvider(
                  create: (context) => listener,
                ))
            .toList(),
        child: gridView,
      );
    }

    return gridView;
  }

  Widget _buildListView(PaginationLoaded loadedState) {
    var listView = CustomScrollView(
      key: const ValueKey('pagination-custom-list-view'),
      reverse: widget.reverse,
      controller: widget.scrollController,
      shrinkWrap: widget.shrinkWrap,
      scrollDirection: widget.scrollDirection,
      physics: widget.physics,
      keyboardDismissBehavior: widget.keyboardDismissBehavior,
      slivers: [
        if (widget.header != null) widget.header!,
        SliverPadding(
          padding: widget.padding,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final itemIndex = index ~/ 2;
                if (index.isEven) {
                  if (itemIndex >= loadedState.documentSnapshots.length) {
                    _cubit!.fetchPaginatedList();
                    return widget.bottomLoader;
                  }
                  return widget.itemBuilder(
                    context,
                    loadedState.documentSnapshots,
                    itemIndex,
                  );
                }
                return widget.separator;
              },
              semanticIndexCallback: (widget, localIndex) {
                if (localIndex.isEven) {
                  return localIndex ~/ 2;
                }
                // ignore: avoid_returning_null
                return null;
              },
              childCount:
                  max(0, (loadedState.hasReachedEnd ? loadedState.documentSnapshots.length : loadedState.documentSnapshots.length + 1) * 2 - 1),
            ),
          ),
        ),
        if (widget.footer != null) widget.footer!,
      ],
    );

    if (widget.listeners != null && widget.listeners!.isNotEmpty) {
      return MultiProvider(
        key: const ValueKey('multi-provider-list-view'),
        providers: widget.listeners!
            .map((listener) => ChangeNotifierProvider(
                  create: (context) => listener,
                ))
            .toList(),
        child: listView,
      );
    }

    return listView;
  }

  Widget _buildPageView(PaginationLoaded loadedState) {
    var pageView = Padding(
      key: const ValueKey('pagination-page-view'),
      padding: widget.padding,
      child: PageView.custom(
        reverse: widget.reverse,
        allowImplicitScrolling: widget.allowImplicitScrolling,
        controller: widget.pageController,
        scrollDirection: widget.scrollDirection,
        physics: widget.physics,
        onPageChanged: widget.onPageChanged,
        childrenDelegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= loadedState.documentSnapshots.length) {
              _cubit!.fetchPaginatedList();
              return widget.bottomLoader;
            }
            return widget.itemBuilder(
              context,
              loadedState.documentSnapshots,
              index,
            );
          },
          childCount: loadedState.hasReachedEnd ? loadedState.documentSnapshots.length : loadedState.documentSnapshots.length + 1,
        ),
      ),
    );

    if (widget.listeners != null && widget.listeners!.isNotEmpty) {
      return MultiProvider(
        key: const ValueKey('multi-provider-page-view'),
        providers: widget.listeners!
            .map((listener) => ChangeNotifierProvider(
                  create: (context) => listener,
                ))
            .toList(),
        child: pageView,
      );
    }

    return pageView;
  }
}

enum PaginateBuilderType { listView, gridView, pageView }
