import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_uz.dart';

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
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('ru'), Locale('tr'), Locale('uz')];

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @notSelected.
  ///
  /// In en, this message translates to:
  /// **'Not selected'**
  String get notSelected;

  /// No description provided for @dismissError.
  ///
  /// In en, this message translates to:
  /// **'Dismiss error'**
  String get dismissError;

  /// No description provided for @dismissNotice.
  ///
  /// In en, this message translates to:
  /// **'Dismiss notice'**
  String get dismissNotice;

  /// No description provided for @languagePickerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Interface language'**
  String get languagePickerTooltip;

  /// No description provided for @mockBanner.
  ///
  /// In en, this message translates to:
  /// **'MOCK PROVIDERS — test tones and placeholder text, not a real translation'**
  String get mockBanner;

  /// No description provided for @bypassBanner.
  ///
  /// In en, this message translates to:
  /// **'BYPASS — your real microphone is going to the call, untranslated'**
  String get bypassBanner;

  /// No description provided for @errorSessionEnded.
  ///
  /// In en, this message translates to:
  /// **'(the session ended)'**
  String get errorSessionEnded;

  /// No description provided for @errProviderUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The translation or voice service is unavailable right now.'**
  String get errProviderUnavailable;

  /// No description provided for @errTranslationFailed.
  ///
  /// In en, this message translates to:
  /// **'A phrase could not be translated.'**
  String get errTranslationFailed;

  /// No description provided for @errTranslationRejected.
  ///
  /// In en, this message translates to:
  /// **'The translation came back unusable, so nothing was spoken.'**
  String get errTranslationRejected;

  /// No description provided for @errTtsFailed.
  ///
  /// In en, this message translates to:
  /// **'A phrase could not be spoken.'**
  String get errTtsFailed;

  /// No description provided for @errCaptureBacklog.
  ///
  /// In en, this message translates to:
  /// **'Audio is piling up faster than it can be processed.'**
  String get errCaptureBacklog;

  /// No description provided for @errCaptureOverflow.
  ///
  /// In en, this message translates to:
  /// **'Some audio was dropped because processing fell behind.'**
  String get errCaptureOverflow;

  /// No description provided for @errSynthesisCongested.
  ///
  /// In en, this message translates to:
  /// **'The voice service is congested; speech may be delayed.'**
  String get errSynthesisCongested;

  /// No description provided for @errPlaybackOverflow.
  ///
  /// In en, this message translates to:
  /// **'Too much audio is waiting to play; some was skipped.'**
  String get errPlaybackOverflow;

  /// No description provided for @errSourceGone.
  ///
  /// In en, this message translates to:
  /// **'The meeting app stopped playing audio or was closed.'**
  String get errSourceGone;

  /// No description provided for @errDeviceRemoved.
  ///
  /// In en, this message translates to:
  /// **'An audio device was disconnected.'**
  String get errDeviceRemoved;

  /// No description provided for @errGatewayUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the gateway. Check the gateway URL and your internet connection.'**
  String get errGatewayUnreachable;

  /// No description provided for @errUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'The gateway rejected the access token. Check it: press Change beside the connection.'**
  String get errUnauthorized;

  /// No description provided for @errSessionLimit.
  ///
  /// In en, this message translates to:
  /// **'The gateway\'s session limit is reached. Try again later.'**
  String get errSessionLimit;

  /// No description provided for @errSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'The session expired. Start a new one.'**
  String get errSessionExpired;

  /// No description provided for @errNoVirtualMic.
  ///
  /// In en, this message translates to:
  /// **'The virtual microphone (BlackHole 2ch) was not found.'**
  String get errNoVirtualMic;

  /// No description provided for @errNoVirtualMicWindows.
  ///
  /// In en, this message translates to:
  /// **'The virtual microphone (VB-CABLE) was not found.'**
  String get errNoVirtualMicWindows;

  /// No description provided for @errNoHeadphones.
  ///
  /// In en, this message translates to:
  /// **'The selected headphones were not found.'**
  String get errNoHeadphones;

  /// No description provided for @errNoMicrophone.
  ///
  /// In en, this message translates to:
  /// **'The selected microphone was not found.'**
  String get errNoMicrophone;

  /// No description provided for @errUnsafeRoute.
  ///
  /// In en, this message translates to:
  /// **'Unsafe audio route refused: the microphone or headphones are a virtual device.'**
  String get errUnsafeRoute;

  /// No description provided for @errAccountsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The account service could not be reached. Check your internet connection.'**
  String get errAccountsUnavailable;

  /// No description provided for @errBadRequest.
  ///
  /// In en, this message translates to:
  /// **'The gateway did not accept the session request.'**
  String get errBadRequest;

  /// No description provided for @errBadRequestKeys.
  ///
  /// In en, this message translates to:
  /// **'The service did not accept the format of your keys. Check them: press Change beside the connection.'**
  String get errBadRequestKeys;

  /// No description provided for @errRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a minute and try again.'**
  String get errRateLimited;

  /// No description provided for @errSettingsFailed.
  ///
  /// In en, this message translates to:
  /// **'The settings could not be saved. Try again.'**
  String get errSettingsFailed;

  /// No description provided for @errGatewayError.
  ///
  /// In en, this message translates to:
  /// **'The gateway ran into an error. Try again in a moment.'**
  String get errGatewayError;

  /// No description provided for @errSignInRefused.
  ///
  /// In en, this message translates to:
  /// **'The service did not accept your sign-in. Try again later.'**
  String get errSignInRefused;

  /// No description provided for @errServiceRefused.
  ///
  /// In en, this message translates to:
  /// **'The service refused the session. Try again later.'**
  String get errServiceRefused;

  /// No description provided for @blockChooseMic.
  ///
  /// In en, this message translates to:
  /// **'Choose a microphone.'**
  String get blockChooseMic;

  /// No description provided for @blockMicIsVirtual.
  ///
  /// In en, this message translates to:
  /// **'Unsafe route: the microphone is the same device as the virtual microphone ({device}). Choose your physical microphone.'**
  String blockMicIsVirtual(String device);

  /// No description provided for @blockMicIsCable.
  ///
  /// In en, this message translates to:
  /// **'Unsafe route: the microphone is a virtual cable ({device}), so the translation would come back into the call. Choose your physical microphone.'**
  String blockMicIsCable(String device);

  /// No description provided for @blockChooseHeadphones.
  ///
  /// In en, this message translates to:
  /// **'Choose headphones.'**
  String get blockChooseHeadphones;

  /// No description provided for @blockHeadphonesVirtual.
  ///
  /// In en, this message translates to:
  /// **'Unsafe route: the headphones are a virtual device ({device}). Choose your physical headphones.'**
  String blockHeadphonesVirtual(String device);

  /// No description provided for @blockBidirectionalNeedsVirtual.
  ///
  /// In en, this message translates to:
  /// **'Bidirectional speech needs a virtual microphone (BlackHole 2ch), which is not installed.'**
  String get blockBidirectionalNeedsVirtual;

  /// No description provided for @blockBidirectionalNeedsVirtualWindows.
  ///
  /// In en, this message translates to:
  /// **'Bidirectional speech needs a virtual microphone (VB-CABLE), which is not installed.'**
  String get blockBidirectionalNeedsVirtualWindows;

  /// No description provided for @blockIncomingNeedsSource.
  ///
  /// In en, this message translates to:
  /// **'Incoming audio needs at least one meeting source.'**
  String get blockIncomingNeedsSource;

  /// No description provided for @blockSameLanguages.
  ///
  /// In en, this message translates to:
  /// **'Choose two different languages.'**
  String get blockSameLanguages;

  /// No description provided for @blockEnterGateway.
  ///
  /// In en, this message translates to:
  /// **'Enter the gateway address: press Change beside the connection.'**
  String get blockEnterGateway;

  /// No description provided for @blockEnterToken.
  ///
  /// In en, this message translates to:
  /// **'Enter the access token: press Change beside the connection.'**
  String get blockEnterToken;

  /// No description provided for @blockEnterKeys.
  ///
  /// In en, this message translates to:
  /// **'Enter your ElevenLabs and Gemini keys.'**
  String get blockEnterKeys;

  /// No description provided for @blockBalanceEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your balance is empty. Top up to start.'**
  String get blockBalanceEmpty;

  /// No description provided for @noticeMicLost.
  ///
  /// In en, this message translates to:
  /// **'Microphone \"{name}\" is no longer available. Choose another microphone.'**
  String noticeMicLost(String name);

  /// No description provided for @noticeHeadphonesLost.
  ///
  /// In en, this message translates to:
  /// **'Headphones \"{name}\" are no longer available. Choose other headphones.'**
  String noticeHeadphonesLost(String name);

  /// No description provided for @startSession.
  ///
  /// In en, this message translates to:
  /// **'Start session'**
  String get startSession;

  /// No description provided for @stopSession.
  ///
  /// In en, this message translates to:
  /// **'Stop session'**
  String get stopSession;

  /// No description provided for @setupLocked.
  ///
  /// In en, this message translates to:
  /// **'Setup is locked while a session is running.'**
  String get setupLocked;

  /// No description provided for @sectionLanguageMode.
  ///
  /// In en, this message translates to:
  /// **'Language and mode'**
  String get sectionLanguageMode;

  /// No description provided for @languageUz.
  ///
  /// In en, this message translates to:
  /// **'Uzbek'**
  String get languageUz;

  /// No description provided for @languageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @languageRu.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get languageRu;

  /// No description provided for @languageTr.
  ///
  /// In en, this message translates to:
  /// **'Turkish'**
  String get languageTr;

  /// No description provided for @myLanguage.
  ///
  /// In en, this message translates to:
  /// **'My language'**
  String get myLanguage;

  /// No description provided for @theirLanguage.
  ///
  /// In en, this message translates to:
  /// **'Their language'**
  String get theirLanguage;

  /// No description provided for @modeCaptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Captions only'**
  String get modeCaptionsTitle;

  /// No description provided for @modeCaptionsDesc.
  ///
  /// In en, this message translates to:
  /// **'Live captions both ways. Nothing is spoken.'**
  String get modeCaptionsDesc;

  /// No description provided for @modeIncomingTitle.
  ///
  /// In en, this message translates to:
  /// **'Incoming audio'**
  String get modeIncomingTitle;

  /// No description provided for @modeIncomingDesc.
  ///
  /// In en, this message translates to:
  /// **'Captions both ways, plus their speech translated into your language in your headphones.'**
  String get modeIncomingDesc;

  /// No description provided for @modeBidirectionalTitle.
  ///
  /// In en, this message translates to:
  /// **'Bidirectional speech'**
  String get modeBidirectionalTitle;

  /// No description provided for @modeBidirectionalDesc.
  ///
  /// In en, this message translates to:
  /// **'Also speaks your translation into the call in a synthesized voice, through the virtual microphone.'**
  String get modeBidirectionalDesc;

  /// No description provided for @sectionDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get sectionDevices;

  /// No description provided for @deviceMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get deviceMicrophone;

  /// No description provided for @deviceHeadphones.
  ///
  /// In en, this message translates to:
  /// **'Headphones'**
  String get deviceHeadphones;

  /// No description provided for @virtualMicFound.
  ///
  /// In en, this message translates to:
  /// **'Virtual microphone: {name} found'**
  String virtualMicFound(String name);

  /// No description provided for @virtualMicFoundWindows.
  ///
  /// In en, this message translates to:
  /// **'Virtual microphone: {name} found. In the meeting app, choose CABLE Output as the microphone.'**
  String virtualMicFoundWindows(String name);

  /// No description provided for @blackHoleMissingNotice.
  ///
  /// In en, this message translates to:
  /// **'BlackHole 2ch not installed — outgoing speech unavailable; captions still work'**
  String get blackHoleMissingNotice;

  /// No description provided for @blackHoleInstallWith.
  ///
  /// In en, this message translates to:
  /// **'Install it with: {command}'**
  String blackHoleInstallWith(String command);

  /// No description provided for @vbCableMissingNotice.
  ///
  /// In en, this message translates to:
  /// **'VB-CABLE not installed — outgoing speech unavailable; captions still work'**
  String get vbCableMissingNotice;

  /// No description provided for @vbCableDownloadFrom.
  ///
  /// In en, this message translates to:
  /// **'Download it free from: {url}'**
  String vbCableDownloadFrom(String url);

  /// No description provided for @sectionMeetingSource.
  ///
  /// In en, this message translates to:
  /// **'Meeting source'**
  String get sectionMeetingSource;

  /// No description provided for @noAudioApps.
  ///
  /// In en, this message translates to:
  /// **'No apps are using audio right now. Open your meeting app, then press Refresh.'**
  String get noAudioApps;

  /// No description provided for @processPid.
  ///
  /// In en, this message translates to:
  /// **'pid {pid}'**
  String processPid(int pid);

  /// No description provided for @processPlaying.
  ///
  /// In en, this message translates to:
  /// **'playing'**
  String get processPlaying;

  /// No description provided for @sectionGateway.
  ///
  /// In en, this message translates to:
  /// **'Outgoing turns and connection'**
  String get sectionGateway;

  /// No description provided for @outgoingTurnMode.
  ///
  /// In en, this message translates to:
  /// **'Outgoing turn mode'**
  String get outgoingTurnMode;

  /// No description provided for @turnPttTitle.
  ///
  /// In en, this message translates to:
  /// **'Push-to-talk'**
  String get turnPttTitle;

  /// No description provided for @turnPttDesc.
  ///
  /// In en, this message translates to:
  /// **'Hold the button or the Space key while you speak.'**
  String get turnPttDesc;

  /// No description provided for @turnVadTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto: VAD'**
  String get turnVadTitle;

  /// No description provided for @turnVadDesc.
  ///
  /// In en, this message translates to:
  /// **'Sends your speech when you pause.'**
  String get turnVadDesc;

  /// No description provided for @turnPredictionTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto: turn prediction'**
  String get turnPredictionTitle;

  /// No description provided for @turnPredictionDesc.
  ///
  /// In en, this message translates to:
  /// **'Predicts when you have finished a thought.'**
  String get turnPredictionDesc;

  /// No description provided for @gatewayUrl.
  ///
  /// In en, this message translates to:
  /// **'Gateway URL'**
  String get gatewayUrl;

  /// No description provided for @accessToken.
  ///
  /// In en, this message translates to:
  /// **'Access token'**
  String get accessToken;

  /// No description provided for @translationModelOptional.
  ///
  /// In en, this message translates to:
  /// **'Translation model (optional)'**
  String get translationModelOptional;

  /// No description provided for @testDevicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Test your devices'**
  String get testDevicesTitle;

  /// No description provided for @testDevicesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not available while a session is running'**
  String get testDevicesUnavailable;

  /// No description provided for @testDevicesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Level meters, test tones, permission'**
  String get testDevicesSubtitle;

  /// No description provided for @levelMic.
  ///
  /// In en, this message translates to:
  /// **'Microphone level'**
  String get levelMic;

  /// No description provided for @levelSource.
  ///
  /// In en, this message translates to:
  /// **'Meeting source level'**
  String get levelSource;

  /// No description provided for @levelSilent.
  ///
  /// In en, this message translates to:
  /// **'silent'**
  String get levelSilent;

  /// No description provided for @testHeadphones.
  ///
  /// In en, this message translates to:
  /// **'Test headphones'**
  String get testHeadphones;

  /// No description provided for @testVirtualMic.
  ///
  /// In en, this message translates to:
  /// **'Test virtual mic'**
  String get testVirtualMic;

  /// No description provided for @testToneNote.
  ///
  /// In en, this message translates to:
  /// **'Each test plays one quiet tone. Leave any call that uses BlackHole 2ch before testing.'**
  String get testToneNote;

  /// No description provided for @testToneNoteWindows.
  ///
  /// In en, this message translates to:
  /// **'Each test plays one quiet tone. Leave any call that uses CABLE Output before testing.'**
  String get testToneNoteWindows;

  /// No description provided for @micPermission.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission: {status}'**
  String micPermission(String status);

  /// No description provided for @permissionGranted.
  ///
  /// In en, this message translates to:
  /// **'granted'**
  String get permissionGranted;

  /// No description provided for @permissionDenied.
  ///
  /// In en, this message translates to:
  /// **'denied'**
  String get permissionDenied;

  /// No description provided for @permissionUndetermined.
  ///
  /// In en, this message translates to:
  /// **'not asked yet'**
  String get permissionUndetermined;

  /// No description provided for @permissionRequest.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get permissionRequest;

  /// No description provided for @micPrivacyWindows.
  ///
  /// In en, this message translates to:
  /// **'On Windows, microphone access for desktop apps is a system setting. If the microphone level stays silent, turn on \"Let desktop apps access your microphone\" in Settings → Privacy & security → Microphone.'**
  String get micPrivacyWindows;

  /// No description provided for @routingTitle.
  ///
  /// In en, this message translates to:
  /// **'Routing instructions'**
  String get routingTitle;

  /// No description provided for @routingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How to set up Zoom, Meet and Upwork'**
  String get routingSubtitle;

  /// No description provided for @routingZoomDesktopTitle.
  ///
  /// In en, this message translates to:
  /// **'Zoom Desktop'**
  String get routingZoomDesktopTitle;

  /// No description provided for @routingZoom1.
  ///
  /// In en, this message translates to:
  /// **'Open Zoom → Settings → Audio.'**
  String get routingZoom1;

  /// No description provided for @routingZoom2.
  ///
  /// In en, this message translates to:
  /// **'Microphone: BlackHole 2ch.'**
  String get routingZoom2;

  /// No description provided for @routingZoom2Windows.
  ///
  /// In en, this message translates to:
  /// **'Microphone: CABLE Output (VB-Audio Virtual Cable).'**
  String get routingZoom2Windows;

  /// No description provided for @routingZoom3.
  ///
  /// In en, this message translates to:
  /// **'Speaker: your headphones.'**
  String get routingZoom3;

  /// No description provided for @routingZoom4.
  ///
  /// In en, this message translates to:
  /// **'Start the session here before you speak.'**
  String get routingZoom4;

  /// No description provided for @routingWebTitle.
  ///
  /// In en, this message translates to:
  /// **'Zoom Web / Google Meet'**
  String get routingWebTitle;

  /// No description provided for @routingWeb1.
  ///
  /// In en, this message translates to:
  /// **'Open the browser\'s audio settings for the call.'**
  String get routingWeb1;

  /// No description provided for @routingWeb2.
  ///
  /// In en, this message translates to:
  /// **'Microphone: BlackHole 2ch. Speaker: your headphones.'**
  String get routingWeb2;

  /// No description provided for @routingWeb2Windows.
  ///
  /// In en, this message translates to:
  /// **'Microphone: CABLE Output (VB-Audio Virtual Cable). Speaker: your headphones.'**
  String get routingWeb2Windows;

  /// No description provided for @routingWeb3.
  ///
  /// In en, this message translates to:
  /// **'Use a dedicated browser window and close other tabs that play audio.'**
  String get routingWeb3;

  /// No description provided for @routingUpworkTitle.
  ///
  /// In en, this message translates to:
  /// **'Upwork'**
  String get routingUpworkTitle;

  /// No description provided for @routingUpwork1.
  ///
  /// In en, this message translates to:
  /// **'Start the call from Upwork Messages.'**
  String get routingUpwork1;

  /// No description provided for @routingUpwork2.
  ///
  /// In en, this message translates to:
  /// **'Then use the same Zoom Desktop or browser settings as above.'**
  String get routingUpwork2;

  /// No description provided for @routingBackTitle.
  ///
  /// In en, this message translates to:
  /// **'How to return to normal'**
  String get routingBackTitle;

  /// No description provided for @routingBack1.
  ///
  /// In en, this message translates to:
  /// **'In the meeting app, select your physical microphone again.'**
  String get routingBack1;

  /// No description provided for @routingBack2.
  ///
  /// In en, this message translates to:
  /// **'Stop the session here.'**
  String get routingBack2;

  /// No description provided for @routingInstallVirtual.
  ///
  /// In en, this message translates to:
  /// **'Install the virtual microphone: {command}'**
  String routingInstallVirtual(String command);

  /// No description provided for @routingInstallVirtualWindows.
  ///
  /// In en, this message translates to:
  /// **'Install the virtual microphone VB-CABLE (free): {url}'**
  String routingInstallVirtualWindows(String url);

  /// No description provided for @consentTitle.
  ///
  /// In en, this message translates to:
  /// **'Tell the other participants first'**
  String get consentTitle;

  /// No description provided for @consentIntro.
  ///
  /// In en, this message translates to:
  /// **'Say or paste this sentence into the call chat before you start.'**
  String get consentIntro;

  /// No description provided for @consentCopyEnglish.
  ///
  /// In en, this message translates to:
  /// **'Copy English'**
  String get consentCopyEnglish;

  /// No description provided for @consentCopyRussian.
  ///
  /// In en, this message translates to:
  /// **'Copy Russian'**
  String get consentCopyRussian;

  /// No description provided for @consentCheckbox.
  ///
  /// In en, this message translates to:
  /// **'The other participants have been informed and agreed'**
  String get consentCheckbox;

  /// No description provided for @laneOut.
  ///
  /// In en, this message translates to:
  /// **'You → them'**
  String get laneOut;

  /// No description provided for @laneIn.
  ///
  /// In en, this message translates to:
  /// **'Them → you'**
  String get laneIn;

  /// No description provided for @noCaptions.
  ///
  /// In en, this message translates to:
  /// **'No captions yet'**
  String get noCaptions;

  /// No description provided for @turnInProgress.
  ///
  /// In en, this message translates to:
  /// **'Still in progress'**
  String get turnInProgress;

  /// No description provided for @turnSkippedSameLanguage.
  ///
  /// In en, this message translates to:
  /// **'Not translated — already in the target language'**
  String get turnSkippedSameLanguage;

  /// No description provided for @turnSkippedEcho.
  ///
  /// In en, this message translates to:
  /// **'Ignored — our own translated speech came back (echo)'**
  String get turnSkippedEcho;

  /// No description provided for @stateChip.
  ///
  /// In en, this message translates to:
  /// **'State: {state}'**
  String stateChip(String state);

  /// No description provided for @stateIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get stateIdle;

  /// No description provided for @stateConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get stateConnecting;

  /// No description provided for @stateReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get stateReady;

  /// No description provided for @stateActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get stateActive;

  /// No description provided for @stateDegraded.
  ///
  /// In en, this message translates to:
  /// **'Degraded'**
  String get stateDegraded;

  /// No description provided for @stateStopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping'**
  String get stateStopping;

  /// No description provided for @outReady.
  ///
  /// In en, this message translates to:
  /// **'OUT: ready'**
  String get outReady;

  /// No description provided for @outNotReady.
  ///
  /// In en, this message translates to:
  /// **'OUT: not ready'**
  String get outNotReady;

  /// No description provided for @inReady.
  ///
  /// In en, this message translates to:
  /// **'IN: ready'**
  String get inReady;

  /// No description provided for @inNotReady.
  ///
  /// In en, this message translates to:
  /// **'IN: not ready'**
  String get inNotReady;

  /// No description provided for @capturing.
  ///
  /// In en, this message translates to:
  /// **'Capturing'**
  String get capturing;

  /// No description provided for @latencyNone.
  ///
  /// In en, this message translates to:
  /// **'Latency: —'**
  String get latencyNone;

  /// No description provided for @latencyValue.
  ///
  /// In en, this message translates to:
  /// **'Latency: {ms} ms'**
  String latencyValue(int ms);

  /// No description provided for @latencyNoMeasurements.
  ///
  /// In en, this message translates to:
  /// **'No measurements yet'**
  String get latencyNoMeasurements;

  /// No description provided for @latencyLastTurnOut.
  ///
  /// In en, this message translates to:
  /// **'Last turn (you → them)'**
  String get latencyLastTurnOut;

  /// No description provided for @latencyLastTurnIn.
  ///
  /// In en, this message translates to:
  /// **'Last turn (them → you)'**
  String get latencyLastTurnIn;

  /// No description provided for @latencyStt.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition commit: {ms} ms'**
  String latencyStt(int ms);

  /// No description provided for @latencyTranslateFirst.
  ///
  /// In en, this message translates to:
  /// **'Translation first text: {ms} ms'**
  String latencyTranslateFirst(int ms);

  /// No description provided for @latencyTranslateTotal.
  ///
  /// In en, this message translates to:
  /// **'Translation total: {ms} ms'**
  String latencyTranslateTotal(int ms);

  /// No description provided for @latencyTtsFirst.
  ///
  /// In en, this message translates to:
  /// **'Voice first audio: {ms} ms'**
  String latencyTtsFirst(int ms);

  /// No description provided for @latencyTtsTotal.
  ///
  /// In en, this message translates to:
  /// **'Voice total: {ms} ms'**
  String latencyTtsTotal(int ms);

  /// No description provided for @latencyAudioLength.
  ///
  /// In en, this message translates to:
  /// **'Audio length: {ms} ms'**
  String latencyAudioLength(int ms);

  /// No description provided for @latencyModel.
  ///
  /// In en, this message translates to:
  /// **'Translation model: {model}'**
  String latencyModel(String model);

  /// No description provided for @panicStop.
  ///
  /// In en, this message translates to:
  /// **'Panic stop (Esc)'**
  String get panicStop;

  /// No description provided for @muteOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Mute my outgoing speech'**
  String get muteOutgoing;

  /// No description provided for @muteIncoming.
  ///
  /// In en, this message translates to:
  /// **'Mute incoming audio'**
  String get muteIncoming;

  /// No description provided for @bypassLabel.
  ///
  /// In en, this message translates to:
  /// **'Original-mic bypass'**
  String get bypassLabel;

  /// No description provided for @switchOn.
  ///
  /// In en, this message translates to:
  /// **'{label}: on'**
  String switchOn(String label);

  /// No description provided for @switchOff.
  ///
  /// In en, this message translates to:
  /// **'{label}: off'**
  String switchOff(String label);

  /// No description provided for @bypassDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Send your real microphone to the call?'**
  String get bypassDialogTitle;

  /// No description provided for @bypassDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Original-mic bypass sends your own voice to the call without translation. Use it only when you want to speak directly.'**
  String get bypassDialogBody;

  /// No description provided for @bypassTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on bypass'**
  String get bypassTurnOn;

  /// No description provided for @pttSemantics.
  ///
  /// In en, this message translates to:
  /// **'Push to talk. Press and hold while you speak.'**
  String get pttSemantics;

  /// No description provided for @turnModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Outgoing speech mode'**
  String get turnModeLabel;

  /// No description provided for @turnModeHold.
  ///
  /// In en, this message translates to:
  /// **'Hold to talk'**
  String get turnModeHold;

  /// No description provided for @turnModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get turnModeAuto;

  /// No description provided for @talkNoSession.
  ///
  /// In en, this message translates to:
  /// **'Works once the session starts'**
  String get talkNoSession;

  /// No description provided for @talkConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get talkConnecting;

  /// No description provided for @talkHoldReady.
  ///
  /// In en, this message translates to:
  /// **'Press and hold, or hold Space'**
  String get talkHoldReady;

  /// No description provided for @talkHoldHeld.
  ///
  /// In en, this message translates to:
  /// **'Speak… release to send'**
  String get talkHoldHeld;

  /// No description provided for @talkListening.
  ///
  /// In en, this message translates to:
  /// **'Listening — sends on each pause'**
  String get talkListening;

  /// No description provided for @talkTranslationPlaying.
  ///
  /// In en, this message translates to:
  /// **'Translation is playing — listening again right after'**
  String get talkTranslationPlaying;

  /// No description provided for @talkMuted.
  ///
  /// In en, this message translates to:
  /// **'Microphone muted — nothing is sent'**
  String get talkMuted;

  /// No description provided for @talkBypass.
  ///
  /// In en, this message translates to:
  /// **'No translation — your microphone goes straight to the call'**
  String get talkBypass;

  /// No description provided for @errModeSwitchUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This gateway can\'t change the mode during a session. Stop and start again to use the other mode.'**
  String get errModeSwitchUnsupported;

  /// No description provided for @showOriginal.
  ///
  /// In en, this message translates to:
  /// **'Show original'**
  String get showOriginal;

  /// No description provided for @showTranslated.
  ///
  /// In en, this message translates to:
  /// **'Show translated'**
  String get showTranslated;

  /// No description provided for @captionsSmaller.
  ///
  /// In en, this message translates to:
  /// **'Smaller captions'**
  String get captionsSmaller;

  /// No description provided for @captionsLarger.
  ///
  /// In en, this message translates to:
  /// **'Larger captions'**
  String get captionsLarger;

  /// No description provided for @captionSize.
  ///
  /// In en, this message translates to:
  /// **'Size {size}'**
  String captionSize(int size);

  /// No description provided for @rateGood.
  ///
  /// In en, this message translates to:
  /// **'Good translation'**
  String get rateGood;

  /// No description provided for @rateBad.
  ///
  /// In en, this message translates to:
  /// **'Poor translation'**
  String get rateBad;

  /// No description provided for @exportConversation.
  ///
  /// In en, this message translates to:
  /// **'Export conversation'**
  String get exportConversation;

  /// No description provided for @exportConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Export the conversation?'**
  String get exportConsentTitle;

  /// No description provided for @exportConsentBody.
  ///
  /// In en, this message translates to:
  /// **'The file will contain the other participant\'s words as well as yours. Confirm that they agreed to this.'**
  String get exportConsentBody;

  /// No description provided for @exportConsentConfirm.
  ///
  /// In en, this message translates to:
  /// **'They agreed — export'**
  String get exportConsentConfirm;

  /// No description provided for @exportSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String exportSaved(String path);

  /// No description provided for @exportDocTitle.
  ///
  /// In en, this message translates to:
  /// **'LiveBridge AI conversation'**
  String get exportDocTitle;

  /// No description provided for @exportDocExported.
  ///
  /// In en, this message translates to:
  /// **'Exported: {time}'**
  String exportDocExported(String time);

  /// No description provided for @exportDocLanguages.
  ///
  /// In en, this message translates to:
  /// **'Languages: {pair}'**
  String exportDocLanguages(String pair);

  /// No description provided for @exportDocMode.
  ///
  /// In en, this message translates to:
  /// **'Mode: {mode}'**
  String exportDocMode(String mode);

  /// No description provided for @exportDocNoTurns.
  ///
  /// In en, this message translates to:
  /// **'No finished turns yet.'**
  String get exportDocNoTurns;

  /// No description provided for @exportDocOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get exportDocOriginal;

  /// No description provided for @exportDocTranslation.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get exportDocTranslation;

  /// No description provided for @exportDocRating.
  ///
  /// In en, this message translates to:
  /// **'Your rating'**
  String get exportDocRating;

  /// No description provided for @exportDocRatingGood.
  ///
  /// In en, this message translates to:
  /// **'good'**
  String get exportDocRatingGood;

  /// No description provided for @exportDocRatingBad.
  ///
  /// In en, this message translates to:
  /// **'bad'**
  String get exportDocRatingBad;

  /// No description provided for @analyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analyticsTitle;

  /// No description provided for @analyticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Numbers about your sessions — never the words'**
  String get analyticsSubtitle;

  /// No description provided for @analyticsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'The log holds numbers only — timings, counts, error codes and your ratings. It contains no transcript text and stays on this Mac.'**
  String get analyticsPrivacy;

  /// No description provided for @analyticsPrivacyWindows.
  ///
  /// In en, this message translates to:
  /// **'The log holds numbers only — timings, counts, error codes and your ratings. It contains no transcript text and stays on this computer.'**
  String get analyticsPrivacyWindows;

  /// No description provided for @analyticsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Record analytics on this Mac'**
  String get analyticsEnabled;

  /// No description provided for @analyticsEnabledWindows.
  ///
  /// In en, this message translates to:
  /// **'Record analytics on this computer'**
  String get analyticsEnabledWindows;

  /// No description provided for @analyticsSessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions: {count}'**
  String analyticsSessions(int count);

  /// No description provided for @analyticsTurns.
  ///
  /// In en, this message translates to:
  /// **'Translated turns: {count}'**
  String analyticsTurns(int count);

  /// No description provided for @analyticsFirst.
  ///
  /// In en, this message translates to:
  /// **'First record: {time}'**
  String analyticsFirst(String time);

  /// No description provided for @analyticsLast.
  ///
  /// In en, this message translates to:
  /// **'Last record: {time}'**
  String analyticsLast(String time);

  /// No description provided for @analyticsTimingTitle.
  ///
  /// In en, this message translates to:
  /// **'Timing (ms)'**
  String get analyticsTimingTitle;

  /// No description provided for @analyticsColCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get analyticsColCount;

  /// No description provided for @analyticsColP50.
  ///
  /// In en, this message translates to:
  /// **'p50'**
  String get analyticsColP50;

  /// No description provided for @analyticsColP95.
  ///
  /// In en, this message translates to:
  /// **'p95'**
  String get analyticsColP95;

  /// No description provided for @analyticsColMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get analyticsColMax;

  /// No description provided for @analyticsRowE2e.
  ///
  /// In en, this message translates to:
  /// **'End-to-end'**
  String get analyticsRowE2e;

  /// No description provided for @analyticsRowStt.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition'**
  String get analyticsRowStt;

  /// No description provided for @analyticsRowTranslateFirst.
  ///
  /// In en, this message translates to:
  /// **'Translation, first text'**
  String get analyticsRowTranslateFirst;

  /// No description provided for @analyticsRowTranslateTotal.
  ///
  /// In en, this message translates to:
  /// **'Translation, complete'**
  String get analyticsRowTranslateTotal;

  /// No description provided for @analyticsRowTtsFirst.
  ///
  /// In en, this message translates to:
  /// **'Voice, first audio'**
  String get analyticsRowTtsFirst;

  /// No description provided for @analyticsErrorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Errors by code'**
  String get analyticsErrorsTitle;

  /// No description provided for @analyticsNoErrors.
  ///
  /// In en, this message translates to:
  /// **'No errors recorded'**
  String get analyticsNoErrors;

  /// No description provided for @analyticsReconnects.
  ///
  /// In en, this message translates to:
  /// **'Reconnects: {count}'**
  String analyticsReconnects(int count);

  /// No description provided for @analyticsEmptyTurns.
  ///
  /// In en, this message translates to:
  /// **'Empty turns: {count}'**
  String analyticsEmptyTurns(int count);

  /// No description provided for @analyticsRatedGood.
  ///
  /// In en, this message translates to:
  /// **'Rated good: {count}'**
  String analyticsRatedGood(int count);

  /// No description provided for @analyticsRatedBad.
  ///
  /// In en, this message translates to:
  /// **'Rated bad: {count}'**
  String analyticsRatedBad(int count);

  /// No description provided for @analyticsFileSize.
  ///
  /// In en, this message translates to:
  /// **'Log size: {sizeText}'**
  String analyticsFileSize(String sizeText);

  /// No description provided for @analyticsPath.
  ///
  /// In en, this message translates to:
  /// **'File: {path}'**
  String analyticsPath(String path);

  /// No description provided for @analyticsExportLog.
  ///
  /// In en, this message translates to:
  /// **'Export log'**
  String get analyticsExportLog;

  /// No description provided for @analyticsClearLog.
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get analyticsClearLog;

  /// No description provided for @analyticsClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear the analytics log?'**
  String get analyticsClearTitle;

  /// No description provided for @analyticsClearBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes all recorded numbers on this Mac. It cannot be undone.'**
  String get analyticsClearBody;

  /// No description provided for @analyticsClearBodyWindows.
  ///
  /// In en, this message translates to:
  /// **'This deletes all recorded numbers on this computer. It cannot be undone.'**
  String get analyticsClearBodyWindows;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @telemetryTitle.
  ///
  /// In en, this message translates to:
  /// **'Share anonymous statistics with the developer'**
  String get telemetryTitle;

  /// No description provided for @telemetryNeedsAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Turn on analytics recording above first — sharing uploads that log.'**
  String get telemetryNeedsAnalytics;

  /// No description provided for @telemetryDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Share anonymous statistics?'**
  String get telemetryDialogTitle;

  /// No description provided for @telemetryDialogSent.
  ///
  /// In en, this message translates to:
  /// **'Sent: timings, counts, error codes, text lengths in characters, your thumbs up/down, the app version, the macOS version, the interface language and a random install ID.'**
  String get telemetryDialogSent;

  /// No description provided for @telemetryDialogSentWindows.
  ///
  /// In en, this message translates to:
  /// **'Sent: timings, counts, error codes, text lengths in characters, your thumbs up/down, the app version, the Windows version, the interface language and a random install ID.'**
  String get telemetryDialogSentWindows;

  /// No description provided for @telemetryDialogNever.
  ///
  /// In en, this message translates to:
  /// **'Never sent: what was said, translations, audio, device names, the gateway address or keys.'**
  String get telemetryDialogNever;

  /// No description provided for @telemetryDialogWhere.
  ///
  /// In en, this message translates to:
  /// **'Goes to: the developer\'s site, jaysonkhan.com.'**
  String get telemetryDialogWhere;

  /// No description provided for @telemetryDialogOff.
  ///
  /// In en, this message translates to:
  /// **'You can switch this off at any time.'**
  String get telemetryDialogOff;

  /// No description provided for @telemetryPending.
  ///
  /// In en, this message translates to:
  /// **'Records waiting to upload: {count}'**
  String telemetryPending(int count);

  /// No description provided for @telemetryLastUpload.
  ///
  /// In en, this message translates to:
  /// **'Last upload: {time}'**
  String telemetryLastUpload(String time);

  /// No description provided for @telemetryNever.
  ///
  /// In en, this message translates to:
  /// **'never'**
  String get telemetryNever;

  /// No description provided for @telemetryLastError.
  ///
  /// In en, this message translates to:
  /// **'Last upload error: {error}'**
  String telemetryLastError(String error);

  /// No description provided for @telemetryInstallId.
  ///
  /// In en, this message translates to:
  /// **'Install ID'**
  String get telemetryInstallId;

  /// No description provided for @telemetryStatsPage.
  ///
  /// In en, this message translates to:
  /// **'Public statistics page'**
  String get telemetryStatsPage;

  /// No description provided for @feedbackButton.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get feedbackButton;

  /// No description provided for @feedbackNote.
  ///
  /// In en, this message translates to:
  /// **'Your message goes to the developer. Your e-mail is only used to reply to you.'**
  String get feedbackNote;

  /// No description provided for @feedbackMessageLabel.
  ///
  /// In en, this message translates to:
  /// **'Your message'**
  String get feedbackMessageLabel;

  /// No description provided for @feedbackEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'E-mail (optional)'**
  String get feedbackEmailLabel;

  /// No description provided for @feedbackEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid e-mail address or leave this empty.'**
  String get feedbackEmailInvalid;

  /// No description provided for @feedbackRatingLabel.
  ///
  /// In en, this message translates to:
  /// **'Rating (optional)'**
  String get feedbackRatingLabel;

  /// No description provided for @feedbackStar.
  ///
  /// In en, this message translates to:
  /// **'{count} out of 5 stars'**
  String feedbackStar(int count);

  /// No description provided for @feedbackSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get feedbackSend;

  /// No description provided for @feedbackSent.
  ///
  /// In en, this message translates to:
  /// **'Thank you — your feedback was sent.'**
  String get feedbackSent;

  /// No description provided for @feedbackRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many messages recently. Please try again later.'**
  String get feedbackRateLimited;

  /// No description provided for @feedbackFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send your feedback. Check your connection and try again.'**
  String get feedbackFailed;

  /// No description provided for @sectionVoices.
  ///
  /// In en, this message translates to:
  /// **'Voices'**
  String get sectionVoices;

  /// No description provided for @voiceOut.
  ///
  /// In en, this message translates to:
  /// **'My voice (outgoing)'**
  String get voiceOut;

  /// No description provided for @voiceIn.
  ///
  /// In en, this message translates to:
  /// **'Their voice (incoming)'**
  String get voiceIn;

  /// No description provided for @voiceDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get voiceDefault;

  /// No description provided for @voiceChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get voiceChange;

  /// No description provided for @voiceNeedsToken.
  ///
  /// In en, this message translates to:
  /// **'To choose voices, enter the gateway token: press Change beside the connection.'**
  String get voiceNeedsToken;

  /// No description provided for @voicePickerTitleOut.
  ///
  /// In en, this message translates to:
  /// **'My voice'**
  String get voicePickerTitleOut;

  /// No description provided for @voicePickerTitleIn.
  ///
  /// In en, this message translates to:
  /// **'Their voice'**
  String get voicePickerTitleIn;

  /// No description provided for @voiceSearch.
  ///
  /// In en, this message translates to:
  /// **'Search voices'**
  String get voiceSearch;

  /// No description provided for @voiceFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get voiceFilterAll;

  /// No description provided for @voiceFilterGender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get voiceFilterGender;

  /// No description provided for @voiceFilterAge.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get voiceFilterAge;

  /// No description provided for @voiceFilterAccent.
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get voiceFilterAccent;

  /// No description provided for @voiceFilterLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get voiceFilterLanguage;

  /// No description provided for @voiceFilterUseCase.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get voiceFilterUseCase;

  /// No description provided for @voiceGenderMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get voiceGenderMale;

  /// No description provided for @voiceGenderFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get voiceGenderFemale;

  /// No description provided for @voiceGenderNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get voiceGenderNeutral;

  /// No description provided for @voiceAgeYoung.
  ///
  /// In en, this message translates to:
  /// **'Young'**
  String get voiceAgeYoung;

  /// No description provided for @voiceAgeMiddle.
  ///
  /// In en, this message translates to:
  /// **'Middle-aged'**
  String get voiceAgeMiddle;

  /// No description provided for @voiceAgeOld.
  ///
  /// In en, this message translates to:
  /// **'Old'**
  String get voiceAgeOld;

  /// No description provided for @voicePlaySample.
  ///
  /// In en, this message translates to:
  /// **'Play sample'**
  String get voicePlaySample;

  /// No description provided for @voiceStopSample.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get voiceStopSample;

  /// No description provided for @voiceNoSample.
  ///
  /// In en, this message translates to:
  /// **'No sample'**
  String get voiceNoSample;

  /// No description provided for @voiceNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No voices match'**
  String get voiceNoMatch;

  /// No description provided for @voiceRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get voiceRetry;

  /// No description provided for @voicesUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'The gateway refused the token.'**
  String get voicesUnauthorized;

  /// No description provided for @voicesUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This gateway cannot list voices. Update it to choose a voice.'**
  String get voicesUnsupported;

  /// No description provided for @voicesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The voice list is not available right now.'**
  String get voicesUnavailable;

  /// No description provided for @voicesNetwork.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the gateway.'**
  String get voicesNetwork;

  /// No description provided for @voicesInvalidKey.
  ///
  /// In en, this message translates to:
  /// **'ElevenLabs refused your key. Check that it is correct.'**
  String get voicesInvalidKey;

  /// No description provided for @errVoiceNotFound.
  ///
  /// In en, this message translates to:
  /// **'The chosen voice is not available. Choose another or go back to Default.'**
  String get errVoiceNotFound;

  /// No description provided for @onboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Real-time interpreter'**
  String get onboardingTitle;

  /// No description provided for @onboardingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in and try 5 minutes for free'**
  String get onboardingSubtitle;

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// No description provided for @onboardingOwnKeys.
  ///
  /// In en, this message translates to:
  /// **'I have my own API keys'**
  String get onboardingOwnKeys;

  /// No description provided for @elevenlabsKey.
  ///
  /// In en, this message translates to:
  /// **'ElevenLabs API key'**
  String get elevenlabsKey;

  /// No description provided for @geminiKey.
  ///
  /// In en, this message translates to:
  /// **'Gemini API key'**
  String get geminiKey;

  /// No description provided for @saveAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Save and continue'**
  String get saveAndContinue;

  /// No description provided for @showSecret.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showSecret;

  /// No description provided for @hideSecret.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hideSecret;

  /// No description provided for @onboardingOwnGateway.
  ///
  /// In en, this message translates to:
  /// **'Own gateway'**
  String get onboardingOwnGateway;

  /// No description provided for @onboardingSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save. Try again.'**
  String get onboardingSaveFailed;

  /// No description provided for @onboardingBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// No description provided for @signInWaitingTitle.
  ///
  /// In en, this message translates to:
  /// **'Continue in your browser'**
  String get signInWaitingTitle;

  /// No description provided for @signInWaitingHint.
  ///
  /// In en, this message translates to:
  /// **'Check that this code is on the page, then approve it.'**
  String get signInWaitingHint;

  /// No description provided for @signInOpenAgain.
  ///
  /// In en, this message translates to:
  /// **'Open again'**
  String get signInOpenAgain;

  /// No description provided for @signInOpenManually.
  ///
  /// In en, this message translates to:
  /// **'Open this address in your browser:'**
  String get signInOpenManually;

  /// No description provided for @signInExpired.
  ///
  /// In en, this message translates to:
  /// **'The code expired. Sign in again.'**
  String get signInExpired;

  /// No description provided for @signInDenied.
  ///
  /// In en, this message translates to:
  /// **'Sign-in was declined in the browser.'**
  String get signInDenied;

  /// No description provided for @signInNetwork.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the sign-in service. Check your internet connection.'**
  String get signInNetwork;

  /// No description provided for @signInRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a minute and try again.'**
  String get signInRateLimited;

  /// No description provided for @noticeSignedOut.
  ///
  /// In en, this message translates to:
  /// **'You were signed out. Sign in again.'**
  String get noticeSignedOut;

  /// No description provided for @topUp.
  ///
  /// In en, this message translates to:
  /// **'Top up'**
  String get topUp;

  /// No description provided for @accountPage.
  ///
  /// In en, this message translates to:
  /// **'Account page'**
  String get accountPage;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @changeConnection.
  ///
  /// In en, this message translates to:
  /// **'Change connection'**
  String get changeConnection;

  /// No description provided for @connectionOwnKeys.
  ///
  /// In en, this message translates to:
  /// **'Own keys'**
  String get connectionOwnKeys;

  /// No description provided for @connectionChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get connectionChange;

  /// No description provided for @chipMinutes.
  ///
  /// In en, this message translates to:
  /// **'≈ {minutes} min'**
  String chipMinutes(int minutes);

  /// No description provided for @topUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Top up your balance'**
  String get topUpTitle;

  /// No description provided for @topUpMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String topUpMinutes(int minutes);

  /// No description provided for @topUpTaxNote.
  ///
  /// In en, this message translates to:
  /// **'Prices are before tax; the checkout page shows the total.'**
  String get topUpTaxNote;

  /// No description provided for @topUpNoPackages.
  ///
  /// In en, this message translates to:
  /// **'Could not load the packages.'**
  String get topUpNoPackages;

  /// No description provided for @topUpTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get topUpTryAgain;

  /// No description provided for @topUpRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a minute and try again.'**
  String get topUpRateLimited;

  /// No description provided for @topUpNetwork.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the site. Check your internet connection.'**
  String get topUpNetwork;

  /// No description provided for @topUpUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The checkout page could not be opened right now. Try again later.'**
  String get topUpUnavailable;

  /// No description provided for @bannerBalanceEmpty.
  ///
  /// In en, this message translates to:
  /// **'Balance is empty — top up'**
  String get bannerBalanceEmpty;

  /// No description provided for @bannerBillingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Billing could not be reached. Try again.'**
  String get bannerBillingUnavailable;

  /// No description provided for @bannerIdleTimeout.
  ///
  /// In en, this message translates to:
  /// **'The session ended after 10 minutes without speech.'**
  String get bannerIdleTimeout;

  /// No description provided for @bannerSessionReplaced.
  ///
  /// In en, this message translates to:
  /// **'The session continued on another device.'**
  String get bannerSessionReplaced;

  /// No description provided for @bannerSessionLimit.
  ///
  /// In en, this message translates to:
  /// **'The service is busy. Try again in a minute.'**
  String get bannerSessionLimit;

  /// No description provided for @connectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get connectionAccount;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @reportButton.
  ///
  /// In en, this message translates to:
  /// **'Report a problem'**
  String get reportButton;

  /// No description provided for @reportNote.
  ///
  /// In en, this message translates to:
  /// **'Tell us what went wrong. The report goes to the developer; the e-mail is only used to reply to you.'**
  String get reportNote;

  /// No description provided for @reportMessageLabel.
  ///
  /// In en, this message translates to:
  /// **'What happened?'**
  String get reportMessageLabel;

  /// No description provided for @reportIncludeLog.
  ///
  /// In en, this message translates to:
  /// **'Include the diagnostic log'**
  String get reportIncludeLog;

  /// No description provided for @reportIncludeLogNote.
  ///
  /// In en, this message translates to:
  /// **'Settings, devices, errors and timings since the app started. Never what was said, keys or tokens.'**
  String get reportIncludeLogNote;

  /// No description provided for @reportShowLog.
  ///
  /// In en, this message translates to:
  /// **'Show what will be sent'**
  String get reportShowLog;

  /// No description provided for @reportPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'What will be sent'**
  String get reportPreviewTitle;

  /// No description provided for @reportSent.
  ///
  /// In en, this message translates to:
  /// **'Report sent. Thank you!'**
  String get reportSent;

  /// No description provided for @reportFailed.
  ///
  /// In en, this message translates to:
  /// **'The report was not sent. Check the connection and try again.'**
  String get reportFailed;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'ru', 'tr', 'uz'].contains(locale.languageCode);

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
    case 'tr':
      return AppLocalizationsTr();
    case 'uz':
      return AppLocalizationsUz();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
