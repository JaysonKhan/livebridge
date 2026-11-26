// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Uzbek (`uz`).
class AppLocalizationsUz extends AppLocalizations {
  AppLocalizationsUz([String locale = 'uz']) : super(locale);

  @override
  String get cancel => 'Bekor qilish';

  @override
  String get confirm => 'Tasdiqlash';

  @override
  String get refresh => 'Yangilash';

  @override
  String get copied => 'Nusxalandi';

  @override
  String get delete => 'O\'chirish';

  @override
  String get notSelected => 'Tanlanmagan';

  @override
  String get dismissError => 'Xatoni yopish';

  @override
  String get dismissNotice => 'Xabarni yopish';

  @override
  String get languagePickerTooltip => 'Interfeys tili';

  @override
  String get mockBanner => 'SINOV REJIMI — sinov ovozlari va namuna matn, haqiqiy tarjima emas';

  @override
  String get bypassBanner => 'BYPASS — haqiqiy mikrofoningiz qo\'ng\'iroqqa tarjimasiz uzatilmoqda';

  @override
  String get errorSessionEnded => '(sessiya tugadi)';

  @override
  String get errProviderUnavailable => 'Tarjima yoki ovoz xizmati hozir mavjud emas.';

  @override
  String get errTranslationFailed => 'Gapni tarjima qilib bo\'lmadi.';

  @override
  String get errTranslationRejected => 'Tarjima yaroqsiz chiqdi, shuning uchun ovoz chiqarilmadi.';

  @override
  String get errTtsFailed => 'Gapni ovozga aylantirib bo\'lmadi.';

  @override
  String get errCaptureBacklog => 'Ovoz qayta ishlashdan tezroq to\'planib qolmoqda.';

  @override
  String get errCaptureOverflow => 'Qayta ishlash ulgurmagani uchun ovozning bir qismi tashlab yuborildi.';

  @override
  String get errSynthesisCongested => 'Ovoz xizmati band; nutq kechikishi mumkin.';

  @override
  String get errPlaybackOverflow => 'Ijroni kutayotgan ovoz juda ko\'p; bir qismi o\'tkazib yuborildi.';

  @override
  String get errSourceGone => 'Uchrashuv ilovasi ovoz chiqarishni to\'xtatdi yoki yopildi.';

  @override
  String get errDeviceRemoved => 'Audio qurilma uzildi.';

  @override
  String get errGatewayUnreachable => 'Gateway\'ga ulanib bo\'lmadi. Gateway manzilini va internetni tekshiring.';

  @override
  String get errUnauthorized => 'Gateway kirish tokenini qabul qilmadi. Sozlamalardagi tokenni tekshiring.';

  @override
  String get errSessionLimit => 'Gateway sessiyalar chegarasiga yetdi. Keyinroq urinib ko\'ring.';

  @override
  String get errSessionExpired => 'Sessiya muddati tugadi. Yangisini boshlang.';

  @override
  String get errNoVirtualMic => 'Virtual mikrofon (BlackHole 2ch) topilmadi.';

  @override
  String get errNoVirtualMicWindows => 'Virtual mikrofon (VB-CABLE) topilmadi.';

  @override
  String get errNoHeadphones => 'Tanlangan naushnik topilmadi.';

  @override
  String get errNoMicrophone => 'Tanlangan mikrofon topilmadi.';

  @override
  String get errUnsafeRoute => 'Xavfli audio yo\'nalish rad etildi: mikrofon yoki naushnik virtual qurilma.';

  @override
  String get blockChooseMic => 'Mikrofonni tanlang.';

  @override
  String blockMicIsVirtual(String device) {
    return 'Xavfli yo\'nalish: mikrofon virtual mikrofon bilan bir xil qurilma ($device). Haqiqiy mikrofoningizni tanlang.';
  }

  @override
  String blockMicIsCable(String device) {
    return 'Xavfli yo\'nalish: mikrofon virtual kabel ($device), tarjima qo\'ng\'iroqqa qaytib keladi. Haqiqiy mikrofoningizni tanlang.';
  }

  @override
  String get blockChooseHeadphones => 'Naushnikni tanlang.';

