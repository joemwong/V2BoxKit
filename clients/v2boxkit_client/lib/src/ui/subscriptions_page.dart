import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_controller.dart';

class SubscriptionsPage extends StatelessWidget {
  const SubscriptionsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('订阅', style: Theme.of(context).textTheme.headlineMedium),
              Text('${controller.subscriptions.length} 个'),
              FilledButton.icon(
                onPressed: () => _addSubscription(context),
                icon: const Icon(Icons.add),
                label: const Text('添加订阅'),
              ),
              OutlinedButton.icon(
                onPressed: controller.subscriptions.isEmpty || controller.busy
                    ? null
                    : controller.refreshAllSubscriptions,
                icon: controller.busy
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('全部更新'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: controller.subscriptions.isEmpty
                ? const Card(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sync_outlined, size: 48),
                          SizedBox(height: 12),
                          Text('还没有订阅'),
                          SizedBox(height: 4),
                          Text('添加 HTTPS 订阅地址以自动更新节点'),
                        ],
                      ),
                    ),
                  )
                : Card(
                    child: ListView.separated(
                      itemCount: controller.subscriptions.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final subscription = controller.subscriptions[index];
                        final nodeCount = controller.nodes
                            .where((node) => node.sourceId == subscription.id)
                            .length;
                        return _SubscriptionTile(
                          subscription: subscription,
                          nodeCount: nodeCount,
                          busy: controller.busy,
                          onRefresh: () => _run(
                            context,
                            controller.refreshSubscription(subscription.id),
                          ),
                          onDelete: () => _confirmDelete(context, subscription),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _addSubscription(BuildContext context) async {
    final result = await showDialog<_SubscriptionInput>(
      context: context,
      builder: (_) => const _AddSubscriptionDialog(),
    );
    if (result == null || !context.mounted) return;
    await _run(
      context,
      controller.addSubscription(
        name: result.name,
        url: result.url,
        refreshHours: result.refreshHours,
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ProxySubscription subscription,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除订阅'),
        content: Text('同时删除“${subscription.name}”导入的所有节点？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _run(context, controller.removeSubscription(subscription.id));
    }
  }

  Future<void> _run(BuildContext context, Future<Object?> operation) async {
    try {
      await operation;
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _SubscriptionTile extends StatelessWidget {
  const _SubscriptionTile({
    required this.subscription,
    required this.nodeCount,
    required this.busy,
    required this.onRefresh,
    required this.onDelete,
  });

  final ProxySubscription subscription;
  final int nodeCount;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final updated = subscription.lastUpdatedAt;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: const Icon(Icons.cloud_download_outlined),
      ),
      title: Text(subscription.name),
      subtitle: Text(
        '${subscription.url}\n'
        '$nodeCount 个节点 · '
        '${updated == null ? '尚未更新' : _relativeTime(updated)}'
        '${subscription.lastError == null ? '' : '\n${subscription.lastError}'}',
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: subscription.lastError == null
              ? null
              : Theme.of(context).colorScheme.error,
        ),
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '更新',
            onPressed: busy ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: busy ? null : onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  String _relativeTime(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) return '刚刚更新';
    if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
    if (difference.inDays < 1) return '${difference.inHours} 小时前';
    return '${difference.inDays} 天前';
  }
}

class _SubscriptionInput {
  const _SubscriptionInput(this.name, this.url, this.refreshHours);

  final String name;
  final String url;
  final int refreshHours;
}

class _AddSubscriptionDialog extends StatefulWidget {
  const _AddSubscriptionDialog();

  @override
  State<_AddSubscriptionDialog> createState() => _AddSubscriptionDialogState();
}

class _AddSubscriptionDialogState extends State<_AddSubscriptionDialog> {
  final name = TextEditingController();
  final url = TextEditingController();
  int refreshHours = 24;

  @override
  void dispose() {
    name.dispose();
    url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加订阅'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '名称（可选）'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              decoration: const InputDecoration(labelText: 'HTTPS 订阅地址'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: refreshHours,
              decoration: const InputDecoration(labelText: '自动更新间隔'),
              items: const [
                DropdownMenuItem(value: 6, child: Text('每 6 小时')),
                DropdownMenuItem(value: 12, child: Text('每 12 小时')),
                DropdownMenuItem(value: 24, child: Text('每天')),
                DropdownMenuItem(value: 168, child: Text('每周')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => refreshHours = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (url.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _SubscriptionInput(
                name.text.trim(),
                url.text.trim(),
                refreshHours,
              ),
            );
          },
          child: const Text('添加并更新'),
        ),
      ],
    );
  }
}
