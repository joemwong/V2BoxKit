import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../model/models.dart';
import '../state/app_controller.dart';

class RoutingPage extends StatefulWidget {
  const RoutingPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<RoutingPage> createState() => _RoutingPageState();
}

class _RoutingPageState extends State<RoutingPage> {
  late RoutingSettings draft;
  late final TextEditingController directDomains;
  late final TextEditingController dns;
  late final TextEditingController shareAddress;
  late final TextEditingController shareUser;
  late final TextEditingController sharePassword;
  late final TextEditingController socksPort;
  late final TextEditingController httpPort;

  @override
  void initState() {
    super.initState();
    draft = widget.controller.routing;
    directDomains = TextEditingController(text: draft.directDomains.join('\n'));
    dns = TextEditingController(text: draft.dnsServer);
    final sharing = draft.localSharing;
    shareAddress = TextEditingController(text: sharing.listenAddress);
    shareUser = TextEditingController(text: sharing.username);
    sharePassword = TextEditingController(text: sharing.password);
    socksPort = TextEditingController(text: '${sharing.socksPort}');
    httpPort = TextEditingController(text: '${sharing.httpPort}');
  }

  @override
  void dispose() {
    directDomains.dispose();
    dns.dispose();
    shareAddress.dispose();
    shareUser.dispose();
    sharePassword.dispose();
    socksPort.dispose();
    httpPort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('分流与 DNS', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        _Section(
          title: '路由模式',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<RoutingMode>(
                segments: [
                  for (final mode in RoutingMode.values)
                    ButtonSegment(value: mode, label: Text(mode.label)),
                ],
                selected: {draft.mode},
                onSelectionChanged: widget.controller.isConnected
                    ? null
                    : (selection) {
                        setState(() {
                          draft = draft.copyWith(mode: selection.first);
                        });
                      },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: draft.bypassPrivateNetworks,
                title: const Text('私有网络直连'),
                subtitle: const Text('绕过局域网、回环、链路本地和 CGNAT 地址'),
                onChanged: widget.controller.isConnected
                    ? null
                    : (value) {
                        setState(() {
                          draft = draft.copyWith(bypassPrivateNetworks: value);
                        });
                      },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: directDomains,
                minLines: 3,
                maxLines: 7,
                enabled: !widget.controller.isConnected,
                decoration: const InputDecoration(
                  labelText: '直连域名（每行一个）',
                  hintText: 'example.com\nfull:api.example.com',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: '自定义规则',
          trailing: TextButton.icon(
            onPressed: widget.controller.isConnected ? null : _addRule,
            icon: const Icon(Icons.add),
            label: const Text('添加'),
          ),
          child: draft.customRules.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('暂无自定义规则，将按私有网络和直连域名规则处理'),
                )
              : Column(
                  children: [
                    for (final rule in draft.customRules)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Switch(
                          value: rule.isEnabled,
                          onChanged: widget.controller.isConnected
                              ? null
                              : (value) => _replaceRule(
                                  rule.copyWith(isEnabled: value),
                                ),
                        ),
                        title: Text(rule.name),
                        subtitle: Text(
                          '${rule.kind.label} · ${rule.action.label} · '
                          '${rule.normalizedValues.length} 项',
                        ),
                        trailing: IconButton(
                          onPressed: widget.controller.isConnected
                              ? null
                              : () => _removeRule(rule.id),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'DNS 与隧道',
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(
                width: 420,
                child: TextField(
                  controller: dns,
                  enabled: !widget.controller.isConnected,
                  decoration: const InputDecoration(
                    labelText: 'DNS 服务器',
                    hintText: '1.1.1.1 或 https://dns.example/dns-query',
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int>(
                  initialValue: draft.mtu,
                  decoration: const InputDecoration(labelText: 'MTU'),
                  items: const [
                    DropdownMenuItem(value: 1280, child: Text('1280')),
                    DropdownMenuItem(value: 1400, child: Text('1400')),
                    DropdownMenuItem(value: 1500, child: Text('1500')),
                  ],
                  onChanged: widget.controller.isConnected
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => draft = draft.copyWith(mtu: value));
                          }
                        },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: '本机 / 局域网代理分享',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: draft.localSharing.isEnabled,
                title: const Text('启用 SOCKS5 与 HTTP 入站'),
                subtitle: const Text('监听 0.0.0.0 时仅应在可信网络使用，并必须设置认证'),
                onChanged: widget.controller.isConnected
                    ? null
                    : (value) {
                        setState(() {
                          draft = draft.copyWith(
                            localSharing: draft.localSharing.copyWith(
                              isEnabled: value,
                            ),
                          );
                        });
                      },
              ),
              if (draft.localSharing.isEnabled)
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: shareAddress,
                        decoration: const InputDecoration(labelText: '监听地址'),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: socksPort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'SOCKS5 端口',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: httpPort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'HTTP 端口'),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: shareUser,
                        decoration: const InputDecoration(labelText: '用户名'),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: sharePassword,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '密码'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: widget.controller.isConnected ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存设置'),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _save() async {
    try {
      final sharing = draft.localSharing.copyWith(
        listenAddress: shareAddress.text.trim(),
        socksPort: int.tryParse(socksPort.text) ?? 0,
        httpPort: int.tryParse(httpPort.text) ?? 0,
        username: shareUser.text.trim(),
        password: sharePassword.text,
      );
      final value = draft.copyWith(
        directDomains: directDomains.text
            .split(RegExp(r'[\r\n]+'))
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
        dnsServer: dns.text.trim(),
        localSharing: sharing,
      );
      if (value.dnsServer.isEmpty) {
        throw const FormatException('DNS 服务器不能为空');
      }
      if (!sharing.isValid) {
        throw const FormatException('代理分享必须设置有效端口、用户名和密码');
      }
      await widget.controller.updateRouting(value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('路由设置已保存'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _addRule() async {
    final rule = await showDialog<RoutingRule>(
      context: context,
      builder: (_) => const _AddRuleDialog(),
    );
    if (rule == null) return;
    setState(() {
      draft = draft.copyWith(customRules: [...draft.customRules, rule]);
    });
  }

  void _replaceRule(RoutingRule replacement) {
    setState(() {
      draft = draft.copyWith(
        customRules: [
          for (final rule in draft.customRules)
            if (rule.id == replacement.id) replacement else rule,
        ],
      );
    });
  }

  void _removeRule(String id) {
    setState(() {
      draft = draft.copyWith(
        customRules: draft.customRules.where((rule) => rule.id != id).toList(),
      );
    });
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _AddRuleDialog extends StatefulWidget {
  const _AddRuleDialog();

  @override
  State<_AddRuleDialog> createState() => _AddRuleDialogState();
}

class _AddRuleDialogState extends State<_AddRuleDialog> {
  final name = TextEditingController();
  final values = TextEditingController();
  RoutingRuleKind kind = RoutingRuleKind.domain;
  RoutingRuleAction action = RoutingRuleAction.proxy;

  @override
  void dispose() {
    name.dispose();
    values.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加路由规则'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '规则名称'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<RoutingRuleKind>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: '匹配类型'),
                    items: [
                      for (final value in RoutingRuleKind.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => kind = value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<RoutingRuleAction>(
                    initialValue: action,
                    decoration: const InputDecoration(labelText: '动作'),
                    items: [
                      for (final value in RoutingRuleAction.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => action = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: values,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(labelText: '匹配值（每行一个）'),
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
            final entries = values.text
                .split(RegExp(r'[\r\n]+'))
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList();
            if (entries.isEmpty) return;
            Navigator.pop(
              context,
              RoutingRule(
                id: const Uuid().v4(),
                name: name.text.trim().isEmpty ? '自定义规则' : name.text.trim(),
                kind: kind,
                action: action,
                values: entries,
              ),
            );
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}