  @override
  String blockHeadphonesVirtual(String device) {
    return 'Xavfli yo\'nalish: naushnik virtual qurilma ($device). Haqiqiy naushnikni tanlang.';
  }

  @override
  String get blockBidirectionalNeedsVirtual =>
      'Ikki tomonlama ovoz uchun virtual mikrofon (BlackHole 2ch) kerak, u o\'rnatilmagan.';

  @override
  String get blockBidirectionalNeedsVirtualWindows =>
      'Ikki tomonlama ovoz uchun virtual mikrofon (VB-CABLE) kerak, u o\'rnatilmagan.';

  @override
  String get blockIncomingNeedsSource => 'Kiruvchi ovoz uchun kamida bitta uchrashuv manbai kerak.';

  @override
  String get blockSameLanguages => 'Ikki xil til tanlang.';

  @override
  String get blockEnterGateway => 'Gateway manzilini kiriting.';

  @override
  String get blockEnterToken => 'Kirish tokenini kiriting.';

  @override
  String noticeMicLost(String name) {
    return '\"$name\" mikrofoni endi mavjud emas. Boshqa mikrofon tanlang.';
  }

  @override
  String noticeHeadphonesLost(String name) {
    return '\"$name\" naushnigi endi mavjud emas. Boshqa naushnik tanlang.';
  }

  @override
  String get startSession => 'Sessiyani boshlash';

  @override
  String get stopSession => 'Sessiyani to\'xtatish';

  @override
  String get setupLocked => 'Sessiya davomida sozlamalar qulflangan.';

  @override
  String get sectionLanguageMode => 'Til va rejim';

  @override
  String get languageUz => 'O\'zbekcha';

  @override
  String get languageEn => 'Inglizcha';

  @override
  String get languageRu => 'Ruscha';

  @override
  String get languageTr => 'Turkcha';

  @override
  String get myLanguage => 'Mening tilim';

  @override
  String get theirLanguage => 'Suhbatdosh tili';

  @override
  String get modeCaptionsTitle => 'Faqat subtitr';

  @override
  String get modeCaptionsDesc => 'Ikki tomonga jonli subtitrlar. Ovoz chiqarilmaydi.';

  @override
  String get modeIncomingTitle => 'Kiruvchi ovoz';

  @override
  String get modeIncomingDesc =>
      'Ikki tomonga subtitrlar, shuningdek suhbatdoshingiz nutqi sizning tilingizga tarjima qilinib naushnikda eshitiladi.';

  @override
  String get modeBidirectionalTitle => 'Ikki tomonlama ovoz';

  @override
  String get modeBidirectionalDesc =>
      'Bundan tashqari tarjimangiz sintez qilingan ovozda virtual mikrofon orqali suhbatga yetkaziladi.';

  @override
  String get sectionDevices => 'Qurilmalar';

  @override
  String get deviceMicrophone => 'Mikrofon';

  @override
  String get deviceHeadphones => 'Naushnik';

  @override
  String virtualMicFound(String name) {
    return 'Virtual mikrofon: $name topildi';
  }

  @override
  String virtualMicFoundWindows(String name) {
    return 'Virtual mikrofon: $name topildi. Uchrashuv ilovasida mikrofon sifatida CABLE Output\'ni tanlang.';
  }

  @override
  String get blackHoleMissingNotice =>
      'BlackHole 2ch o\'rnatilmagan — chiquvchi ovoz mavjud emas, subtitrlar ishlayveradi';

  @override
  String blackHoleInstallWith(String command) {
    return 'O\'rnatish: $command';
  }

  @override
  String get vbCableMissingNotice => 'VB-CABLE o\'rnatilmagan — chiquvchi ovoz mavjud emas, subtitrlar ishlayveradi';

  @override
  String vbCableDownloadFrom(String url) {
    return 'Bepul yuklab olish: $url';
  }

  @override
  String get sectionMeetingSource => 'Uchrashuv manbai';

  @override
  String get noAudioApps =>
      'Hozir hech bir ilova ovoz ishlatmayapti. Uchrashuv ilovasini oching va «Yangilash» tugmasini bosing.';

  @override
  String processPid(int pid) {
    return 'pid $pid';
  }

  @override
  String get processPlaying => 'ovoz chiqarmoqda';

