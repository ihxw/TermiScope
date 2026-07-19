import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/antd_tokens.dart';
import '../providers/app_state.dart';
import '../utils/translation.dart';
import '../widgets/antd/index.dart';

/// AuthScaffold 为登录、初始化、忘记密码、重置密码等页面提供统一外壳。
///
/// 视觉与 Web 端 ant-design-vue 登录页一致：
/// - 居中卡片
/// - 顶部右侧的语言切换 + 主题切换
class AuthScaffold extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const AuthScaffold({
    super.key,
    required this.child,
    this.maxWidth = 400,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = AntdTokens.containerColor(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: 20,
            right: 20,
            child: Consumer<AppState>(
              builder: (context, state, _) => AntdSpace(
                children: [
                  AntdButton(
                    size: AntdSize.small,
                    onPressed: () =>
                        state.updateLocale(state.locale == 'zh' ? 'en' : 'zh'),
                    child: Text(state.locale == 'zh' ? 'EN' : '中文'),
                  ),
                  AntdButton(
                    size: AntdSize.small,
                    icon: state.themeMode == ThemeMode.dark
                        ? Icons.lightbulb_outline
                        : Icons.lightbulb,
                    onPressed: () => state.updateThemeMode(
                      state.themeMode == ThemeMode.dark
                          ? ThemeMode.light
                          : ThemeMode.dark,
                    ),
                    child: Text(
                      state.themeMode == ThemeMode.dark
                          ? Translation.getText(state.locale, 'theme.light')
                          : Translation.getText(state.locale, 'theme.dark'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final isPhone = width <= AntdTokens.smallMobileBreakpoint;
                final isMobile = width <= AntdTokens.mobileBreakpoint;
                final outerPadding = isPhone ? 8.0 : (isMobile ? 16.0 : 0.0);
                final cardPadding = isPhone ? 16.0 : (isMobile ? 24.0 : 40.0);

                return Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(outerPadding),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Container(
                        padding: EdgeInsets.all(cardPadding),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius:
                              BorderRadius.circular(AntdTokens.cardRadius),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(
                                  AntdTokens.isDark(context) ? 77 : 20),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: child,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// AuthBranding 用于在认证类页面顶部统一显示 logo + 标题。
class AuthBranding extends StatelessWidget {
  const AuthBranding({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = width <= AntdTokens.smallMobileBreakpoint
        ? 18.0
        : (width <= AntdTokens.mobileBreakpoint ? 20.0 : 24.0);
    final color = AntdTokens.textColor(context);

    return Column(
      children: [
        Icon(Icons.terminal, size: 32, color: color),
        const SizedBox(height: 8),
        Text(
          'TermiScope',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
