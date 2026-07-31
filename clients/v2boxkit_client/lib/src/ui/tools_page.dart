import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_controller.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  Future<Map<String, Object?>>? diagnostics;

  @override
  void initState() {
    super.initState();
    diagnostics = widget.controller.diagnostics();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('工具', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        _ToolCard(
          icon: Icons.backup_outlined,
          title: '配置备份',
          description: '导出或恢复节点、订阅和路由设置。备份包含节点凭证，请妥善保管。',
          children: [
            FilledButton.tonalIcon(
              onPressed: _exportBackup,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('导出备份'),
            ),
            OutlinedButton.icon(
              onPressed: widget.controller.isConnected ? null : _importBackup,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('恢复备份'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ToolCard(
          icon: Icons.speed,
          title: '批量测速',
          description: '连接前逐个启动短生命周期 Xray 实例并测试真实代理链路。',
          children: [
            FilledButton.tonalIcon(
              onPressed:
                  widget.controller.nodes.isEmpty ||
                      widget.controller.isConnected
                  ? null
                  : widget.controller.measureAllLatencies,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始全部测速'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.monitor_heart_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '运行诊断',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新',
                      onPressed: () {
                        setState(() {
                          diagnostics = widget.controller.diagnostics();
                        });
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FutureBuilder<Map<String, Object?>>(
                  future: diagnostics,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final values = snapshot.data!;
                    return Column(
                      children: [
                        for (final entry in values.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 160,
                                  child: Text(
                                    entry.key,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Expanded(child: Text('${entry.value}')),
                              ],
                            ),
                          ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(
                                  text: const JsonEncoder.withIndent(
                                    '  ',
                                  ).convert(values),
                                ),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('诊断信息已复制')),
                              );
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('复制诊断信息'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _ToolCard(
          icon: Icons.security_outlined,
          title: '平台说明',
          description: Platform.isAndroid
              ? '首次连接会显示系统 VPN 授权；Android 8 及以上会保持前台通知。Always-on VPN 可在系统 VPN 设置中启用。'
              : 'Windows 使用 Wintun 创建系统隧道，需要管理员权限。应用清单已请求管理员启动。',
          children: const [],
        ),
        const SizedBox(height: 16),
        const _ToolCard(
          icon: Icons.info_outline,
          title: '安全边界',
          description:
              '本 MVP 不内置或售卖节点。配置目前保存在本机应用存储，文件备份为明文 JSON；正式发布前应加入系统安全存储与加密备份。',
          children: [],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _exportBackup() async {
    try {
      final path = await widget.controller.exportBackup();
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('备份已保存：$path')));
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _importBackup() async {
    try {
      await widget.controller.importBackup();
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

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 5),
                  Text(description),
                  if (children.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(spacing: 10, runSpacing: 10, children: children),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