  @override
  String get sectionGateway => 'Chiquvchi gaplar va gateway';

  @override
  String get outgoingTurnMode => 'Gapni yuborish usuli';

  @override
  String get turnPttTitle => 'Bosib turib gapirish';

  @override
  String get turnPttDesc => 'Gapirayotganda tugmani yoki Probel klavishini bosib turing.';

  @override
  String get turnVadTitle => 'Avtomatik: VAD';

  @override
  String get turnVadDesc => 'Pauza qilganingizda nutqingiz yuboriladi.';

  @override
  String get turnPredictionTitle => 'Avtomatik: gap tugashini aniqlash';

  @override
  String get turnPredictionDesc => 'Fikringizni tugatganingizni o\'zi aniqlaydi.';

  @override
  String get gatewayUrl => 'Gateway manzili';

  @override
  String get accessToken => 'Kirish tokeni';

  @override
  String get translationModelOptional => 'Tarjima modeli (ixtiyoriy)';

  @override
  String get testDevicesTitle => 'Qurilmalarni sinash';

  @override
  String get testDevicesUnavailable => 'Sessiya davomida mavjud emas';

  @override
  String get testDevicesSubtitle => 'Daraja o\'lchagichlar, sinov ovozi, ruxsat';

  @override
  String get levelMic => 'Mikrofon darajasi';

  @override
  String get levelSource => 'Uchrashuv manbai darajasi';

  @override
  String get levelSilent => 'jim';

  @override
  String get testHeadphones => 'Naushnikni sinash';

  @override
  String get testVirtualMic => 'Virtual mikrofonni sinash';

  @override
  String get testToneNote =>
      'Har bir sinov bitta sokin ovoz chiqaradi. Sinashdan oldin BlackHole 2ch ishlatayotgan qo\'ng\'iroqdan chiqing.';

  @override
  String get testToneNoteWindows =>
      'Har bir sinov bitta sokin ovoz chiqaradi. Sinashdan oldin CABLE Output ishlatayotgan qo\'ng\'iroqdan chiqing.';

  @override
  String micPermission(String status) {
    return 'Mikrofon ruxsati: $status';
  }

  @override
  String get permissionGranted => 'berilgan';

  @override
  String get permissionDenied => 'rad etilgan';

  @override
  String get permissionUndetermined => 'so\'ralmagan';

  @override
  String get permissionRequest => 'So\'rash';

  @override
  String get micPrivacyWindows =>
      'Windows\'da kompyuter ilovalarining mikrofonga kirishi tizim sozlamasi bilan boshqariladi. Mikrofon darajasi jim tursa, Settings → Privacy & security → Microphone bo\'limida «Let desktop apps access your microphone» sozlamasini yoqing.';

  @override
  String get routingTitle => 'Yo\'naltirish ko\'rsatmalari';

  @override
  String get routingSubtitle => 'Zoom, Meet va Upwork\'ni sozlash';

  @override
  String get routingZoomDesktopTitle => 'Zoom (kompyuter ilovasi)';

  @override
  String get routingZoom1 => 'Zoom\'ni oching → Settings → Audio.';

  @override
  String get routingZoom2 => 'Mikrofon: BlackHole 2ch.';

  @override
  String get routingZoom2Windows => 'Mikrofon: CABLE Output (VB-Audio Virtual Cable).';

  @override
  String get routingZoom3 => 'Karnay: naushnigingiz.';

  @override
  String get routingZoom4 => 'Gapirishdan oldin sessiyani shu yerda boshlang.';

  @override
  String get routingWebTitle => 'Zoom (brauzer) / Google Meet';

  @override
  String get routingWeb1 => 'Qo\'ng\'iroq uchun brauzerning audio sozlamalarini oching.';

  @override
  String get routingWeb2 => 'Mikrofon: BlackHole 2ch. Karnay: naushnigingiz.';

  @override
  String get routingWeb2Windows => 'Mikrofon: CABLE Output (VB-Audio Virtual Cable). Karnay: naushnigingiz.';

  @override
  String get routingWeb3 => 'Alohida brauzer oynasidan foydalaning va ovoz chiqaradigan boshqa yorliqlarni yoping.';

