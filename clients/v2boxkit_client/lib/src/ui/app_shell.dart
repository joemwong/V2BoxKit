import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'nodes_page.dart';
import 'routing_page.dart';
import 'subscriptions_page.dart';
import 'tools_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selectedIndex = 0;
  String? shownMessage;

  static const destinations = <_Destination>[
    _Destination('节点', Icons.hub_outlined, Icons.hub),
    _Destination('订阅', Icons.sync_outlined, Icons.sync),
    _Destination('分流', Icons.alt_route_outlined, Icons.alt_route),
    _Destination('工具', Icons.build_outlined, Icons.build),
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_showControllerMessage);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_showControllerMessage);
    super.dispose();
  }

  void _showControllerMessage() {
    final message = widget.controller.lastMessage;
    if (message == null || message == shownMessage || !mounted) return;
    shownMessage = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final page = switch (selectedIndex) {
          0 => NodesPage(controller: widget.controller),
          1 => SubscriptionsPage(controller: widget.controller),
          2 => RoutingPage(controller: widget.controller),
          _ => ToolsPage(controller: widget.controller),
        };
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            return Scaffold(
              appBar: AppBar(
                title: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(Icons.bolt, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    const Text('V2BoxKit'),
                  ],
                ),
                actions: [
                  _TunnelStatusBadge(controller: widget.controller),
                  const SizedBox(width: 16),
                ],
              ),
              body: wide
                  ? Row(
                      children: [
                        NavigationRail(
                          selectedIndex: selectedIndex,
                          groupAlignment: -0.75,
                          labelType: NavigationRailLabelType.all,
                          onDestinationSelected: (value) {
                            setState(() => selectedIndex = value);
                          },
                          destinations: [
                            for (final destination in destinations)
                              NavigationRailDestination(
                                icon: Icon(destination.icon),
                                selectedIcon: Icon(destination.selectedIcon),
                                label: Text(destination.label),
                              ),
                          ],
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: page),
                      ],
                    )
                  : page,
              bottomNavigationBar: wide
                  ? null
                  : NavigationBar(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: (value) {
                        setState(() => selectedIndex = value);
                      },
                      destinations: [
                        for (final destination in destinations)
                          NavigationDestination(
                            icon: Icon(destination.icon),
                            selectedIcon: Icon(destination.selectedIcon),
                            label: destination.label,
                          ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }
}

class _TunnelStatusBadge extends StatelessWidget {
  const _TunnelStatusBadge({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final connected = controller.isConnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: connected
            ? const Color(0xffe4f7ed)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: connected ? const Color(0xff159455) : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            controller.tunnelStatus.label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
