// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get cancel => 'İptal';

  @override
  String get confirm => 'Onayla';

  @override
  String get refresh => 'Yenile';

  @override
  String get copied => 'Kopyalandı';

  @override
  String get delete => 'Sil';

  @override
  String get notSelected => 'Seçilmedi';

  @override
  String get dismissError => 'Hatayı kapat';

  @override
  String get dismissNotice => 'Bildirimi kapat';

  @override
  String get languagePickerTooltip => 'Arayüz dili';

  @override
  String get mockBanner => 'TEST MODU — deneme sesleri ve örnek metin, gerçek çeviri değil';

  @override
  String get bypassBanner => 'BYPASS — gerçek mikrofonunuz çeviri yapılmadan görüşmeye gidiyor';

  @override
  String get errorSessionEnded => '(oturum sona erdi)';

  @override
  String get errProviderUnavailable => 'Çeviri veya ses hizmeti şu anda kullanılamıyor.';

  @override
  String get errTranslationFailed => 'Bir cümle çevrilemedi.';

  @override
  String get errTranslationRejected => 'Çeviri kullanılamaz çıktı, bu yüzden seslendirilmedi.';

  @override
  String get errTtsFailed => 'Bir cümle seslendirilemedi.';

  @override
  String get errCaptureBacklog => 'Ses, işlenebileceğinden daha hızlı birikiyor.';

  @override
  String get errCaptureOverflow => 'İşleme yetişemediği için sesin bir kısmı atıldı.';

  @override
  String get errSynthesisCongested => 'Ses hizmeti yoğun; konuşma gecikebilir.';

  @override
  String get errPlaybackOverflow => 'Çalmayı bekleyen çok fazla ses var; bir kısmı atlandı.';

  @override
  String get errSourceGone => 'Toplantı uygulaması ses çalmayı bıraktı veya kapatıldı.';

  @override
  String get errDeviceRemoved => 'Bir ses cihazının bağlantısı kesildi.';

  @override
  String get errGatewayUnreachable =>
      'Gateway\'e ulaşılamıyor. Gateway adresini ve internet bağlantınızı kontrol edin.';

  @override
  String get errUnauthorized => 'Gateway erişim jetonunu reddetti. Kurulumdaki jetonu kontrol edin.';

  @override
  String get errSessionLimit => 'Gateway oturum sınırına ulaştı. Daha sonra tekrar deneyin.';

  @override
  String get errSessionExpired => 'Oturumun süresi doldu. Yeni bir oturum başlatın.';

  @override
  String get errNoVirtualMic => 'Sanal mikrofon (BlackHole 2ch) bulunamadı.';

  @override
  String get errNoVirtualMicWindows => 'Sanal mikrofon (VB-CABLE) bulunamadı.';

  @override
  String get errNoHeadphones => 'Seçilen kulaklık bulunamadı.';

  @override
  String get errNoMicrophone => 'Seçilen mikrofon bulunamadı.';

  @override
  String get errUnsafeRoute => 'Güvenli olmayan ses yönlendirmesi reddedildi: mikrofon veya kulaklık sanal bir cihaz.';

  @override
  String get blockChooseMic => 'Bir mikrofon seçin.';

  @override
  String blockMicIsVirtual(String device) {
    return 'Güvenli olmayan yönlendirme: mikrofon, sanal mikrofonla aynı cihaz ($device). Fiziksel mikrofonunuzu seçin.';
  }

  @override
  String blockMicIsCable(String device) {
    return 'Güvenli olmayan yönlendirme: mikrofon sanal bir kablo ($device), çeviri görüşmeye geri döner. Fiziksel mikrofonunuzu seçin.';
  }

  @override
  String get blockChooseHeadphones => 'Kulaklık seçin.';

  @override
  String blockHeadphonesVirtual(String device) {
    return 'Güvenli olmayan yönlendirme: kulaklık sanal bir cihaz ($device). Fiziksel kulaklığınızı seçin.';
  }

  @override
  String get blockBidirectionalNeedsVirtual =>
      'Çift yönlü ses için sanal mikrofon (BlackHole 2ch) gerekir, ancak kurulu değil.';

  @override
  String get blockBidirectionalNeedsVirtualWindows =>
      'Çift yönlü ses için sanal mikrofon (VB-CABLE) gerekir, ancak kurulu değil.';

  @override
  String get blockIncomingNeedsSource => 'Gelen ses için en az bir toplantı kaynağı gerekir.';

  @override
  String get blockSameLanguages => 'İki farklı dil seçin.';

  @override
  String get blockEnterGateway => 'Gateway adresini girin.';

  @override
  String get blockEnterToken => 'Erişim jetonunu girin.';

  @override
  String get blockEnterKeys => 'ElevenLabs ve Gemini anahtarlarınızı girin.';

  @override
  String get blockBalanceEmpty => 'Bakiyeniz boş. Başlamak için bakiye yükleyin.';

  @override
  String noticeMicLost(String name) {
    return '\"$name\" mikrofonu artık kullanılamıyor. Başka bir mikrofon seçin.';
  }

  @override
  String noticeHeadphonesLost(String name) {
    return '\"$name\" kulaklığı artık kullanılamıyor. Başka bir kulaklık seçin.';
  }

  @override
  String get startSession => 'Oturumu başlat';

  @override
  String get stopSession => 'Oturumu durdur';

  @override
  String get setupLocked => 'Oturum sürerken ayarlar kilitli.';

  @override
  String get sectionLanguageMode => 'Dil ve mod';

  @override
  String get languageUz => 'Özbekçe';

  @override
  String get languageEn => 'İngilizce';

  @override
  String get languageRu => 'Rusça';

  @override
  String get languageTr => 'Türkçe';

  @override
  String get myLanguage => 'Benim dilim';

  @override
  String get theirLanguage => 'Karşı tarafın dili';

  @override
  String get modeCaptionsTitle => 'Yalnızca altyazı';

  @override
  String get modeCaptionsDesc => 'Her iki yönde canlı altyazı. Hiçbir şey seslendirilmez.';

  @override
  String get modeIncomingTitle => 'Gelen ses';

  @override
  String get modeIncomingDesc =>
      'Her iki yönde altyazı; ayrıca karşı tarafın konuşması sizin dilinize çevrilip kulaklığınızda duyulur.';

  @override
  String get modeBidirectionalTitle => 'Çift yönlü ses';

  @override
  String get modeBidirectionalDesc =>
      'Ayrıca çevirinizi sentezlenmiş bir sesle, sanal mikrofon üzerinden görüşmeye iletir.';

  @override
  String get sectionDevices => 'Cihazlar';

  @override
  String get deviceMicrophone => 'Mikrofon';

  @override
  String get deviceHeadphones => 'Kulaklık';

  @override
  String virtualMicFound(String name) {
    return 'Sanal mikrofon: $name bulundu';
  }

  @override
  String virtualMicFoundWindows(String name) {
    return 'Sanal mikrofon: $name bulundu. Toplantı uygulamasında mikrofon olarak CABLE Output\'u seçin.';
  }

  @override
  String get blackHoleMissingNotice =>
      'BlackHole 2ch kurulu değil — giden ses kullanılamıyor, altyazılar çalışmaya devam ediyor';

  @override
  String blackHoleInstallWith(String command) {
    return 'Kurmak için: $command';
  }

  @override
  String get vbCableMissingNotice =>
      'VB-CABLE kurulu değil — giden ses kullanılamıyor, altyazılar çalışmaya devam ediyor';

  @override
  String vbCableDownloadFrom(String url) {
    return 'Ücretsiz indirmek için: $url';
  }

  @override
  String get sectionMeetingSource => 'Toplantı kaynağı';

  @override
  String get noAudioApps => 'Şu anda sesi kullanan uygulama yok. Toplantı uygulamasını açın ve Yenile düğmesine basın.';

  @override
  String processPid(int pid) {
    return 'pid $pid';
  }

  @override
  String get processPlaying => 'çalıyor';

  @override
  String get sectionGateway => 'Giden konuşmalar ve gateway';

  @override
  String get outgoingTurnMode => 'Konuşmanın gönderilme şekli';

  @override
  String get turnPttTitle => 'Bas-konuş';

  @override
  String get turnPttDesc => 'Konuşurken düğmeyi veya Boşluk tuşunu basılı tutun.';

  @override
  String get turnVadTitle => 'Otomatik: VAD';

  @override
  String get turnVadDesc => 'Duraklattığınızda konuşmanızı gönderir.';

  @override
  String get turnPredictionTitle => 'Otomatik: konuşma sonu tahmini';

  @override
  String get turnPredictionDesc => 'Düşüncenizi ne zaman bitirdiğinizi tahmin eder.';

  @override
  String get gatewayUrl => 'Gateway adresi';

  @override
  String get accessToken => 'Erişim jetonu';

  @override
  String get translationModelOptional => 'Çeviri modeli (isteğe bağlı)';

  @override
  String get testDevicesTitle => 'Cihazlarınızı test edin';

  @override
  String get testDevicesUnavailable => 'Oturum sürerken kullanılamaz';

  @override
  String get testDevicesSubtitle => 'Seviye göstergeleri, deneme sesleri, izin';

  @override
  String get levelMic => 'Mikrofon seviyesi';

  @override
  String get levelSource => 'Toplantı kaynağı seviyesi';

  @override
  String get levelSilent => 'sessiz';

  @override
  String get testHeadphones => 'Kulaklığı test et';

  @override
  String get testVirtualMic => 'Sanal mikrofonu test et';

  @override
  String get testToneNote =>
      'Her test tek bir sessiz ton çalar. Test etmeden önce BlackHole 2ch kullanan görüşmelerden çıkın.';

  @override
  String get testToneNoteWindows =>
      'Her test tek bir sessiz ton çalar. Test etmeden önce CABLE Output kullanan görüşmelerden çıkın.';

  @override
  String micPermission(String status) {
    return 'Mikrofon izni: $status';
  }

  @override
  String get permissionGranted => 'verildi';

  @override
  String get permissionDenied => 'reddedildi';

  @override
  String get permissionUndetermined => 'henüz sorulmadı';

  @override
  String get permissionRequest => 'İste';

  @override
  String get micPrivacyWindows =>
      'Windows\'ta masaüstü uygulamalarının mikrofon erişimi bir sistem ayarıdır. Mikrofon seviyesi sessiz kalırsa Ayarlar → Gizlilik ve güvenlik → Mikrofon bölümünde \"Masaüstü uygulamalarının mikrofonunuza erişmesine izin verin\" seçeneğini açın.';

  @override
  String get routingTitle => 'Ses yönlendirme talimatları';

  @override
  String get routingSubtitle => 'Zoom, Meet ve Upwork nasıl ayarlanır';

  @override
  String get routingZoomDesktopTitle => 'Zoom (masaüstü uygulaması)';

  @override
  String get routingZoom1 => 'Zoom\'u açın → Settings → Audio.';

  @override
  String get routingZoom2 => 'Mikrofon: BlackHole 2ch.';

  @override
  String get routingZoom2Windows => 'Mikrofon: CABLE Output (VB-Audio Virtual Cable).';

  @override
  String get routingZoom3 => 'Hoparlör: kulaklığınız.';

  @override
  String get routingZoom4 => 'Konuşmadan önce oturumu burada başlatın.';

  @override
  String get routingWebTitle => 'Zoom (tarayıcı) / Google Meet';

  @override
  String get routingWeb1 => 'Görüşme için tarayıcının ses ayarlarını açın.';

  @override
  String get routingWeb2 => 'Mikrofon: BlackHole 2ch. Hoparlör: kulaklığınız.';

  @override
  String get routingWeb2Windows => 'Mikrofon: CABLE Output (VB-Audio Virtual Cable). Hoparlör: kulaklığınız.';

  @override
  String get routingWeb3 => 'Ayrı bir tarayıcı penceresi kullanın ve ses çalan diğer sekmeleri kapatın.';

  @override
  String get routingUpworkTitle => 'Upwork';

  @override
  String get routingUpwork1 => 'Görüşmeyi Upwork Messages bölümünden başlatın.';

  @override
  String get routingUpwork2 => 'Ardından yukarıdaki Zoom veya tarayıcı ayarlarını kullanın.';

  @override
  String get routingBackTitle => 'Normale nasıl dönülür';

  @override
  String get routingBack1 => 'Toplantı uygulamasında fiziksel mikrofonunuzu yeniden seçin.';

  @override
  String get routingBack2 => 'Oturumu burada durdurun.';

  @override
  String routingInstallVirtual(String command) {
    return 'Sanal mikrofonu kurmak için: $command';
  }

  @override
  String routingInstallVirtualWindows(String url) {
    return 'Sanal mikrofon VB-CABLE\'ı kurmak için (ücretsiz): $url';
  }

  @override
  String get consentTitle => 'Önce diğer katılımcılara söyleyin';

  @override
  String get consentIntro => 'Başlamadan önce bu cümleyi söyleyin veya görüşme sohbetine yapıştırın.';

  @override
  String get consentCopyEnglish => 'İngilizcesini kopyala';

  @override
  String get consentCopyRussian => 'Rusçasını kopyala';

  @override
  String get consentCheckbox => 'Diğer katılımcılar bilgilendirildi ve kabul etti';

  @override
  String get laneOut => 'Siz → karşı taraf';

  @override
  String get laneIn => 'Karşı taraf → siz';

  @override
  String get noCaptions => 'Henüz altyazı yok';

  @override
  String get turnInProgress => 'Hâlâ sürüyor';

  @override
  String get turnSkippedSameLanguage => 'Çevrilmedi — konuşma zaten hedef dilde';

  @override
  String get turnSkippedEcho => 'Yok sayıldı — kendi çeviri sesimiz geri geldi (yankı)';

  @override
  String stateChip(String state) {
    return 'Durum: $state';
  }

  @override
  String get stateIdle => 'Boşta';

  @override
  String get stateConnecting => 'Bağlanıyor';

  @override
  String get stateReady => 'Hazır';

  @override
  String get stateActive => 'Etkin';

  @override
  String get stateDegraded => 'Kısıtlı çalışıyor';

  @override
  String get stateStopping => 'Durduruluyor';

  @override
  String get outReady => 'GİDEN: hazır';

  @override
  String get outNotReady => 'GİDEN: hazır değil';

  @override
  String get inReady => 'GELEN: hazır';

  @override
  String get inNotReady => 'GELEN: hazır değil';

  @override
  String get capturing => 'Ses alınıyor';

  @override
  String get latencyNone => 'Gecikme: —';

  @override
  String latencyValue(int ms) {
    return 'Gecikme: $ms ms';
  }

  @override
  String get latencyNoMeasurements => 'Henüz ölçüm yok';

  @override
  String get latencyLastTurnOut => 'Son konuşma (siz → karşı taraf)';

  @override
  String get latencyLastTurnIn => 'Son konuşma (karşı taraf → siz)';

  @override
  String latencyStt(int ms) {
    return 'Konuşma tanıma: $ms ms';
  }

  @override
  String latencyTranslateFirst(int ms) {
    return 'Çevirinin ilk metni: $ms ms';
  }

  @override
  String latencyTranslateTotal(int ms) {
    return 'Çeviri toplam: $ms ms';
  }

  @override
  String latencyTtsFirst(int ms) {
    return 'Sesin ilk çıkışı: $ms ms';
  }

  @override
  String latencyTtsTotal(int ms) {
    return 'Ses toplam: $ms ms';
  }

  @override
  String latencyAudioLength(int ms) {
    return 'Ses uzunluğu: $ms ms';
  }

  @override
  String latencyModel(String model) {
    return 'Çeviri modeli: $model';
  }

  @override
  String get panicStop => 'Acil durdurma (Esc)';

  @override
  String get muteOutgoing => 'Giden konuşmamı sessize al';

  @override
  String get muteIncoming => 'Gelen sesi sessize al';

  @override
  String get bypassLabel => 'Mikrofonu doğrudan aktarma';

  @override
  String switchOn(String label) {
    return '$label: açık';
  }

  @override
  String switchOff(String label) {
    return '$label: kapalı';
  }

  @override
  String get bypassDialogTitle => 'Gerçek mikrofonunuz görüşmeye gönderilsin mi?';

  @override
  String get bypassDialogBody =>
      'Bu modda sesiniz çeviri yapılmadan görüşmeye gider. Yalnızca doğrudan konuşmak istediğinizde kullanın.';

  @override
  String get bypassTurnOn => 'Bypass\'ı aç';

  @override
  String get pttHintHeld => 'Konuşuyorsunuz… göndermek için bırakın';

  @override
  String get pttHintReady => 'Konuşmak için basılı tutun (veya Boşluk)';

  @override
  String get pttHintWaiting => 'Bas-konuş — oturum hazır olduğunda kullanılabilir';

  @override
  String get pttHintOff => 'Bas-konuş kapalı — konuşmalar otomatik gönderiliyor';

  @override
  String get pttSemantics => 'Bas-konuş. Konuşurken basılı tutun.';

  @override
  String get showOriginal => 'Orijinali göster';

  @override
  String get showTranslated => 'Çeviriyi göster';

  @override
  String get captionsSmaller => 'Altyazıyı küçült';

  @override
  String get captionsLarger => 'Altyazıyı büyüt';

  @override
  String captionSize(int size) {
    return 'Boyut $size';
  }

  @override
  String get rateGood => 'İyi çeviri';

  @override
  String get rateBad => 'Kötü çeviri';

  @override
  String get exportConversation => 'Görüşmeyi dışa aktar';

  @override
  String get exportConsentTitle => 'Görüşme dışa aktarılsın mı?';

  @override
  String get exportConsentBody =>
      'Dosya yalnızca sizin değil, karşı tarafın sözlerini de içerecek. Bunu kabul ettiğini onaylayın.';

  @override
  String get exportConsentConfirm => 'Kabul etti — dışa aktar';

  @override
  String exportSaved(String path) {
    return 'Kaydedildi: $path';
  }

  @override
  String get exportDocTitle => 'LiveBridge AI görüşmesi';

  @override
  String exportDocExported(String time) {
    return 'Dışa aktarma: $time';
  }

  @override
  String exportDocLanguages(String pair) {
    return 'Diller: $pair';
  }

  @override
  String exportDocMode(String mode) {
    return 'Mod: $mode';
  }

  @override
  String get exportDocNoTurns => 'Henüz tamamlanmış konuşma yok.';

  @override
  String get exportDocOriginal => 'Orijinal';

  @override
  String get exportDocTranslation => 'Çeviri';

  @override
  String get exportDocRating => 'Puanınız';

  @override
  String get exportDocRatingGood => 'iyi';

  @override
  String get exportDocRatingBad => 'kötü';

  @override
  String get analyticsTitle => 'Analitik';

  @override
  String get analyticsSubtitle => 'Oturumlarınız hakkında sayılar — asla metin değil';

  @override
  String get analyticsPrivacy =>
      'Günlükte yalnızca sayılar var: süreler, sayaçlar, hata kodları ve puanlarınız. Konuşma metni içermez ve bu Mac\'ten dışarı çıkmaz.';

  @override
  String get analyticsPrivacyWindows =>
      'Günlükte yalnızca sayılar var: süreler, sayaçlar, hata kodları ve puanlarınız. Konuşma metni içermez ve bu bilgisayardan dışarı çıkmaz.';

  @override
  String get analyticsEnabled => 'Analitiği bu Mac\'te kaydet';

  @override
  String get analyticsEnabledWindows => 'Analitiği bu bilgisayarda kaydet';

  @override
  String analyticsSessions(int count) {
    return 'Oturum: $count';
  }

  @override
  String analyticsTurns(int count) {
    return 'Çevrilen konuşma: $count';
  }

  @override
  String analyticsFirst(String time) {
    return 'İlk kayıt: $time';
  }

  @override
  String analyticsLast(String time) {
    return 'Son kayıt: $time';
  }

  @override
  String get analyticsTimingTitle => 'Süreler (ms)';

  @override
  String get analyticsColCount => 'Adet';

  @override
  String get analyticsColP50 => 'p50';

  @override
  String get analyticsColP95 => 'p95';

  @override
  String get analyticsColMax => 'Maks.';

  @override
  String get analyticsRowE2e => 'Uçtan uca';

  @override
  String get analyticsRowStt => 'Konuşma tanıma';

  @override
  String get analyticsRowTranslateFirst => 'Çeviri, ilk metin';

  @override
  String get analyticsRowTranslateTotal => 'Çeviri, tamamı';

  @override
  String get analyticsRowTtsFirst => 'Ses, ilk çıkış';

  @override
  String get analyticsErrorsTitle => 'Koda göre hatalar';

  @override
  String get analyticsNoErrors => 'Kayıtlı hata yok';

  @override
  String analyticsReconnects(int count) {
    return 'Yeniden bağlanma: $count';
  }

  @override
  String analyticsEmptyTurns(int count) {
    return 'Boş konuşma: $count';
  }

  @override
  String analyticsRatedGood(int count) {
    return 'İyi diye puanlanan: $count';
  }

  @override
  String analyticsRatedBad(int count) {
    return 'Kötü diye puanlanan: $count';
  }

  @override
  String analyticsFileSize(String sizeText) {
    return 'Günlük boyutu: $sizeText';
  }

  @override
  String analyticsPath(String path) {
    return 'Dosya: $path';
  }

  @override
  String get analyticsExportLog => 'Günlüğü dışa aktar';

  @override
  String get analyticsClearLog => 'Günlüğü temizle';

  @override
  String get analyticsClearTitle => 'Analitik günlüğü temizlensin mi?';

  @override
  String get analyticsClearBody => 'Bu Mac\'teki tüm kayıtlı sayılar silinir. Bu işlem geri alınamaz.';

  @override
  String get analyticsClearBodyWindows => 'Bu bilgisayardaki tüm kayıtlı sayılar silinir. Bu işlem geri alınamaz.';

  @override
  String get copy => 'Kopyala';

  @override
  String get telemetryTitle => 'Geliştiriciyle anonim istatistik paylaş';

  @override
  String get telemetryNeedsAnalytics => 'Önce yukarıdaki analitik kaydını açın — paylaşım bu günlüğü yükler.';

  @override
  String get telemetryDialogTitle => 'Anonim istatistikler paylaşılsın mı?';

  @override
  String get telemetryDialogSent =>
      'Gönderilenler: süreler, sayılar, hata kodları, metin uzunlukları (karakter olarak), beğendim/beğenmedim puanlarınız, uygulama sürümü, macOS sürümü, arayüz dili ve rastgele bir kurulum kimliği.';

  @override
  String get telemetryDialogSentWindows =>
      'Gönderilenler: süreler, sayılar, hata kodları, metin uzunlukları (karakter olarak), beğendim/beğenmedim puanlarınız, uygulama sürümü, Windows sürümü, arayüz dili ve rastgele bir kurulum kimliği.';

  @override
  String get telemetryDialogNever =>
      'Asla gönderilmeyenler: söylenenler, çeviriler, ses, cihaz adları, gateway adresi ve anahtarlar.';

  @override
  String get telemetryDialogWhere => 'Gittiği yer: geliştiricinin sitesi, jaysonkhan.com.';

  @override
  String get telemetryDialogOff => 'Bunu istediğiniz zaman kapatabilirsiniz.';

  @override
  String telemetryPending(int count) {
    return 'Yüklenmeyi bekleyen kayıt: $count';
  }

  @override
  String telemetryLastUpload(String time) {
    return 'Son yükleme: $time';
  }

  @override
  String get telemetryNever => 'hiç';

  @override
  String telemetryLastError(String error) {
    return 'Son yükleme hatası: $error';
  }

  @override
  String get telemetryInstallId => 'Kurulum kimliği';

  @override
  String get telemetryStatsPage => 'Herkese açık istatistik sayfası';

  @override
  String get feedbackButton => 'Geri bildirim gönder';

  @override
  String get feedbackNote => 'Mesajınız geliştiriciye gider. E-postanız yalnızca size yanıt vermek için kullanılır.';

  @override
  String get feedbackMessageLabel => 'Mesajınız';

  @override
  String get feedbackEmailLabel => 'E-posta (isteğe bağlı)';

  @override
  String get feedbackEmailInvalid => 'Geçerli bir e-posta adresi girin veya boş bırakın.';

  @override
  String get feedbackRatingLabel => 'Puan (isteğe bağlı)';

  @override
  String feedbackStar(int count) {
    return '5 yıldızdan $count';
  }

  @override
  String get feedbackSend => 'Gönder';

  @override
  String get feedbackSent => 'Teşekkürler — geri bildiriminiz gönderildi.';

  @override
  String get feedbackRateLimited => 'Kısa süre içinde çok fazla mesaj gönderildi. Lütfen daha sonra tekrar deneyin.';

  @override
  String get feedbackFailed => 'Geri bildiriminiz gönderilemedi. Bağlantınızı kontrol edip tekrar deneyin.';

  @override
  String get sectionVoices => 'Sesler';

  @override
  String get voiceOut => 'Benim sesim (giden)';

  @override
  String get voiceIn => 'Karşı tarafın sesi (gelen)';

  @override
  String get voiceDefault => 'Varsayılan';

  @override
  String get voiceChange => 'Değiştir';

  @override
  String get voiceNeedsToken => 'Ses seçmek için erişim jetonunu girin.';

  @override
  String get voicePickerTitleOut => 'Benim sesim';

  @override
  String get voicePickerTitleIn => 'Karşı tarafın sesi';

  @override
  String get voiceSearch => 'Ses ara';

  @override
  String get voiceFilterAll => 'Tümü';

  @override
  String get voiceFilterGender => 'Cinsiyet';

  @override
  String get voiceFilterAge => 'Yaş';

  @override
  String get voiceFilterAccent => 'Aksan';

  @override
  String get voiceFilterLanguage => 'Dil';

  @override
  String get voiceFilterUseCase => 'Kullanım';

  @override
  String get voiceGenderMale => 'Erkek';

  @override
  String get voiceGenderFemale => 'Kadın';

  @override
  String get voiceGenderNeutral => 'Nötr';

  @override
  String get voiceAgeYoung => 'Genç';

  @override
  String get voiceAgeMiddle => 'Orta yaşlı';

  @override
  String get voiceAgeOld => 'Yaşlı';

  @override
  String get voicePlaySample => 'Örneği dinle';

  @override
  String get voiceStopSample => 'Durdur';

  @override
  String get voiceNoSample => 'Örnek yok';

  @override
  String get voiceNoMatch => 'Eşleşen ses yok';

  @override
  String get voiceRetry => 'Tekrar dene';

  @override
  String get voicesUnauthorized => 'Gateway jetonu reddetti.';

  @override
  String get voicesUnsupported => 'Bu gateway sesleri listeleyemiyor. Ses seçmek için onu güncelleyin.';

  @override
  String get voicesUnavailable => 'Ses listesi şu anda kullanılamıyor.';

  @override
  String get voicesNetwork => 'Gateway\'e ulaşılamadı.';

  @override
  String get errVoiceNotFound => 'Seçilen ses kullanılamıyor. Başka bir ses seçin veya Varsayılan\'a dönün.';

  @override
  String get onboardingTitle => 'Gerçek zamanlı tercüman';

  @override
  String get onboardingSubtitle => 'Giriş yapın ve 5 dakikayı ücretsiz deneyin';

  @override
  String get signInWithGoogle => 'Google ile oturum aç';

  @override
  String get onboardingOwnKeys => 'Kendi API anahtarlarım var';

  @override
  String get onboardingOwnKeysHint => 'Kendi ElevenLabs ve Gemini anahtarlarınızı kullanın. Burada ücret alınmaz.';

  @override
  String get elevenlabsKey => 'ElevenLabs API anahtarı';

  @override
  String get geminiKey => 'Gemini API anahtarı';

  @override
  String get saveAndContinue => 'Kaydet ve devam et';

  @override
  String get showSecret => 'Göster';

  @override
  String get hideSecret => 'Gizle';

  @override
  String get onboardingOwnGateway => 'Kendi gateway\'im';

  @override
  String get onboardingSaveFailed => 'Kaydedilemedi. Tekrar deneyin.';

  @override
  String get signInWaitingTitle => 'Tarayıcınızda devam edin';

  @override
  String get signInWaitingHint => 'Sayfadaki kodun bu kod olduğunu doğrulayın ve onaylayın.';

  @override
  String get signInOpenAgain => 'Yeniden aç';

  @override
  String get signInExpired => 'Kodun süresi doldu. Yeniden giriş yapın.';

  @override
  String get signInDenied => 'Giriş tarayıcıda reddedildi.';

  @override
  String get signInNetwork => 'Giriş hizmetine ulaşılamadı. İnternet bağlantınızı kontrol edin.';

  @override
  String get signInRateLimited => 'Çok fazla deneme yapıldı. Bir dakika bekleyip tekrar deneyin.';

  @override
  String get noticeSignedOut => 'Oturumunuz kapandı. Yeniden giriş yapın.';
}
