import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';

/// AntdEmpty 复刻 ant-design `a-empty` 空状态。
class AntdEmpty extends StatelessWidget {
  const AntdEmpty({
    super.key,
    this.description,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String? description;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final secondary = AntdTokens.secondaryTextColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: secondary),
          const SizedBox(height: 8),
          Text(
            description ?? '暂无数据',
            style: TextStyle(color: secondary, fontSize: AntdTokens.fontSize),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}
