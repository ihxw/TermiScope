import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import 'theme_switch.dart';

/// PC端顶部Header导航组件
/// 参照Web版本Dashboard.vue的Header结构
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final int currentIndex;
  final ValueChanged<int> onNavigate;

  const AppHeader({
    super.key,
    required this.currentIndex,
    required this.onNavigate,
  });

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = Provider.of<AuthProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF303030) : const Color(0xFFF0F0F0),
              width: 1,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            // Logo区域
            Row(
              children: [
                Icon(
                  Icons.code,
                  color: isDark ? Colors.white : const Color(0xFF001529),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'TermiScope',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF001529),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(width: 24),

            // 导航菜单
            Expanded(
              child: Row(
                children: [
                  _buildNavItem(context, 0, Icons.dashboard, l10n.monitor),
                  _buildNavItem(context, 1, Icons.terminal, l10n.terminal),
                  _buildNavItem(context, 2, Icons.computer, l10n.hosts),
                  _buildNavItem(context, 3, Icons.history, l10n.history),
                  _buildNavItem(context, 4, Icons.code, l10n.commands),
                  if (auth.user?.role == 'admin') ...[
                    _buildNavItem(context, 5, Icons.people, l10n.users),
                    _buildNavItem(context, 6, Icons.settings, l10n.system),
                  ],
                ],
              ),
            ),

            // 右侧操作区
            Row(
              children: [
                // 版本号（暂时写死）
                Text(
                  'v1.0.0',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 16),

                // 主题切换
                const ThemeSwitch(),
                const SizedBox(width: 16),

                // 用户下拉菜单
                PopupMenuButton<String>(
                  offset: const Offset(0, 40),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person,
                        size: 16,
                        color: isDark ? Colors.white : const Color(0xFF001529),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        auth.user?.username ?? '',
                        style: TextStyle(
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF001529),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: isDark ? Colors.white : const Color(0xFF001529),
                      ),
                    ],
                  ),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'profile',
                      child: Row(
                        children: [
                          const Icon(Icons.person, size: 16),
                          const SizedBox(width: 8),
                          Text(l10n.profile),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          const Icon(Icons.logout, size: 16, color: Colors.red),
                          const SizedBox(width: 8),
                          Text(
                            l10n.logout,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) async {
                    if (value == 'logout') {
                      await auth.logout();
                    } else if (value == 'profile') {
                      onNavigate(7); // Profile页面索引
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    int index,
    IconData icon,
    String label,
  ) {
    final isSelected = currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return InkWell(
      onTap: () => onNavigate(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? primaryColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? primaryColor
                  : (isDark ? Colors.white70 : Colors.black54),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isSelected
                    ? primaryColor
                    : (isDark ? Colors.white70 : Colors.black54),
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
