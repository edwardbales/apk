# Signtech File Sharing

**Flutter (Dart) Windows app** — IP-based file sharing for Signtech Digital print house.

Same language / toolchain as the user's TeamDrive workflow: **Flutter 3.24.x, Windows (windows-2022 runner), Inno Setup installer.** No WebView anywhere — 100% Flutter widgets, direct LAN calls (`dart:io` HttpServer on the Printer PC, HttpClient on the Designer PC).

## Setup — 4 ta PC, sob Windows, same WiFi

| PC | Role in the app |
|---|---|
| Designer PC 1 | Designer |
| Designer PC 2 | Designer |
| Printer PC 1 | Printer — Human Y-Jet |
| Printer PC 2 | Printer — Challenger |

Internet lagbe na. Sob PC same WiFi / LAN-e thakte hobe.

## Kivabe cholbe

1. **Printer PC-te app kholo** — prothom bar role becho: Human Y-Jet / Challenger. Server nije chalu hobe (port **8080**). Screen-e ei PC-r IP dekhabe, jemon `192.168.1.101:8080`.
2. **Designer PC-te app kholo** — role: Designer. Age printer becho (Y-Jet / Challenger), tarpor oi printer PC-r IP likho, **“Printer PC online?”** diye check koro.
3. **File beche, biboron likho** — Printer + Material + Note (optional), Black Fix toggle — tarpor **“file pathao”**.
4. File sorasori oi printer PC-te jabe: `Documents/Signtech File Sharing/Incoming/Human-Y-Jet/` ba `.../Challenger/`. Designer-er screen-e “Pathano hoyeche” dekhabe, printer-er screen-e job list-e asbe.
5. **Printer operator RIP khule print dibe.** App nije print dey na — RIP software-e size / colour setting operator-er hatei thake. Status bodlao: Pending → Printing → Done.
6. **Vul printer-e gele:** printer screen-e **“arek printer-e pathao”** button — ek click-e file arek printer PC-te forward hoye jabe.

## 16-bit + planar CMYK TIFF — v1.16

- **Photoshop theke asol file-ta jemon-i asuk, khulbe.** v1.15 sudhu 8-bit chunky CMYK TIFF nito; ekhon **16-bit** CMYK TIFF-o ney (high byte niye 8-bit-e ane — K 65535 hoy 255, K 32768 hoy 128, exact), ar **planar** TIFF-o ney (channel alada plane-e thakleo). Big-endian (Mac) ar little-endian (Windows) — duitoi chole. Compression ager motoi: uncompressed / LZW / PackBits.
- **Kalo 3-colour black hobe ager motoi** — 16-bit file pathaleo output 8-bit CMYK TIFF hoy (RIP-ready), K-ta C/M/Y-te jog hoy, K 0.
- **JPEG-compressed TIFF ekhono reject** — oita re-export korte hobe uncompressed ba LZW-te; dialog-e tai likha thakbe.
- Test: 16-bit big-endian, 8-bit planar, 16-bit planar — tin ta notun fixture diye verify kora; CMYK reader-er sob check 14/14 pass (standalone Dart-e, karon ei machine-e pub.dev reach kora jay nai — full `flutter test` GitHub Actions-e cholbe).

## No file-size limit — v1.16

- **EPS thakbe, TIF/EPS sob support.** EPS ager motoi jay (vector, check/convert hoy na). CMYK TIFF: **kono size limit nai** — ager 50 MP cap tule deoa hoyeche.
- **Kivabe:** conversion ekhon **streaming** — file-ta 1 MB tukro kore pore, 4 MB tukro kore convert kore, sorasori disk-e lekhe. Memory ~5 MB-ei thake, file joto boroi hok. Upload ar printer server age thekei streaming chilo (openRead + pipe), tai puro chain-e ar kono limit nai.
- **Sob format-ei kaj kore:** 8-bit / 16-bit (16-bit-er high byte neoa hoy), chunky / planar, uncompressed / LZW / PackBits, little- / big-endian. Planar file-er jonno 4-ta plane alada temp file-e decode kore tarpor merge kora hoy (memory tobuo bounded).
- **Proof:** 52 MP (8000×6500, 208 MB) file convert kore test kora — ager cap-er upore. Test 42/42 pass.

## CMYK ONLY + K black -> 3-colour black — v1.15