  @override
  String get routingUpworkTitle => 'Upwork';

  @override
  String get routingUpwork1 => 'Qo\'ng\'iroqni Upwork Messages bo\'limidan boshlang.';

  @override
  String get routingUpwork2 => 'Keyin yuqoridagi Zoom yoki brauzer sozlamalaridan foydalaning.';

  @override
  String get routingBackTitle => 'Odatiy holatga qaytish';

  @override
  String get routingBack1 => 'Uchrashuv ilovasida haqiqiy mikrofoningizni qayta tanlang.';

  @override
  String get routingBack2 => 'Sessiyani shu yerda to\'xtating.';

  @override
  String routingInstallVirtual(String command) {
    return 'Virtual mikrofonni o\'rnatish: $command';
  }

  @override
  String routingInstallVirtualWindows(String url) {
    return 'Virtual mikrofon VB-CABLE\'ni o\'rnatish (bepul): $url';
  }

  @override
  String get consentTitle => 'Avval boshqa ishtirokchilarga ayting';

  @override
  String get consentIntro => 'Boshlashdan oldin bu gapni ayting yoki qo\'ng\'iroq chatiga qo\'ying.';

  @override
  String get consentCopyEnglish => 'Inglizchasini nusxalash';

  @override
  String get consentCopyRussian => 'Ruschasini nusxalash';

  @override
  String get consentCheckbox => 'Boshqa ishtirokchilar xabardor qilindi va rozilik berdi';

  @override
  String get laneOut => 'Siz → suhbatdosh';

  @override
  String get laneIn => 'Suhbatdosh → siz';

  @override
  String get noCaptions => 'Hozircha subtitrlar yo\'q';

  @override
  String get turnInProgress => 'Hali davom etmoqda';

  @override
  String get turnSkippedSameLanguage => 'Tarjima qilinmadi — gap allaqachon tarjima tilida';

  @override
  String get turnSkippedEcho => 'E\'tiborga olinmadi — o\'z tarjima ovozimiz qaytib keldi (aks-sado)';

  @override
  String stateChip(String state) {
    return 'Holat: $state';
  }

  @override
  String get stateIdle => 'Kutmoqda';

  @override
  String get stateConnecting => 'Ulanmoqda';

  @override
  String get stateReady => 'Tayyor';

  @override
  String get stateActive => 'Faol';

  @override
  String get stateDegraded => 'Cheklangan holatda';

  @override
  String get stateStopping => 'To\'xtatilmoqda';

  @override
  String get outReady => 'Chiquvchi: tayyor';

  @override
  String get outNotReady => 'Chiquvchi: tayyor emas';

  @override
  String get inReady => 'Kiruvchi: tayyor';

  @override
  String get inNotReady => 'Kiruvchi: tayyor emas';

  @override
  String get capturing => 'Ovoz olinmoqda';

  @override
  String get latencyNone => 'Kechikish: —';

  @override
  String latencyValue(int ms) {
    return 'Kechikish: $ms ms';
  }

  @override
  String get latencyNoMeasurements => 'Hozircha o\'lchovlar yo\'q';

  @override
  String get latencyLastTurnOut => 'Oxirgi gap (siz → suhbatdosh)';

  @override
  String get latencyLastTurnIn => 'Oxirgi gap (suhbatdosh → siz)';

  @override
  String latencyStt(int ms) {
    return 'Nutqni aniqlash: $ms ms';
  }

  @override
  String latencyTranslateFirst(int ms) {
    return 'Tarjimaning birinchi matni: $ms ms';
  }

  @override
  String latencyTranslateTotal(int ms) {
    return 'Tarjima to\'liq: $ms ms';
  }

  @override
  String latencyTtsFirst(int ms) {
    return 'Ovozning birinchi chiqishi: $ms ms';
  }

  @override
  String latencyTtsTotal(int ms) {
    return 'Ovoz to\'liq: $ms ms';
  }

  @override
  String latencyAudioLength(int ms) {
    return 'Audio uzunligi: $ms ms';
  }

  @override
  String latencyModel(String model) {
    return 'Tarjima modeli: $model';
  }

  @override
  String get panicStop => 'Favqulodda to\'xtatish (Esc)';

