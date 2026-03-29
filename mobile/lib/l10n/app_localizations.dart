import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'TermiScope'**
  String get appTitle;

  /// No description provided for @monitor.
  ///
  /// In en, this message translates to:
  /// **'Monitor'**
  String get monitor;

  /// No description provided for @hosts.
  ///
  /// In en, this message translates to:
  /// **'Hosts'**
  String get hosts;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @commands.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get commands;

  /// No description provided for @recordings.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
  String get recordings;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @users.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get users;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back!'**
  String get welcomeBack;

  /// No description provided for @signInToContinue.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue'**
  String get signInToContinue;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get currentPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully'**
  String get passwordChanged;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @sshConnections.
  ///
  /// In en, this message translates to:
  /// **'SSH Connections'**
  String get sshConnections;

  /// No description provided for @loginHistory.
  ///
  /// In en, this message translates to:
  /// **'Login History'**
  String get loginHistory;

  /// No description provided for @sshTimeout.
  ///
  /// In en, this message translates to:
  /// **'SSH Timeout'**
  String get sshTimeout;

  /// No description provided for @idleTimeout.
  ///
  /// In en, this message translates to:
  /// **'Idle Timeout'**
  String get idleTimeout;

  /// No description provided for @smtpServer.
  ///
  /// In en, this message translates to:
  /// **'SMTP Server'**
  String get smtpServer;

  /// No description provided for @backup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backup;

  /// No description provided for @downloadBackup.
  ///
  /// In en, this message translates to:
  /// **'Download Backup'**
  String get downloadBackup;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming Soon'**
  String get comingSoon;

  /// No description provided for @featureNotImplemented.
  ///
  /// In en, this message translates to:
  /// **'This feature is not yet implemented.'**
  String get featureNotImplemented;

  /// No description provided for @statusAuthenticated.
  ///
  /// In en, this message translates to:
  /// **'Authenticated'**
  String get statusAuthenticated;

  /// No description provided for @statusUnauthenticated.
  ///
  /// In en, this message translates to:
  /// **'Unauthenticated'**
  String get statusUnauthenticated;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @lastLogin.
  ///
  /// In en, this message translates to:
  /// **'Last Login'**
  String get lastLogin;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this?'**
  String get confirmDelete;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @enterServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Please enter a server URL'**
  String get enterServerUrl;

  /// No description provided for @addUser.
  ///
  /// In en, this message translates to:
  /// **'Add User'**
  String get addUser;

  /// No description provided for @editUser.
  ///
  /// In en, this message translates to:
  /// **'Edit User'**
  String get editUser;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @userRole.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get userRole;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @accessExpiration.
  ///
  /// In en, this message translates to:
  /// **'Access Expiration'**
  String get accessExpiration;

  /// No description provided for @limits.
  ///
  /// In en, this message translates to:
  /// **'Limits'**
  String get limits;

  /// No description provided for @maxConnectionsPerUser.
  ///
  /// In en, this message translates to:
  /// **'Max Connections/User'**
  String get maxConnectionsPerUser;

  /// No description provided for @loginRateLimit.
  ///
  /// In en, this message translates to:
  /// **'Login Rate Limit'**
  String get loginRateLimit;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @senderEmail.
  ///
  /// In en, this message translates to:
  /// **'Sender Email'**
  String get senderEmail;

  /// No description provided for @adminEmail.
  ///
  /// In en, this message translates to:
  /// **'Admin Email'**
  String get adminEmail;

  /// No description provided for @saveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save Settings'**
  String get saveSettings;

  /// No description provided for @systemBackup.
  ///
  /// In en, this message translates to:
  /// **'System Backup'**
  String get systemBackup;

  /// No description provided for @enterBackupPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter a password to encrypt the backup file:'**
  String get enterBackupPassword;

  /// No description provided for @startBackup.
  ///
  /// In en, this message translates to:
  /// **'Start Backup'**
  String get startBackup;

  /// No description provided for @leaveBlankToKeep.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to keep current'**
  String get leaveBlankToKeep;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @noHostsFound.
  ///
  /// In en, this message translates to:
  /// **'No hosts found'**
  String get noHostsFound;

  /// No description provided for @noHostsMonitored.
  ///
  /// In en, this message translates to:
  /// **'No hosts monitored'**
  String get noHostsMonitored;

  /// No description provided for @cpu.
  ///
  /// In en, this message translates to:
  /// **'CPU'**
  String get cpu;

  /// No description provided for @ram.
  ///
  /// In en, this message translates to:
  /// **'RAM'**
  String get ram;

  /// No description provided for @disk.
  ///
  /// In en, this message translates to:
  /// **'Disk'**
  String get disk;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @monitorOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get monitorOffline;

  /// No description provided for @connectToTerminal.
  ///
  /// In en, this message translates to:
  /// **'Connect to Terminal'**
  String get connectToTerminal;

  /// No description provided for @terminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get terminal;

  /// No description provided for @terminals.
  ///
  /// In en, this message translates to:
  /// **'Terminals'**
  String get terminals;

  /// No description provided for @terminalSelectHost.
  ///
  /// In en, this message translates to:
  /// **'Select a host'**
  String get terminalSelectHost;

  /// No description provided for @terminalQuickConnect.
  ///
  /// In en, this message translates to:
  /// **'Quick Connect'**
  String get terminalQuickConnect;

  /// No description provided for @terminalNewHost.
  ///
  /// In en, this message translates to:
  /// **'New Host'**
  String get terminalNewHost;

  /// No description provided for @terminalRecordSession.
  ///
  /// In en, this message translates to:
  /// **'Record Session'**
  String get terminalRecordSession;

  /// No description provided for @terminalNoActive.
  ///
  /// In en, this message translates to:
  /// **'No active terminals'**
  String get terminalNoActive;

  /// No description provided for @terminalConnectToHost.
  ///
  /// In en, this message translates to:
  /// **'Connect to Host'**
  String get terminalConnectToHost;

  /// No description provided for @serverHost.
  ///
  /// In en, this message translates to:
  /// **'Server Address'**
  String get serverHost;

  /// No description provided for @monitorTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get monitorTotal;

  /// No description provided for @monitorOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get monitorOnline;

  /// No description provided for @networkTitle.
  ///
  /// In en, this message translates to:
  /// **'Network Detail'**
  String get networkTitle;

  /// No description provided for @monitorOnly.
  ///
  /// In en, this message translates to:
  /// **'Monitor Only'**
  String get monitorOnly;

  /// No description provided for @monitorHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get monitorHistory;

  /// No description provided for @uptime.
  ///
  /// In en, this message translates to:
  /// **'Uptime'**
  String get uptime;

  /// No description provided for @agentOutdated.
  ///
  /// In en, this message translates to:
  /// **'Agent Outdated'**
  String get agentOutdated;

  /// No description provided for @networkUsage.
  ///
  /// In en, this message translates to:
  /// **'Traffic Usage'**
  String get networkUsage;

  /// No description provided for @expirationDate.
  ///
  /// In en, this message translates to:
  /// **'Expiration'**
  String get expirationDate;

  /// No description provided for @remainingDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String remainingDays(Object days);

  /// No description provided for @remainingValueLong.
  ///
  /// In en, this message translates to:
  /// **'Remaining Value'**
  String get remainingValueLong;

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// No description provided for @daysRemaining.
  ///
  /// In en, this message translates to:
  /// **'days left'**
  String get daysRemaining;

  /// No description provided for @billingMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get billingMonthly;

  /// No description provided for @billingQuarterly.
  ///
  /// In en, this message translates to:
  /// **'Quarterly'**
  String get billingQuarterly;

  /// No description provided for @billingSemiannually.
  ///
  /// In en, this message translates to:
  /// **'Semiannually'**
  String get billingSemiannually;

  /// No description provided for @billingAnnually.
  ///
  /// In en, this message translates to:
  /// **'Annually'**
  String get billingAnnually;

  /// No description provided for @billingBiennial.
  ///
  /// In en, this message translates to:
  /// **'Biennial'**
  String get billingBiennial;

  /// No description provided for @billingTriennial.
  ///
  /// In en, this message translates to:
  /// **'Triennial'**
  String get billingTriennial;

  /// No description provided for @billingOneTime.
  ///
  /// In en, this message translates to:
  /// **'One Time'**
  String get billingOneTime;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @features.
  ///
  /// In en, this message translates to:
  /// **'Features'**
  String get features;

  /// No description provided for @sshHistory.
  ///
  /// In en, this message translates to:
  /// **'SSH Connections'**
  String get sshHistory;

  /// No description provided for @basicSettings.
  ///
  /// In en, this message translates to:
  /// **'Basic Settings'**
  String get basicSettings;

  /// No description provided for @emailNotifications.
  ///
  /// In en, this message translates to:
  /// **'Email Notifications'**
  String get emailNotifications;

  /// No description provided for @telegramNotifications.
  ///
  /// In en, this message translates to:
  /// **'Telegram Notifications'**
  String get telegramNotifications;

  /// No description provided for @databaseManagement.
  ///
  /// In en, this message translates to:
  /// **'Database Management'**
  String get databaseManagement;

  /// No description provided for @systemUpdates.
  ///
  /// In en, this message translates to:
  /// **'System Updates'**
  String get systemUpdates;

  /// No description provided for @smtpPort.
  ///
  /// In en, this message translates to:
  /// **'SMTP Port'**
  String get smtpPort;

  /// No description provided for @smtpUser.
  ///
  /// In en, this message translates to:
  /// **'SMTP User'**
  String get smtpUser;

  /// No description provided for @smtpPassword.
  ///
  /// In en, this message translates to:
  /// **'SMTP Password'**
  String get smtpPassword;

  /// No description provided for @smtpFrom.
  ///
  /// In en, this message translates to:
  /// **'SMTP From'**
  String get smtpFrom;

  /// No description provided for @smtpTo.
  ///
  /// In en, this message translates to:
  /// **'SMTP To'**
  String get smtpTo;

  /// No description provided for @smtpSkipVerify.
  ///
  /// In en, this message translates to:
  /// **'Skip TLS Verification'**
  String get smtpSkipVerify;

  /// No description provided for @testEmail.
  ///
  /// In en, this message translates to:
  /// **'Test Email'**
  String get testEmail;

  /// No description provided for @telegramBotToken.
  ///
  /// In en, this message translates to:
  /// **'Telegram Bot Token'**
  String get telegramBotToken;

  /// No description provided for @telegramChatId.
  ///
  /// In en, this message translates to:
  /// **'Telegram Chat ID'**
  String get telegramChatId;

  /// No description provided for @notificationTemplate.
  ///
  /// In en, this message translates to:
  /// **'Notification Template'**
  String get notificationTemplate;

  /// No description provided for @testTelegram.
  ///
  /// In en, this message translates to:
  /// **'Test Telegram'**
  String get testTelegram;

  /// No description provided for @databaseManagementDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage database backups and restores'**
  String get databaseManagementDescription;

  /// No description provided for @backupDatabase.
  ///
  /// In en, this message translates to:
  /// **'Backup Database'**
  String get backupDatabase;

  /// No description provided for @restoreDatabase.
  ///
  /// In en, this message translates to:
  /// **'Restore Database'**
  String get restoreDatabase;

  /// No description provided for @checkUpdate.
  ///
  /// In en, this message translates to:
  /// **'Check Update'**
  String get checkUpdate;

  /// No description provided for @performUpdate.
  ///
  /// In en, this message translates to:
  /// **'Perform Update'**
  String get performUpdate;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update Available'**
  String get updateAvailable;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update Now'**
  String get updateNow;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @noUpdatesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No Updates Available'**
  String get noUpdatesAvailable;

  /// No description provided for @settingsSavedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Settings saved successfully'**
  String get settingsSavedSuccessfully;

  /// No description provided for @failedToSaveSettings.
  ///
  /// In en, this message translates to:
  /// **'Failed to save settings'**
  String get failedToSaveSettings;

  /// No description provided for @emailTestSentSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Email test sent successfully'**
  String get emailTestSentSuccessfully;

  /// No description provided for @failedToSendEmailTest.
  ///
  /// In en, this message translates to:
  /// **'Failed to send email test'**
  String get failedToSendEmailTest;

  /// No description provided for @telegramTestSentSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Telegram test sent successfully'**
  String get telegramTestSentSuccessfully;

  /// No description provided for @failedToSendTelegramTest.
  ///
  /// In en, this message translates to:
  /// **'Failed to send telegram test'**
  String get failedToSendTelegramTest;

  /// No description provided for @databaseBackupCreated.
  ///
  /// In en, this message translates to:
  /// **'Database backup created'**
  String get databaseBackupCreated;

  /// No description provided for @failedToCreateDatabaseBackup.
  ///
  /// In en, this message translates to:
  /// **'Failed to create database backup'**
  String get failedToCreateDatabaseBackup;

  /// No description provided for @timezone.
  ///
  /// In en, this message translates to:
  /// **'Timezone'**
  String get timezone;

  /// No description provided for @refreshExpiration.
  ///
  /// In en, this message translates to:
  /// **'Refresh Expiration'**
  String get refreshExpiration;

  /// No description provided for @lightTheme.
  ///
  /// In en, this message translates to:
  /// **'Light Theme'**
  String get lightTheme;

  /// No description provided for @darkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark Theme'**
  String get darkTheme;

  /// No description provided for @systemTheme.
  ///
  /// In en, this message translates to:
  /// **'System Theme'**
  String get systemTheme;

  /// No description provided for @addHost.
  ///
  /// In en, this message translates to:
  /// **'Add Host'**
  String get addHost;

  /// No description provided for @failedToCheckForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Failed to check for updates'**
  String get failedToCheckForUpdates;

  /// No description provided for @noHostsForTerminal.
  ///
  /// In en, this message translates to:
  /// **'No hosts available for terminal'**
  String get noHostsForTerminal;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// No description provided for @clearTerminal.
  ///
  /// In en, this message translates to:
  /// **'Clear Terminal'**
  String get clearTerminal;

  /// No description provided for @copySelection.
  ///
  /// In en, this message translates to:
  /// **'Copy Selection'**
  String get copySelection;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @noUsersFound.
  ///
  /// In en, this message translates to:
  /// **'No users found'**
  String get noUsersFound;

  /// No description provided for @systemManagement.
  ///
  /// In en, this message translates to:
  /// **'System Management'**
  String get systemManagement;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
