import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_tr.dart';
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
/// import 'generated/app_localizations.dart';
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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('pt'),
    Locale('tr'),
    Locale('zh'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'NodeQL'**
  String get appName;

  /// No description provided for @blockLibrary.
  ///
  /// In en, this message translates to:
  /// **'Block Library'**
  String get blockLibrary;

  /// No description provided for @workspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get workspace;

  /// No description provided for @stage.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get stage;

  /// No description provided for @workspaceHint.
  ///
  /// In en, this message translates to:
  /// **'Drag blocks here to build your script.'**
  String get workspaceHint;

  /// No description provided for @stageHint.
  ///
  /// In en, this message translates to:
  /// **'Run scripts and interact with sprites.'**
  String get stageHint;

  /// No description provided for @blockWhenFlagClicked.
  ///
  /// In en, this message translates to:
  /// **'when green flag clicked'**
  String get blockWhenFlagClicked;

  /// No description provided for @blockMoveSteps.
  ///
  /// In en, this message translates to:
  /// **'move {steps} steps'**
  String blockMoveSteps(int steps);

  /// No description provided for @blockRepeatTimes.
  ///
  /// In en, this message translates to:
  /// **'repeat {times}'**
  String blockRepeatTimes(int times);

  /// No description provided for @blockTurnDegrees.
  ///
  /// In en, this message translates to:
  /// **'turn {degrees} degrees'**
  String blockTurnDegrees(int degrees);

  /// No description provided for @blockForever.
  ///
  /// In en, this message translates to:
  /// **'forever'**
  String get blockForever;

  /// No description provided for @desktopFeatureOnly.
  ///
  /// In en, this message translates to:
  /// **'This feature is only available in the desktop app.'**
  String get desktopFeatureOnly;

  /// No description provided for @joinConnectTables.
  ///
  /// In en, this message translates to:
  /// **'Connect tables'**
  String get joinConnectTables;

  /// No description provided for @joinExistingData.
  ///
  /// In en, this message translates to:
  /// **'Existing data'**
  String get joinExistingData;

  /// No description provided for @joinNewTable.
  ///
  /// In en, this message translates to:
  /// **'New table'**
  String get joinNewTable;

  /// No description provided for @joinConnectSource.
  ///
  /// In en, this message translates to:
  /// **'Connect SELECT or FROM'**
  String get joinConnectSource;

  /// No description provided for @joinChooseTable.
  ///
  /// In en, this message translates to:
  /// **'Choose table'**
  String get joinChooseTable;

  /// No description provided for @joinChooseColumn.
  ///
  /// In en, this message translates to:
  /// **'Choose column'**
  String get joinChooseColumn;

  /// No description provided for @joinResult.
  ///
  /// In en, this message translates to:
  /// **'Rows in the result'**
  String get joinResult;

  /// No description provided for @joinMatchesOnly.
  ///
  /// In en, this message translates to:
  /// **'Matching rows only'**
  String get joinMatchesOnly;

  /// No description provided for @joinKeepExisting.
  ///
  /// In en, this message translates to:
  /// **'Keep all existing rows'**
  String get joinKeepExisting;

  /// No description provided for @joinKeepNew.
  ///
  /// In en, this message translates to:
  /// **'Keep all new rows'**
  String get joinKeepNew;

  /// No description provided for @joinKeepAll.
  ///
  /// In en, this message translates to:
  /// **'Keep all rows from both'**
  String get joinKeepAll;

  /// No description provided for @joinEveryPair.
  ///
  /// In en, this message translates to:
  /// **'Every possible pair'**
  String get joinEveryPair;

  /// No description provided for @joinSameNames.
  ///
  /// In en, this message translates to:
  /// **'Match column names'**
  String get joinSameNames;

  /// No description provided for @joinSameTable.
  ///
  /// In en, this message translates to:
  /// **'Same table, two roles'**
  String get joinSameTable;

  /// No description provided for @joinInnerDescription.
  ///
  /// In en, this message translates to:
  /// **'Only pairs whose selected column values match.'**
  String get joinInnerDescription;

  /// No description provided for @joinLeftDescription.
  ///
  /// In en, this message translates to:
  /// **'Keep every existing row, even without a matching new row.'**
  String get joinLeftDescription;

  /// No description provided for @joinRightDescription.
  ///
  /// In en, this message translates to:
  /// **'Keep every new row, even without a matching existing row.'**
  String get joinRightDescription;

  /// No description provided for @joinFullDescription.
  ///
  /// In en, this message translates to:
  /// **'Keep matches and unmatched rows from either side.'**
  String get joinFullDescription;

  /// No description provided for @joinCrossDescription.
  ///
  /// In en, this message translates to:
  /// **'Pair every existing row with every new row. No matching condition.'**
  String get joinCrossDescription;

  /// No description provided for @joinNaturalDescription.
  ///
  /// In en, this message translates to:
  /// **'Use all shared column names. With none, produce every possible pair.'**
  String get joinNaturalDescription;

  /// No description provided for @joinSelfDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the same table again with a different alias to compare two roles.'**
  String get joinSelfDescription;

  /// No description provided for @joinChooseResult.
  ///
  /// In en, this message translates to:
  /// **'Which rows should stay?'**
  String get joinChooseResult;

  /// No description provided for @joinExampleHint.
  ///
  /// In en, this message translates to:
  /// **'Example: existing values 1, 2; new values 1, 3. Match equal values. Each pair of cells is one result row.'**
  String get joinExampleHint;

  /// No description provided for @joinNullHint.
  ///
  /// In en, this message translates to:
  /// **'NULL means that no partner was found. Several matches produce several result rows.'**
  String get joinNullHint;

  /// No description provided for @joinSpecialCases.
  ///
  /// In en, this message translates to:
  /// **'Special cases'**
  String get joinSpecialCases;

  /// No description provided for @joinClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get joinClose;

  /// No description provided for @joinPaletteDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose a table, connect matching columns, then decide which rows to keep.'**
  String get joinPaletteDescription;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'ar',
    'de',
    'en',
    'es',
    'fr',
    'it',
    'ja',
    'ko',
    'pt',
    'tr',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'pt':
      return AppLocalizationsPt();
    case 'tr':
      return AppLocalizationsTr();
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