  @override
  String get muteOutgoing => 'Chiquvchi nutqimni o\'chirish';

  @override
  String get muteIncoming => 'Kiruvchi ovozni o\'chirish';

  @override
  String get bypassLabel => 'Asl mikrofonni uzatish';

  @override
  String switchOn(String label) {
    return '$label: yoqilgan';
  }

  @override
  String switchOff(String label) {
    return '$label: o\'chirilgan';
  }

  @override
  String get bypassDialogTitle => 'Haqiqiy mikrofoningiz qo\'ng\'iroqqa uzatilsinmi?';

  @override
  String get bypassDialogBody =>
      'Bu rejimda ovozingiz tarjimasiz qo\'ng\'iroqqa boradi. Faqat to\'g\'ridan-to\'g\'ri gapirmoqchi bo\'lganda yoqing.';

  @override
  String get bypassTurnOn => 'Bypassni yoqish';

  @override
  String get pttHintHeld => 'Gapiryapsiz… yuborish uchun qo\'yib yuboring';

  @override
  String get pttHintReady => 'Gapirish uchun bosib turing (yoki Probelni)';

  @override
  String get pttHintWaiting => 'Bosib turib gapirish — sessiya tayyor bo\'lganda ishlaydi';

  @override
  String get pttHintOff => 'Bosib turib gapirish o\'chiq — gaplar avtomatik yuboriladi';

  @override
  String get pttSemantics => 'Bosib turib gapirish. Gapirayotganda bosib turing.';

  @override
  String get showOriginal => 'Asl matnni ko\'rsatish';

  @override
  String get showTranslated => 'Tarjimani ko\'rsatish';

  @override
  String get captionsSmaller => 'Subtitrlarni kichraytirish';

  @override
  String get captionsLarger => 'Subtitrlarni kattalashtirish';

  @override
  String captionSize(int size) {
    return 'O\'lcham $size';
  }

  @override
  String get rateGood => 'Yaxshi tarjima';

  @override
  String get rateBad => 'Yomon tarjima';

  @override
  String get exportConversation => 'Suhbatni eksport qilish';

  @override
  String get exportConsentTitle => 'Suhbat eksport qilinsinmi?';

  @override
  String get exportConsentBody =>
      'Faylda sizning so\'zlaringiz bilan birga suhbatdoshingiz so\'zlari ham bo\'ladi. U bunga rozilik berganini tasdiqlang.';

  @override
  String get exportConsentConfirm => 'U rozi bo\'ldi — eksport qilish';

  @override
  String exportSaved(String path) {
    return 'Saqlandi: $path';
  }

  @override
  String get exportDocTitle => 'LiveBridge AI suhbati';

  @override
  String exportDocExported(String time) {
    return 'Eksport vaqti: $time';
  }

  @override
  String exportDocLanguages(String pair) {
    return 'Tillar: $pair';
  }

  @override
  String exportDocMode(String mode) {
    return 'Rejim: $mode';
  }

  @override
  String get exportDocNoTurns => 'Hali tugallangan gaplar yo\'q.';

  @override
  String get exportDocOriginal => 'Asl matn';

  @override
  String get exportDocTranslation => 'Tarjima';

  @override
  String get exportDocRating => 'Sizning bahoingiz';

  @override
  String get exportDocRatingGood => 'yaxshi';

  @override
  String get exportDocRatingBad => 'yomon';

  @override
  String get analyticsTitle => 'Analitika';

  @override
  String get analyticsSubtitle => 'Sessiyalaringiz haqida raqamlar — hech qachon matn emas';

  @override
  String get analyticsPrivacy =>
      'Jurnalda faqat raqamlar bor: vaqtlar, sonlar, xato kodlari va baholaringiz. Unda suhbat matni yo\'q va u shu Mac\'dan chiqmaydi.';

  @override
  String get analyticsPrivacyWindows =>
      'Jurnalda faqat raqamlar bor: vaqtlar, sonlar, xato kodlari va baholaringiz. Unda suhbat matni yo\'q va u shu kompyuterdan chiqmaydi.';

  @override
  String get analyticsEnabled => 'Analitikani shu Mac\'da yozib borish';

  @override
  String get analyticsEnabledWindows => 'Analitikani shu kompyuterda yozib borish';

