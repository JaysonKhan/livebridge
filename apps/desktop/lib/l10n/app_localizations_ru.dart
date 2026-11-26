// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get cancel => 'Отмена';

  @override
  String get confirm => 'Подтвердить';

  @override
  String get refresh => 'Обновить';

  @override
  String get copied => 'Скопировано';

  @override
  String get delete => 'Удалить';

  @override
  String get notSelected => 'Не выбрано';

  @override
  String get dismissError => 'Закрыть ошибку';

  @override
  String get dismissNotice => 'Закрыть уведомление';

  @override
  String get languagePickerTooltip => 'Язык интерфейса';

  @override
  String get mockBanner => 'ТЕСТОВЫЙ РЕЖИМ — тестовые сигналы и текст-заглушка, это не настоящий перевод';

  @override
  String get bypassBanner => 'BYPASS — ваш настоящий микрофон идёт в звонок без перевода';

  @override
  String get errorSessionEnded => '(сессия завершена)';

  @override
  String get errProviderUnavailable => 'Сервис перевода или озвучки сейчас недоступен.';

  @override
  String get errTranslationFailed => 'Не удалось перевести фразу.';

  @override
  String get errTranslationRejected => 'Перевод получился непригодным, поэтому ничего не озвучено.';

  @override
  String get errTtsFailed => 'Не удалось озвучить фразу.';

  @override
  String get errCaptureBacklog => 'Звук накапливается быстрее, чем обрабатывается.';

  @override
  String get errCaptureOverflow => 'Часть звука потеряна: обработка не успевала.';

  @override
  String get errSynthesisCongested => 'Сервис озвучки перегружен, речь может запаздывать.';

  @override
  String get errPlaybackOverflow => 'Слишком много звука ждёт воспроизведения, часть пропущена.';

  @override
  String get errSourceGone => 'Приложение встречи перестало воспроизводить звук или закрыто.';

  @override
  String get errDeviceRemoved => 'Аудиоустройство отключено.';

  @override
  String get errGatewayUnreachable => 'Не удаётся связаться со шлюзом. Проверьте адрес шлюза и интернет.';

  @override
  String get errUnauthorized => 'Шлюз отклонил токен доступа. Проверьте токен в настройках.';

  @override
  String get errSessionLimit => 'Достигнут лимит сессий на шлюзе. Попробуйте позже.';

  @override
  String get errSessionExpired => 'Сессия истекла. Начните новую.';

  @override
  String get errNoVirtualMic => 'Виртуальный микрофон (BlackHole 2ch) не найден.';

  @override
  String get errNoVirtualMicWindows => 'Виртуальный микрофон (VB-CABLE) не найден.';

  @override
  String get errNoHeadphones => 'Выбранные наушники не найдены.';

  @override
  String get errNoMicrophone => 'Выбранный микрофон не найден.';

  @override
  String get errUnsafeRoute =>
      'Небезопасная маршрутизация звука отклонена: микрофон или наушники — виртуальное устройство.';

  @override
  String get blockChooseMic => 'Выберите микрофон.';

  @override
  String blockMicIsVirtual(String device) {
    return 'Небезопасный маршрут: микрофон совпадает с виртуальным микрофоном ($device). Выберите физический микрофон.';
  }

  @override
  String blockMicIsCable(String device) {
    return 'Небезопасный маршрут: микрофон — виртуальный кабель ($device), перевод вернётся обратно в звонок. Выберите физический микрофон.';
  }

  @override
  String get blockChooseHeadphones => 'Выберите наушники.';

  @override
  String blockHeadphonesVirtual(String device) {
    return 'Небезопасный маршрут: наушники — виртуальное устройство ($device). Выберите физические наушники.';
  }

  @override
  String get blockBidirectionalNeedsVirtual =>
      'Для двусторонней озвучки нужен виртуальный микрофон (BlackHole 2ch), он не установлен.';

  @override
  String get blockBidirectionalNeedsVirtualWindows =>
      'Для двусторонней озвучки нужен виртуальный микрофон (VB-CABLE), он не установлен.';

  @override
  String get blockIncomingNeedsSource => 'Для входящего звука нужен хотя бы один источник встречи.';

  @override
  String get blockSameLanguages => 'Выберите два разных языка.';

  @override
  String get blockEnterGateway => 'Введите адрес шлюза.';

  @override
  String get blockEnterToken => 'Введите токен доступа.';

  @override
  String get blockEnterKeys => 'Введите свои ключи ElevenLabs и Gemini.';

  @override
  String get blockBalanceEmpty => 'Баланс пуст. Пополните его, чтобы начать.';

  @override
  String noticeMicLost(String name) {
    return 'Микрофон «$name» больше недоступен. Выберите другой микрофон.';
  }

  @override
  String noticeHeadphonesLost(String name) {
    return 'Наушники «$name» больше недоступны. Выберите другие наушники.';
  }

  @override
  String get startSession => 'Начать сессию';

  @override
  String get stopSession => 'Остановить сессию';

  @override
  String get setupLocked => 'Во время сессии настройки заблокированы.';

  @override
  String get sectionLanguageMode => 'Язык и режим';

  @override
  String get languageUz => 'Узбекский';

  @override
  String get languageEn => 'Английский';

  @override
  String get languageRu => 'Русский';

  @override
  String get languageTr => 'Турецкий';

  @override
  String get myLanguage => 'Мой язык';

  @override
  String get theirLanguage => 'Язык собеседника';

  @override
  String get modeCaptionsTitle => 'Только субтитры';

  @override
  String get modeCaptionsDesc => 'Живые субтитры в обе стороны. Ничего не озвучивается.';

  @override
  String get modeIncomingTitle => 'Входящий звук';

  @override
  String get modeIncomingDesc =>
      'Субтитры в обе стороны, а речь собеседника звучит в ваших наушниках в переводе на ваш язык.';

  @override
  String get modeBidirectionalTitle => 'Двусторонняя озвучка';

  @override
  String get modeBidirectionalDesc =>
      'Вдобавок ваш перевод звучит в звонке синтезированным голосом через виртуальный микрофон.';

  @override
  String get sectionDevices => 'Устройства';

  @override
  String get deviceMicrophone => 'Микрофон';

  @override
  String get deviceHeadphones => 'Наушники';

  @override
  String virtualMicFound(String name) {
    return 'Виртуальный микрофон: $name найден';
  }

  @override
  String virtualMicFoundWindows(String name) {
    return 'Виртуальный микрофон: $name найден. В приложении встречи выберите микрофоном CABLE Output.';
  }

  @override
  String get blackHoleMissingNotice => 'BlackHole 2ch не установлен — исходящая озвучка недоступна, субтитры работают';

  @override
  String blackHoleInstallWith(String command) {
    return 'Установить: $command';
  }

  @override
  String get vbCableMissingNotice => 'VB-CABLE не установлен — исходящая озвучка недоступна, субтитры работают';

  @override
  String vbCableDownloadFrom(String url) {
    return 'Скачать бесплатно: $url';
  }

  @override
  String get sectionMeetingSource => 'Источник встречи';

  @override
  String get noAudioApps =>
      'Сейчас ни одно приложение не использует звук. Откройте приложение встречи и нажмите «Обновить».';

  @override
  String processPid(int pid) {
    return 'pid $pid';
  }

  @override
  String get processPlaying => 'играет';

  @override
  String get sectionGateway => 'Исходящие фразы и шлюз';

  @override
  String get outgoingTurnMode => 'Как отправлять вашу речь';

  @override
  String get turnPttTitle => 'Нажми и говори';

  @override
  String get turnPttDesc => 'Удерживайте кнопку или пробел, пока говорите.';

  @override
  String get turnVadTitle => 'Авто: VAD';

  @override
  String get turnVadDesc => 'Отправляет речь, когда вы делаете паузу.';

  @override
  String get turnPredictionTitle => 'Авто: определение конца фразы';

  @override
  String get turnPredictionDesc => 'Определяет, когда вы закончили мысль.';

  @override
  String get gatewayUrl => 'Адрес шлюза';

  @override
  String get accessToken => 'Токен доступа';

  @override
  String get translationModelOptional => 'Модель перевода (необязательно)';

  @override
  String get testDevicesTitle => 'Проверка устройств';

  @override
  String get testDevicesUnavailable => 'Недоступно во время сессии';

  @override
  String get testDevicesSubtitle => 'Индикаторы уровня, тестовые сигналы, разрешение';

  @override
  String get levelMic => 'Уровень микрофона';

  @override
  String get levelSource => 'Уровень источника встречи';

  @override
  String get levelSilent => 'тишина';

  @override
  String get testHeadphones => 'Проверить наушники';

  @override
  String get testVirtualMic => 'Проверить виртуальный микрофон';

  @override
  String get testToneNote =>
      'Каждая проверка воспроизводит один тихий сигнал. Перед проверкой выйдите из звонков, где используется BlackHole 2ch.';

  @override
  String get testToneNoteWindows =>
      'Каждая проверка воспроизводит один тихий сигнал. Перед проверкой выйдите из звонков, где используется CABLE Output.';

  @override
  String micPermission(String status) {
    return 'Доступ к микрофону: $status';
  }

  @override
  String get permissionGranted => 'предоставлен';

  @override
  String get permissionDenied => 'запрещён';

  @override
  String get permissionUndetermined => 'ещё не запрашивался';

  @override
  String get permissionRequest => 'Запросить';

  @override
  String get micPrivacyWindows =>
      'В Windows доступ классических приложений к микрофону задаётся системной настройкой. Если уровень микрофона остаётся на нуле, включите «Разрешить классическим приложениям доступ к микрофону» в разделе Параметры → Конфиденциальность и защита → Микрофон.';

  @override
  String get routingTitle => 'Инструкции по маршрутизации звука';

  @override
  String get routingSubtitle => 'Как настроить Zoom, Meet и Upwork';

  @override
  String get routingZoomDesktopTitle => 'Zoom (приложение)';

  @override
  String get routingZoom1 => 'Откройте Zoom → Settings → Audio.';

  @override
  String get routingZoom2 => 'Микрофон: BlackHole 2ch.';

  @override
  String get routingZoom2Windows => 'Микрофон: CABLE Output (VB-Audio Virtual Cable).';

  @override
  String get routingZoom3 => 'Динамик: ваши наушники.';

  @override
  String get routingZoom4 => 'Перед началом разговора запустите сессию здесь.';

  @override
  String get routingWebTitle => 'Zoom в браузере / Google Meet';

  @override
  String get routingWeb1 => 'Откройте настройки звука в браузере для этого звонка.';

  @override
  String get routingWeb2 => 'Микрофон: BlackHole 2ch. Динамик: ваши наушники.';

  @override
  String get routingWeb2Windows => 'Микрофон: CABLE Output (VB-Audio Virtual Cable). Динамик: ваши наушники.';

  @override
  String get routingWeb3 => 'Используйте отдельное окно браузера и закройте другие вкладки со звуком.';

  @override
  String get routingUpworkTitle => 'Upwork';

  @override
  String get routingUpwork1 => 'Начните звонок из раздела Upwork Messages.';

  @override
  String get routingUpwork2 => 'Затем используйте те же настройки Zoom или браузера, что описаны выше.';

  @override
  String get routingBackTitle => 'Как вернуться к обычному режиму';

  @override
  String get routingBack1 => 'В приложении встречи снова выберите физический микрофон.';

  @override
  String get routingBack2 => 'Остановите сессию здесь.';

  @override
  String routingInstallVirtual(String command) {
    return 'Установка виртуального микрофона: $command';
  }

  @override
  String routingInstallVirtualWindows(String url) {
    return 'Установка виртуального микрофона VB-CABLE (бесплатно): $url';
  }

  @override
  String get consentTitle => 'Сначала предупредите других участников';

  @override
  String get consentIntro => 'Перед началом произнесите это предложение или вставьте его в чат звонка.';

  @override
  String get consentCopyEnglish => 'Скопировать по-английски';

  @override
  String get consentCopyRussian => 'Скопировать по-русски';

  @override
  String get consentCheckbox => 'Другие участники предупреждены и согласны';

  @override
  String get laneOut => 'Вы → собеседник';

  @override
  String get laneIn => 'Собеседник → вы';

  @override
  String get noCaptions => 'Субтитров пока нет';

  @override
  String get turnInProgress => 'Ещё в процессе';

  @override
  String get turnSkippedSameLanguage => 'Не переведено — речь уже на языке перевода';

  @override
  String get turnSkippedEcho => 'Пропущено — вернулся наш собственный перевод (эхо)';

  @override
  String stateChip(String state) {
    return 'Состояние: $state';
  }

  @override
  String get stateIdle => 'Ожидание';

  @override
  String get stateConnecting => 'Подключение';

  @override
  String get stateReady => 'Готово';

  @override
  String get stateActive => 'Активно';

  @override
  String get stateDegraded => 'Работает с ограничениями';

  @override
  String get stateStopping => 'Остановка';

  @override
  String get outReady => 'ИСХ.: готово';

  @override
  String get outNotReady => 'ИСХ.: не готово';

  @override
  String get inReady => 'ВХ.: готово';

  @override
  String get inNotReady => 'ВХ.: не готово';

  @override
  String get capturing => 'Идёт захват звука';

  @override
  String get latencyNone => 'Задержка: —';

  @override
  String latencyValue(int ms) {
    return 'Задержка: $ms мс';
  }

  @override
  String get latencyNoMeasurements => 'Измерений пока нет';

  @override
  String get latencyLastTurnOut => 'Последняя фраза (вы → собеседник)';

  @override
  String get latencyLastTurnIn => 'Последняя фраза (собеседник → вы)';

  @override
  String latencyStt(int ms) {
    return 'Распознавание речи: $ms мс';
  }

  @override
  String latencyTranslateFirst(int ms) {
    return 'Первый текст перевода: $ms мс';
  }

  @override
  String latencyTranslateTotal(int ms) {
    return 'Перевод целиком: $ms мс';
  }

  @override
  String latencyTtsFirst(int ms) {
    return 'Первый звук озвучки: $ms мс';
  }

  @override
  String latencyTtsTotal(int ms) {
    return 'Озвучка целиком: $ms мс';
  }

  @override
  String latencyAudioLength(int ms) {
    return 'Длина аудио: $ms мс';
  }

  @override
  String latencyModel(String model) {
    return 'Модель перевода: $model';
  }

  @override
  String get panicStop => 'Аварийная остановка (Esc)';

  @override
  String get muteOutgoing => 'Отключить мою исходящую речь';

  @override
  String get muteIncoming => 'Отключить входящий звук';

  @override
  String get bypassLabel => 'Прямая передача микрофона';

  @override
  String switchOn(String label) {
    return '$label: включено';
  }

  @override
  String switchOff(String label) {
    return '$label: выключено';
  }

  @override
  String get bypassDialogTitle => 'Передавать в звонок ваш настоящий микрофон?';

  @override
  String get bypassDialogBody =>
      'В этом режиме ваш голос идёт в звонок без перевода. Включайте его, только когда хотите говорить напрямую.';

  @override
  String get bypassTurnOn => 'Включить передачу';

  @override
  String get pttHintHeld => 'Говорите… отпустите, чтобы отправить';

  @override
  String get pttHintReady => 'Удерживайте, чтобы говорить (или пробел)';

  @override
  String get pttHintWaiting => 'Нажми и говори — доступно, когда сессия готова';

  @override
  String get pttHintOff => 'Режим «нажми и говори» выключен — фразы отправляются автоматически';

  @override
  String get pttSemantics => 'Нажми и говори. Удерживайте, пока говорите.';

  @override
  String get showOriginal => 'Показывать оригинал';

  @override
  String get showTranslated => 'Показывать перевод';

  @override
  String get captionsSmaller => 'Уменьшить субтитры';

  @override
  String get captionsLarger => 'Увеличить субтитры';

  @override
  String captionSize(int size) {
    return 'Размер $size';
  }

  @override
  String get rateGood => 'Хороший перевод';

  @override
  String get rateBad => 'Плохой перевод';

  @override
  String get exportConversation => 'Экспортировать беседу';

  @override
  String get exportConsentTitle => 'Экспортировать беседу?';

  @override
  String get exportConsentBody =>
      'В файле будут не только ваши слова, но и слова собеседника. Подтвердите, что он на это согласился.';

  @override
  String get exportConsentConfirm => 'Он согласен — экспортировать';

  @override
  String exportSaved(String path) {
    return 'Сохранено: $path';
  }

  @override
  String get exportDocTitle => 'Беседа в LiveBridge AI';

  @override
  String exportDocExported(String time) {
    return 'Экспортировано: $time';
  }

  @override
  String exportDocLanguages(String pair) {
    return 'Языки: $pair';
  }

  @override
  String exportDocMode(String mode) {
    return 'Режим: $mode';
  }

  @override
  String get exportDocNoTurns => 'Завершённых фраз пока нет.';

  @override
  String get exportDocOriginal => 'Оригинал';

  @override
  String get exportDocTranslation => 'Перевод';

  @override
  String get exportDocRating => 'Ваша оценка';

  @override
  String get exportDocRatingGood => 'хорошо';

  @override
  String get exportDocRatingBad => 'плохо';

  @override
  String get analyticsTitle => 'Аналитика';

  @override
  String get analyticsSubtitle => 'Цифры о ваших сессиях — без текста';

  @override
  String get analyticsPrivacy =>
      'В журнале только цифры: время, счётчики, коды ошибок и ваши оценки. Текста бесед в нём нет, и он остаётся на этом Mac.';

  @override
  String get analyticsPrivacyWindows =>
      'В журнале только цифры: время, счётчики, коды ошибок и ваши оценки. Текста бесед в нём нет, и он остаётся на этом компьютере.';

  @override
  String get analyticsEnabled => 'Вести аналитику на этом Mac';

  @override
  String get analyticsEnabledWindows => 'Вести аналитику на этом компьютере';

  @override
  String analyticsSessions(int count) {
    return 'Сессий: $count';
  }

  @override
  String analyticsTurns(int count) {
    return 'Переведённых фраз: $count';
  }

  @override
  String analyticsFirst(String time) {
    return 'Первая запись: $time';
  }

  @override
  String analyticsLast(String time) {
    return 'Последняя запись: $time';
  }

  @override
  String get analyticsTimingTitle => 'Время (мс)';

  @override
  String get analyticsColCount => 'Кол-во';

  @override
  String get analyticsColP50 => 'p50';

  @override
  String get analyticsColP95 => 'p95';

  @override
  String get analyticsColMax => 'Макс.';

  @override
  String get analyticsRowE2e => 'Сквозная';

  @override
  String get analyticsRowStt => 'Распознавание речи';

  @override
  String get analyticsRowTranslateFirst => 'Перевод, первый текст';

  @override
  String get analyticsRowTranslateTotal => 'Перевод, целиком';

  @override
  String get analyticsRowTtsFirst => 'Озвучка, первый звук';

  @override
  String get analyticsErrorsTitle => 'Ошибки по кодам';

  @override
  String get analyticsNoErrors => 'Ошибок не зафиксировано';

  @override
  String analyticsReconnects(int count) {
    return 'Переподключений: $count';
  }

  @override
  String analyticsEmptyTurns(int count) {
    return 'Пустых фраз: $count';
  }

  @override
  String analyticsRatedGood(int count) {
    return 'Оценено как хорошие: $count';
  }

  @override
  String analyticsRatedBad(int count) {
    return 'Оценено как плохие: $count';
  }

  @override
  String analyticsFileSize(String sizeText) {
    return 'Размер журнала: $sizeText';
  }

  @override
  String analyticsPath(String path) {
    return 'Файл: $path';
  }

  @override
  String get analyticsExportLog => 'Экспортировать журнал';

  @override
  String get analyticsClearLog => 'Очистить журнал';

  @override
  String get analyticsClearTitle => 'Очистить журнал аналитики?';

  @override
  String get analyticsClearBody => 'Все записанные цифры на этом Mac будут удалены. Это нельзя отменить.';

  @override
  String get analyticsClearBodyWindows => 'Все записанные цифры на этом компьютере будут удалены. Это нельзя отменить.';

  @override
  String get copy => 'Копировать';

  @override
  String get telemetryTitle => 'Отправлять разработчику анонимную статистику';

  @override
  String get telemetryNeedsAnalytics => 'Сначала включите запись аналитики выше — отправляется именно этот журнал.';

  @override
  String get telemetryDialogTitle => 'Отправлять анонимную статистику?';

  @override
  String get telemetryDialogSent =>
      'Отправляется: тайминги, счётчики, коды ошибок, длина текста в символах, ваши оценки «палец вверх/вниз», версия приложения, версия macOS, язык интерфейса и случайный ID установки.';

  @override
  String get telemetryDialogSentWindows =>
      'Отправляется: тайминги, счётчики, коды ошибок, длина текста в символах, ваши оценки «палец вверх/вниз», версия приложения, версия Windows, язык интерфейса и случайный ID установки.';

  @override
  String get telemetryDialogNever =>
      'Никогда не отправляется: сказанное, переводы, аудио, названия устройств, адрес шлюза и ключи.';

  @override
  String get telemetryDialogWhere => 'Куда уходит: на сайт разработчика — jaysonkhan.com.';

  @override
  String get telemetryDialogOff => 'Это можно отключить в любой момент.';

  @override
  String telemetryPending(int count) {
    return 'Записей ждёт отправки: $count';
  }

  @override
  String telemetryLastUpload(String time) {
    return 'Последняя отправка: $time';
  }

  @override
  String get telemetryNever => 'никогда';

  @override
  String telemetryLastError(String error) {
    return 'Ошибка последней отправки: $error';
  }

  @override
  String get telemetryInstallId => 'ID установки';

  @override
  String get telemetryStatsPage => 'Публичная страница статистики';

  @override
  String get feedbackButton => 'Отправить отзыв';

  @override
  String get feedbackNote => 'Ваше сообщение уходит разработчику. E-mail используется только для ответа вам.';

  @override
  String get feedbackMessageLabel => 'Ваше сообщение';

  @override
  String get feedbackEmailLabel => 'E-mail (необязательно)';

  @override
  String get feedbackEmailInvalid => 'Введите корректный адрес e-mail или оставьте поле пустым.';

  @override
  String get feedbackRatingLabel => 'Оценка (необязательно)';

  @override
  String feedbackStar(int count) {
    return '$count из 5 звёзд';
  }

  @override
  String get feedbackSend => 'Отправить';

  @override
  String get feedbackSent => 'Спасибо — отзыв отправлен.';

  @override
  String get feedbackRateLimited => 'Слишком много сообщений за последнее время. Попробуйте позже.';

  @override
  String get feedbackFailed => 'Не удалось отправить отзыв. Проверьте соединение и попробуйте снова.';

  @override
  String get sectionVoices => 'Голоса';

  @override
  String get voiceOut => 'Мой голос (исходящий)';

  @override
  String get voiceIn => 'Голос собеседника (входящий)';

  @override
  String get voiceDefault => 'По умолчанию';

  @override
  String get voiceChange => 'Изменить';

  @override
  String get voiceNeedsToken => 'Чтобы выбрать голос, введите токен доступа.';

  @override
  String get voicePickerTitleOut => 'Мой голос';

  @override
  String get voicePickerTitleIn => 'Голос собеседника';

  @override
  String get voiceSearch => 'Поиск голосов';

  @override
  String get voiceFilterAll => 'Все';

  @override
  String get voiceFilterGender => 'Пол';

  @override
  String get voiceFilterAge => 'Возраст';

  @override
  String get voiceFilterAccent => 'Акцент';

  @override
  String get voiceFilterLanguage => 'Язык';

  @override
  String get voiceFilterUseCase => 'Назначение';

  @override
  String get voiceGenderMale => 'Мужской';

  @override
  String get voiceGenderFemale => 'Женский';

  @override
  String get voiceGenderNeutral => 'Нейтральный';

  @override
  String get voiceAgeYoung => 'Молодой';

  @override
  String get voiceAgeMiddle => 'Средних лет';

  @override
  String get voiceAgeOld => 'Пожилой';

  @override
  String get voicePlaySample => 'Прослушать образец';

  @override
  String get voiceStopSample => 'Остановить';

  @override
  String get voiceNoSample => 'Нет образца';

  @override
  String get voiceNoMatch => 'Подходящих голосов нет';

  @override
  String get voiceRetry => 'Повторить';

  @override
  String get voicesUnauthorized => 'Шлюз отклонил токен.';

  @override
  String get voicesUnsupported => 'Этот шлюз не умеет показывать список голосов. Обновите его, чтобы выбрать голос.';

  @override
  String get voicesUnavailable => 'Список голосов сейчас недоступен.';

  @override
  String get voicesNetwork => 'Не удалось связаться со шлюзом.';

  @override
  String get errVoiceNotFound => 'Выбранный голос недоступен. Выберите другой или вернитесь к голосу по умолчанию.';
}