- **Sudu CMYK support.** RGB file ar pathano jabe na — bechlei app dialog dekhiye reject kore debe (“Only CMYK files can be sent — Photoshop / Illustrator theke CMYK TIFF export koro”). Grayscale file-o reject. CMYK JPG-o reject — tar K thik kora jay na, TIFF lagbe. EPS ager motoi jay (vector bole colour check kora jay na, convert-o kora jay na).
- **Design-e kalo thakle seta 3-colour black hobe (Human Y-Jet).** CMYK TIFF-er vitore K (black) channel-ta app nije pore: K-ta C, M, Y-te jog hoy (255 cap), K hoy 0. Pure K black hoy **C95 M95 Y95**; 50% K grey hoy ordhek CMY; sada ar K-chara colour bodlay na. Challenger-e kichu bodlay na (tar K head ache).
- **Kivabe pore:** app-er nijer CMYK TIFF reader ache (uncompressed / LZW / PackBits) — karon `image` package CMYK TIFF-ke RGB baniye fele, K hariye jay. 8-bit ba 16-bit, chunky ba planar CMYK TIFF support kore (v1.16); JPEG-compressed TIFF hole poriskar message diye reject kore.
- Ager RGB -> CMYK conversion tule deoa hoyeche — RGB ar dhokei na, tai oi code-er dorkar nai.
- **Asol file diye verify (2026-11-13):** tomar pathano `01-01_0_d0ui.tif` (1241×1754 CMYK, 13 MB) diye test korechi — 46% pixel-e K chilo, 52,209 pure kalo pixel C95 M95 Y95 hoyeche, ar converted file-ta PIL diye alada kore khuleo check korechi (CMYK, K ekdom 0). Ei file-tai ekta bug dhora porechilo (resolution tag-e crash korto) — thik kore ZIP abar banano hoyeche.

## OK folder — auto Done — v1.14

- **RIP folder-er vitore ekta OK folder thakbe** — app nijei baniye ney (`Documents/Signtech File Sharing/Incoming/<Printer>/OK/`), operator-ke kichu korte hobe na.
- **Kivabe kaj kore:** file RIP-e print hoye gele operator file-ta **OK folder-e move/copy** kore dibe. Printer PC proti **5 second-e** OK folder check kore — file-er nam-er sathe milano job-ta **auto Done** hoye jabe, dashboard-e ar kono click lagbe na.
- Done howar sathe sathe Designer-er PC-te **"Printing Ready" notification** jabe (ager poll system diye, 15 second-er vitore).
- Matching **exact file name** diye hoy; ekta OK file = ekta job (ekoi nam-er ekadhik job thakle sobcheye purono-ta Done hobe). Age thekei Done ba onno printer-e forward kora job abar Done hobe na.
- Dashboard-e sobuj **"OK folder — auto Done"** banner ache — ki korte hobe lekha ache, ar **"Open OK folder"** button-e click korlei folder-ta khulbe.
- Manual Done button ager motoi ache — OK folder sudhu shortcut, bikalpa na.

## Smaller window — v1.13

- **App ekhon choto window-e khulbe: 1080x680** (age Flutter-er default 1280x720 chilo, 1366x768 screen-e pray full screen hoye jeto).
- Window **resize kora jay + maximize kora jay** — eta shudhu kholar somoyer size.
- Kivabe: GitHub Actions workflow-e ekta step (`Smaller default window size`) `windows/runner/main.cpp`-er default size bodle dey — kono notun package lage nai. Step-ta fail korbe jodi Flutter-er template kokhono default line-ta bodle fele, tai boro window ar chupchap asbe na.

## Font — v1.12 (Team Drive screenshot)

- **Font ekhon Poppins** — tomar Team Drive screenshot-er font. Google Fonts theke ana (OFL license, free), app-er vitore bundle kora ache (`assets/fonts/` — Regular 400 / Medium 500 / SemiBold 600 / Bold 700), tai internet charao cholbe.
- Dark + Light — duita theme-ei Poppins.

## Printer dashboard sidebar — v1.11

- **Printer PC-r dashboard ekhon sidebar layout:** uporer top bar ar nai — bam dike ekta panel, dan dike Incoming files.
- **Sidebar-e ja ja ache:**
  - Logo + "Signtech File Sharing / Printer dashboard"
  - **Printer profile** — printer-er nam (Human Y-Jet / Challenger) + "Printer PC", ar **Server ON / OFF** status pill (sobuj / lal)
  - **Server address** — ei PC-r IP:port (jemon 192.168.1.101:8080), pashe **copy button** — ek click-e copy hoye jabe, Designer PC-te boshanor jonno
  - **Light / Dark theme button** — sidebar thekei theme bodlano jay
  - **Profile / Settings button** — Profile screen khole (IP, role change)
- Dan diker main area shudhu kajer jinis: stats (Total / Pending / Printing / Done) + Incoming files list, filter, Printing/Done button, forward.
- Designer screen ager motoi ache (top bar-e bell + theme + gear).

## Notification bell + profile photo — v1.10

