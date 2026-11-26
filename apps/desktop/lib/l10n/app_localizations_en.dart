// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get refresh => 'Refresh';

  @override
  String get copied => 'Copied';

  @override
  String get delete => 'Delete';

  @override
  String get notSelected => 'Not selected';

  @override
  String get dismissError => 'Dismiss error';

  @override
  String get dismissNotice => 'Dismiss notice';

  @override
  String get languagePickerTooltip => 'Interface language';

  @override
  String get mockBanner => 'MOCK PROVIDERS — test tones and placeholder text, not a real translation';

  @override
  String get bypassBanner => 'BYPASS — your real microphone is going to the call, untranslated';

  @override
  String get errorSessionEnded => '(the session ended)';

  @override
  String get errProviderUnavailable => 'The translation or voice service is unavailable right now.';

  @override
  String get errTranslationFailed => 'A phrase could not be translated.';

  @override
  String get errTranslationRejected => 'The translation came back unusable, so nothing was spoken.';

  @override
  String get errTtsFailed => 'A phrase could not be spoken.';

  @override
  String get errCaptureBacklog => 'Audio is piling up faster than it can be processed.';

  @override
  String get errCaptureOverflow => 'Some audio was dropped because processing fell behind.';

  @override
  String get errSynthesisCongested => 'The voice service is congested; speech may be delayed.';

  @override
  String get errPlaybackOverflow => 'Too much audio is waiting to play; some was skipped.';

  @override
  String get errSourceGone => 'The meeting app stopped playing audio or was closed.';

  @override
  String get errDeviceRemoved => 'An audio device was disconnected.';

  @override
  String get errGatewayUnreachable => 'Cannot reach the gateway. Check the gateway URL and your internet connection.';

  @override
  String get errUnauthorized => 'The gateway rejected the access token. Check it: press Change beside the connection.';

  @override
  String get errSessionLimit => 'The gateway\'s session limit is reached. Try again later.';

  @override
  String get errSessionExpired => 'The session expired. Start a new one.';

  @override
  String get errNoVirtualMic => 'The virtual microphone (BlackHole 2ch) was not found.';

  @override
  String get errNoVirtualMicWindows => 'The virtual microphone (VB-CABLE) was not found.';

  @override
  String get errNoHeadphones => 'The selected headphones were not found.';

  @override
  String get errNoMicrophone => 'The selected microphone was not found.';

  @override
  String get errUnsafeRoute => 'Unsafe audio route refused: the microphone or headphones are a virtual device.';

  @override
  String get errAccountsUnavailable => 'The account service could not be reached. Check your internet connection.';

  @override
  String get errBadRequest => 'The gateway did not accept the session request.';

  @override
  String get errBadRequestKeys =>
      'The service did not accept the format of your keys. Check them: press Change beside the connection.';

  @override
  String get errRateLimited => 'Too many attempts. Wait a minute and try again.';

  @override
  String get errSettingsFailed => 'The settings could not be saved. Try again.';

  @override
  String get errGatewayError => 'The gateway ran into an error. Try again in a moment.';

  @override
  String get errSignInRefused => 'The service did not accept your sign-in. Try again later.';

  @override
  String get errServiceRefused => 'The service refused the session. Try again later.';

  @override
  String get blockChooseMic => 'Choose a microphone.';

  @override
  String blockMicIsVirtual(String device) {
    return 'Unsafe route: the microphone is the same device as the virtual microphone ($device). Choose your physical microphone.';
  }

  @override
  String blockMicIsCable(String device) {
    return 'Unsafe route: the microphone is a virtual cable ($device), so the translation would come back into the call. Choose your physical microphone.';
  }

  @override
  String get blockChooseHeadphones => 'Choose headphones.';

  @override
  String blockHeadphonesVirtual(String device) {
    return 'Unsafe route: the headphones are a virtual device ($device). Choose your physical headphones.';
  }

  @override
  String get blockBidirectionalNeedsVirtual =>
      'Bidirectional speech needs a virtual microphone (BlackHole 2ch), which is not installed.';

  @override
  String get blockBidirectionalNeedsVirtualWindows =>
      'Bidirectional speech needs a virtual microphone (VB-CABLE), which is not installed.';

  @override
  String get blockIncomingNeedsSource => 'Incoming audio needs at least one meeting source.';

  @override
  String get blockSameLanguages => 'Choose two different languages.';

  @override
  String get blockEnterGateway => 'Enter the gateway address: press Change beside the connection.';

  @override
  String get blockEnterToken => 'Enter the access token: press Change beside the connection.';

  @override
  String get blockEnterKeys => 'Enter your ElevenLabs and Gemini keys.';

  @override
  String get blockBalanceEmpty => 'Your balance is empty. Top up to start.';

  @override
  String noticeMicLost(String name) {
    return 'Microphone \"$name\" is no longer available. Choose another microphone.';
  }

  @override
  String noticeHeadphonesLost(String name) {
    return 'Headphones \"$name\" are no longer available. Choose other headphones.';
  }

  @override
  String get startSession => 'Start session';

  @override
  String get stopSession => 'Stop session';

  @override
  String get setupLocked => 'Setup is locked while a session is running.';

  @override
  String get sectionLanguageMode => 'Language and mode';

  @override
  String get languageUz => 'Uzbek';

  @override
  String get languageEn => 'English';

  @override
  String get languageRu => 'Russian';

  @override
  String get languageTr => 'Turkish';

  @override
  String get myLanguage => 'My language';

  @override
  String get theirLanguage => 'Their language';

  @override
  String get modeCaptionsTitle => 'Captions only';

  @override
  String get modeCaptionsDesc => 'Live captions both ways. Nothing is spoken.';

  @override
  String get modeIncomingTitle => 'Incoming audio';

  @override
  String get modeIncomingDesc =>
      'Captions both ways, plus their speech translated into your language in your headphones.';

  @override
  String get modeBidirectionalTitle => 'Bidirectional speech';

  @override
  String get modeBidirectionalDesc =>
      'Also speaks your translation into the call in a synthesized voice, through the virtual microphone.';

  @override
  String get sectionDevices => 'Devices';

  @override
  String get deviceMicrophone => 'Microphone';

  @override
  String get deviceHeadphones => 'Headphones';

  @override
  String virtualMicFound(String name) {
    return 'Virtual microphone: $name found';
  }

  @override
  String virtualMicFoundWindows(String name) {
    return 'Virtual microphone: $name found. In the meeting app, choose CABLE Output as the microphone.';
  }

  @override
  String get blackHoleMissingNotice => 'BlackHole 2ch not installed — outgoing speech unavailable; captions still work';

  @override
  String blackHoleInstallWith(String command) {
    return 'Install it with: $command';
  }

  @override
  String get vbCableMissingNotice => 'VB-CABLE not installed — outgoing speech unavailable; captions still work';

  @override
  String vbCableDownloadFrom(String url) {
    return 'Download it free from: $url';
  }

  @override
  String get sectionMeetingSource => 'Meeting source';

  @override
  String get noAudioApps => 'No apps are using audio right now. Open your meeting app, then press Refresh.';

  @override
  String processPid(int pid) {
    return 'pid $pid';
  }

  @override
  String get processPlaying => 'playing';

  @override
  String get sectionGateway => 'Outgoing turns and connection';

  @override
  String get outgoingTurnMode => 'Outgoing turn mode';

  @override
  String get turnPttTitle => 'Push-to-talk';

  @override
  String get turnPttDesc => 'Hold the button or the Space key while you speak.';

  @override
  String get turnVadTitle => 'Auto: VAD';

  @override
  String get turnVadDesc => 'Sends your speech when you pause.';

  @override
  String get turnPredictionTitle => 'Auto: turn prediction';

  @override
  String get turnPredictionDesc => 'Predicts when you have finished a thought.';

  @override
  String get gatewayUrl => 'Gateway URL';

  @override
  String get accessToken => 'Access token';

  @override
  String get translationModelOptional => 'Translation model (optional)';

  @override
  String get testDevicesTitle => 'Test your devices';

  @override
  String get testDevicesUnavailable => 'Not available while a session is running';

  @override
  String get testDevicesSubtitle => 'Level meters, test tones, permission';

  @override
  String get levelMic => 'Microphone level';

  @override
  String get levelSource => 'Meeting source level';

  @override
  String get levelSilent => 'silent';

  @override
  String get testHeadphones => 'Test headphones';

  @override
  String get testVirtualMic => 'Test virtual mic';

  @override
  String get testToneNote => 'Each test plays one quiet tone. Leave any call that uses BlackHole 2ch before testing.';

  @override
  String get testToneNoteWindows =>
      'Each test plays one quiet tone. Leave any call that uses CABLE Output before testing.';

  @override
  String micPermission(String status) {
    return 'Microphone permission: $status';
  }

  @override
  String get permissionGranted => 'granted';

  @override
  String get permissionDenied => 'denied';

  @override
  String get permissionUndetermined => 'not asked yet';

  @override
  String get permissionRequest => 'Request';

  @override
  String get micPrivacyWindows =>
      'On Windows, microphone access for desktop apps is a system setting. If the microphone level stays silent, turn on \"Let desktop apps access your microphone\" in Settings → Privacy & security → Microphone.';

  @override
  String get routingTitle => 'Routing instructions';

  @override
  String get routingSubtitle => 'How to set up Zoom, Meet and Upwork';

  @override
  String get routingZoomDesktopTitle => 'Zoom Desktop';

  @override
  String get routingZoom1 => 'Open Zoom → Settings → Audio.';

  @override
  String get routingZoom2 => 'Microphone: BlackHole 2ch.';

  @override
  String get routingZoom2Windows => 'Microphone: CABLE Output (VB-Audio Virtual Cable).';

  @override
  String get routingZoom3 => 'Speaker: your headphones.';

  @override
  String get routingZoom4 => 'Start the session here before you speak.';

  @override
  String get routingWebTitle => 'Zoom Web / Google Meet';

  @override
  String get routingWeb1 => 'Open the browser\'s audio settings for the call.';

  @override
  String get routingWeb2 => 'Microphone: BlackHole 2ch. Speaker: your headphones.';

  @override
  String get routingWeb2Windows => 'Microphone: CABLE Output (VB-Audio Virtual Cable). Speaker: your headphones.';

  @override
  String get routingWeb3 => 'Use a dedicated browser window and close other tabs that play audio.';

  @override
  String get routingUpworkTitle => 'Upwork';

  @override
  String get routingUpwork1 => 'Start the call from Upwork Messages.';

  @override
  String get routingUpwork2 => 'Then use the same Zoom Desktop or browser settings as above.';

  @override
  String get routingBackTitle => 'How to return to normal';

  @override
  String get routingBack1 => 'In the meeting app, select your physical microphone again.';

  @override
  String get routingBack2 => 'Stop the session here.';

  @override
  String routingInstallVirtual(String command) {
    return 'Install the virtual microphone: $command';
  }

  @override
  String routingInstallVirtualWindows(String url) {
    return 'Install the virtual microphone VB-CABLE (free): $url';
  }

  @override
  String get consentTitle => 'Tell the other participants first';

  @override
  String get consentIntro => 'Say or paste this sentence into the call chat before you start.';

  @override
  String get consentCopyEnglish => 'Copy English';

  @override
  String get consentCopyRussian => 'Copy Russian';

  @override
  String get consentCheckbox => 'The other participants have been informed and agreed';

  @override
  String get laneOut => 'You → them';

  @override
  String get laneIn => 'Them → you';

  @override
  String get noCaptions => 'No captions yet';

  @override
  String get turnInProgress => 'Still in progress';

  @override
  String get turnSkippedSameLanguage => 'Not translated — already in the target language';

  @override
  String get turnSkippedEcho => 'Ignored — our own translated speech came back (echo)';

  @override
  String stateChip(String state) {
    return 'State: $state';
  }

  @override
  String get stateIdle => 'Idle';

  @override
  String get stateConnecting => 'Connecting';

  @override
  String get stateReady => 'Ready';

  @override
  String get stateActive => 'Active';

  @override
  String get stateDegraded => 'Degraded';

  @override
  String get stateStopping => 'Stopping';

  @override
  String get outReady => 'OUT: ready';

  @override
  String get outNotReady => 'OUT: not ready';

  @override
  String get inReady => 'IN: ready';

  @override
  String get inNotReady => 'IN: not ready';

  @override
  String get capturing => 'Capturing';

  @override
  String get latencyNone => 'Latency: —';

  @override
  String latencyValue(int ms) {
    return 'Latency: $ms ms';
  }

  @override
  String get latencyNoMeasurements => 'No measurements yet';

  @override
  String get latencyLastTurnOut => 'Last turn (you → them)';

  @override
  String get latencyLastTurnIn => 'Last turn (them → you)';

  @override
  String latencyStt(int ms) {
    return 'Speech recognition commit: $ms ms';
  }

  @override
  String latencyTranslateFirst(int ms) {
    return 'Translation first text: $ms ms';
  }

  @override
  String latencyTranslateTotal(int ms) {
    return 'Translation total: $ms ms';
  }

  @override
  String latencyTtsFirst(int ms) {
    return 'Voice first audio: $ms ms';
  }

  @override
  String latencyTtsTotal(int ms) {
    return 'Voice total: $ms ms';
  }

  @override
  String latencyAudioLength(int ms) {
    return 'Audio length: $ms ms';
  }

  @override
  String latencyModel(String model) {
    return 'Translation model: $model';
  }

  @override
  String get panicStop => 'Panic stop (Esc)';

  @override
  String get muteOutgoing => 'Mute my outgoing speech';

  @override
  String get muteIncoming => 'Mute incoming audio';

  @override
  String get bypassLabel => 'Original-mic bypass';

  @override
  String switchOn(String label) {
    return '$label: on';
  }

  @override
  String switchOff(String label) {
    return '$label: off';
  }

  @override
  String get bypassDialogTitle => 'Send your real microphone to the call?';

  @override
  String get bypassDialogBody =>
      'Original-mic bypass sends your own voice to the call without translation. Use it only when you want to speak directly.';

  @override
  String get bypassTurnOn => 'Turn on bypass';

  @override
  String get pttHintHeld => 'Talking… release to send';

  @override
  String get pttHintReady => 'Hold to talk (or hold Space)';

  @override
  String get pttHintWaiting => 'Hold to talk — available when the session is ready';

  @override
  String get pttHintOff => 'Push-to-talk is off — outgoing turns are automatic';

  @override
  String get pttSemantics => 'Push to talk. Press and hold while you speak.';

  @override
  String get showOriginal => 'Show original';

  @override
  String get showTranslated => 'Show translated';

  @override
  String get captionsSmaller => 'Smaller captions';

  @override
  String get captionsLarger => 'Larger captions';

  @override
  String captionSize(int size) {
    return 'Size $size';
  }

  @override
  String get rateGood => 'Good translation';

  @override
  String get rateBad => 'Poor translation';

  @override
  String get exportConversation => 'Export conversation';

  @override
  String get exportConsentTitle => 'Export the conversation?';

  @override
  String get exportConsentBody =>
      'The file will contain the other participant\'s words as well as yours. Confirm that they agreed to this.';

  @override
  String get exportConsentConfirm => 'They agreed — export';

  @override
  String exportSaved(String path) {
    return 'Saved to $path';
  }

  @override
  String get exportDocTitle => 'LiveBridge AI conversation';

  @override
  String exportDocExported(String time) {
    return 'Exported: $time';
  }

  @override
  String exportDocLanguages(String pair) {
    return 'Languages: $pair';
  }

  @override
  String exportDocMode(String mode) {
    return 'Mode: $mode';
  }

  @override
  String get exportDocNoTurns => 'No finished turns yet.';

  @override
  String get exportDocOriginal => 'Original';

  @override
  String get exportDocTranslation => 'Translation';

  @override
  String get exportDocRating => 'Your rating';

  @override
  String get exportDocRatingGood => 'good';

  @override
  String get exportDocRatingBad => 'bad';

  @override
  String get analyticsTitle => 'Analytics';

  @override
  String get analyticsSubtitle => 'Numbers about your sessions — never the words';

  @override
  String get analyticsPrivacy =>
      'The log holds numbers only — timings, counts, error codes and your ratings. It contains no transcript text and stays on this Mac.';

  @override
  String get analyticsPrivacyWindows =>
      'The log holds numbers only — timings, counts, error codes and your ratings. It contains no transcript text and stays on this computer.';

  @override
  String get analyticsEnabled => 'Record analytics on this Mac';

  @override
  String get analyticsEnabledWindows => 'Record analytics on this computer';

  @override
  String analyticsSessions(int count) {
    return 'Sessions: $count';
  }

  @override
  String analyticsTurns(int count) {
    return 'Translated turns: $count';
  }

  @override
  String analyticsFirst(String time) {
    return 'First record: $time';
  }

  @override
  String analyticsLast(String time) {
    return 'Last record: $time';
  }

  @override
  String get analyticsTimingTitle => 'Timing (ms)';

  @override
  String get analyticsColCount => 'Count';

  @override
  String get analyticsColP50 => 'p50';

  @override
  String get analyticsColP95 => 'p95';

  @override
  String get analyticsColMax => 'Max';

  @override
  String get analyticsRowE2e => 'End-to-end';

  @override
  String get analyticsRowStt => 'Speech recognition';

  @override
  String get analyticsRowTranslateFirst => 'Translation, first text';

  @override
  String get analyticsRowTranslateTotal => 'Translation, complete';

  @override
  String get analyticsRowTtsFirst => 'Voice, first audio';

  @override
  String get analyticsErrorsTitle => 'Errors by code';

  @override
  String get analyticsNoErrors => 'No errors recorded';

  @override
  String analyticsReconnects(int count) {
    return 'Reconnects: $count';
  }

  @override
  String analyticsEmptyTurns(int count) {
    return 'Empty turns: $count';
  }

  @override
  String analyticsRatedGood(int count) {
    return 'Rated good: $count';
  }

  @override
  String analyticsRatedBad(int count) {
    return 'Rated bad: $count';
  }

  @override
  String analyticsFileSize(String sizeText) {
    return 'Log size: $sizeText';
  }

  @override
  String analyticsPath(String path) {
    return 'File: $path';
  }

  @override
  String get analyticsExportLog => 'Export log';

  @override
  String get analyticsClearLog => 'Clear log';

  @override
  String get analyticsClearTitle => 'Clear the analytics log?';

  @override
  String get analyticsClearBody => 'This deletes all recorded numbers on this Mac. It cannot be undone.';

  @override
  String get analyticsClearBodyWindows => 'This deletes all recorded numbers on this computer. It cannot be undone.';

  @override
  String get copy => 'Copy';

  @override
  String get telemetryTitle => 'Share anonymous statistics with the developer';

  @override
  String get telemetryNeedsAnalytics => 'Turn on analytics recording above first — sharing uploads that log.';

  @override
  String get telemetryDialogTitle => 'Share anonymous statistics?';

  @override
  String get telemetryDialogSent =>
      'Sent: timings, counts, error codes, text lengths in characters, your thumbs up/down, the app version, the macOS version, the interface language and a random install ID.';

  @override
  String get telemetryDialogSentWindows =>
      'Sent: timings, counts, error codes, text lengths in characters, your thumbs up/down, the app version, the Windows version, the interface language and a random install ID.';

  @override
  String get telemetryDialogNever =>
      'Never sent: what was said, translations, audio, device names, the gateway address or keys.';

  @override
  String get telemetryDialogWhere => 'Goes to: the developer\'s site, jaysonkhan.com.';

  @override
  String get telemetryDialogOff => 'You can switch this off at any time.';

  @override
  String telemetryPending(int count) {
    return 'Records waiting to upload: $count';
  }

  @override
  String telemetryLastUpload(String time) {
    return 'Last upload: $time';
  }

  @override
  String get telemetryNever => 'never';

  @override
  String telemetryLastError(String error) {
    return 'Last upload error: $error';
  }

  @override
  String get telemetryInstallId => 'Install ID';

  @override
  String get telemetryStatsPage => 'Public statistics page';

  @override
  String get feedbackButton => 'Send feedback';

  @override
  String get feedbackNote => 'Your message goes to the developer. Your e-mail is only used to reply to you.';

  @override
  String get feedbackMessageLabel => 'Your message';

  @override
  String get feedbackEmailLabel => 'E-mail (optional)';

  @override
  String get feedbackEmailInvalid => 'Enter a valid e-mail address or leave this empty.';

  @override
  String get feedbackRatingLabel => 'Rating (optional)';

  @override
  String feedbackStar(int count) {
    return '$count out of 5 stars';
  }

  @override
  String get feedbackSend => 'Send';

  @override
  String get feedbackSent => 'Thank you — your feedback was sent.';

  @override
  String get feedbackRateLimited => 'Too many messages recently. Please try again later.';

  @override
  String get feedbackFailed => 'Could not send your feedback. Check your connection and try again.';

  @override
  String get sectionVoices => 'Voices';

  @override
  String get voiceOut => 'My voice (outgoing)';

  @override
  String get voiceIn => 'Their voice (incoming)';

  @override
  String get voiceDefault => 'Default';

  @override
  String get voiceChange => 'Change';

  @override
  String get voiceNeedsToken => 'To choose voices, enter the gateway token: press Change beside the connection.';

  @override
  String get voicePickerTitleOut => 'My voice';

  @override
  String get voicePickerTitleIn => 'Their voice';

  @override
  String get voiceSearch => 'Search voices';

  @override
  String get voiceFilterAll => 'All';

  @override
  String get voiceFilterGender => 'Gender';

  @override
  String get voiceFilterAge => 'Age';

  @override
  String get voiceFilterAccent => 'Accent';

  @override
  String get voiceFilterLanguage => 'Language';

  @override
  String get voiceFilterUseCase => 'Use';

  @override
  String get voiceGenderMale => 'Male';

  @override
  String get voiceGenderFemale => 'Female';

  @override
  String get voiceGenderNeutral => 'Neutral';

  @override
  String get voiceAgeYoung => 'Young';

  @override
  String get voiceAgeMiddle => 'Middle-aged';

  @override
  String get voiceAgeOld => 'Old';

  @override
  String get voicePlaySample => 'Play sample';

  @override
  String get voiceStopSample => 'Stop';

  @override
  String get voiceNoSample => 'No sample';

  @override
  String get voiceNoMatch => 'No voices match';

  @override
  String get voiceRetry => 'Retry';

  @override
  String get voicesUnauthorized => 'The gateway refused the token.';

  @override
  String get voicesUnsupported => 'This gateway cannot list voices. Update it to choose a voice.';

  @override
  String get voicesUnavailable => 'The voice list is not available right now.';

  @override
  String get voicesNetwork => 'Could not reach the gateway.';

  @override
  String get voicesInvalidKey => 'ElevenLabs refused your key. Check that it is correct.';

  @override
  String get errVoiceNotFound => 'The chosen voice is not available. Choose another or go back to Default.';

  @override
  String get onboardingTitle => 'Real-time interpreter';

  @override
  String get onboardingSubtitle => 'Sign in and try 5 minutes for free';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get onboardingOwnKeys => 'I have my own API keys';

  @override
  String get elevenlabsKey => 'ElevenLabs API key';

  @override
  String get geminiKey => 'Gemini API key';

  @override
  String get saveAndContinue => 'Save and continue';

  @override
  String get showSecret => 'Show';

  @override
  String get hideSecret => 'Hide';

  @override
  String get onboardingOwnGateway => 'Own gateway';

  @override
  String get onboardingSaveFailed => 'Could not save. Try again.';

  @override
  String get onboardingBack => 'Back';

  @override
  String get signInWaitingTitle => 'Continue in your browser';

  @override
  String get signInWaitingHint => 'Check that this code is on the page, then approve it.';

  @override
  String get signInOpenAgain => 'Open again';

  @override
  String get signInOpenManually => 'Open this address in your browser:';

  @override
  String get signInExpired => 'The code expired. Sign in again.';

  @override
  String get signInDenied => 'Sign-in was declined in the browser.';

  @override
  String get signInNetwork => 'Could not reach the sign-in service. Check your internet connection.';

  @override
  String get signInRateLimited => 'Too many attempts. Wait a minute and try again.';

  @override
  String get noticeSignedOut => 'You were signed out. Sign in again.';

  @override
  String get topUp => 'Top up';

  @override
  String get accountPage => 'Account page';

  @override
  String get signOut => 'Sign out';

  @override
  String get changeConnection => 'Change connection';

  @override
  String get connectionOwnKeys => 'Own keys';

  @override
  String get connectionChange => 'Change';

  @override
  String chipMinutes(int minutes) {
    return '≈ $minutes min';
  }

  @override
  String get topUpTitle => 'Top up your balance';

  @override
  String topUpMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get topUpTaxNote => 'Prices are before tax; the checkout page shows the total.';

  @override
  String get topUpNoPackages => 'Could not load the packages.';

  @override
  String get topUpTryAgain => 'Try again';

  @override
  String get topUpRateLimited => 'Too many attempts. Wait a minute and try again.';

  @override
  String get topUpNetwork => 'Could not reach the site. Check your internet connection.';

  @override
  String get topUpUnavailable => 'The checkout page could not be opened right now. Try again later.';

  @override
  String get bannerBalanceEmpty => 'Balance is empty — top up';

  @override
  String get bannerBillingUnavailable => 'Billing could not be reached. Try again.';

  @override
  String get bannerIdleTimeout => 'The session ended after 10 minutes without speech.';

  @override
  String get bannerSessionReplaced => 'The session continued on another device.';

  @override
  String get bannerSessionLimit => 'The service is busy. Try again in a minute.';

  @override
  String get connectionAccount => 'Your account';
}
