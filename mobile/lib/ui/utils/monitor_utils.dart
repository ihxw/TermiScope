import 'package:flutter/material.dart';
import 'package:mobile/l10n/app_localizations.dart';

class MonitorUtils {
  static String formatBytes(double bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
    var i = 0;
    while (bytes >= 1024 && i < suffixes.length - 1) {
      bytes /= 1024;
      i++;
    }
    return '${bytes.toStringAsFixed(1)} ${suffixes[i]}';
  }

  static String formatSpeed(double bytesPerSec) {
    return '${formatBytes(bytesPerSec)}/s';
  }

  static String formatUptime(int seconds) {
    final dys = (seconds / 86400).floor();
    final hrs = ((seconds % 86400) / 3600).floor();
    final min = ((seconds % 3600) / 60).floor();

    if (dys > 0) {
      return '${dys}d ${hrs}h';
    }
    if (hrs > 0) {
      return '${hrs}h ${min}m';
    }
    return '${min}m';
  }

  static String formatMhz(double mhz) {
    if (mhz >= 1000) {
      return '${(mhz / 1000).toStringAsFixed(2)} GHz';
    }
    return '${mhz.toStringAsFixed(0)} MHz';
  }

  static Color getStatusColor(double percent) {
    if (percent >= 90) {
      return Colors.red;
    }
    if (percent >= 80) {
      return Colors.orange;
    }
    return Colors.blue;
  }

  static Color getFlagColor(String flag) {
    switch (flag) {
      case 'red':
        return const Color(0xFFFF3B30);
      case 'orange':
        return const Color(0xFFFF9500);
      case 'yellow':
        return const Color(0xFFFFCC00);
      case 'green':
        return const Color(0xFF4CD964);
      case 'blue':
        return const Color(0xFF007AFF);
      case 'purple':
        return const Color(0xFF5856D6);
      case 'gray':
        return const Color(0xFF8E8E93);
      default:
        return Colors.transparent;
    }
  }

  static IconData getOsIcon(String os) {
    os = (os).toLowerCase();
    if (os.contains('win')) {
      return Icons.window; // Windows
    }
    if (os.contains('mac') || os.contains('darwin')) {
      return Icons.laptop_mac; // Apple/Mac
    }
    // Android Icon is Icons.android but TermiScope might not monitor androids much.
    // Linux generic:
    return Icons.desktop_windows;
    // Material doesn't have a perfect Tux icon, so desktop_windows or computer is fine.
  }

  // Traffic Logic
  static int getTrafficUsagePct(
    double limit,
    String mode,
    double rx,
    double tx,
    double adjustment,
  ) {
    if (limit <= 0) {
      return 0;
    }

    double measured = 0;
    if (mode == 'rx') {
      measured = rx;
    } else if (mode == 'tx') {
      measured = tx;
    } else {
      measured = rx + tx;
    }

    final used = measured + adjustment;
    final pct = (used / limit * 100).round();
    return pct > 100 ? 100 : pct;
  }

  static String formatTrafficUsage(
    double limit,
    String mode,
    double rx,
    double tx,
    double adjustment,
  ) {
    if (limit <= 0) {
      return '';
    }

    double measured = 0;
    if (mode == 'rx') {
      measured = rx;
    } else if (mode == 'tx') {
      measured = tx;
    } else {
      measured = rx + tx;
    }

    final used = measured + adjustment;
    return '${formatBytes(used)} / ${formatBytes(limit)}';
  }

  // Financial Logic
  static int getDaysUntilExpiration(String? expirationDate) {
    if (expirationDate == null || expirationDate.isEmpty) return 0;
    try {
      final now = DateTime.now();
      // Parse YYYY-MM-DD or ISO string
      final exp = DateTime.parse(expirationDate);
      final diff = exp.difference(now).inDays;
      return diff;
    } catch (e) {
      return 0;
    }
  }

  static String formatBillingPeriod(BuildContext context, String period) {
    if (period.isEmpty) return '';
    final l10n = AppLocalizations.of(context)!;
    switch (period) {
      case 'monthly':
        return l10n.billingMonthly;
      case 'quarterly':
        return l10n.billingQuarterly;
      case 'semiannually':
        return l10n.billingSemiannually;
      case 'annually':
        return l10n.billingAnnually;
      case 'biennial':
        return l10n.billingBiennial;
      case 'triennial':
        return l10n.billingTriennial;
      case 'onetime':
        return l10n.billingOneTime;
      default:
        return period;
    }
  }

  static String getCurrencySymbol(String currency) {
    const symbols = {
      'CNY': '¥',
      'USD': '\$',
      'EUR': '€',
      'GBP': '£',
      'JPY': '¥',
    };
    return symbols[currency] ?? '¥';
  }

  static String formatRemainingValueOnly(
    BuildContext context,
    String expirationDate,
    String billingPeriod,
    double billingAmount,
    String currency,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final daysRemaining = getDaysUntilExpiration(expirationDate);
    if (daysRemaining < 0) return l10n.expired;

    const periodDays = {
      'monthly': 30,
      'quarterly': 90,
      'semiannually': 180,
      'annually': 365,
      'biennial': 730,
      'triennial': 1095,
    };

    final days = periodDays[billingPeriod] ?? 30;
    final dailyRate = billingAmount / days;
    final remaining = (dailyRate * daysRemaining).toStringAsFixed(2);
    final symbol = getCurrencySymbol(currency);

    return '$symbol$remaining';
  }
}