- **Notification button ekhon top bar-e:** Designer screen-er upore bell icon (🔔). Kono file Done hole bell-er upore **lal badge-e notun notification-er sonkha** dekhabe. Bell-e click korle **Notifications page** khulbe — sob "Printing Ready" notification-er list, protita card-e file-er nam / printer / material, X diye alada kore bondho kora jay, ar "Clear all" diye sob muche fela jay. Page khullei notification gulo "read" hoye jabe, badge clear hoye jabe.
- Notifications save thake (`Documents/Signtech File Sharing/Sent/notifications.json`) — app bondho kore khulleo ager notification gulo thakbe.
- **Designer-er Profile photo:** Profile / Settings (gear icon) — upore **Profile photo** section. **Choose photo**-te click kore JPG/PNG chobi beche nile photo set hoye jabe, **Remove**-te muche fela jay. Photo set thakle Designer screen-er identity bar-e ar Sent files list-e nam-er pashe photo dekhabe; photo na thakle ager moto initials (D1/D2) avatar dekhabe. Photo sudhu oi Designer PC-tei thake — printer PC-te pathano hoy na, tai printer screen-e ager moto initials avatar-i dekhabe.

## Printing Ready notification — v1.9

- **Operator Done click korle designer notification pay:** Designer PC proti 15 second-e printer PC-ke jiggesh kore (GET /status) — kono file Done hole designer-er screen-e **sobuj Notifications card** asbe: **"Hey Designer 1, your design file completely Printing Ready"** — file-er nam, printer, material soho, X diye bondho kora jay. Sathe ekta green SnackBar-o dekhabe. Sent files list-e oi file-er pashe **"Printing Ready"** chip boshe jabe.
- **Ekbar-i notification:** ekta Done click = ekta notification — status save hoye jay, tai app bondho kore khulleo ar repeat hobe na. Designer app bondho thakle Done howar somoy notification asbe na, kintu app kholar sathe sathe check kore notification dekhiye dibe.
- Kivabe kaj kore: Printer PC-te `GET /status` endpoint (job id + status), Designer PC `TransferService.fetchStatuses` diye poll kore.

## Logo — v1.8

- **Tomar pathano printer logo-tai ekhon app-er logo + icon** — app-er vitore header-e (sob screen-e upore bam-e) ei logo dekhabe, ager "S" tile ar nei.
- **Windows icon:** `packaging/windows/app_icon.ico` (16–256px, 6 size) — workflow `flutter create`-er por ei .ico diye generated icon replace kore, tai EXE, taskbar, Start menu ar installer-eo same logo asbe. Installer-er icon-o same (`SetupIconFile`).

## All-English UI + clean printer dashboard — v1.7

- **All UI text is now English** — every label, button, message, dialog and error in the Designer screen, Printer dashboard, Profile and role select. No Bangla text anywhere in the app.
- **Printer dashboard cleaned up:** server card is one compact row (status + one IP line, no folder path); stats are now one slim strip (Total / Pending / Printing / Done) instead of 4 big cards; the two big buttons are gone — RIP folder + Refresh are small icons next to "Incoming files"; job cards lost the duplicate designer chip and the colour/black chips — material, size, colour and black fix are now one grey line.

## Professional layout + designer identification — v1.6

- **Designer screen:** upore identity bar (avatar + nam + chip) — ke pathacche sobsomoy dekha jay. Boro window-e **duita column**: bam-e printer + connection, dan-e file + pathao. File bechar jaiga ekhon boro drop-zone card.
- **Printer screen:** upore **stats row** (Mot file / Pending / Printing / Done). Tarpor filter: status (Sob / Pending / Printing / Done / Forwarded) + **Designer filter**.
- **Kon designer file patalo — ek nojore:** prottek job card-er upore designer-er **avatar (initials, jemon D1 / D2) + bold nam + rong-er chip**. Prottek designer-er ekta fixed rong thake (Designer 1 = beguni, Designer 2 = komola) — same designer sobsomoy same rong-e asbe. Designer-er nam Profile-e (gear icon) bosate hoy — nam na bosale 'Unknown designer' dekhabe.

## Theme — v1.5 (Team Drive blue, glassy)

