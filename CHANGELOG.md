# Changelog

รูปแบบตาม [Keep a Changelog](https://keepachangelog.com/) และใช้ [Semantic Versioning](https://semver.org/)

## [Unreleased]

### งานค้าง
- Performance: RAM ที่ค้างหลังปิดหน้าต่าง (~35 MB) เป็น fragmentation ของ malloc; ยังไม่ได้ทดสอบโหมดประหยัดบนเครื่องสเปกต่ำจริง
- ทดสอบ pair กับ PC Windows จริง (ทั้งสองทิศการ dial) และ Mac 2 เครื่องที่อัปเดตเป็น build นี้ทั้งคู่
- เปิด popup จริงจาก menu bar ยืนยันขอบอีกรอบ (ทดสอบด้วยตัว copy ของ view ใน panel แล้ว)
- ท่าไต่ยังใช้ท่าเดิน (ยังไม่หมุนตัวแนวตั้ง); Windows ยังไม่ไต่หน้าต่าง
- click ไอคอนใน menu bar ด้วยเมาส์จริง (ทดสอบแล้วแค่ ^P/Esc)

## [1.7.0] - 2026-11-26

### Added
- **Windows companion** (`windows/`, Python 3.13+): pair PC กับ Mac ได้ (รหัส 6 หลักเดียวกัน, X25519 + HKDF, TLS 1.2 PSK), mascot เดิน/ถูกโยนข้ามจอ Mac ⇄ PC ได้ทั้งสองทาง คงสัตว์/สี/ขนาดของเครื่องต้นทาง, คลิกให้กระโดด ลากโยนได้, pair ได้หลายเครื่อง. รัน `windows/run.bat` หรือ build `.exe` ด้วย `windows/build-exe.bat`. ยังไม่มี: wallpaper sync, ไต่หน้าต่างบน Windows
  - ทดสอบ: pytest 16 ตัว (wire format/crypto เทียบ test vector จาก Swift), e2e กับแอป Mac จริงบนเครื่องนี้ผ่าน `python -m syscontrol --headless`: pair, PC→Mac (Mac เห็นเป็น `tabby` สี 200 ขนาด 1.6), Mac→PC, `roamingReturn` (mascot กลับมาครบ id เดิม), Network.framework TLS-PSK client → Python server (key ผิดโดนปฏิเสธ)
  - ข้อจำกัดตอนทดสอบบนเครื่องเดียว: Mac dial หา companion บนเครื่องเดียวกันไม่ได้ (mDNS lookup ไปที่ lo0). ระหว่าง 2 เครื่องจริงต้องได้ทั้งสองทาง: **ยังต้องทดสอบกับ PC จริง**
- **Mascot ไต่หน้าต่าง**: เดินชนขอบหน้าต่างที่ตั้งอยู่บนพื้น (45% ของครั้ง, พัก 20 วิระหว่างครั้ง) → ไต่ขึ้นขอบข้าง → เดินบนขอบบน 5–17 วิ → กระโดดลงแบบโยน. หน้าต่างย้ายก็พาไปด้วย ปิดหน้าต่างก็ตก. หน้าต่างเต็มจอไต่ขอบด้านในได้. `WindowClimber` (Core, test 6 ตัว) + `WindowSurfaces` (อ่านแค่กรอบหน้าต่างผ่าน `CGWindowListCopyWindowInfo` ทุก 0.5 วิ ไม่ต้องขอสิทธิ์ Screen Recording). ทดสอบสดแล้ว: ไต่ขึ้น lift 0→752, เดินบนขอบ, กระโดดลง
- `docs/LAN-PROTOCOL.md`: protocol + test vector สำหรับ implement ฝั่งอื่น
- `UISnapshot` (dev): `open --env SC_UI_SNAPSHOT=<dir>` แล้วส่ง distributed notification `com.pond.soundcontrol.uisnapshot` object = `do:popup`, `do:tab:<x>`, `do:settings`, `do:dump` (state.txt), `do:export-sprites`, `do:pair-open`, `do:pair-confirm`, `do:push:<side>`, `do:unpair:<id>`, `do:side:<id>:<side>`, `do:roaming-on|off` หรือชื่อภาพ (PNG ของหน้าต่างแอป) ใช้ทดสอบโดยไม่ต้องมีสิทธิ์ Screen Recording. ต้องเปิดผ่าน `open` (ถ้ารันจาก shell ใน sandbox จะไม่ได้รับ notification)

### Performance
- Settings → Performance: CPU และ RAM ตอนนี้/ต่ำสุด/เฉลี่ย/สูงสุด/พีค ตั้งแต่เปิดแอป (`ResourceMonitor`, `PerformanceStats`) อ่านค่าทุก 5 วินาที และ UI อัปเดตเฉพาะตอนเปิดหน้านี้
- โหมดประหยัด (`ResourceBudget`, ตั้งได้ Automatic/Always save/Off): ลดระดับเมื่อเครื่องร้อน เปิด Low Power Mode มี memory pressure หรือ load ต่อ core ≥1 (minimal เมื่อ ≥2) ผลคือ mascot เดิน 24→15→10 fps, ตอนถูกโยน cap 30/20 fps, ระดับ minimal ปิดการไต่หน้าต่าง, อ่าน session ทุก 1→2→4 วินาที และคืน heap เมื่อมี memory pressure
- ระหว่าง screen saver หรือ keyboard lock: desktop mascot หยุดทำงาน (`setPaused`)
- Claude usage widget: สแกน transcript ด้วย memchr/memmem (`ClaudeUsage.entries(inLines:since:)`) แทน `Data.split` ที่ช้า
- หน้าต่างหลักเปลี่ยนเป็น AppKit (`MainWindowController`) ปิดแล้ว view/layer ถูกปล่อยหมด (SwiftUI `Window` เดิมค้างไว้ ทำให้ RAM ขึ้นถึง 253 MB หลังเปิดแอป 1 วัน)
- หน้าในหน้าต่างหลักใช้ `LazyVStack` (`WindowPage`): section ที่ยังไม่ได้เลื่อนไปถึงจะยังไม่ถูกสร้าง
- ค่าที่วัดได้ (M-series): idle 33–46 MB, CPU 1–2%; หน้าต่างหลักเปิด 146 → 81 MB, ปิดแล้ว 87–99 → 69 MB; screen saver ตอนเปิดพีค ~105–115 MB ชั่วครู่ แล้วนิ่งที่ 45–58 MB, CPU สูงสุดตอนเปิด 67% → 25–28%, ปิดแล้วเหลือ 44 MB และเปิดซ้ำ 3 รอบไม่โต
- Idle CPU 1.6–1.9% → ~0.9%: อ่านท้าย transcript ใน background (`SessionTranscriptReader.startReading`) เพราะการเปิดไฟล์ใหญ่โดน security agent สแกนจนบล็อก main thread; ไฟล์ใน `~/.claude/sessions` อ่าน/parse ใหม่เฉพาะเมื่อ mtime เปลี่ยน; ตอนไม่มีใครดู feed อ่านแค่ชื่อ session ทุก 60 วินาที (เดิม 15); key ของ peer cache ไว้ใน memory (`LANSyncService.peerKeys`) เดิมอ่านจากดิสก์ทุก 10 วินาที และการ pair เครื่องเดิมซ้ำจะ restart listener ให้ใช้ key ใหม่
- เวลาที่ main thread ใช้กับ session monitor ลดจาก ~800 เหลือ ~100 ms ต่อ 30 วินาที
- Popup ปิดเกิน 10 วินาทีจะรื้อ view ทิ้ง ใส่ placeholder ขนาดเดิมไว้แทน (`MenuBarView.isContentLoaded`, `WindowVisibilityReader` ดู occlusion และ key) เปิดใหม่ใช้เวลาสร้าง 26–40 ms; ทดสอบกับ popup จริงด้วยการ click ผ่าน CGEvent 6 รอบ ครบทุก tab และหน้า Settings แสดงครบทุกรอบ; ใน heap ไม่มี view และ layer ค้าง (CALayer เหลือ 18) แต่ footprint ลดไม่มากเพราะ malloc fragmentation; popup ที่ปิดอยู่ไม่ redraw แล้ว
- การทดสอบ: click status item ที่ตำแหน่ง AX ของ menu extra ได้ (สคริปต์ใน scratchpad: press/click/wins) ส่วน hotkey ^P ที่จำลองด้วย CGEvent เปิด popup ไม่ได้ทั้ง build เก่าและใหม่ ต้องทดสอบด้วยมือ
- แก้: ^P เปิด popup ไม่ได้ (บน macOS ใหม่ ปุ่มของ `MenuBarExtra` ไม่มี target/action ทำให้ `performClick` ไม่มีผล และ SwiftUI ไม่มี API เปิด popup) เปลี่ยนเป็น AppKit `MenuBarPopup` ใช้ NSStatusItem + `PopupPanel` (borderless, nonactivating, พื้นหลัง NSVisualEffectView มุมโค้ง 12) ให้ click ไอคอนและ ^P เรียก `toggle()` ตัวเดียวกัน; ตอนเปิดดึงแอปขึ้นมา active เพื่อให้ Esc/Cmd-Q ใช้ได้; ปิดเมื่อเสีย focus (ถ้าเสีย focus ภายใน 0.5 วินาทีแรกจะดึง focus กลับ); popup อยู่บนจอที่ pointer อยู่; scene `MenuBarExtra` เหลือไว้แบบ `isInserted: false`
- ทดสอบแล้ว: ^P จากแอปอื่น 4/4, Esc ปิด 4/4, ^P ซ้ำปิดได้, สลับแอปแล้วปิดเอง, เปลี่ยน tab/Settings แล้วขนาดเปลี่ยนตาม, รื้อ view แล้วสร้างใหม่; ยังไม่ได้ทดสอบ: click ไอคอนจริง (AXPress ใช้ไม่ได้ทั้ง build เก่าและใหม่)
- ⚠️ ทดสอบด้วย click จำลองผ่าน CGEvent ทำให้ระบบค้างการปัด 3 นิ้วข้าม Space (WindowServer log "has been in phase") ห้ามใช้ click จำลองโดยไม่บอกผู้ใช้
- UISnapshot เพิ่มคำสั่ง `main`, `main-close`, `relief`, `screensaver:<วินาที>` (แสดง screen saver แบบไม่ล็อกคีย์บอร์ดแล้วปิดเอง)

### Fixed
- **Popup ชิดขอบซ้าย/บน** (เป็นซ้ำหลายรอบ): segmented `Picker` + ปุ่ม gear กว้างเกินความกว้างที่กำหนด → SwiftUI จัด overflow ไว้กลาง ดันทั้งหน้าไปชิดขอบ. เปลี่ยนเป็น `ModuleTabBar` ที่แบ่งความกว้างเท่ากันและไม่มีทางกว้างเกิน, frame จัด `.topLeading` (ถ้ามีอะไรล้นจะล้นไปทางขวาเท่านั้น). popup กว้างขึ้น 340 → 380pt, ขอบ 16pt
- Settings ใน popup: แถว "Open this popup" ไม่ยืดสูงแล้ว (`ShortcutRecorder` `.fixedSize()`), แถว Mac ที่ pair และปุ่ม Pair ใช้ layout เดียวกับแถวอื่น
- **Mascot ข้ามเครื่องแล้วกลายเป็นสัตว์ของปลายทาง**: สัตว์ใหม่ (Ginger Cat/`tabby`) decode ไม่ได้บนเครื่องที่เก่ากว่า → `look` เป็น nil → วาดสัตว์ของเครื่องนั้น. ตอนนี้ส่ง `look` เป็นสัตว์ที่ 1.6.0 รู้จัก (`Mascot.legacy`) + `species` ตัวจริง, ส่ง `hue`/`scale` ไปด้วย ปลายทางเห็นสี/ขนาดตามที่ตั้งที่บ้าน
- Mascot หายระหว่างทางเมื่อปลายทางเต็มหรือปิด roaming: ปลายทางส่ง `roamingReturn` กลับ ตัวเดินกลับเข้าจอเดิม; visitor มีโควต้าแยก 8 ตัว ไม่โดนนับรวมกับตัวของเครื่อง
- hello ส่ง `appVersion`/`platform`; แถว Mac ที่ pair เตือนเมื่ออีกเครื่องคนละเวอร์ชัน (ต้องอัปเดตทั้งสองเครื่อง)
- ตรวจแล้ว: TLS-PSK server หลาย key เลือก key ตาม identity ถูก (ทดสอบ 3 peer + key ผิดโดนปฏิเสธ) จึงไม่ใช่สาเหตุของ pair หลายเครื่อง


## [1.3.0] - 2026-11-12

### Added
- **Lock keyboard for cleaning** ใน menu bar: ล็อกคีย์บอร์ดไว้เช็ดโดยไม่ต้องปิดจอ. block ทุกปุ่มรวม modifier และปุ่ม media/เสียง/ความสว่าง, overlay ทุกจอกันคลิกพลาดจาก trackpad, ปลดล็อกด้วยการกดค้าง "Hold to unlock" 1 วินาที หรือปลดเองหลัง 10 นาที (กันกรณีเมาส์ใช้ไม่ได้), ไม่เล่นเสียงคีย์บอร์ดระหว่างล็อก. ต้องให้สิทธิ์ Accessibility (Settings → Permissions มีปุ่มเปิดหน้านั้น)
- **Lock for owner (screen stays on)** ใน menu bar: ล็อกคีย์บอร์ด+overlay เหมือน Lock keyboard for cleaning แต่ปลดด้วย **"Unlock as owner"** → Touch ID ขึ้นในหน้าล็อค (ไม่มี popup) หรือ prompt รหัสผ่าน login ถ้าไม่มี Touch ID แทนการกดค้าง. ไม่หมดเวลาเอง. ระหว่าง prompt รหัสผ่านให้ key ผ่านไปพิมพ์ได้. ไม่มีรหัสผ่าน login จะล็อกไม่ได้ (แสดงข้อความให้ตั้งก่อน). `UnlockMethod` ใน Core, `OwnerAuth` ใน Services (LocalAuthentication). ไม่ใช่ lock screen ของ macOS: force quit Sound Control ยังปลดได้
- `install.sh`: ติดตั้งด้วยคำสั่งเดียว `curl -fsSL https://raw.githubusercontent.com/chairat25/system-controller/main/install.sh | bash` โหลด release ล่าสุด, เช็ค SHA-256 และ code signature, ปิดตัวเก่าที่รันอยู่ (คืนเสียง macOS ก่อน) แล้วติดตั้งและเปิดแอป ไม่เจอ Gatekeeper prompt

### Changed
- เปลี่ยนชื่อแอปเป็น **System Controller** (bundle id `com.pond.soundcontrol` เดิม เพื่อให้สิทธิ์ที่ให้ไว้ยังอยู่). หน้าต่างหลักเป็น tab: tab แรก Sound Control, tab ถัดไปเพิ่มเป็น module ใหม่ได้ใน `ModuleTab`
- Keyboard lock overlay ทึบสนิท (สีดำ 100% จากเดิม 72%) ทั้งจอหลักและจอรอง ไม่เห็นว่าเปิดอะไรอยู่ใต้ overlay
- Lock for owner: Touch ID แสดงในหน้าล็อคเป็นไอคอนสแกนพร้อม animation วงแหวนตอนรอนิ้ว แทน popup กลางจอ. มี "Use password" กับ "Cancel" ระหว่างสแกน. Mac ที่ไม่มี Touch ID ใช้ prompt รหัสผ่านของ macOS เหมือนเดิม
- README: ขั้นตอน Open Anyway ชัดขึ้น (ปุ่มขึ้นใต้ "Allow applications from" หลังลองเปิดแอป และต้องเปิดหน้า Settings ใหม่)

### Fixed
- แอป crash เองตอนพับจอ: ระหว่าง DarkWake (Mac ตื่นแปปเดียวตอนจอพับ) Wi-Fi reconnect ทำให้ trigger network ยิง แล้ว AVFAudio throw exception เพราะยังไม่มี audio output → แอปปิดไปเอง
  - ไม่เล่นเสียงระหว่าง Mac หลับ/DarkWake (เสียง "Mac sleeps" ยังเล่นได้ภายใน 5 วินาทีแรก) Activity log ขึ้น "Mac is asleep"
  - เช็คว่ามี output device ก่อนเล่น และดัก exception จาก AVFAudio (target `ObjCExceptionCatcher`) ถ้าเล่นไม่ได้แค่ข้ามเสียงนั้น แอปไม่ตาย

## [1.2.0] - 2026-10-22

### Added
- release แบบ universal binary (Apple Silicon + Intel) เป็น `.dmg` (ลากลง Applications) และ `.zip` พร้อม checksum SHA-256
- `scripts/build-app.sh --universal --dmg` สำหรับสร้างไฟล์ release

### Changed
- **Replace macOS sounds** ทำงานอัตโนมัติ (เปิดเป็นค่าเริ่มต้น): trigger ไหนเปิดอยู่และ macOS มีเสียงของตัวเองซ้ำ (charging chime, shutter screenshot/Trash, volume feedback) แอปจะ mute เสียง macOS นั้นให้ ไม่ต้องไปเปิดเอง. ใน v1.1 ต้องเปิดเอง เลยยังได้ยินเสียงชาร์จของ macOS ดังก่อนเสียงของแอป
- macOS ได้เสียงคืนเมื่อปิด trigger นั้น, ปิด Listening หรือ Quit แอป และ mute ใหม่ตอนเปิดแอป
- Settings แสดงสถานะ "Muted by Sound Control" / "macOS default" ต่อเสียง ส่วน floating thumbnail ยังเป็น toggle ให้เลือกเอง
- แถว trigger แสดง "Replaces the macOS …" เมื่อแอป mute เสียง macOS ของจังหวะนั้นอยู่

### Fixed
- แอปค้างทั้งตัว (menu bar, Quit, การคืนค่าเสียง) เมื่อ macOS ขอสิทธิ์โฟลเดอร์ Desktop/Downloads เพราะ `open()` บน main thread รอจนกว่าจะกดตอบ prompt. ตอนนี้เปิดโฟลเดอร์บน background queue แล้ว
- `kill`/`pkill` (SIGTERM) ผ่านขั้นตอนปิดแอปปกติ จึงคืนเสียง macOS และบันทึก settings ก่อนออก

## [1.1.0] - 2026-10-22

เน้นเสียงดังทันที และไม่มีเสียง macOS ดังทับ

### Added
- Settings → **macOS sounds that overlap**: ปิด charging chime, interface sound effects (shutter screenshot, Trash), volume change feedback และซ่อน floating screenshot thumbnail. แอปจำค่าเดิมไว้ ปิด toggle เมื่อไหร่ก็คืนค่าเดิมให้ (Reset all settings ไม่ลบค่าเดิมที่จำไว้)
- แถว trigger ที่ macOS เล่นเสียงของตัวเองซ้ำ (Charger connected, Screenshot taken, Trash changed, Volume changed) มีลิงก์ **Silence it**
- **One sound per moment** (เปิดเป็นค่าเริ่มต้น): event ที่เกิดห่างกันไม่ถึง 0.35 วินาที (เช่น wake + display wake, USB + disk mounted) เล่นแค่ตัวแรก ไม่รวม event ถี่ๆ เช่นการพิมพ์
- **Instant sounds** (เปิดเป็นค่าเริ่มต้น): audio output พร้อมเล่นตลอดขณะใช้เครื่อง

### Changed
- เลิก pause audio engine หลังเงียบ 20 วินาที ซึ่งทำให้เสียงถัดไปช้าราว 45 ms (วัดจริง). ตอนนี้ engine พร้อมเล่นตลอดขณะใช้เครื่อง และ pause เมื่อไม่มี input เกิน 60 วินาทีและไม่มีเสียงมา 20 วินาที เพราะ engine ที่รันค้างทำให้ coreaudiod ถือ assertion กัน idle sleep (ตรวจด้วย `pmset -g assertions`)
- โหลด/สร้างเสียงของทุก trigger ที่เปิดไว้ล่วงหน้าตอนเปิดแอปและหลังเปลี่ยน setting ครั้งแรกที่เล่นจึงไม่ต้องรอ
- Charger connected/disconnected ใช้ `IOPSCreateLimitedPowerNotification` ซึ่งยิงทันทีที่เสียบ/ถอด adapter
- Screenshot taken ดูโฟลเดอร์เก็บ screenshot ตรงๆ ร่วมกับ xattr `kMDItemIsScreenCapture` (Spotlight ยังเป็นตัวสำรอง) จึงดังทันทีที่ไฟล์ถูกเขียน
- ลด debounce/poll: clipboard 0.4 → 0.12 s, จอ 1.0 → 0.3 s, โฟลเดอร์ 0.6 → 0.12 s, idle 1.5 → 1.0 s, audio output 0.4 → 0.25 s, dark mode ไม่รอเลย
- unit tests 79 ตัว

## [1.0.0] - 2026-10-22

เวอร์ชันแรก

### Added
- แอป menu-bar (`LSUIElement`) พร้อมหน้าต่างหลัก 5 หน้า: Triggers, Sound Packs, My Sounds, Activity, Settings
- popover ใน menu bar: สวิตช์ Listening, master volume, เลือก pack, 5 event ล่าสุด
- 60 triggers ใน 10 หมวด: Power, System, Screen & Display, Apps, Devices, Audio, Network, Keyboard & Mouse, Files & Clipboard, Time & Activity
- monitor ของระบบ: IOKit power sources, clamshell, USB; NSWorkspace; distributed notifications (lock, screen saver, appearance); CoreAudio (output device, volume, mute); IOBluetooth; NWPathMonitor; CGEvent tap แบบ listen-only; Spotlight screenshot query; การเปลี่ยนแปลงในโฟลเดอร์ Downloads/Trash; clipboard change count; idle time; นาฬิกาตีบอกเวลา
- monitor เริ่มเฉพาะเมื่อมี trigger ของมันเปิดอยู่ จึงไม่ขอ permission โดยไม่จำเป็น
- synthesizer ในตัว: 5 synth pack (Crystal, Arcade, Marimba, Cosmic, Soft Keys) × 18 motif × 2 takes และ pack macOS Classic จากเสียงในระบบ
- ตั้งเสียงต่อ trigger: Follow pack หรือหลายเสียงแบบ Rotate/Shuffle (Shuffle ไม่เล่นเสียงซ้ำติดกัน), volume ต่อ trigger, ฟังตัวอย่าง
- custom pack ("game master"): เลือก pack ตั้งต้น + override ทีละ trigger, export/import เป็นโฟลเดอร์ `.soundpack`
- My Sounds: import / ลากไฟล์มาวาง (WAV, AIFF, MP3, M4A, CAF, AAC, FLAC; ≤ 30 วินาที, ≤ 25 MB), rename, delete พร้อมล้างทุกที่ที่อ้างถึงเสียงนั้น
- Activity log (200 รายการล่าสุด, ไม่บันทึก event ถี่ๆ เช่นการกดคีย์)
- Settings: quiet hours (ข้ามเที่ยงคืนได้), เกณฑ์แบต low/critical, เวลาไม่อยู่หน้าเครื่อง, launch at login (`SMAppService`), สถานะ permission, reset
- cooldown ต่อ trigger กันเสียงรัว, audio engine พักเองเมื่อเงียบ 20 วินาที
- config เก็บเป็น JSON, อ่านแบบทนทาน (key ที่ขาดใช้ค่าเริ่มต้น), ไฟล์เสียถูกเก็บสำรองไว้ ไม่เขียนทับ
- ตรวจ input จากภายนอก: ชนิด/ขนาด/ความยาวไฟล์เสียง, ชื่อไฟล์ใน pack ที่ import (กัน path traversal), ชื่อ system sound
- `scripts/build-app.sh`: build release, ประกอบ `.app`, สร้าง icon, ad-hoc codesign, `--install`
- unit tests 73 ตัวใน `SoundControlCore` (line coverage ~99%)

### Fixed (จาก code review ก่อน release)
- import pack ที่มี sound id ซ้ำทำแอป crash → `validate()` ปฏิเสธ id ซ้ำ, จำกัด 200 เสียงและ `pack.json` ≤ 1 MB, แจ้งเสียงที่ import ไม่สำเร็จ
- ค่าเดียวที่ไม่รู้จักใน `config.json` (trigger/เสียง/pack จากเวอร์ชันอื่น) ทำให้ reset ทั้งไฟล์ → ตอนนี้ข้ามเฉพาะรายการนั้น
- import เสียง: ปฏิเสธ symlink และไฟล์ที่อ่านขนาดไม่ได้, เช็คขนาดก่อนเปิดไฟล์เป็น audio
- เสียง "Audio output changed" ถูกตัดตอนสลับอุปกรณ์ → engine ต่อสายใหม่แล้วเล่นต่อ, หน่วงเสียง 0.4 วินาที
- CoreAudio / Bluetooth callback ที่ค้างคิวทำงานหลัง monitor หยุด; Bluetooth ไม่ส่งเสียงซ้ำ และไม่ดังให้อุปกรณ์ที่ต่ออยู่แล้วตอนเริ่ม
- event tap / run-loop source ถูก invalidate ตอนหยุด, folder watcher ไม่รั่ว file descriptor
- ตีบอกเวลาหลังเครื่องหลับสั้นๆ ข้ามชั่วโมง → gap เกิน 60 วินาทีไม่ตี
- battery critical ต้องต่ำกว่า low เสมอ (low 2–99%, critical 1–98%)
- เสียงไฟล์ไหนโหลดไม่ได้ จะลองเสียงถัดไปใน rotation แทนการเงียบ
- Reset all settings เก็บ My Sounds ไว้ ไม่ทิ้งไฟล์กำพร้า
