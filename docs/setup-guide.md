# LiveBridge — o'rnatish va ishlatish qo'llanmasi

LiveBridge siz o'z tilingizda gapirganingizni suhbatdosh tiliga o'girib, sintez qilingan ovoz bilan qo'ng'iroqqa
uzatadi, suhbatdoshning nutqini esa sizning tilingizda subtitr va ovoz qilib beradi. Har ikki til 90 tildan
tanlanadi (standart: o'zbekcha ↔ inglizcha). Suhbatdosh hech narsa o'rnatmaydi. Ilova **macOS** va **Windows**'da
ishlaydi.

> **Holat (2026-11-26):** haqiqiy ElevenLabs va Gemini bilan boshdan-oxir ishlaydi, muallif Google Meet
> qo'ng'iroqlarida ishlatadi; Windows ilovasi haqiqiy kompyuterda ishlatib ko'rilgan. Gap tugagach tarjima ovozi
> o'rtacha 1,35–1,41 soniyada eshitiladi (sun'iy nutq bilan o'lchangan); gateway provayderlarga yaqin serverda
> turganda ~0,8 soniya. Zoom va Upwork qo'ng'iroqlarida hali sinalmagan.
> Batafsil: `IMPLEMENTATION_STATUS.md`, o'lchovlar: `docs/benchmark.md`.

## 0. Windows'da

Windows 10 yoki 11 (64-bit) kerak. Uchala rejim ham ishlaydi.

1. **O'rnatish:** [Releases sahifasidan](https://github.com/JaysonKhan/livebridge/releases/latest)
   `JK-LiveBridge-<versiya>-windows-setup.exe` ni yuklab, ishga tushiring (administrator huquqi kerak emas).
   O'rnatuvchi imzolanmagan, shuning uchun Windows «noma'lum nashriyotchi» deydi: **More info → Run anyway**. Ilova
   Start menyuda **JK - LiveBridge** nomi bilan chiqadi.
2. **Virtual mikrofon (faqat ikki tomonlama rejim uchun):** [VB-CABLE](https://vb-audio.com/Cable/) ni o'rnating va
   kompyuterni qayta yoqing. U ikki qurilma qo'shadi: ilova tarjimani **CABLE Input** ga chiqaradi, Zoom/Meet'da
   mikrofon sifatida **CABLE Output** ni tanlaysiz.
3. **Ulanish:** Windows ilovasi ham macOS'dagi kabi uch usuldan biri bilan ulanadi (1.3-bo'lim). O'z gateway'ingizni
   tanlasangiz, serverdagi gateway'ning `https://` manzilini va tokenni kiriting. Mac'dagi gateway'dan foydalansangiz, uni tarmoq uchun oching (`HOST=0.0.0.0 npm run gateway`),
   ilovaga `http://<Mac manzili>:8201` va o'sha tokenni kiriting.
4. **Mikrofon ruxsati:** Settings → Privacy & security → Microphone → «Let desktop apps access your microphone» yoqilgan
   bo'lsin.
5. **Suhbatdosh ovozini ushlash** (kiruvchi va ikki tomonlama rejimlar) **Windows 11** yoki Windows 10'ning yangi
   build'ini talab qiladi; eski Windows'da ilova buni xato bilan aytadi.

Qolgan qadamlar macOS bilan bir xil (2-bo'limdan); uchrashuv ilovasida mikrofon sifatida **BlackHole 2ch** o'rniga
**CABLE Output** ni tanlaysiz.

## 1. Bir martalik tayyorgarlik

### 1.1 BlackHole 2ch (virtual mikrofon)

Tarjima qilingan ovoz qo'ng'iroqqa «virtual mikrofon» orqali boradi. Rasmiy BlackHole 2ch drayverini o'rnating
(administrator paroli so'raladi):

```bash
brew install blackhole-2ch
```

O'rnatgach Mac'ni qayta ishga tushiring. **Audio MIDI Setup** ilovasida «BlackHole 2ch» ko'rinishi va 48 000 Hz
bo'lishi kerak. Tekshirish:

```bash
apps/desktop/native/LiveBridgeAudio/.build/debug/lbaudio devices
```

BlackHole'siz ham ilova ishlaydi, lekin faqat **subtitr** rejimida (Captions only).

### 1.2 Gateway (server qismi)

> Bu bo'lim faqat **o'z gateway'ingiz** bilan ishlasangiz kerak. Hisob (Google) yoki o'z kalitlaringiz bilan
> ulanishda gateway'ni o'zingiz ishga tushirmaysiz — 1.3-bo'limga o'ting.

Gateway'ga ulanganda kalitlar faqat gateway'da turadi, ilovaga kiritilmaydi.

```bash
cp .env.example .env          # so'ng .env ni to'ldiring
openssl rand -base64 36       # GATEWAY_ACCESS_TOKEN uchun
npm install
npm run probe                 # haqiqiy API'lar ishlashini tekshiradi (qisqa sintetik jumlalar bilan)
npm run gateway               # http://127.0.0.1:8201
```

`.env` da kerak: `ELEVENLABS_API_KEY` va `GEMINI_API_KEY`. Ovoz ID'lari (`ELEVENLABS_OWNER_VOICE_ID` — chiquvchi
inglizcha/ruscha, `ELEVENLABS_INCOMING_VOICE_ID` — kiruvchi o'zbekcha) standart holda ikkalasi ham
`ehTFHBkERkWR22A3sR8M`: bu loyiha muallifining o'z ovozi («JaysonKhan - Natural Uzbek Voice»), uni muallifning o'zi
ElevenLabs Voice Library'da ochiq qilgan. Kutubxona ovozlari uchun pullik ElevenLabs tarifi kerak; hisobingiz bu ID'ni
rad etsa, ovozni Voice Library'dan «My Voices»ga qo'shing va u yerda ko'rsatilgan ID'ni yozing. O'z klon ovozingizni
ishlatmoqchi bo'lsangiz, shu ikki qatorga uning ID'sini qo'ying yoki ovozni ilovaning o'zida tanlang (2-bo'lim,
«Ovozlar»). Suhbatdoshning ovozi hech qachon klonlanmaydi.
Kalitsiz sinab ko'rish: `.env` da `PROVIDER_MODE=fake` (soxta matn va signal ovozi — tarjima emas).

Serverga joylash: `docs/deployment.md`.

### 1.3 Ilova

```bash
cd apps/desktop
flutter build macos --release
open "build/macos/Build/Products/Release/JK - LiveBridge.app"
```

Ilova Dock, Finder va Spotlight'da **JK - LiveBridge** nomi bilan ko'rinadi (Spotlight'ga «JK» deb yozing).

**Ulanish usuli.** Birinchi ishga tushirishda ilova tarjima xizmatiga qanday ulanishni so'raydi:

- **Google bilan kirish (hisob).** Tugmani bosing: ilova qisqa kod ko'rsatadi va brauzerda saytni ochadi. Sahifadagi
  kod ilovadagi kod bilan bir xilligini tekshirib, tasdiqlang (brauzerda rad etsangiz, ilova bu haqda
  xabar beradi; kod bir necha daqiqadan keyin eskiradi — qaytadan kiring). Yangi hisobda **5 daqiqalik sinov** bor.
  Davomi uchun asosiy ekrandagi **Hisobni to'ldirish** ni bosing: ilova saytdagi paketlarni ko'rsatadi, to'lov sahifasi
  brauzerda ochiladi (narxlar soliqsiz ko'rsatiladi). Qoldiq «≈ N daq» ko'rinishida chiqadi; **Hisob sahifasi** saytdagi
  hisobingizni ochadi, **Chiqish** hisobdan chiqaradi. Qoldiq nolga tushsa, Start bosilmaydi. Apple bilan kirish hozircha yo'q.
- **Menda o'z API kalitlarim bor.** ElevenLabs va Gemini kalitlarini kiriting. Ular Keychain (macOS) yoki Credential
  Manager'da (Windows) saqlanadi; hisobdan pul yechilmaydi.
- **O'z gateway'im** («o'z kalitlarim» qismi ichida): gateway manzili va access token. Ilovada token avvaldan saqlangan bo'lsa,
  ilova shu usulda ochiladi va qayta so'ramaydi.

Tanlangan ulanish sozlamalar panelida bir qatorda ko'rinadi; **O'zgartirish** (boshqa usullarda **Ulanishni
o'zgartirish**) uni almashtiradi. Ovoz tanlovi har ulanish uchun alohida saqlanadi — ro'yxatlar farq qiladi.

Birinchi ishga tushirishda macOS ikki ruxsat so'raydi — ikkalasiga ham **Allow** bosing:

| Ruxsat | Nima uchun | Keyin qayerda |
|---|---|---|
| Microphone | sizning nutqingizni olish | System Settings → Privacy & Security → Microphone |
| System Audio Recording | faqat tanlangan uchrashuv ilovasining ovozini olish | System Settings → Privacy & Security → Screen & System Audio Recording → «System Audio Recording Only» |

Ruxsat berilmasa: mikrofon/manba ko'rsatkichi (meter) jim turadi va subtitr chiqmaydi. Ilova hozircha ad-hoc
imzolangan — qayta build qilinganda macOS ruxsatlarni yana so'rashi mumkin (bu kutilgan holat).

## 2. Har qo'ng'iroqdan oldin

1. **Naushnik taqing.** Karnay ishlatilsa tarjima ovozi mikrofonga qaytib kiradi (aks-sado).
2. Ilovada:
   - **Mening tilim / Suhbatdosh tili** — ikki ro'yxat. Standart: O'zbekcha ↔ Inglizcha. Har ikkisini 90 tildan
     tanlash mumkin (ElevenLabs v4 qo'llaydigan va nutqni tanish ham tushunadigan tillar); maydonga yozsangiz ro'yxat
     saralanadi. Ikki til bir xil bo'lsa sessiya boshlanmaydi. O'zbek ↔ ingliz/rusdan boshqa juftliklar
     o'lchanmagan — sifatini o'zingiz sinab ko'ring.
   - **Mode** — `Captions only` (faqat subtitr), `Incoming audio` (subtitr + o'zbekcha ovoz naushnikda),
     `Bidirectional speech` (ikki tomonlama ovoz; virtual mikrofon kerak — macOS'da BlackHole, Windows'da VB-CABLE).
   - **Microphone** — haqiqiy mikrofoningiz. **Headphones** — naushnigingiz.
   - **Meeting source** — Zoom yoki brauzer jarayonini belgilang (avval qo'ng'iroqni oching, so'ng **Refresh**).
     Brauzerda bo'lsa: alohida brauzer oynasi ishlating va boshqa ovozli tablarni yoping — ilova bitta tabni emas,
     butun brauzer jarayonining ovozini oladi.
   - **Ulanish** — hisob bilan bo'lsa qoldiq ko'rinadi; faqat o'z gateway'ingizda **Gateway URL** va **Access token**
     kerak.
   - **Ovozlar** — ikki qator: «Mening ovozim (chiquvchi)» suhbatdosh eshitadigan tarjimangiz ovozi, «Suhbatdosh ovozi
     (kiruvchi)» siz eshitadigan ovoz. **O'zgartirish** gateway'dagi ElevenLabs hisobining ovozlarini ochadi: nomini
     qidiring, jins, yosh, aksent, til va qo'llanish bo'yicha saralang, ▶ bilan namunani eshiting, keyin ovozni
     bosing. **Standart** — gateway'da sozlangan ovozga qaytish. Tanlov darhol saqlanadi. Ro'yxat uchun ulanish (token yoki hisob) kerak,
     gateway'ning ElevenLabs kalitida esa *voices read* ruxsati bo'lishi kerak; aks holda oyna ro'yxat mavjud emasligini
     aytadi va sessiya sozlangan ovozlar bilan ishlayveradi.
3. **Device test** bo'limida: gapirganingizda mikrofon ko'rsatkichi qimirlashi, suhbatdosh gapirganda manba
   ko'rsatkichi qimirlashi, «Test headphones» signali naushnikda eshitilishi kerak.
4. Uchrashuv ilovasida audio sozlamalari:

| Platforma | Microphone | Speaker |
|---|---|---|
| Zoom Desktop — Settings → Audio | **BlackHole 2ch** (Windows'da **CABLE Output**) | naushnigingiz |
| Zoom Web / Google Meet — brauzerdagi audio sozlamalari | **BlackHole 2ch** (Windows'da **CABLE Output**) | naushnigingiz |
| Upwork — qo'ng'iroqni Upwork Messages'dan boshlang, so'ng yuqoridagi Zoom/brauzer sozlamasi | **BlackHole 2ch** (Windows'da **CABLE Output**) | naushnigingiz |

   Faqat subtitr rejimida uchrashuv ilovasidagi mikrofonni o'zgartirmang.
5. **Start session** bosing. Ochilgan oynadagi jumlani suhbatdoshga ayting yoki chatga yozing va roziligini oling:

   > “I use a live AI interpreter that translates my speech and speaks it in a synthesized voice. May I use it during this call?”
   > «Я использую ИИ-переводчик в реальном времени: он озвучивает мой перевод синтезированным голосом. Вы не против?»

   Rozilik belgilanmaguncha sessiya boshlanmaydi. Yashirin ishlatish mumkin emas.

## 3. Qo'ng'iroq paytida

| Amal | Qanday |
|---|---|
| Gapirish (push-to-talk) | **Space** ni bosib turing (yoki katta tugmani), gapiring, qo'yib yuboring. Qo'yib yuborilgach tarjima ketadi. |
| Chiquvchi ovozni o'chirish | **Mute outgoing** — tarjima uzatilmaydi, navbatdagisi tashlanadi. |
| Kiruvchi ovozni o'chirish | **Mute incoming** — subtitr qoladi, o'zbekcha ovoz jim. |
| Favqulodda to'xtatish | **Panic** yoki **Esc** — barcha navbat tashlanadi, virtual mikrofon jim, sessiya yopiladi. |
| Asl mikrofonga o'tish | **Bypass** — haqiqiy ovozingiz TARJIMASIZ qo'ng'iroqqa boradi (katta ogohlantirish chiqadi, server ishlatilmaydi). |

Ekranda ikki alohida yo'lak bor: **You → them** (sizning nutqingiz va tarjimasi) va **Them → you**
(suhbatdosh nutqi va o'zbekchasi). `OUT: ready` / `IN: ready` yozuvi chiqmaguncha u yo'nalish ishlamaydi.
`MOCK PROVIDERS` bayrog'i chiqsa — gateway soxta rejimda, bu haqiqiy tarjima emas.

Naushnikda suhbatdoshning asl ovozi ham, o'zbekcha tarjima ham eshitiladi (asl ovozni o'chirish hali qilinmagan).

**Ovozlar aralashmasligi uchun.** Ikki filtr bor, ular gapni yo'lakda qoldiradi, lekin tarjima qilmaydi va
aytmaydi (ostida kichik izoh chiqadi):

- *Tarjima qilinmadi — gap allaqachon tarjima tilida.* Sizning yo'lagingizga inglizcha/ruscha gap tushsa (odatda
  suhbatdoshning ovozi mikrofoningizga yetib kelgan), yoki suhbatdosh yo'lagiga o'zbekcha gap tushsa (sizning
  ovozingiz qo'ng'iroq orqali qaytgan).
- *E'tiborga olinmadi — o'z tarjima ovozimiz qaytib keldi (aks-sado).* Suhbatdosh karnayda bo'lsa yoki siz
  naushniksiz bo'lsangiz, tarjima ovozi yana mikrofonga tushadi; u qayta tarjima qilinmaydi.

Filtrlar tilga va matnga qaraydi, ovoz egasini tanimaydi. Shuning uchun **bir xonada sinamang**: ikki mikrofon
ikkala odamni ham eshitadi, uchinchi tildagi (masalan turkcha) gap esa baribir ikkala yo'lakda chiqishi mumkin.
Sinov uchun alohida xona va ikkalangizga naushnik kerak. Siz o'zingiz ataylab inglizcha gapirsangiz ham, u
suhbatdoshga uzatilmaydi.

## 3a. Til, eksport va analitika

- **Interfeys tili:** ilova tepasidagi ro'yxatdan O'zbekcha / Русский / Türkçe / English ni tanlang. Tanlov saqlanadi.
  Bu faqat ilova yozuvlari tili; tarjima yo'nalishlari o'zgarmaydi (o'zbek ↔ ingliz/rus).
- **Avtomatik rejim:** *Outgoing turn mode* da `Auto: VAD` yoki `Auto: turn prediction` tanlansa, Space bosish
  kerak emas. Naushnik taqing: karnay bilan suhbatdosh ovozi mikrofonga qaytib tushadi. (Tarjima ovozi o'ynayotgan
  paytda ilova mikrofonni vaqtincha yopadi, lekin bu faqat o'z tarjima ovozidan himoya qiladi.)
- **Suhbatni eksport qilish:** *Export conversation* tugmasi ikkala tomon gaplari va tarjimalarini vaqt belgilari
  bilan Markdown faylga saqlaydi. Fayl faqat siz tugmani bosganda va joyini tanlaganda yoziladi. Unda suhbatdoshning
  so'zlari ham bo'ladi — uning roziligi kerak.
- **Baholash:** har bir tarjima yonida 👍 / 👎 bor. Belgilaganingiz analitikaga yoziladi (matn emas, faqat belgi).
- **Analitika:** chap paneldagi *Analytics* bo'limi tezlik (boshdan-oxir, nutqni tanish, tarjima, ovoz sintezi —
  o'rtacha va eng yomon holatlar), xatolar, uzilishlar va baholaringizni ko'rsatadi. Jurnalda faqat raqamlar
  saqlanadi, matn yo'q; u shu Mac'da qoladi. Bo'limdan o'chirish, eksport qilish va tozalash mumkin.

- **Statistikani ulashish (ixtiyoriy):** *Analytics* bo'limidagi «Share anonymous statistics» o'chiq holda keladi.
  Yoqsangiz, o'sha raqamli yozuvlar (matn emas) tasodifiy o'rnatish ID'si bilan ishlab chiquvchining saytiga
  (jaysonkhan.com) yuboriladi; umumiy natijalar `https://jaysonkhan.com/services/livebridge/` sahifasida ko'rinadi.
  Istalgan payt o'chirsa bo'ladi.
- **Fikr yuborish:** *Send feedback* tugmasi yozgan xabaringizni (xohlasangiz email va baho bilan) ishlab chiquvchiga
  yuboradi.

## 4. Oddiy mikrofonga qaytish

Uchrashuv ilovasida Microphone'ni yana haqiqiy mikrofoningizga o'zgartiring. LiveBridge macOS'ning standart
mikrofon/karnay sozlamasini hech qachon o'zi o'zgartirmaydi, shuning uchun boshqa hech narsani tiklash shart emas.
Ilova yopilsa yoki qulasa, BlackHole'ga hech narsa yozilmaydi — suhbatdosh jimlik eshitadi, asl ovozingiz
«sizib» chiqmaydi.

## 5. Muammolar

| Belgi | Sabab va yechim |
|---|---|
| `OUT: not ready` / `provider_unavailable` | Gateway provayderga ulana olmadi: `.env` kalitlari, ovoz ID'lari, kredit qoldig'i. `npm run probe` aniq sababni ko'rsatadi. |
| Start tugmasi bosilmaydi | Tugma ostida sabab yozilgan (masalan mikrofon va virtual mikrofon bir xil qurilma, yoki BlackHole yo'q). |
| Subtitr bor, suhbatdosh eshitmayapti | Uchrashuv ilovasida Microphone = BlackHole 2ch ekanini va rejim `Bidirectional speech` ekanini tekshiring; «Test virtual mic» bosing. |
| Manba ko'rsatkichi jim | «System Audio Recording» ruxsati yo'q, yoki noto'g'ri jarayon tanlangan (brauzerda «Helper» jarayonini ham belgilang), yoki uchrashuv ilovasi hali ovoz chiqarmagan. |
| `source_gone` | Uchrashuv ilovasi yopildi — sessiyani qayta boshlang va manbani yana tanlang. |
| `device_removed` | Naushnik/mikrofon uzildi. Ilova o'zi boshqa qurilmaga o'tmaydi — qurilmani tanlab qayta boshlang. |
| «Balans tugadi — hisobni to'ldiring» / `balance_exhausted` | Hisob qoldig'i tugadi: sessiya to'xtaydi. **Hisobni to'ldirish** ni bosing. |
| «To'lov xizmatiga ulanib bo'lmadi» | Qayta urinib ko'ring; takrorlansa birozdan keyin. |
| «Seans 10 daqiqa gapirilmagani uchun tugadi» | Hisobda 10 daqiqa jim turilsa sessiya yopiladi — qayta boshlang. |
| «Seans boshqa qurilmada davom ettirildi» | Shu hisob boshqa qurilmada ishga tushirildi; bir vaqtda bitta sessiya. |
| «Xizmat band» | Bir daqiqadan so'ng qayta urinib ko'ring. |
| `Connection lost — reconnecting` | Tarmoq uzildi; 5 martagacha qayta ulanadi. Uzilishgacha aytilgan gap qayta yuborilmaydi — takrorlang. |
| Ovoz uzilib-uzilib chiqyapti | Tarmoq sekin (`capture_backlog`, `synthesis_congested`). Gateway'ni yaqinroq serverga qo'yishni o'ylab ko'ring. |

Diagnostika buyruqlari (`lbaudio` — Flutter'siz, terminaldan):

```bash
cd apps/desktop/native/LiveBridgeAudio && swift build
.build/debug/lbaudio devices                          # qurilmalar ro'yxati
.build/debug/lbaudio processes                        # ovoz chiqarayotgan jarayonlar
.build/debug/lbaudio mic --seconds 2                  # mikrofon darajasi
.build/debug/lbaudio tone --uid <UID> --db -20        # qurilmaga sinov signali
.build/debug/lbaudio tap --pid <PID> --seconds 3      # jarayon ovozini olish (-120 dB = ruxsat yo'q yoki jim)
.build/debug/lbaudio loopback --uid BlackHole2ch_UID  # BlackHole'ga yozib, undan qayta o'qish
.build/debug/lbaudio session --gateway http://127.0.0.1:8201 --token <TOKEN> --turns 3   # boshdan-oxir sinov
```