- **Tomar pathano Team Drive screenshot-er blue (#4F5BD5)** — lal ar nei. Dark-e ektu ujjol blue (#5B6BE0), Light-e #4F5BD5. Glassy look: halka transparent card, norom border, boro 16px round corner.
- **Customer nam, Order No, Size, Quantity — TOTAL REMOVE.** Upload form, job list, printer screen, folder nam — kothao ar nei. Upload form-e ekhon shudhu: printer, file (CMYK TIFF / EPS — v1.15 theke JPG ar jay na), Black Fix, Material, Note, ar Pathao button. Folder-er nam ekhon sudhu tarikh + job id.

## Profile / Settings — v1.4

- **Gear icon (upore dan-e) → Profile / Settings.** Ekhane **shudhu** Designer nam ar Printer PC-r IP thake (Designer PC-te: Designer nam + Y-Jet IP + Challenger IP; Printer PC-te: arek printer-er IP). Ekbar likhle save thake.
- **Profile-e egula thake na:** Customer nam, Order No, Size, Quantity — egula v1.5-e app theke puropuri sorano hoyeche, upload form-eo ar nei. Upload form theke Designer nam ar IP-er box sorano hoyeche — ekhon sudhu ekta line-e IP dekhay (`Human Y-Jet PC: 192.168.1.101`) ar “Printer PC online?” button.
- Role bodlao-o ekhon Profile thekei hoy.

## Theme — v1.3 (Dark & Light)

- **Professional Dark & Light** — AppBar-er upore sun/moon button-e theme bodlay, pochondo save thake (porer bar khulle sei theme-i khulbe). Dark = shop-er black + red glassy look (#0B0B10 bg, #CD242B red accent); Light = clean paper background, diner alo-te counter-e pora jay. Dui theme-ei brand red, card, button, input sob same system-e.
- Header-e ekhon red **S** logo tile + “Signtech File Sharing” nam, role card-e red icon tile.

## File format & name — v1.2 (v1.15-e update)

- **Shudhu CMYK TIFF / EPS** — file picker-e ar kono format dekhabe na, onno format bechle app nibe na. JPG pathano jay na (v1.15 theke CMYK JPG-o reject hoy — tar K thik kora jay na).
- **File-er nam hubuhu same thakbe** — designer je name pathabe, printer PC-te sei name-i thakbe. Kono suffix (`_YJet-CMYK`) ba `(2)` jog hobe na. Same name-e duita alada job ashle ager file harabe na — prottek job nijer folder-e jabe (`Incoming/Human-Y-Jet/2026-11-13_<job-id>/banner.tif`), folder-er vitore nam ekdom same.

## Colour — v1.1

- **CMYK ONLY (sob printer):** sudhu CMYK file pathano jay. RGB ba grayscale file bechle app dialog dekhiye reject kore debe — “Only CMYK files can be sent — Photoshop / Illustrator theke CMYK TIFF export koro.” CMYK JPG-o reject (tar K thik kora jay na — TIFF lagbe). EPS jemon chilo temon-i jay (vector, colour check kora jay na).
- **Human Y-Jet Black Fix (shudhu Y-Jet):** oi printer-er K (black) head nai. Designer screen-e option — **“Human Y-Jet Black Fix: C95 M95 Y95”** (default ON). ON thakle CMYK TIFF pathanor somoy app file-tar K black ke 3 colour-e banay dey: K-ta C, M, Y-te jog hoy (255 cap), K hoy 0. Pure K black (0,0,0,255) hoy **C95 M95 Y95, K0**; 50% K grey hoy ordhek CMY; sada ar K-chara colour bodlay na. App nije CMYK TIFF porte pare (uncompressed / LZW / PackBits). Printer screen-e job-e **“Black: C95 M95 Y95”** badge dekhabe.
- **Limit:** Black Fix shudhu CMYK TIFF-e kaj kore — JPG pathanoi jay na (reject hoy). 50 MP-er beshi boro CMYK TIFF holeo convert hobe na — tokhon Photoshop / Illustrator theke choto CMYK TIFF export kore pathate hobe. JPEG-compressed TIFF-o khole na — uncompressed ba LZW-te re-export korte hobe. EPS-er khetre app convert kore na.

## Install (GitHub Actions)

1. Puro project folder (`.github` folder **shoho**, lukano folder bad dio na) GitHub repo-te upload koro.
2. Actions tab → **Build Signtech File Sharing (Windows EXE)** → **Run workflow**.
3. Build sesh hole Artifacts theke nao:
   - `signtech-file-sharing-windows-installer` — `SigntechFileSharing-Setup-1.0.0.exe` (installer, recommended)
   - `signtech-file-sharing-windows-portable` — portable ZIP
4. **4 ta PC-tei same installer** install koro. Protteke prothom kholar somoy nijer role beche nibe.

> Windows firewall prothom bar jiggesh korle **Allow** dio — na dile Designer PC Printer PC-ke khuje pabe na. Printer PC-r IP jeno na bodlay, router-e static IP / DHCP reservation kore rakha valo.

## Technical notes

- Protocol: `GET /ping` → `signtech-ok`; `POST /upload` → raw file bytes as body, metadata in `x-signtech-*` headers (URI-encoded). No multipart parser, no extra server dependency.
- Boro file stream kore pathano / save kora hoy (64 KB chunk), tai 100+ MB banner file-o memory-te puro uthbe na.
- Same file name duibar ashle overwrite hoy na — `banner (2).jpg` hoye jabe.
- Jobs `jobs.json`-e save thake, app bondho korleo list thakbe.
- Port: 8080 (sob PC-te same). `lib/models/print_job.dart`-e `kDefaultPort`.

## Local check (optional)

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```