  @override
  String analyticsSessions(int count) {
    return 'Sessiyalar: $count';
  }

  @override
  String analyticsTurns(int count) {
    return 'Tarjima qilingan gaplar: $count';
  }

  @override
  String analyticsFirst(String time) {
    return 'Birinchi yozuv: $time';
  }

  @override
  String analyticsLast(String time) {
    return 'Oxirgi yozuv: $time';
  }

  @override
  String get analyticsTimingTitle => 'Vaqtlar (ms)';

  @override
  String get analyticsColCount => 'Soni';

  @override
  String get analyticsColP50 => 'p50';

  @override
  String get analyticsColP95 => 'p95';

  @override
  String get analyticsColMax => 'Maks.';

  @override
  String get analyticsRowE2e => 'Boshidan oxirigacha';

  @override
  String get analyticsRowStt => 'Nutqni aniqlash';

  @override
  String get analyticsRowTranslateFirst => 'Tarjima, birinchi matn';

  @override
  String get analyticsRowTranslateTotal => 'Tarjima, to\'liq';

  @override
  String get analyticsRowTtsFirst => 'Ovoz, birinchi chiqish';

  @override
  String get analyticsErrorsTitle => 'Xatolar (kod bo\'yicha)';

  @override
  String get analyticsNoErrors => 'Xatolar qayd etilmagan';

  @override
  String analyticsReconnects(int count) {
    return 'Qayta ulanishlar: $count';
  }

  @override
  String analyticsEmptyTurns(int count) {
    return 'Bo\'sh gaplar: $count';
  }

  @override
  String analyticsRatedGood(int count) {
    return '\"Yaxshi\" deb baholangan: $count';
  }

  @override
  String analyticsRatedBad(int count) {
    return '\"Yomon\" deb baholangan: $count';
  }

  @override
  String analyticsFileSize(String sizeText) {
    return 'Jurnal hajmi: $sizeText';
  }

  @override
  String analyticsPath(String path) {
    return 'Fayl: $path';
  }

  @override
  String get analyticsExportLog => 'Jurnalni eksport qilish';

  @override
  String get analyticsClearLog => 'Jurnalni tozalash';

  @override
  String get analyticsClearTitle => 'Analitika jurnali tozalansinmi?';

  @override
  String get analyticsClearBody => 'Bu Mac\'dagi barcha yozilgan raqamlar o\'chiriladi. Buni qaytarib bo\'lmaydi.';

  @override
  String get analyticsClearBodyWindows =>
      'Bu kompyuterdagi barcha yozilgan raqamlar o\'chiriladi. Buni qaytarib bo\'lmaydi.';

  @override
  String get copy => 'Nusxalash';

  @override
  String get telemetryTitle => 'Dasturchiga anonim statistikani yuborish';

  @override
  String get telemetryNeedsAnalytics => 'Avval yuqoridagi analitika yozuvini yoqing — yuborish shu jurnalni yuklaydi.';

  @override
  String get telemetryDialogTitle => 'Anonim statistika yuborilsinmi?';

  @override
  String get telemetryDialogSent =>
      'Yuboriladi: vaqtlar, sonlar, xato kodlari, matn uzunligi (belgilarda), yoqdi/yoqmadi baholaringiz, ilova versiyasi, macOS versiyasi, interfeys tili va tasodifiy o\'rnatish ID\'si.';

  @override
  String get telemetryDialogSentWindows =>
      'Yuboriladi: vaqtlar, sonlar, xato kodlari, matn uzunligi (belgilarda), yoqdi/yoqmadi baholaringiz, ilova versiyasi, Windows versiyasi, interfeys tili va tasodifiy o\'rnatish ID\'si.';

  @override
  String get telemetryDialogNever =>
      'Hech qachon yuborilmaydi: aytilgan gaplar, tarjimalar, audio, qurilma nomlari, gateway manzili va kalitlar.';

  @override
  String get telemetryDialogWhere => 'Qayerga boradi: dasturchining saytiga — jaysonkhan.com.';

  @override
  String get telemetryDialogOff => 'Buni istalgan vaqtda o\'chirib qo\'yishingiz mumkin.';

