import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

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
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('ru')];

  /// No description provided for @tabConfigs.
  ///
  /// In en, this message translates to:
  /// **'Configs'**
  String get tabConfigs;

  /// No description provided for @tabRouting.
  ///
  /// In en, this message translates to:
  /// **'Routing'**
  String get tabRouting;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @homeNoConfigShort.
  ///
  /// In en, this message translates to:
  /// **'no config'**
  String get homeNoConfigShort;

  /// No description provided for @homeUnsupported.
  ///
  /// In en, this message translates to:
  /// **'not supported'**
  String get homeUnsupported;

  /// No description provided for @homeNoConfig.
  ///
  /// In en, this message translates to:
  /// **'no configuration'**
  String get homeNoConfig;

  /// No description provided for @homeLogs.
  ///
  /// In en, this message translates to:
  /// **'logs'**
  String get homeLogs;

  /// No description provided for @homeTunnel.
  ///
  /// In en, this message translates to:
  /// **'TUNNEL · {proto}'**
  String homeTunnel(String proto);

  /// No description provided for @homeStateConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get homeStateConnected;

  /// No description provided for @homeStateConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get homeStateConnecting;

  /// No description provided for @homeStateDisconnecting.
  ///
  /// In en, this message translates to:
  /// **'Disconnecting'**
  String get homeStateDisconnecting;

  /// No description provided for @homeStateOff.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get homeStateOff;

  /// No description provided for @homeStateFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get homeStateFailed;

  /// No description provided for @homeStateBlocked.
  ///
  /// In en, this message translates to:
  /// **'Traffic blocked'**
  String get homeStateBlocked;

  /// No description provided for @homeKillSwitchBlocked.
  ///
  /// In en, this message translates to:
  /// **'The kill switch holds traffic until the VPN connects. Disconnect to go online without the VPN.'**
  String get homeKillSwitchBlocked;

  /// No description provided for @homeTapToRetry.
  ///
  /// In en, this message translates to:
  /// **'tap to retry'**
  String get homeTapToRetry;

  /// No description provided for @homeConnecting.
  ///
  /// In en, this message translates to:
  /// **'establishing connection…'**
  String get homeConnecting;

  /// No description provided for @homeDisconnecting.
  ///
  /// In en, this message translates to:
  /// **'closing session…'**
  String get homeDisconnecting;

  /// No description provided for @homeNoConfigAdd.
  ///
  /// In en, this message translates to:
  /// **'no configuration — add one'**
  String get homeNoConfigAdd;

  /// No description provided for @homeTapToConnect.
  ///
  /// In en, this message translates to:
  /// **'tap to connect'**
  String get homeTapToConnect;

  /// No description provided for @homeIpUnknown.
  ///
  /// In en, this message translates to:
  /// **'IP not detected'**
  String get homeIpUnknown;

  /// No description provided for @homeDisconnectButton.
  ///
  /// In en, this message translates to:
  /// **'DISCONNECT'**
  String get homeDisconnectButton;

  /// No description provided for @homeActionReconnect.
  ///
  /// In en, this message translates to:
  /// **'reconnect'**
  String get homeActionReconnect;

  /// No description provided for @homeActionDisconnect.
  ///
  /// In en, this message translates to:
  /// **'disconnect'**
  String get homeActionDisconnect;

  /// No description provided for @homeActionWait.
  ///
  /// In en, this message translates to:
  /// **'waiting'**
  String get homeActionWait;

  /// No description provided for @homeActionConnect.
  ///
  /// In en, this message translates to:
  /// **'connect'**
  String get homeActionConnect;

  /// No description provided for @homeChangeServer.
  ///
  /// In en, this message translates to:
  /// **'change server'**
  String get homeChangeServer;

  /// No description provided for @homeServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get homeServer;

  /// No description provided for @homePing.
  ///
  /// In en, this message translates to:
  /// **'Ping to server'**
  String get homePing;

  /// No description provided for @homeUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get homeUpload;

  /// No description provided for @homeDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get homeDownload;

  /// No description provided for @homeCoreEnableHint.
  ///
  /// In en, this message translates to:
  /// **'enable a core in settings or switch the config'**
  String get homeCoreEnableHint;

  /// No description provided for @homeCorePinned.
  ///
  /// In en, this message translates to:
  /// **'pinned'**
  String get homeCorePinned;

  /// No description provided for @homeManagedOnlySelected.
  ///
  /// In en, this message translates to:
  /// **'domain \"Only\" mode and DNS settings don\'t apply · routing is controlled by the server'**
  String get homeManagedOnlySelected;

  /// No description provided for @homeManagedDns.
  ///
  /// In en, this message translates to:
  /// **'DNS settings don\'t apply · routing is controlled by the server'**
  String get homeManagedDns;

  /// No description provided for @homeTrafficLive.
  ///
  /// In en, this message translates to:
  /// **'TRAFFIC — THIS SESSION'**
  String get homeTrafficLive;

  /// No description provided for @homePeak.
  ///
  /// In en, this message translates to:
  /// **'peak ↓ {value} Mbit/s'**
  String homePeak(String value);

  /// No description provided for @commonErrorWith.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String commonErrorWith(String error);

  /// No description provided for @commonRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get commonRename;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get commonName;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @configsHideGroups.
  ///
  /// In en, this message translates to:
  /// **'hide groups'**
  String get configsHideGroups;

  /// No description provided for @configsSortByPing.
  ///
  /// In en, this message translates to:
  /// **'sort by ping'**
  String get configsSortByPing;

  /// No description provided for @configsSortMode.
  ///
  /// In en, this message translates to:
  /// **'sort mode'**
  String get configsSortMode;

  /// No description provided for @configsPin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get configsPin;

  /// No description provided for @configsUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get configsUnpin;

  /// No description provided for @configsCore.
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get configsCore;

  /// No description provided for @configsCoreNone.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get configsCoreNone;

  /// No description provided for @configsEditUri.
  ///
  /// In en, this message translates to:
  /// **'Edit URI'**
  String get configsEditUri;

  /// No description provided for @configsCopyUrl.
  ///
  /// In en, this message translates to:
  /// **'Copy URL'**
  String get configsCopyUrl;

  /// No description provided for @configsUrlCopied.
  ///
  /// In en, this message translates to:
  /// **'URL copied'**
  String get configsUrlCopied;

  /// No description provided for @configsShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get configsShare;

  /// No description provided for @configsUriParseFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t parse the URI'**
  String get configsUriParseFailed;

  /// No description provided for @configsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete?'**
  String get configsDeleteTitle;

  /// No description provided for @configsDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Configuration \"{name}\" will be deleted.'**
  String configsDeleteMessage(String name);

  /// No description provided for @configsSubUpdated.
  ///
  /// In en, this message translates to:
  /// **'Subscription updated'**
  String get configsSubUpdated;

  /// No description provided for @certUntrustedTitle.
  ///
  /// In en, this message translates to:
  /// **'Untrusted certificate'**
  String get certUntrustedTitle;

  /// No description provided for @certUntrustedMessage.
  ///
  /// In en, this message translates to:
  /// **'The server uses a self-signed or unknown certificate. The connection may be insecure.'**
  String get certUntrustedMessage;

  /// No description provided for @certServer.
  ///
  /// In en, this message translates to:
  /// **'Server: {host}'**
  String certServer(String host);

  /// No description provided for @certSubject.
  ///
  /// In en, this message translates to:
  /// **'Certificate: {subject}'**
  String certSubject(String subject);

  /// No description provided for @certIssuer.
  ///
  /// In en, this message translates to:
  /// **'Issuer: {issuer}'**
  String certIssuer(String issuer);

  /// No description provided for @certFingerprint.
  ///
  /// In en, this message translates to:
  /// **'SHA-256: {fingerprint}'**
  String certFingerprint(String fingerprint);

  /// No description provided for @certContinueAnyway.
  ///
  /// In en, this message translates to:
  /// **'Continue anyway?'**
  String get certContinueAnyway;

  /// No description provided for @configsUpdateError.
  ///
  /// In en, this message translates to:
  /// **'Update error: {error}'**
  String configsUpdateError(String error);

  /// No description provided for @configsRenameSub.
  ///
  /// In en, this message translates to:
  /// **'Rename subscription'**
  String get configsRenameSub;

  /// No description provided for @configsEditSubUrl.
  ///
  /// In en, this message translates to:
  /// **'Change subscription URL'**
  String get configsEditSubUrl;

  /// No description provided for @configsSaveAndRefresh.
  ///
  /// In en, this message translates to:
  /// **'Save and refresh'**
  String get configsSaveAndRefresh;

  /// No description provided for @configsSubUpdatedNewUrl.
  ///
  /// In en, this message translates to:
  /// **'Subscription updated from the new URL'**
  String get configsSubUpdatedNewUrl;

  /// No description provided for @configsDeleteSubTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete subscription?'**
  String get configsDeleteSubTitle;

  /// No description provided for @configsDeleteSubMessage.
  ///
  /// In en, this message translates to:
  /// **'Subscription \"{name}\" and all its configurations will be deleted.'**
  String configsDeleteSubMessage(String name);

  /// No description provided for @configsSubsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions updated: {count}'**
  String configsSubsUpdated(int count);

  /// No description provided for @configsSubsUpdatedPartial.
  ///
  /// In en, this message translates to:
  /// **'Updated {ok} of {total}'**
  String configsSubsUpdatedPartial(int ok, int total);

  /// No description provided for @configsTagline.
  ///
  /// In en, this message translates to:
  /// **'CONFIGURATIONS'**
  String get configsTagline;

  /// No description provided for @configsDisplaySettings.
  ///
  /// In en, this message translates to:
  /// **'display settings'**
  String get configsDisplaySettings;

  /// No description provided for @configsSubSettings.
  ///
  /// In en, this message translates to:
  /// **'subscription settings'**
  String get configsSubSettings;

  /// No description provided for @configsExport.
  ///
  /// In en, this message translates to:
  /// **'export connections'**
  String get configsExport;

  /// No description provided for @configsRefreshSubs.
  ///
  /// In en, this message translates to:
  /// **'refresh subscriptions'**
  String get configsRefreshSubs;

  /// No description provided for @configsAdd.
  ///
  /// In en, this message translates to:
  /// **'add'**
  String get configsAdd;

  /// No description provided for @subNeverUpdated.
  ///
  /// In en, this message translates to:
  /// **'Never updated'**
  String get subNeverUpdated;

  /// No description provided for @subJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get subJustNow;

  /// No description provided for @subMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String subMinutesAgo(int count);

  /// No description provided for @subHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} h ago'**
  String subHoursAgo(int count);

  /// No description provided for @subDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} d ago'**
  String subDaysAgo(int count);

  /// No description provided for @subExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get subExpired;

  /// No description provided for @configsSubMenu.
  ///
  /// In en, this message translates to:
  /// **'subscription menu'**
  String get configsSubMenu;

  /// No description provided for @configsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} config} other{{count} configs}}'**
  String configsCount(int count);

  /// No description provided for @configsAutoSelectReset.
  ///
  /// In en, this message translates to:
  /// **'Reset auto-select'**
  String get configsAutoSelectReset;

  /// No description provided for @configsAutoSelectBest.
  ///
  /// In en, this message translates to:
  /// **'Auto-select best'**
  String get configsAutoSelectBest;

  /// No description provided for @configsEditUrl.
  ///
  /// In en, this message translates to:
  /// **'Change URL'**
  String get configsEditUrl;

  /// No description provided for @configsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get configsRefresh;

  /// No description provided for @configsConfigMenu.
  ///
  /// In en, this message translates to:
  /// **'configuration menu'**
  String get configsConfigMenu;

  /// No description provided for @configsNotInSub.
  ///
  /// In en, this message translates to:
  /// **'not in subscription'**
  String get configsNotInSub;

  /// No description provided for @configsPinned.
  ///
  /// In en, this message translates to:
  /// **'pinned'**
  String get configsPinned;

  /// No description provided for @configsPinUnavailable.
  ///
  /// In en, this message translates to:
  /// **'unavailable · tap to unpin'**
  String get configsPinUnavailable;

  /// No description provided for @configsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add a configuration\nor a subscription'**
  String get configsEmpty;

  /// No description provided for @routingSplitOff.
  ///
  /// In en, this message translates to:
  /// **'off · all apps through VPN'**
  String get routingSplitOff;

  /// No description provided for @routingSplitOnly.
  ///
  /// In en, this message translates to:
  /// **'{count} apps · ONLY'**
  String routingSplitOnly(int count);

  /// No description provided for @routingSplitExcept.
  ///
  /// In en, this message translates to:
  /// **'{count} apps · EXCEPT'**
  String routingSplitExcept(int count);

  /// No description provided for @routingModeGlobalHint.
  ///
  /// In en, this message translates to:
  /// **'all traffic through VPN · rules off'**
  String get routingModeGlobalHint;

  /// No description provided for @routingModeBypassHint.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} rule} other{{count} rules}} · matched go direct, the rest through VPN'**
  String routingModeBypassHint(int count);

  /// No description provided for @routingModeOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} rule} other{{count} rules}} · only matched through VPN'**
  String routingModeOnlyHint(int count);

  /// No description provided for @routingGeoMissingHint.
  ///
  /// In en, this message translates to:
  /// **'Download the geo databases (geo.data section below)'**
  String get routingGeoMissingHint;

  /// No description provided for @routingSniffHint.
  ///
  /// In en, this message translates to:
  /// **'Requires sniffing (the \"Sniffing\" switch above)'**
  String get routingSniffHint;

  /// No description provided for @routingTagline.
  ///
  /// In en, this message translates to:
  /// **'ROUTING · SPLIT-TUNNEL'**
  String get routingTagline;

  /// No description provided for @routingSplitTunnel.
  ///
  /// In en, this message translates to:
  /// **'Split tunneling'**
  String get routingSplitTunnel;

  /// No description provided for @routingLocalNetworks.
  ///
  /// In en, this message translates to:
  /// **'Local networks'**
  String get routingLocalNetworks;

  /// No description provided for @routingLocalNetworksHint.
  ///
  /// In en, this message translates to:
  /// **'Don\'t tunnel 10/8, 192.168/16'**
  String get routingLocalNetworksHint;

  /// No description provided for @routingAddRegion.
  ///
  /// In en, this message translates to:
  /// **'region'**
  String get routingAddRegion;

  /// No description provided for @routingSniffing.
  ///
  /// In en, this message translates to:
  /// **'Sniffing'**
  String get routingSniffing;

  /// No description provided for @routingSniffingHint.
  ///
  /// In en, this message translates to:
  /// **'Detect the domain from TLS SNI · needed for domain.suffix and geosite'**
  String get routingSniffingHint;

  /// No description provided for @routingAddSuffix.
  ///
  /// In en, this message translates to:
  /// **'suffix'**
  String get routingAddSuffix;

  /// No description provided for @routingAddCategory.
  ///
  /// In en, this message translates to:
  /// **'category'**
  String get routingAddCategory;

  /// No description provided for @routingAddSite.
  ///
  /// In en, this message translates to:
  /// **'site'**
  String get routingAddSite;

  /// No description provided for @routingAdBlock.
  ///
  /// In en, this message translates to:
  /// **'Ad blocking'**
  String get routingAdBlock;

  /// No description provided for @routingRuServices.
  ///
  /// In en, this message translates to:
  /// **'Russian services'**
  String get routingRuServices;

  /// No description provided for @routingRuServicesHint.
  ///
  /// In en, this message translates to:
  /// **'Yandex, VK, Sber, Ozon, Avito, etc. → selected outbound'**
  String get routingRuServicesHint;

  /// No description provided for @routingKillSwitchHint.
  ///
  /// In en, this message translates to:
  /// **'Block traffic when the VPN drops'**
  String get routingKillSwitchHint;

  /// No description provided for @routingSource.
  ///
  /// In en, this message translates to:
  /// **'SOURCE'**
  String get routingSource;

  /// No description provided for @routingSourceCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get routingSourceCustom;

  /// No description provided for @countryRu.
  ///
  /// In en, this message translates to:
  /// **'Russia'**
  String get countryRu;

  /// No description provided for @countryBy.
  ///
  /// In en, this message translates to:
  /// **'Belarus'**
  String get countryBy;

  /// No description provided for @countryKz.
  ///
  /// In en, this message translates to:
  /// **'Kazakhstan'**
  String get countryKz;

  /// No description provided for @countryUa.
  ///
  /// In en, this message translates to:
  /// **'Ukraine'**
  String get countryUa;

  /// No description provided for @countryCn.
  ///
  /// In en, this message translates to:
  /// **'China'**
  String get countryCn;

  /// No description provided for @countryUs.
  ///
  /// In en, this message translates to:
  /// **'USA'**
  String get countryUs;

  /// No description provided for @countryDe.
  ///
  /// In en, this message translates to:
  /// **'Germany'**
  String get countryDe;

  /// No description provided for @countryGb.
  ///
  /// In en, this message translates to:
  /// **'United Kingdom'**
  String get countryGb;

  /// No description provided for @countryFr.
  ///
  /// In en, this message translates to:
  /// **'France'**
  String get countryFr;

  /// No description provided for @countryNl.
  ///
  /// In en, this message translates to:
  /// **'Netherlands'**
  String get countryNl;

  /// No description provided for @countryTr.
  ///
  /// In en, this message translates to:
  /// **'Turkey'**
  String get countryTr;

  /// No description provided for @countryJp.
  ///
  /// In en, this message translates to:
  /// **'Japan'**
  String get countryJp;

  /// No description provided for @countrySe.
  ///
  /// In en, this message translates to:
  /// **'Sweden'**
  String get countrySe;

  /// No description provided for @countryFi.
  ///
  /// In en, this message translates to:
  /// **'Finland'**
  String get countryFi;

  /// No description provided for @countryPl.
  ///
  /// In en, this message translates to:
  /// **'Poland'**
  String get countryPl;

  /// No description provided for @routingRegions.
  ///
  /// In en, this message translates to:
  /// **'REGIONS'**
  String get routingRegions;

  /// No description provided for @routingCountries.
  ///
  /// In en, this message translates to:
  /// **'countries'**
  String get routingCountries;

  /// No description provided for @routingServices.
  ///
  /// In en, this message translates to:
  /// **'services'**
  String get routingServices;

  /// No description provided for @routingGeoipCustomHint.
  ///
  /// In en, this message translates to:
  /// **'Code or category (e.g. IT, netflix)'**
  String get routingGeoipCustomHint;

  /// No description provided for @routingSuffixes.
  ///
  /// In en, this message translates to:
  /// **'SUFFIXES'**
  String get routingSuffixes;

  /// No description provided for @routingDomainCustomHint.
  ///
  /// In en, this message translates to:
  /// **'Domain or zone (e.g. example.com)'**
  String get routingDomainCustomHint;

  /// No description provided for @routingSites.
  ///
  /// In en, this message translates to:
  /// **'SITES'**
  String get routingSites;

  /// No description provided for @routingSiteCustomHint.
  ///
  /// In en, this message translates to:
  /// **'Site (e.g. example.com)'**
  String get routingSiteCustomHint;

  /// No description provided for @geositeCategoryRu.
  ///
  /// In en, this message translates to:
  /// **'Russia (category)'**
  String get geositeCategoryRu;

  /// No description provided for @geositeGeoDetect.
  ///
  /// In en, this message translates to:
  /// **'Geo-detect services'**
  String get geositeGeoDetect;

  /// No description provided for @geositeGames.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get geositeGames;

  /// No description provided for @routingCategories.
  ///
  /// In en, this message translates to:
  /// **'CATEGORIES'**
  String get routingCategories;

  /// No description provided for @routingGeositeCustomHint.
  ///
  /// In en, this message translates to:
  /// **'Category (e.g. geolocation-!cn)'**
  String get routingGeositeCustomHint;

  /// No description provided for @routingModeAll.
  ///
  /// In en, this message translates to:
  /// **'all traffic'**
  String get routingModeAll;

  /// No description provided for @routingModeRules.
  ///
  /// In en, this message translates to:
  /// **'by rules'**
  String get routingModeRules;

  /// No description provided for @routingModeMatch.
  ///
  /// In en, this message translates to:
  /// **'match only'**
  String get routingModeMatch;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'DONE'**
  String get commonDone;

  /// No description provided for @geoNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'Geo databases not downloaded'**
  String get geoNotLoaded;

  /// No description provided for @geoHttpStatus.
  ///
  /// In en, this message translates to:
  /// **'The geo database server answered HTTP {status}'**
  String geoHttpStatus(int status);

  /// No description provided for @geoChecksumMismatch.
  ///
  /// In en, this message translates to:
  /// **'{file} doesn\'t match the checksum published next to it; the old geo databases are kept'**
  String geoChecksumMismatch(String file);

  /// No description provided for @geoDownload.
  ///
  /// In en, this message translates to:
  /// **'DOWNLOAD'**
  String get geoDownload;

  /// No description provided for @geoLoaded.
  ///
  /// In en, this message translates to:
  /// **'Geo databases downloaded'**
  String get geoLoaded;

  /// No description provided for @geoUpdate.
  ///
  /// In en, this message translates to:
  /// **'UPDATE'**
  String get geoUpdate;

  /// No description provided for @geoDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading geo databases...'**
  String get geoDownloading;

  /// No description provided for @unitMb.
  ///
  /// In en, this message translates to:
  /// **'MB'**
  String get unitMb;

  /// No description provided for @commonRetryUpper.
  ///
  /// In en, this message translates to:
  /// **'RETRY'**
  String get commonRetryUpper;

  /// No description provided for @geoUpdatedToday.
  ///
  /// In en, this message translates to:
  /// **'Updated today'**
  String get geoUpdatedToday;

  /// No description provided for @geoUpdatedYesterday.
  ///
  /// In en, this message translates to:
  /// **'Updated yesterday'**
  String get geoUpdatedYesterday;

  /// No description provided for @geoUpdatedDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'Updated {count} days ago'**
  String geoUpdatedDaysAgo(int count);

  /// No description provided for @commonApplyUpper.
  ///
  /// In en, this message translates to:
  /// **'APPLY'**
  String get commonApplyUpper;

  /// No description provided for @settingsTagline.
  ///
  /// In en, this message translates to:
  /// **'PARAMETERS · LOCAL PROFILE'**
  String get settingsTagline;

  /// No description provided for @settingsProfileLocked.
  ///
  /// In en, this message translates to:
  /// **'profile locked · read-only'**
  String get settingsProfileLocked;

  /// No description provided for @settingsProfileAutosave.
  ///
  /// In en, this message translates to:
  /// **'profile: {name} · autosave'**
  String settingsProfileAutosave(String name);

  /// No description provided for @settingsLogs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get settingsLogs;

  /// No description provided for @settingsLogsHint.
  ///
  /// In en, this message translates to:
  /// **'app and xray log'**
  String get settingsLogsHint;

  /// No description provided for @settingsAutoConnect.
  ///
  /// In en, this message translates to:
  /// **'Auto-connect'**
  String get settingsAutoConnect;

  /// No description provided for @settingsAutoConnectHint.
  ///
  /// In en, this message translates to:
  /// **'Connect when the app starts'**
  String get settingsAutoConnectHint;

  /// No description provided for @settingsStartOnBoot.
  ///
  /// In en, this message translates to:
  /// **'Start on boot'**
  String get settingsStartOnBoot;

  /// No description provided for @settingsStartOnBootHint.
  ///
  /// In en, this message translates to:
  /// **'Connect automatically after the device reboots'**
  String get settingsStartOnBootHint;

  /// No description provided for @settingsAutomation.
  ///
  /// In en, this message translates to:
  /// **'Automation'**
  String get settingsAutomation;

  /// No description provided for @settingsAutomationHint.
  ///
  /// In en, this message translates to:
  /// **'Tasker/Anubis: CONNECT/DISCONNECT commands and state broadcasts. Any app will be able to turn off the VPN and learn that it is on'**
  String get settingsAutomationHint;

  /// No description provided for @settingsNotification.
  ///
  /// In en, this message translates to:
  /// **'Notification'**
  String get settingsNotification;

  /// No description provided for @settingsPingWhileConnected.
  ///
  /// In en, this message translates to:
  /// **'Ping servers while connected'**
  String get settingsPingWhileConnected;

  /// No description provided for @settingsPingWhileConnectedHint.
  ///
  /// In en, this message translates to:
  /// **'Pings go outside the VPN: the network sees every server in your list'**
  String get settingsPingWhileConnectedHint;

  /// No description provided for @configsPingWhileConnectedOff.
  ///
  /// In en, this message translates to:
  /// **'Pings go outside the VPN and would show the network your server list. Disconnect to ping, or allow it in Settings → Ping servers while connected.'**
  String get configsPingWhileConnectedOff;

  /// No description provided for @settingsNotificationHint.
  ///
  /// In en, this message translates to:
  /// **'Speed and a disconnect button in the shade'**
  String get settingsNotificationHint;

  /// No description provided for @settingsBattery.
  ///
  /// In en, this message translates to:
  /// **'Battery optimization'**
  String get settingsBattery;

  /// No description provided for @settingsBatteryHint.
  ///
  /// In en, this message translates to:
  /// **'Let the VPN run in the background without being stopped'**
  String get settingsBatteryHint;

  /// No description provided for @settingsSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get settingsSubscriptions;

  /// No description provided for @settingsSubAutoRefreshOn.
  ///
  /// In en, this message translates to:
  /// **'auto-refresh · {hours}h'**
  String settingsSubAutoRefreshOn(int hours);

  /// No description provided for @settingsSubAutoRefreshOff.
  ///
  /// In en, this message translates to:
  /// **'auto-refresh off'**
  String get settingsSubAutoRefreshOff;

  /// No description provided for @settingsNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get settingsNetwork;

  /// No description provided for @settingsProxyOnlyShort.
  ///
  /// In en, this message translates to:
  /// **'proxy only'**
  String get settingsProxyOnlyShort;

  /// No description provided for @dnsViaVpn.
  ///
  /// In en, this message translates to:
  /// **'via VPN'**
  String get dnsViaVpn;

  /// No description provided for @dnsDirect.
  ///
  /// In en, this message translates to:
  /// **'direct'**
  String get dnsDirect;

  /// No description provided for @settingsUpdateChannel.
  ///
  /// In en, this message translates to:
  /// **'Update channel'**
  String get settingsUpdateChannel;

  /// No description provided for @settingsCoreLastEnabled.
  ///
  /// In en, this message translates to:
  /// **'At least one core must stay enabled'**
  String get settingsCoreLastEnabled;

  /// No description provided for @settingsCores.
  ///
  /// In en, this message translates to:
  /// **'Cores'**
  String get settingsCores;

  /// No description provided for @settingsCoresHint.
  ///
  /// In en, this message translates to:
  /// **'A profile runs on the topmost core that supports it'**
  String get settingsCoresHint;

  /// No description provided for @settingsCoreMoveUp.
  ///
  /// In en, this message translates to:
  /// **'move {core} up'**
  String settingsCoreMoveUp(String core);

  /// No description provided for @settingsCoreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'doesn\'t load on this device'**
  String get settingsCoreUnavailable;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'DARK'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'LIGHT'**
  String get settingsThemeLight;

  /// No description provided for @settingsSystem.
  ///
  /// In en, this message translates to:
  /// **'SYSTEM'**
  String get settingsSystem;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get settingsFontSize;

  /// No description provided for @settingsFontNormal.
  ///
  /// In en, this message translates to:
  /// **'NORMAL'**
  String get settingsFontNormal;

  /// No description provided for @settingsFontLarge.
  ///
  /// In en, this message translates to:
  /// **'LARGE'**
  String get settingsFontLarge;

  /// No description provided for @settingsAccentColor.
  ///
  /// In en, this message translates to:
  /// **'ACCENT COLOR'**
  String get settingsAccentColor;

  /// No description provided for @updateTitle.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updateTitle;

  /// No description provided for @updateCheck.
  ///
  /// In en, this message translates to:
  /// **'CHECK'**
  String get updateCheck;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get updateChecking;

  /// No description provided for @updateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading v{version}'**
  String updateDownloading(String version);

  /// No description provided for @commonCancelUpper.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get commonCancelUpper;

  /// No description provided for @updateReadyToInstall.
  ///
  /// In en, this message translates to:
  /// **'v{version} ready to install'**
  String updateReadyToInstall(String version);

  /// No description provided for @updateInstall.
  ///
  /// In en, this message translates to:
  /// **'INSTALL'**
  String get updateInstall;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'update available'**
  String get updateAvailable;

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'up to date'**
  String get updateUpToDate;

  /// No description provided for @updateResume.
  ///
  /// In en, this message translates to:
  /// **'RESUME'**
  String get updateResume;

  /// No description provided for @updateDownload.
  ///
  /// In en, this message translates to:
  /// **'DOWNLOAD'**
  String get updateDownload;

  /// No description provided for @updateReinstall.
  ///
  /// In en, this message translates to:
  /// **'REINSTALL'**
  String get updateReinstall;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'loading...'**
  String get commonLoading;

  /// No description provided for @profileReadonly.
  ///
  /// In en, this message translates to:
  /// **'read-only'**
  String get profileReadonly;

  /// No description provided for @settingsProfiles.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get settingsProfiles;

  /// No description provided for @networkTagline.
  ///
  /// In en, this message translates to:
  /// **'NETWORK · SOCKS · TUN'**
  String get networkTagline;

  /// No description provided for @networkRandomPort.
  ///
  /// In en, this message translates to:
  /// **'Random port'**
  String get networkRandomPort;

  /// No description provided for @networkRandomPortHint.
  ///
  /// In en, this message translates to:
  /// **'Random SOCKS port on every connection'**
  String get networkRandomPortHint;

  /// No description provided for @networkSocksPort.
  ///
  /// In en, this message translates to:
  /// **'SOCKS5 port'**
  String get networkSocksPort;

  /// No description provided for @networkRandomCreds.
  ///
  /// In en, this message translates to:
  /// **'Random credentials'**
  String get networkRandomCreds;

  /// No description provided for @networkRandomCredsHint.
  ///
  /// In en, this message translates to:
  /// **'Generate a random SOCKS login/password'**
  String get networkRandomCredsHint;

  /// No description provided for @networkSocksLogin.
  ///
  /// In en, this message translates to:
  /// **'SOCKS login'**
  String get networkSocksLogin;

  /// No description provided for @networkNoAuth.
  ///
  /// In en, this message translates to:
  /// **'no password'**
  String get networkNoAuth;

  /// No description provided for @networkSocksPassword.
  ///
  /// In en, this message translates to:
  /// **'SOCKS password'**
  String get networkSocksPassword;

  /// No description provided for @networkProxyOnly.
  ///
  /// In en, this message translates to:
  /// **'Proxy only'**
  String get networkProxyOnly;

  /// No description provided for @networkProxyOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Run the SOCKS proxy without a VPN tunnel'**
  String get networkProxyOnlyHint;

  /// No description provided for @networkUdpHint.
  ///
  /// In en, this message translates to:
  /// **'Allow UDP traffic through SOCKS'**
  String get networkUdpHint;

  /// No description provided for @networkIcmpHint.
  ///
  /// In en, this message translates to:
  /// **'Answer pings: the proxy doesn\'t carry ICMP, the VPN replies itself — the time doesn\'t reflect latency to the host'**
  String get networkIcmpHint;

  /// No description provided for @networkBlockQuic.
  ///
  /// In en, this message translates to:
  /// **'Block QUIC'**
  String get networkBlockQuic;

  /// No description provided for @networkBlockQuicHint.
  ///
  /// In en, this message translates to:
  /// **'TUN answers UDP 443 with an ICMP \"port unreachable\": the browser instantly falls back to TCP instead of waiting for the QUIC timeout (~55s). No traffic leaves the device.'**
  String get networkBlockQuicHint;

  /// No description provided for @networkFingerprintHint.
  ///
  /// In en, this message translates to:
  /// **'uTLS ClientHello camouflage (TLS/REALITY)'**
  String get networkFingerprintHint;

  /// No description provided for @networkIpv6.
  ///
  /// In en, this message translates to:
  /// **'IPv6 in tunnel'**
  String get networkIpv6;

  /// No description provided for @networkIpv6Hint.
  ///
  /// In en, this message translates to:
  /// **'Add an IPv6 address to the TUN interface. Enable only if the VPN server has IPv6: otherwise apps with IPv6 addresses (Telegram) hang. When off, IPv6 is blocked by the system without leaks — apps fall back to IPv4 instantly.'**
  String get networkIpv6Hint;

  /// No description provided for @networkObservatoryInterval.
  ///
  /// In en, this message translates to:
  /// **'Observatory min. interval, sec'**
  String get networkObservatoryInterval;

  /// No description provided for @networkFragment.
  ///
  /// In en, this message translates to:
  /// **'Fragmentation'**
  String get networkFragment;

  /// No description provided for @networkFragmentHint.
  ///
  /// In en, this message translates to:
  /// **'Splits the outgoing TCP stream into pieces so DPI can\'t reassemble the whole ClientHello. Doesn\'t apply to Hysteria2 (QUIC over UDP).'**
  String get networkFragmentHint;

  /// No description provided for @networkFragmentPackets.
  ///
  /// In en, this message translates to:
  /// **'Packets'**
  String get networkFragmentPackets;

  /// No description provided for @networkFragmentLength.
  ///
  /// In en, this message translates to:
  /// **'Chunk length, bytes'**
  String get networkFragmentLength;

  /// No description provided for @networkPauseMs.
  ///
  /// In en, this message translates to:
  /// **'Pause, ms'**
  String get networkPauseMs;

  /// No description provided for @networkFragmentInvalid.
  ///
  /// In en, this message translates to:
  /// **'Length and pause must be ranges like 100-200 and 10-20, packets — tlshello or a range. Fragmentation is not applied.'**
  String get networkFragmentInvalid;

  /// No description provided for @networkNoise.
  ///
  /// In en, this message translates to:
  /// **'Noise'**
  String get networkNoise;

  /// No description provided for @networkNoiseHint.
  ///
  /// In en, this message translates to:
  /// **'Junk UDP datagrams before the first real one. Work only on the UDP leg — Hysteria2 and the QUIC transport; they don\'t affect TCP (use fragmentation there). Xray DNS queries are not affected.'**
  String get networkNoiseHint;

  /// No description provided for @networkNoiseType.
  ///
  /// In en, this message translates to:
  /// **'Packet type'**
  String get networkNoiseType;

  /// No description provided for @networkNoiseTypeHint.
  ///
  /// In en, this message translates to:
  /// **'RAND — random bytes; STR / HEX / BASE64 — set manually'**
  String get networkNoiseTypeHint;

  /// No description provided for @networkNoiseLength.
  ///
  /// In en, this message translates to:
  /// **'Length, bytes'**
  String get networkNoiseLength;

  /// No description provided for @networkNoisePacket.
  ///
  /// In en, this message translates to:
  /// **'Packet'**
  String get networkNoisePacket;

  /// No description provided for @networkNoiseContent.
  ///
  /// In en, this message translates to:
  /// **'content'**
  String get networkNoiseContent;

  /// No description provided for @networkNoiseInvalidRand.
  ///
  /// In en, this message translates to:
  /// **'Length must be a range like 50-100, pause — 10-20. Noise is not applied.'**
  String get networkNoiseInvalidRand;

  /// No description provided for @networkNoiseInvalidPacket.
  ///
  /// In en, this message translates to:
  /// **'Packet must not be empty, pause — a range like 10-20. Noise is not applied.'**
  String get networkNoiseInvalidPacket;

  /// No description provided for @networkMuxHint.
  ///
  /// In en, this message translates to:
  /// **'Multiplexes several connections into one — fewer handshakes. With XTLS Vision the TCP branch is disabled automatically (XUDP stays). Doesn\'t apply to Hysteria2.'**
  String get networkMuxHint;

  /// No description provided for @networkMuxTcp.
  ///
  /// In en, this message translates to:
  /// **'TCP substreams'**
  String get networkMuxTcp;

  /// No description provided for @networkMuxXudp.
  ///
  /// In en, this message translates to:
  /// **'XUDP substreams'**
  String get networkMuxXudp;

  /// No description provided for @networkMuxQuic.
  ///
  /// In en, this message translates to:
  /// **'QUIC (UDP/443) via mux'**
  String get networkMuxQuic;

  /// No description provided for @networkMuxQuicHint.
  ///
  /// In en, this message translates to:
  /// **'reject — drop, allow — pass through mux, skip — bypass mux'**
  String get networkMuxQuicHint;

  /// No description provided for @networkProbeType.
  ///
  /// In en, this message translates to:
  /// **'Probe type'**
  String get networkProbeType;

  /// No description provided for @networkProbeTypeHint.
  ///
  /// In en, this message translates to:
  /// **'SOCKS — HTTP request through SOCKS5 into xray; XRAYDELAY — measured inside the core, gives latency directly; PASSIVE — no active probes, only tun2socks metrics (saves battery, a drop is noticed only with real traffic)'**
  String get networkProbeTypeHint;

  /// No description provided for @networkProbeTarget.
  ///
  /// In en, this message translates to:
  /// **'Probe target'**
  String get networkProbeTarget;

  /// No description provided for @networkProbeTargetHint.
  ///
  /// In en, this message translates to:
  /// **'Where the probe goes. CUSTOM — your own URL below'**
  String get networkProbeTargetHint;

  /// No description provided for @networkFailureThreshold.
  ///
  /// In en, this message translates to:
  /// **'Failures before action'**
  String get networkFailureThreshold;

  /// No description provided for @networkFailAction.
  ///
  /// In en, this message translates to:
  /// **'When the tunnel is lost'**
  String get networkFailAction;

  /// No description provided for @networkFailActionHint.
  ///
  /// In en, this message translates to:
  /// **'RECONNECT — reconnect to the same server; SWITCHCONFIG — move to the fastest live config'**
  String get networkFailActionHint;

  /// No description provided for @networkSwitchSource.
  ///
  /// In en, this message translates to:
  /// **'Where to take a config from'**
  String get networkSwitchSource;

  /// No description provided for @networkSwitchSourceHint.
  ///
  /// In en, this message translates to:
  /// **'SUBSCRIPTION — configs of the same subscription; PINNED — pinned ones; ALL — all saved. Candidates are checked with a full measurement through the protocol itself, not a TCP ping'**
  String get networkSwitchSourceHint;

  /// No description provided for @profilesTagline.
  ///
  /// In en, this message translates to:
  /// **'MANAGEMENT · PROFILES'**
  String get profilesTagline;

  /// No description provided for @profilesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'switch and manage settings profiles'**
  String get profilesSubtitle;

  /// No description provided for @profilesNew.
  ///
  /// In en, this message translates to:
  /// **'New profile'**
  String get profilesNew;

  /// No description provided for @profilesNameHint.
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get profilesNameHint;

  /// No description provided for @profilesCopyCurrent.
  ///
  /// In en, this message translates to:
  /// **'Copy current settings'**
  String get profilesCopyCurrent;

  /// No description provided for @commonCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get commonCreate;

  /// No description provided for @profileImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import profile'**
  String get profileImportTitle;

  /// No description provided for @profilesImportHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a link (teapod://...) or profile JSON'**
  String get profilesImportHint;

  /// No description provided for @profilesSwitchAfterImport.
  ///
  /// In en, this message translates to:
  /// **'Switch after import'**
  String get profilesSwitchAfterImport;

  /// No description provided for @profilesReadonly.
  ///
  /// In en, this message translates to:
  /// **'Read-only'**
  String get profilesReadonly;

  /// No description provided for @bundleInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid format: {detail}'**
  String bundleInvalid(String detail);

  /// No description provided for @commonImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get commonImport;

  /// No description provided for @profilesExportUpper.
  ///
  /// In en, this message translates to:
  /// **'EXPORT'**
  String get profilesExportUpper;

  /// No description provided for @profilesCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get profilesCopyLink;

  /// No description provided for @profilesLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get profilesLinkCopied;

  /// No description provided for @profilesShareFile.
  ///
  /// In en, this message translates to:
  /// **'Share as file'**
  String get profilesShareFile;

  /// No description provided for @profilesDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete profile?'**
  String get profilesDeleteTitle;

  /// No description provided for @profilesDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be deleted permanently.'**
  String profilesDeleteMessage(String name);

  /// No description provided for @profilesUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile \"{name}\" updated'**
  String profilesUpdated(String name);

  /// No description provided for @profilesUpdateError.
  ///
  /// In en, this message translates to:
  /// **'Update error'**
  String get profilesUpdateError;

  /// No description provided for @profilesSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get profilesSwitch;

  /// No description provided for @profilesUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get profilesUnlock;

  /// No description provided for @profilesLock.
  ///
  /// In en, this message translates to:
  /// **'Lock editing'**
  String get profilesLock;

  /// No description provided for @profilesExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get profilesExport;

  /// No description provided for @deeplinkFetchFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load data from the link'**
  String get deeplinkFetchFailed;

  /// No description provided for @splitTethering.
  ///
  /// In en, this message translates to:
  /// **'Tethering through VPN'**
  String get splitTethering;

  /// No description provided for @splitTetheringWarning.
  ///
  /// In en, this message translates to:
  /// **'Hotspot traffic is indistinguishable from the traffic of excluded apps. With this option any excluded app can send a request through the VPN and learn the server IP — for example, to report it.\n\nEnable only if you need to share internet through the VPN.'**
  String get splitTetheringWarning;

  /// No description provided for @commonEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get commonEnable;

  /// No description provided for @splitTagline.
  ///
  /// In en, this message translates to:
  /// **'APPS · SPLIT-TUNNEL'**
  String get splitTagline;

  /// No description provided for @splitSelectedOnly.
  ///
  /// In en, this message translates to:
  /// **'{count} selected · only through VPN'**
  String splitSelectedOnly(int count);

  /// No description provided for @splitExcluded.
  ///
  /// In en, this message translates to:
  /// **'{count} excluded · the rest through VPN'**
  String splitExcluded(int count);

  /// No description provided for @splitEnabled.
  ///
  /// In en, this message translates to:
  /// **'enabled'**
  String get splitEnabled;

  /// No description provided for @splitDisabled.
  ///
  /// In en, this message translates to:
  /// **'disabled — all traffic through VPN'**
  String get splitDisabled;

  /// No description provided for @splitVpnMode.
  ///
  /// In en, this message translates to:
  /// **'VPN mode'**
  String get splitVpnMode;

  /// No description provided for @splitModeOnly.
  ///
  /// In en, this message translates to:
  /// **'ONLY'**
  String get splitModeOnly;

  /// No description provided for @splitModeExcept.
  ///
  /// In en, this message translates to:
  /// **'EXCEPT'**
  String get splitModeExcept;

  /// No description provided for @splitTetheringHint.
  ///
  /// In en, this message translates to:
  /// **'Route hotspot traffic into the tunnel'**
  String get splitTetheringHint;

  /// No description provided for @splitTetheringWeakened.
  ///
  /// In en, this message translates to:
  /// **'Protection weakened: excluded apps can go out through the VPN and learn the server IP'**
  String get splitTetheringWeakened;

  /// No description provided for @splitSearchHint.
  ///
  /// In en, this message translates to:
  /// **'search apps...'**
  String get splitSearchHint;

  /// No description provided for @splitHideSystem.
  ///
  /// In en, this message translates to:
  /// **'Hide system apps'**
  String get splitHideSystem;

  /// No description provided for @splitNoApps.
  ///
  /// In en, this message translates to:
  /// **'no apps'**
  String get splitNoApps;

  /// No description provided for @addTagline.
  ///
  /// In en, this message translates to:
  /// **'CONFIGURATION · NEW PROFILE'**
  String get addTagline;

  /// No description provided for @addFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'from clipboard: {text}'**
  String addFromClipboard(String text);

  /// No description provided for @addPaste.
  ///
  /// In en, this message translates to:
  /// **'PASTE'**
  String get addPaste;

  /// No description provided for @addAdd.
  ///
  /// In en, this message translates to:
  /// **'ADD'**
  String get addAdd;

  /// No description provided for @addEnterUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a URL'**
  String get addEnterUrl;

  /// No description provided for @addDeeplinkParseFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t parse the deeplink'**
  String get addDeeplinkParseFailed;

  /// No description provided for @addImported.
  ///
  /// In en, this message translates to:
  /// **'Imported: {configs}, {subscriptions}'**
  String addImported(String configs, String subscriptions);

  /// No description provided for @subscriptionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} subscription} other{{count} subscriptions}}'**
  String subscriptionsCount(int count);

  /// No description provided for @addParseFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t recognize the configuration. Supported: vless://, vmess://, trojan://, ss://, hy2://, wireguard://, vpn:// (AmneziaVPN) and WireGuard .conf'**
  String get addParseFailed;

  /// No description provided for @whatsNewTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get whatsNewTitle;

  /// No description provided for @whatsNewTagline.
  ///
  /// In en, this message translates to:
  /// **'RELEASE NOTES · ALL VERSIONS'**
  String get whatsNewTagline;

  /// No description provided for @subsTagline.
  ///
  /// In en, this message translates to:
  /// **'SUBSCRIPTIONS · REFRESH'**
  String get subsTagline;

  /// No description provided for @subsAutoRefresh.
  ///
  /// In en, this message translates to:
  /// **'Subscription auto-refresh'**
  String get subsAutoRefresh;

  /// No description provided for @subsAutoRefreshHint.
  ///
  /// In en, this message translates to:
  /// **'Refresh subscriptions on a schedule'**
  String get subsAutoRefreshHint;

  /// No description provided for @subsInterval.
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get subsInterval;

  /// No description provided for @unitHours.
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String unitHours(int count);

  /// No description provided for @subsHwidHint.
  ///
  /// In en, this message translates to:
  /// **'Send the device ID to bind the subscription'**
  String get subsHwidHint;

  /// No description provided for @commonDefaultLower.
  ///
  /// In en, this message translates to:
  /// **'default'**
  String get commonDefaultLower;

  /// No description provided for @shareProfileText.
  ///
  /// In en, this message translates to:
  /// **'Teapod profile: {name}'**
  String shareProfileText(String name);

  /// No description provided for @shareLogSubject.
  ///
  /// In en, this message translates to:
  /// **'TeapodStream log'**
  String get shareLogSubject;

  /// No description provided for @logsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Log is empty'**
  String get logsEmpty;

  /// No description provided for @logsTagline.
  ///
  /// In en, this message translates to:
  /// **'LOG · XRAY · TUN2SOCKS'**
  String get logsTagline;

  /// No description provided for @qrCameraError.
  ///
  /// In en, this message translates to:
  /// **'Camera error: {error}'**
  String qrCameraError(String error);

  /// No description provided for @qrTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get qrTitle;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @qrHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at a QR code'**
  String get qrHint;

  /// No description provided for @commonSaveUpper.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get commonSaveUpper;

  /// No description provided for @dnsTagline.
  ///
  /// In en, this message translates to:
  /// **'SETTINGS · DNS RESOLVER'**
  String get dnsTagline;

  /// No description provided for @dnsMode.
  ///
  /// In en, this message translates to:
  /// **'DNS mode'**
  String get dnsMode;

  /// No description provided for @dnsViaTunnel.
  ///
  /// In en, this message translates to:
  /// **'via VPN tunnel'**
  String get dnsViaTunnel;

  /// No description provided for @dnsStrategy.
  ///
  /// In en, this message translates to:
  /// **'DNS strategy'**
  String get dnsStrategy;

  /// No description provided for @dnsStrategyHint.
  ///
  /// In en, this message translates to:
  /// **'IP version for DNS queries'**
  String get dnsStrategyHint;

  /// No description provided for @dnsProtocolType.
  ///
  /// In en, this message translates to:
  /// **'PROTOCOL TYPE'**
  String get dnsProtocolType;

  /// No description provided for @dnsServerAddress.
  ///
  /// In en, this message translates to:
  /// **'SERVER ADDRESS'**
  String get dnsServerAddress;

  /// No description provided for @coreInUse.
  ///
  /// In en, this message translates to:
  /// **'in use'**
  String get coreInUse;

  /// No description provided for @coreCompatible.
  ///
  /// In en, this message translates to:
  /// **'compatible'**
  String get coreCompatible;

  /// No description provided for @coreProfileCore.
  ///
  /// In en, this message translates to:
  /// **'PROFILE CORE'**
  String get coreProfileCore;

  /// No description provided for @coreAuto.
  ///
  /// In en, this message translates to:
  /// **'AUTO'**
  String get coreAuto;

  /// No description provided for @coreAutoHint.
  ///
  /// In en, this message translates to:
  /// **'AUTO — the first suitable core by the priority in settings. A pinned core is tried first.'**
  String get coreAutoHint;

  /// No description provided for @featureUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Not supported: {cores}.'**
  String featureUnsupported(String cores);

  /// No description provided for @reconnectBanner.
  ///
  /// In en, this message translates to:
  /// **'settings changed · will apply after reconnecting'**
  String get reconnectBanner;

  /// No description provided for @reconnectButton.
  ///
  /// In en, this message translates to:
  /// **'RECONNECT'**
  String get reconnectButton;

  /// No description provided for @settingsReadonlySnack.
  ///
  /// In en, this message translates to:
  /// **'Profile is read-only'**
  String get settingsReadonlySnack;

  /// No description provided for @deeplinkHttpsOnly.
  ///
  /// In en, this message translates to:
  /// **'Import by link supports https only'**
  String get deeplinkHttpsOnly;

  /// No description provided for @deeplinkProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile: \"{name}\"'**
  String deeplinkProfile(String name);

  /// No description provided for @deeplinkExported.
  ///
  /// In en, this message translates to:
  /// **'Exported: {date}'**
  String deeplinkExported(String date);

  /// No description provided for @deeplinkSource.
  ///
  /// In en, this message translates to:
  /// **'Source: {url}'**
  String deeplinkSource(String url);

  /// No description provided for @deeplinkProfileImported.
  ///
  /// In en, this message translates to:
  /// **'Profile \"{name}\" imported'**
  String deeplinkProfileImported(String name);

  /// No description provided for @deeplinkConnectionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Import connections'**
  String get deeplinkConnectionsTitle;

  /// No description provided for @deeplinkBundle.
  ///
  /// In en, this message translates to:
  /// **'Bundle: \"{label}\"'**
  String deeplinkBundle(String label);

  /// No description provided for @deeplinkAdded.
  ///
  /// In en, this message translates to:
  /// **'Added: {items}'**
  String deeplinkAdded(String items);

  /// No description provided for @deeplinkAddedNew.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Added: {count} new config} other{Added: {count} new configs}}'**
  String deeplinkAddedNew(int count);

  /// No description provided for @deeplinkFetchTitle.
  ///
  /// In en, this message translates to:
  /// **'Load from link?'**
  String get deeplinkFetchTitle;

  /// No description provided for @deeplinkFetchMessage.
  ///
  /// In en, this message translates to:
  /// **'Import data will be loaded from {host} directly, bypassing the VPN: the server will see your real IP.'**
  String deeplinkFetchMessage(String host);

  /// No description provided for @deeplinkFetchButton.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get deeplinkFetchButton;

  /// No description provided for @rustNoRawJson.
  ///
  /// In en, this message translates to:
  /// **'Full JSON import isn\'t available in the xray-rust core yet.'**
  String get rustNoRawJson;

  /// No description provided for @rustNoFinalmask.
  ///
  /// In en, this message translates to:
  /// **'The xray-rust core doesn\'t apply the link\'s fm (finalmask) parameter. Set fragmentation and noise in network settings.'**
  String get rustNoFinalmask;

  /// No description provided for @rustLinkMux.
  ///
  /// In en, this message translates to:
  /// **'The link asks for Mux (mux=on), which isn\'t available in the xray-rust core.'**
  String get rustLinkMux;

  /// No description provided for @rustVlessEncryption.
  ///
  /// In en, this message translates to:
  /// **'The xray-rust core only accepts VLESS with encryption=none so far.'**
  String get rustVlessEncryption;

  /// No description provided for @rustVlessUuid.
  ///
  /// In en, this message translates to:
  /// **'The VLESS UUID must be a real UUID: the Rust core doesn\'t accept arbitrary strings.'**
  String get rustVlessUuid;

  /// No description provided for @rustVlessSecurity.
  ///
  /// In en, this message translates to:
  /// **'For VLESS in the xray-rust core choose TLS or Reality.'**
  String get rustVlessSecurity;

  /// No description provided for @rustVlessFlow.
  ///
  /// In en, this message translates to:
  /// **'Unknown VLESS flow.'**
  String get rustVlessFlow;

  /// No description provided for @rustVision.
  ///
  /// In en, this message translates to:
  /// **'Vision with encryption=none is supported only over TCP/RAW with TLS or Reality.'**
  String get rustVision;

  /// No description provided for @rustTrojanPassword.
  ///
  /// In en, this message translates to:
  /// **'The Trojan password must be non-empty and at most 4096 bytes.'**
  String get rustTrojanPassword;

  /// No description provided for @rustTrojanSecurity.
  ///
  /// In en, this message translates to:
  /// **'Trojan in the xray-rust core works only with TLS or Reality.'**
  String get rustTrojanSecurity;

  /// No description provided for @rustVmessId.
  ///
  /// In en, this message translates to:
  /// **'The VMess id must be a real UUID: the Rust core doesn\'t accept arbitrary strings.'**
  String get rustVmessId;

  /// No description provided for @rustSsMethod.
  ///
  /// In en, this message translates to:
  /// **'The Rust core supports only Shadowsocks 2022 (2022-blake3-aes-128-gcm, 2022-blake3-aes-256-gcm, 2022-blake3-chacha20-poly1305). Method \"{method}\" is not supported.'**
  String rustSsMethod(String method);

  /// No description provided for @rustSsPlugin.
  ///
  /// In en, this message translates to:
  /// **'The xray-rust core doesn\'t support Shadowsocks plugins (SIP003, plugin=…).'**
  String get rustSsPlugin;

  /// No description provided for @rustSsPrefix.
  ///
  /// In en, this message translates to:
  /// **'The xray-rust core doesn\'t support the Outline prefix (prefix=…) for Shadowsocks.'**
  String get rustSsPrefix;

  /// No description provided for @rustTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport not supported. Available: TCP/RAW, WebSocket, HTTPUpgrade, gRPC and xHTTP.'**
  String get rustTransport;

  /// No description provided for @rustTcpHeader.
  ///
  /// In en, this message translates to:
  /// **'The Rust core doesn\'t support TCP with HTTP camouflage (headerType={header}).'**
  String rustTcpHeader(String header);

  /// No description provided for @rustReality.
  ///
  /// In en, this message translates to:
  /// **'Reality is supported with TCP/RAW, gRPC and xHTTP. WebSocket/HTTPUpgrade need TLS.'**
  String get rustReality;

  /// No description provided for @rustEch.
  ///
  /// In en, this message translates to:
  /// **'ECH isn\'t available in the xray-rust core yet.'**
  String get rustEch;

  /// No description provided for @rustSsOneKey.
  ///
  /// In en, this message translates to:
  /// **'{method} needs a single key (no colon-separated identity keys).'**
  String rustSsOneKey(String method);

  /// No description provided for @rustSsMaxKeys.
  ///
  /// In en, this message translates to:
  /// **'{method} allows up to 8 colon-separated keys.'**
  String rustSsMaxKeys(String method);

  /// No description provided for @rustSsKey.
  ///
  /// In en, this message translates to:
  /// **'The Shadowsocks 2022 key ({method}) must be padded base64 of at least {bytes} bytes.'**
  String rustSsKey(String method, int bytes);

  /// No description provided for @rustInsecure.
  ///
  /// In en, this message translates to:
  /// **'Rust doesn\'t support allowInsecure without pinSHA256. Use a valid TLS certificate or set the server certificate\'s pinSHA256.'**
  String get rustInsecure;

  /// No description provided for @rustHy2Obfs.
  ///
  /// In en, this message translates to:
  /// **'Hysteria2 obfuscation \"{obfs}\" is not supported: the Rust core knows only Salamander.'**
  String rustHy2Obfs(String obfs);

  /// No description provided for @rustSalamanderNoPassword.
  ///
  /// In en, this message translates to:
  /// **'Salamander (obfs=salamander) needs obfs-password.'**
  String get rustSalamanderNoPassword;

  /// No description provided for @rustSalamanderPassword.
  ///
  /// In en, this message translates to:
  /// **'The Salamander password (obfs-password) must be 4 to 4096 bytes.'**
  String get rustSalamanderPassword;

  /// No description provided for @rustPortHopping.
  ///
  /// In en, this message translates to:
  /// **'The port hopping list is too long: the Rust core accepts up to 65535 ports.'**
  String get rustPortHopping;

  /// No description provided for @rustHy2Password.
  ///
  /// In en, this message translates to:
  /// **'The Hysteria2 password must be non-empty, at most 4096 bytes and without control characters.'**
  String get rustHy2Password;

  /// No description provided for @rustTunOnly.
  ///
  /// In en, this message translates to:
  /// **'Only VPN (TUN) mode is available in the xray-rust core.'**
  String get rustTunOnly;

  /// No description provided for @rustMux.
  ///
  /// In en, this message translates to:
  /// **'Mux isn\'t available in the xray-rust core: turn it off in network settings.'**
  String get rustMux;

  /// No description provided for @rustMtu.
  ///
  /// In en, this message translates to:
  /// **'The xray-rust core works with MTU 1500: restore that value in network settings.'**
  String get rustMtu;

  /// No description provided for @rustSniffing.
  ///
  /// In en, this message translates to:
  /// **'Enable domain sniffing for GeoSite and domain rules.'**
  String get rustSniffing;

  /// No description provided for @rustGeositeLimit.
  ///
  /// In en, this message translates to:
  /// **'The selected GeoSite categories exceed the xray-rust core\'s limit of 250k domain rules. Remove some of them or use another core.'**
  String get rustGeositeLimit;

  /// No description provided for @rustFragmentPackets.
  ///
  /// In en, this message translates to:
  /// **'The Rust core splits only the TLS ClientHello: set tlshello in the fragmentation \"Packets\" field.'**
  String get rustFragmentPackets;

  /// No description provided for @rustFragmentLength.
  ///
  /// In en, this message translates to:
  /// **'Fragment chunk length in the Rust core is 1 to 16384 bytes.'**
  String get rustFragmentLength;

  /// No description provided for @rustFragmentDelay.
  ///
  /// In en, this message translates to:
  /// **'Fragmentation pause in the Rust core is at most 1000 ms.'**
  String get rustFragmentDelay;

  /// No description provided for @rustFragmentXhttp.
  ///
  /// In en, this message translates to:
  /// **'The Rust core doesn\'t apply ClientHello fragmentation to xHTTP with a separate downloadSettings. Fragmentation is a global setting: turn it off in network settings to connect to this profile.'**
  String get rustFragmentXhttp;

  /// No description provided for @rustNoiseSs.
  ///
  /// In en, this message translates to:
  /// **'The Rust core doesn\'t send noise before Shadowsocks UDP (only for Hysteria2 and xHTTP over HTTP/3). Noise is a global setting: turn it off in network settings to connect to this profile.'**
  String get rustNoiseSs;

  /// No description provided for @rustNoiseDelay.
  ///
  /// In en, this message translates to:
  /// **'Noise pause in the Rust core is at most 1000 ms.'**
  String get rustNoiseDelay;

  /// No description provided for @rustNoiseHex.
  ///
  /// In en, this message translates to:
  /// **'HEX noise must consist of pairs of hex digits.'**
  String get rustNoiseHex;

  /// No description provided for @rustNoiseBase64.
  ///
  /// In en, this message translates to:
  /// **'BASE64 noise must be standard padded base64.'**
  String get rustNoiseBase64;

  /// No description provided for @rustNoisePacket.
  ///
  /// In en, this message translates to:
  /// **'A noise packet in the Rust core is at most 4096 bytes.'**
  String get rustNoisePacket;

  /// No description provided for @coreSingBoxOnly.
  ///
  /// In en, this message translates to:
  /// **'Protocol {protocol} is supported only by the sing-box core.'**
  String coreSingBoxOnly(String protocol);

  /// No description provided for @validateNoProtocolParams.
  ///
  /// In en, this message translates to:
  /// **'No {protocol} protocol parameters'**
  String validateNoProtocolParams(String protocol);

  /// No description provided for @validateEmptyAddress.
  ///
  /// In en, this message translates to:
  /// **'Empty server address'**
  String get validateEmptyAddress;

  /// No description provided for @validateInvalidPort.
  ///
  /// In en, this message translates to:
  /// **'Invalid port: {port}'**
  String validateInvalidPort(int port);

  /// No description provided for @validateEmptyUuid.
  ///
  /// In en, this message translates to:
  /// **'Empty UUID'**
  String get validateEmptyUuid;

  /// No description provided for @validateEmptyPassword.
  ///
  /// In en, this message translates to:
  /// **'Empty password'**
  String get validateEmptyPassword;

  /// No description provided for @dnsCustomServer.
  ///
  /// In en, this message translates to:
  /// **'Custom server'**
  String get dnsCustomServer;

  /// No description provided for @coreNoneAvailable.
  ///
  /// In en, this message translates to:
  /// **'No cores available.'**
  String get coreNoneAvailable;

  /// No description provided for @coreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Doesn\'t load on this device.'**
  String get coreUnavailable;

  /// No description provided for @coreDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled in settings.'**
  String get coreDisabled;

  /// No description provided for @wgOneInterface.
  ///
  /// In en, this message translates to:
  /// **'A single [Interface] section is required.'**
  String get wgOneInterface;

  /// No description provided for @wgNoPeer.
  ///
  /// In en, this message translates to:
  /// **'No [Peer] section.'**
  String get wgNoPeer;

  /// No description provided for @wgOnePeer.
  ///
  /// In en, this message translates to:
  /// **'A single [Peer] is supported; the config has {count}.'**
  String wgOnePeer(int count);

  /// No description provided for @wgMissingKey.
  ///
  /// In en, this message translates to:
  /// **'The config has no {key}.'**
  String wgMissingKey(String key);

  /// No description provided for @wgInvalidEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Invalid Endpoint: {value}'**
  String wgInvalidEndpoint(String value);

  /// No description provided for @singboxNoNoise.
  ///
  /// In en, this message translates to:
  /// **'Noise isn\'t available in the sing-box core and is not applied.'**
  String get singboxNoNoise;

  /// No description provided for @singboxNoMux.
  ///
  /// In en, this message translates to:
  /// **'Xray Mux is incompatible with the sing-box core and is not applied.'**
  String get singboxNoMux;

  /// No description provided for @singboxNoObservatory.
  ///
  /// In en, this message translates to:
  /// **'Observatory and managed Xray JSON configs aren\'t available in the sing-box core.'**
  String get singboxNoObservatory;

  /// No description provided for @singboxNoRawConfig.
  ///
  /// In en, this message translates to:
  /// **'A full Xray JSON config isn\'t available in the sing-box core.'**
  String get singboxNoRawConfig;

  /// No description provided for @singboxNoPqv.
  ///
  /// In en, this message translates to:
  /// **'Reality: the sing-box core doesn\'t verify the ML-DSA signature (pqv) — the server is verified by the Reality key only.'**
  String get singboxNoPqv;

  /// No description provided for @singboxFragmentMode.
  ///
  /// In en, this message translates to:
  /// **'Fragmentation in the sing-box core covers only the TLS ClientHello; mode \"{mode}\" is not applied.'**
  String singboxFragmentMode(String mode);

  /// No description provided for @singboxNoXhttp.
  ///
  /// In en, this message translates to:
  /// **'The XHTTP transport isn\'t available in the sing-box core.'**
  String get singboxNoXhttp;

  /// No description provided for @singboxNoXrayExtra.
  ///
  /// In en, this message translates to:
  /// **'Advanced Xray settings (finalmask/extra) aren\'t available in the sing-box core.'**
  String get singboxNoXrayExtra;

  /// No description provided for @singboxLinkMux.
  ///
  /// In en, this message translates to:
  /// **'The link asks for Xray Mux (mux=on), which the sing-box core doesn\'t have.'**
  String get singboxLinkMux;

  /// No description provided for @singboxNoCertPin.
  ///
  /// In en, this message translates to:
  /// **'The sing-box core doesn\'t support certificate pinning: it checks only the public key hash.'**
  String get singboxNoCertPin;

  /// No description provided for @singboxNoVlessEncryption.
  ///
  /// In en, this message translates to:
  /// **'VLESS Encryption isn\'t available in the sing-box core.'**
  String get singboxNoVlessEncryption;

  /// No description provided for @singboxFlow.
  ///
  /// In en, this message translates to:
  /// **'Flow \"{flow}\" isn\'t available in the sing-box core.'**
  String singboxFlow(String flow);

  /// No description provided for @singboxNoSsPlugins.
  ///
  /// In en, this message translates to:
  /// **'Shadowsocks plugins aren\'t available in the sing-box core.'**
  String get singboxNoSsPlugins;

  /// No description provided for @singboxSsMethod.
  ///
  /// In en, this message translates to:
  /// **'Shadowsocks method \"{method}\" isn\'t available in the sing-box core.'**
  String singboxSsMethod(String method);

  /// No description provided for @singboxAwgReserved.
  ///
  /// In en, this message translates to:
  /// **'AmneziaWG doesn\'t support reserved.'**
  String get singboxAwgReserved;

  /// No description provided for @singboxAwgHeaders.
  ///
  /// In en, this message translates to:
  /// **'AmneziaWG: header protection requires S1–S4 of at least 12.'**
  String get singboxAwgHeaders;

  /// No description provided for @singboxNoTcpHttp.
  ///
  /// In en, this message translates to:
  /// **'TCP with HTTP obfuscation isn\'t available in the sing-box core.'**
  String get singboxNoTcpHttp;

  /// No description provided for @rustNoProxyOnly.
  ///
  /// In en, this message translates to:
  /// **'\"Proxy only\" mode isn\'t available in the xray-rust core: it works only through TUN.'**
  String get rustNoProxyOnly;

  /// No description provided for @rustIcmpLocal.
  ///
  /// In en, this message translates to:
  /// **'ICMP is handled locally by the xray-rust core; the setting is not applied.'**
  String get rustIcmpLocal;

  /// No description provided for @rustMtuIgnored.
  ///
  /// In en, this message translates to:
  /// **'The xray-rust core works with MTU 1500; another value is not applied.'**
  String get rustMtuIgnored;

  /// No description provided for @rustMuxIgnored.
  ///
  /// In en, this message translates to:
  /// **'Mux isn\'t available in the xray-rust core and is not applied.'**
  String get rustMuxIgnored;

  /// No description provided for @rustNoObservatory.
  ///
  /// In en, this message translates to:
  /// **'Observatory and managed JSON configs aren\'t available in the xray-rust core.'**
  String get rustNoObservatory;

  /// No description provided for @rustNoRawConfig.
  ///
  /// In en, this message translates to:
  /// **'A full JSON config isn\'t available in the xray-rust core.'**
  String get rustNoRawConfig;

  /// No description provided for @rustSniffingForced.
  ///
  /// In en, this message translates to:
  /// **'Domain rules in the xray-rust core require domain sniffing — it is enabled for this connection.'**
  String get rustSniffingForced;

  /// No description provided for @rustAdBlockDropped.
  ///
  /// In en, this message translates to:
  /// **'Ad blocking together with the selected GeoSite categories exceeds the xray-rust core\'s limit of 250k domain rules — ad blocking is not applied.'**
  String get rustAdBlockDropped;

  /// No description provided for @rustGeositeTrimmed.
  ///
  /// In en, this message translates to:
  /// **'GeoSite {codes}: over the xray-rust core\'s limit for one category (32 MB or 200k domains) — only its first domains within the limit are applied.'**
  String rustGeositeTrimmed(String codes);

  /// No description provided for @geositeMissing.
  ///
  /// In en, this message translates to:
  /// **'geosite.dat has no {codes} — these rules are not applied.'**
  String geositeMissing(String codes);

  /// No description provided for @rustFragmentDropped.
  ///
  /// In en, this message translates to:
  /// **'Fragmentation is not applied: {reason}'**
  String rustFragmentDropped(String reason);

  /// No description provided for @rustNoiseDropped.
  ///
  /// In en, this message translates to:
  /// **'Noise is not applied: {reason}'**
  String rustNoiseDropped(String reason);

  /// No description provided for @xrayNoH2Quic.
  ///
  /// In en, this message translates to:
  /// **'The HTTP/2 and QUIC transports were removed from Xray-core: the server needs to move to xHTTP.'**
  String get xrayNoH2Quic;

  /// No description provided for @xrayInsecure.
  ///
  /// In en, this message translates to:
  /// **'Xray-core no longer supports allowInsecure: set the server certificate\'s pinSHA256 or use a valid certificate.'**
  String get xrayInsecure;

  /// No description provided for @xrayNoSsPlugins.
  ///
  /// In en, this message translates to:
  /// **'Shadowsocks plugins (SIP003, plugin=…) aren\'t available in the Xray-core core.'**
  String get xrayNoSsPlugins;

  /// No description provided for @linkUnknownSecurity.
  ///
  /// In en, this message translates to:
  /// **'Unknown security in the link: \"{value}\".'**
  String linkUnknownSecurity(String value);

  /// No description provided for @linkUnknownTransport.
  ///
  /// In en, this message translates to:
  /// **'Unknown transport in the link: \"{value}\".'**
  String linkUnknownTransport(String value);

  /// No description provided for @linkUnknownObfs.
  ///
  /// In en, this message translates to:
  /// **'Unknown Hysteria2 obfuscation in the link: \"{value}\". Supported: salamander, gecko.'**
  String linkUnknownObfs(String value);

  /// No description provided for @xrayPinFormat.
  ///
  /// In en, this message translates to:
  /// **'pinSHA256 must be the certificate\'s SHA-256: 64 hex characters or base64 of 32 bytes.'**
  String get xrayPinFormat;

  /// No description provided for @xrayRawJsonParse.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t parse the subscription JSON config: {error}'**
  String xrayRawJsonParse(String error);

  /// No description provided for @xrayRawConflictingKeys.
  ///
  /// In en, this message translates to:
  /// **'The subscription JSON config spells one key in several ways ({keys}): it\'s unclear which one Xray would take.'**
  String xrayRawConflictingKeys(String keys);

  /// No description provided for @profileDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get profileDefaultName;

  /// No description provided for @geoNoFilesDir.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get the files directory'**
  String get geoNoFilesDir;

  /// No description provided for @subHwidLimit.
  ///
  /// In en, this message translates to:
  /// **'Subscription device limit reached (HWID)'**
  String get subHwidLimit;

  /// No description provided for @subEmpty.
  ///
  /// In en, this message translates to:
  /// **'The subscription returned no configurations'**
  String get subEmpty;

  /// No description provided for @updateUnsupportedDevice.
  ///
  /// In en, this message translates to:
  /// **'Device not supported: {abi}'**
  String updateUnsupportedDevice(String abi);

  /// No description provided for @updateNoReleaseInfo.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get release info'**
  String get updateNoReleaseInfo;

  /// No description provided for @updateCheckError.
  ///
  /// In en, this message translates to:
  /// **'Check error: {error}'**
  String updateCheckError(String error);

  /// No description provided for @updateDownloadError.
  ///
  /// In en, this message translates to:
  /// **'Download error: {error}'**
  String updateDownloadError(String error);

  /// No description provided for @updateInstallError.
  ///
  /// In en, this message translates to:
  /// **'Install error'**
  String get updateInstallError;

  /// No description provided for @vpnConnectTimeout.
  ///
  /// In en, this message translates to:
  /// **'Connection timeout'**
  String get vpnConnectTimeout;

  /// No description provided for @vpnConnectError.
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get vpnConnectError;

  /// No description provided for @vpnNoConfigSelected.
  ///
  /// In en, this message translates to:
  /// **'No configuration selected'**
  String get vpnNoConfigSelected;

  /// No description provided for @importReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Check before importing'**
  String get importReviewTitle;

  /// No description provided for @importReviewTraffic.
  ///
  /// In en, this message translates to:
  /// **'Changes how traffic goes:'**
  String get importReviewTraffic;

  /// No description provided for @importReviewSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Adds subscriptions, the app will load them from:'**
  String get importReviewSubscriptions;

  /// No description provided for @importChangeKillSwitch.
  ///
  /// In en, this message translates to:
  /// **'Kill switch'**
  String get importChangeKillSwitch;

  /// No description provided for @importChangeDns.
  ///
  /// In en, this message translates to:
  /// **'DNS'**
  String get importChangeDns;

  /// No description provided for @importChangeRouting.
  ///
  /// In en, this message translates to:
  /// **'Routing rules'**
  String get importChangeRouting;

  /// No description provided for @importChangeLogLevel.
  ///
  /// In en, this message translates to:
  /// **'Log level'**
  String get importChangeLogLevel;

  /// No description provided for @logsPause.
  ///
  /// In en, this message translates to:
  /// **'Pause the log'**
  String get logsPause;

  /// No description provided for @logsResume.
  ///
  /// In en, this message translates to:
  /// **'Resume the log'**
  String get logsResume;

  /// No description provided for @logsTunnelDiag.
  ///
  /// In en, this message translates to:
  /// **'Write tunnel diagnostics to the log'**
  String get logsTunnelDiag;

  /// No description provided for @logsShare.
  ///
  /// In en, this message translates to:
  /// **'Share the log'**
  String get logsShare;

  /// No description provided for @logsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear the log'**
  String get logsClear;

  /// No description provided for @profilesImport.
  ///
  /// In en, this message translates to:
  /// **'Import a profile'**
  String get profilesImport;

  /// No description provided for @settingsAccentSwatch.
  ///
  /// In en, this message translates to:
  /// **'Accent color {hex}'**
  String settingsAccentSwatch(String hex);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
