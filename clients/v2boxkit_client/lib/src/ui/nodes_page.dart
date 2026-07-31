import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/models.dart';
import '../state/app_controller.dart';

class NodesPage extends StatefulWidget {
  const NodesPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends State<NodesPage> {
  String searchText = '';
  bool favoritesOnly = false;

  @override
  Widget build(BuildContext context) {
    final nodes = widget.controller.visibleNodes(
      searchText: searchText,
      favoritesOnly: favoritesOnly,
    );
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            controller: widget.controller,
            favoritesOnly: favoritesOnly,
            onFavoritesChanged: (value) {
              setState(() => favoritesOnly = value);
            },
            onAdd: _showAddDialog,
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (value) => setState(() => searchText = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索名称、地址或分组',
              filled: true,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 950) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _NodeList(
                          nodes: nodes,
                          controller: widget.controller,
                          onError: _showError,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 3,
                        child: _ConnectionPanel(
                          controller: widget.controller,
                          onError: _showError,
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    SizedBox(
                      height: 190,
                      child: _ConnectionPanel(
                        controller: widget.controller,
                        onError: _showError,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _NodeList(
                        nodes: nodes,
                        controller: widget.controller,
                        onError: _showError,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog() async {
    final payload = await showDialog<String>(
      context: context,
      builder: (_) => const _AddNodeDialog(),
    );
    if (payload == null || !mounted) return;
    try {
      await widget.controller.importPayload(payload);
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.favoritesOnly,
    required this.onFavoritesChanged,
    required this.onAdd,
  });

  final AppController controller;
  final bool favoritesOnly;
  final ValueChanged<bool> onFavoritesChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('节点', style: Theme.of(context).textTheme.headlineMedium),
        Text(
          '${controller.nodes.length} 个',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        FilterChip(
          selected: favoritesOnly,
          onSelected: onFavoritesChanged,
          avatar: const Icon(Icons.star_outline, size: 18),
          label: const Text('只看收藏'),
        ),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_link),
          label: const Text('导入链接'),
        ),
        OutlinedButton.icon(
          onPressed: controller.nodes.isEmpty || controller.isConnected
              ? null
              : () => controller.measureAllLatencies(),
          icon: const Icon(Icons.speed),
          label: const Text('全部测速'),
        ),
      ],
    );
  }
}

class _NodeList extends StatelessWidget {
  const _NodeList({
    required this.nodes,
    required this.controller,
    required this.onError,
  });

  final List<ProxyNode> nodes;
  final AppController controller;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return const Card(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hub_outlined, size: 46),
                SizedBox(height: 12),
                Text('还没有匹配节点'),
                SizedBox(height: 4),
                Text('导入分享链接或添加订阅后即可连接'),
              ],
            ),
          ),
        ),
      );
    }
    return Card(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: nodes.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final node = nodes[index];
          final selected = node.id == controller.selectedNodeId;
          return ListTile(
            selected: selected,
            selectedTileColor: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.55),
            onTap: () async {
              try {
                await controller.selectNode(node.id);
              } catch (error) {
                onError(error);
              }
            },
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                node.isFavorite ? Icons.star : Icons.lan_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Row(
              children: [
                if (node.isPinned) ...[
                  const Icon(Icons.push_pin, size: 15),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(node.name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            subtitle: Text(
              '${node.kind.displayName} · ${node.endpoint}\n${node.groupName}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.measuringNodeIds.contains(node.id))
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    node.latencyText,
                    style: TextStyle(
                      color: (node.latencyMilliseconds ?? 10000) < 1000
                          ? const Color(0xff159455)
                          : null,
                    ),
                  ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    try {
                      switch (value) {
                        case 'latency':
                          await controller.measureLatency(node.id);
                        case 'favorite':
                          controller.toggleFavorite(node.id);
                        case 'pin':
                          controller.togglePinned(node.id);
                        case 'delete':
                          await controller.removeNode(node.id);
                      }
                    } catch (error) {
                      onError(error);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'latency', child: Text('测试延迟')),
                    PopupMenuItem(
                      value: 'favorite',
                      child: Text(node.isFavorite ? '取消收藏' : '收藏'),
                    ),
                    PopupMenuItem(
                      value: 'pin',
                      child: Text(node.isPinned ? '取消置顶' : '置顶'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({required this.controller, required this.onError});

  final AppController controller;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context) {
    final node = controller.selectedNode;
    return Card(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前连接', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
              node?.name ?? '尚未选择节点',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              node == null
                  ? '从节点列表选择一个配置'
                  : '${node.kind.displayName} · ${node.endpoint}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  backgroundColor: controller.isConnected
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                onPressed:
                    node == null ||
                        controller.tunnelStatus == TunnelStatus.disconnecting ||
                        controller.tunnelStatus == TunnelStatus.connecting
                    ? null
                    : () async {
                        try {
                          if (controller.isConnected) {
                            await controller.disconnect();
                          } else {
                            await controller.connect();
                          }
                        } catch (error) {
                          onError(error);
                        }
                      },
                icon: Icon(
                  controller.isConnected
                      ? Icons.power_settings_new
                      : Icons.shield_outlined,
                ),
                label: Text(controller.isConnected ? '断开连接' : '连接'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddNodeDialog extends StatefulWidget {
  const _AddNodeDialog();

  @override
  State<_AddNodeDialog> createState() => _AddNodeDialogState();
}

class _AddNodeDialogState extends State<_AddNodeDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入分享链接'),
      content: SizedBox(
        width: 560,
        child: TextField(
          controller: controller,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(
            hintText: '支持 VLESS、VMess、Trojan、Shadowsocks、Hysteria2；可一次粘贴多行',
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            final data = await Clipboard.getData('text/plain');
            if (data?.text != null) controller.text = data!.text!;
          },
          icon: const Icon(Icons.content_paste),
          label: const Text('粘贴'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final value = controller.text.trim();
            if (value.isNotEmpty) Navigator.pop(context, value);
          },
          child: const Text('导入'),
        ),
      ],
    );
  }
}