  @override
  String telemetryPending(int count) {
    return 'Yuklanishni kutayotgan yozuvlar: $count';
  }

  @override
  String telemetryLastUpload(String time) {
    return 'Oxirgi yuklash: $time';
  }

  @override
  String get telemetryNever => 'hech qachon';

  @override
  String telemetryLastError(String error) {
    return 'Oxirgi yuklash xatosi: $error';
  }

  @override
  String get telemetryInstallId => 'O\'rnatish ID\'si';

  @override
  String get telemetryStatsPage => 'Ochiq statistika sahifasi';

  @override
  String get feedbackButton => 'Fikr yuborish';

  @override
  String get feedbackNote => 'Xabaringiz dasturchiga boradi. E-pochtangiz faqat sizga javob berish uchun ishlatiladi.';

  @override
  String get feedbackMessageLabel => 'Xabaringiz';

  @override
  String get feedbackEmailLabel => 'E-pochta (ixtiyoriy)';

  @override
  String get feedbackEmailInvalid => 'To\'g\'ri e-pochta manzilini kiriting yoki bo\'sh qoldiring.';

  @override
  String get feedbackRatingLabel => 'Baho (ixtiyoriy)';

  @override
  String feedbackStar(int count) {
    return '5 yulduzdan $count';
  }

  @override
  String get feedbackSend => 'Yuborish';

  @override
  String get feedbackSent => 'Rahmat — fikringiz yuborildi.';

  @override
  String get feedbackRateLimited => 'So\'nggi vaqtda juda ko\'p xabar yuborildi. Keyinroq qayta urinib ko\'ring.';

  @override
  String get feedbackFailed => 'Fikringizni yuborib bo\'lmadi. Ulanishni tekshirib, qayta urinib ko\'ring.';

  @override
  String get sectionVoices => 'Ovozlar';

  @override
  String get voiceOut => 'Mening ovozim (chiquvchi)';

  @override
  String get voiceIn => 'Suhbatdosh ovozi (kiruvchi)';

  @override
  String get voiceDefault => 'Standart';

  @override
  String get voiceChange => 'O\'zgartirish';

  @override
  String get voiceNeedsToken => 'Ovoz tanlash uchun kirish tokenini kiriting.';

  @override
  String get voicePickerTitleOut => 'Mening ovozim';

  @override
  String get voicePickerTitleIn => 'Suhbatdosh ovozi';

  @override
  String get voiceSearch => 'Ovozlarni qidirish';

  @override
  String get voiceFilterAll => 'Hammasi';

  @override
  String get voiceFilterGender => 'Jins';

  @override
  String get voiceFilterAge => 'Yosh';

  @override
  String get voiceFilterAccent => 'Aksent';

  @override
  String get voiceFilterLanguage => 'Til';

  @override
  String get voiceFilterUseCase => 'Qo\'llanish';

  @override
  String get voiceGenderMale => 'Erkak';

  @override
  String get voiceGenderFemale => 'Ayol';

  @override
  String get voiceGenderNeutral => 'Neytral';

  @override
  String get voiceAgeYoung => 'Yosh';

  @override
  String get voiceAgeMiddle => 'O\'rta yosh';

  @override
  String get voiceAgeOld => 'Keksa';

  @override
  String get voicePlaySample => 'Namunani eshitish';

  @override
  String get voiceStopSample => 'To\'xtatish';

  @override
  String get voiceNoSample => 'Namuna yo\'q';

  @override
  String get voiceNoMatch => 'Mos ovoz topilmadi';

  @override
  String get voiceRetry => 'Qayta urinish';

  @override
  String get voicesUnauthorized => 'Gateway tokenni qabul qilmadi.';

  @override
  String get voicesUnsupported => 'Bu gateway ovozlar ro\'yxatini bera olmaydi. Ovoz tanlash uchun uni yangilang.';

  @override
  String get voicesUnavailable => 'Ovozlar ro\'yxati hozir mavjud emas.';

  @override
  String get voicesNetwork => 'Gateway\'ga ulanib bo\'lmadi.';

  @override
  String get errVoiceNotFound => 'Tanlangan ovoz mavjud emas. Boshqasini tanlang yoki Standart ovozga qayting.';
}
