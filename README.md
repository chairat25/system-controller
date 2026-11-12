# System Controller

แอป menu-bar บน macOS ที่รวมเครื่องมือจัดการ Mac ไว้ในที่เดียว แต่ละอย่างเป็น tab ใน popover:

- **Control** เล่นเสียงเมื่อ Mac ทำอะไรบางอย่าง: เสียบสายชาร์จ, ล็อกจอ, เสียบ USB, เน็ตหลุด, กดคีย์บอร์ด, ดาวน์โหลดเสร็จ รวม 60 เหตุการณ์ ทุก trigger เปลี่ยนเสียงได้เอง ใช้ sound pack สำเร็จรูป หรือสร้าง pack ของตัวเองก็ได้ และมีปุ่มล็อกคีย์บอร์ดไว้เช็ด
- **Screen Saver** (Smartheart Screen Saver) ล็อกเครื่องแบบจอยังเปิด แสดงนาฬิกา ปฏิทิน การใช้ Claude และ Claude Code session ที่กำลังทำงานแบบ realtime ปลดล็อกด้วยลายนิ้วมือเจ้าของ
- **Dev** ดูแล Claude Code session บนเครื่อง: `/compact` อัตโนมัติเมื่อ idle และส่งต่องาน (handoff) ก่อน 5-hour limit หมด

ฟีเจอร์ทั้งหมดเปิดใช้ได้เลย ไม่มีระบบ Pro/License

---

## ความต้องการ

- macOS 15 (Sequoia) ขึ้นไป · Apple Silicon หรือ Intel

## ติดตั้งแบบง่าย (3 ขั้น)

1. เปิดแอป **Terminal** (กด ⌘ Space พิมพ์ `Terminal` แล้ว Enter)
2. copy คำสั่งนี้ไปวาง แล้วกด Enter:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/chairat25/system-controller/main/install.sh | bash
   ```
3. รอสักครู่ แอปเปิดเอง ไอคอนรูป slider ขึ้นใน menu bar ด้านบนขวา ถ้ามีหน้าต่างขออนุญาต กด **Allow**

อัพเดตเวอร์ชันใหม่: รันคำสั่งเดิมอีกครั้ง (settings ยังอยู่) · ไม่อยากใช้ Terminal: ดู [ติดตั้งจาก DMG](#ติดตั้งจาก-dmg)

## ติดตั้งด้วยคำสั่งเดียว (รายละเอียด)

เปิด **Terminal** แล้ววาง:

```bash
curl -fsSL https://raw.githubusercontent.com/chairat25/system-controller/main/install.sh | bash
```

สคริปต์โหลด release ล่าสุด, เช็ค SHA-256, ติดตั้งลง `/Applications` แล้วเปิดแอปให้ ไม่เจอหน้าต่าง "Apple could not verify…" เพราะไฟล์ที่โหลดผ่าน `curl` ไม่ถูกติด quarantine. รันซ้ำเพื่ออัพเดตเป็นเวอร์ชันใหม่ได้ (settings และเสียงที่ import ไว้ยังอยู่)

ตัวเลือก: `SOUND_CONTROL_VERSION=1.3.1` เลือกเวอร์ชัน, `SOUND_CONTROL_DIR=~/Applications` เปลี่ยนที่ติดตั้ง, `SOUND_CONTROL_NO_OPEN=1` ไม่เปิดแอปหลังติดตั้ง เช่น `curl -fsSL …/install.sh | SOUND_CONTROL_NO_OPEN=1 bash`

## เริ่มใช้งาน (ผู้ใช้ใหม่)

1. **ติดตั้ง** ด้วยคำสั่งข้างบน แอปเปิดเองและไอคอนขึ้นใน menu bar
2. **อนุญาต Automation** ถ้า iTerm2 หรือ Terminal เปิดอยู่ จะมี prompt *"System Controller wants to control iTerm2/Terminal"* ขึ้นตอนเปิดแอป กด **Allow** (ถ้า terminal ยังไม่เปิด prompt จะขึ้นตอนเปิดครั้งแรก) ใช้เพื่ออ่านหน้าจอ session และพิมพ์ `/compact` ให้
3. **Login Claude Code** ถ้ายังไม่เคย: เปิด terminal พิมพ์ `claude` แล้ว login หนึ่งครั้ง แอปใช้ login นี้อ่าน % ของ 5-hour window
4. **ตั้งค่าตามที่ใช้**
   - Screen saver / ล็อกคีย์บอร์ด ต้องการ **Accessibility**: กดครั้งแรก macOS จะเด้งขอ → System Settings → Privacy & Security → Accessibility → เปิด System Controller
   - คีย์ลัดเปิด screen saver: tab Screen Saver → ⚙️ → SHORTCUT → กดปุ่มแล้วกดคีย์ (ต้องมี ⌘ ⌥ หรือ ⌃)
   - คีย์ลัดเปิด popup และ **Launch at login**: ปุ่ม ⚙️ ข้าง tab ด้านบนของ popup
5. **เช็คว่าพร้อม** ที่ tab Dev ควรเห็น *Window left xx%* และ iTerm2 / Terminal เป็น **Allowed**

ไม่ต้องติดตั้ง hook, status line หรือ script เพิ่ม แอปหา session, tmux และโฟลเดอร์ของ Claude Code (`$CLAUDE_CONFIG_DIR` หรือ `~/.claude`) เองบนแต่ละเครื่อง

## ติดตั้งจาก DMG

1. โหลด `SystemController-<version>.dmg` จากหน้า [Releases](https://github.com/chairat25/system-controller/releases/latest)
2. เปิด DMG แล้วลาก **System Controller** ไปวางที่ **Applications**
3. เปิดครั้งแรก: แอปไม่ได้ notarize กับ Apple macOS จึงบล็อกไว้ ปลดได้ 2 วิธี
   - เปิดแอปหนึ่งครั้ง (จะขึ้นเตือน) กด **Done** → เปิด **System Settings → Privacy & Security** ใหม่ → ปุ่ม **Open Anyway** อยู่ใต้ "Allow applications from" (ขึ้นแค่ราว 1 ชั่วโมงหลังลองเปิด และต้องเปิดหน้า Settings ใหม่หลังลองเปิดแอป)
   - หรือใน Terminal:
     ```bash
     xattr -dr com.apple.quarantine "/Applications/System Controller.app"
     ```
4. ไอคอนจะขึ้นใน menu bar

ตรวจไฟล์ที่โหลดมา: `shasum -a 256 SystemController-<version>.dmg` แล้วเทียบกับไฟล์ `.sha256` ใน release

อัพเดตเวอร์ชัน: Quit แอปตัวเดิม → ลากตัวใหม่ไปทับใน Applications (settings และเสียงที่ import ไว้ยังอยู่) → ต้องให้สิทธิ์ Input Monitoring ใหม่ถ้าใช้ trigger คีย์บอร์ด/เมาส์

## Build เอง

ต้องมี Xcode 16+ หรือ Swift 6 toolchain

```bash
git clone https://github.com/chairat25/system-controller.git
cd system-controller
scripts/build-app.sh                     # ได้ build/System Controller.app (เฉพาะ CPU เครื่องนี้)
scripts/build-app.sh --install           # build แล้ว copy ไป /Applications
scripts/build-app.sh --universal --dmg   # แบบ release: Apple Silicon + Intel, ได้ .dmg .zip .sha256 ใน build/
```

ตอนเปิดครั้งแรก หน้าต่างหลักจะเด้งขึ้นมาเอง หลังจากนั้นแอปจะอยู่ใน menu bar เท่านั้น

> แอป sign แบบ ad-hoc ถ้า build ใหม่ macOS จะมองเป็นแอปใหม่ ต้องให้สิทธิ์ Input Monitoring และ Accessibility ใหม่อีกครั้ง

## วิธีใช้

### Menu bar
คลิกไอคอนใน menu bar (หรือกดคีย์ลัดที่ตั้งไว้ จะเปิดที่ tab Control กดซ้ำเพื่อปิด):
- **⚙️ ข้าง tab** settings ของทั้งแอป: คีย์ลัด **Open this popup** (ใช้ได้จากทุกแอป) และ **Launch at login**
- **สวิตช์ Listening** เปิด/ปิดเสียงทั้งหมดทีเดียว
- **Volume** ระดับเสียงหลัก
- **Pack** เปลี่ยน sound pack ที่ใช้อยู่
- **Lock keyboard for cleaning** ล็อกคีย์บอร์ดไว้เช็ด โดยจอยังเปิด: ทุกปุ่ม (รวม modifier, ปุ่ม media/เสียง/ความสว่าง) ไม่ทำงาน, จอขึ้น overlay กันคลิกพลาดจาก trackpad. ปลดล็อกโดย **กดค้าง "Hold to unlock" 1 วินาที** ด้วยเมาส์/trackpad หรือรอ 10 นาทีปลดเอง. ระหว่างล็อกไม่เล่นเสียงคีย์บอร์ด. ครั้งแรกต้องให้สิทธิ์ **Accessibility**. ปุ่ม power และ Touch ID block ไม่ได้
- **Recent** 5 event ล่าสุด
- **Open…** (⌘,) เปิดหน้าต่างหลัก · **Quit** (⌘Q)

### Screen Saver
ล็อกคีย์บอร์ดและคลุมทุกจอด้วย Smartheart Screen Saver โดยจอยังเปิด ปลดได้เฉพาะเจ้าของ: วางนิ้วบน Touch ID ที่โซนด้านล่างของจอ หรือใช้ **รหัสผ่าน login** ถ้าไม่มี Touch ID ไม่หมดเวลาเอง เริ่มได้จากปุ่ม **Start screen saver** หรือคีย์ลัดที่ตั้งไว้ (ใช้ได้จากทุกแอป)

หน้าแรกของ tab:
- **SHOW** เลือก widget: Clock, Calendar, Claude usage (token ของ 5-hour window และของวันนี้), Claude sessions และมุมที่แสดงใน grid **Position** 4 มุม
- **Mascot** สัตว์น่ารักเดินเล่นไปมาด้านล่างจอ เลือกได้ 5 ตัว: Cat, Puppy, Bunny, Panda, Penguin หรือ None (แสดงเฉพาะจอหลัก)
- **Claude sessions** แสดงเป็นชิปชื่อ session ก่อน ประหยัดที่เมื่อมีหลาย session: คลิกชิปเพื่อกางดูหน้าจอ terminal แบบ realtime (iTerm2, Terminal, tmux; terminal อื่นใช้ข้อความจาก transcript) คลิกอีกครั้งเพื่อพับ จุดเขียว = กำลังทำงาน session ที่หยุดแล้วค้างไว้ราว 15 วินาทีแล้ว fade ออก ยกเว้นที่ **pin** ไว้ (ปุ่ม pin บนชิป หรือติ๊กในหน้า settings)

ปุ่ม ⚙️ **Dimming, clock, shortcut, pins…** ด้านล่างเปิดหน้า settings:
- **DIMMING** หรี่จอเองเมื่อไม่ขยับเมาส์: เริ่มหลัง (Start after), ใช้เวลาหรี่ (Fade over ตั้งแต่ทันทีถึง 1 ชั่วโมง), หรี่ถึงระดับ (Dim to, 0 = ดับ) ขยับเมาส์เพื่อให้สว่างกลับ
- **STAY LIT** เลือกว่าอะไรสว่างค้างขณะส่วนอื่นหรี่: **Clock** และ **mascot** ติ๊กแล้วเลื่อนความสว่างแยกกันได้ (5–100%) mascot ที่ไม่ได้ติ๊กจะหยุดเดินเมื่อจอดับ (ประหยัด CPU)
- **SHORTCUT** กดปุ่มแล้วกดคีย์ที่ต้องการ (Esc ยกเลิก, Delete หรือ Clear ลบ) ถ้าคีย์ซ้ำกับแอปอื่นจะขึ้นเตือน
- **PINNED SESSIONS** ติ๊ก session ที่อยากให้ค้างบน screen saver

ไม่ใช่ระบบกันเครื่องแบบ lock screen ของ macOS: force quit แอป (Cmd+Opt+Esc) ยังปิด overlay ได้ ถ้าต้องกันจริงใช้ Lock Screen (Control+Command+Q)

### Dev
ดูแล Claude Code session ทุกตัวบนเครื่อง ใช้ได้กับ iTerm2, Terminal และ tmux

- **Auto /compact when idle** ส่ง `/compact` ให้ session ที่ตอบเสร็จแล้วปล่อยว่างตามเวลาที่ตั้ง (Idle time) เฉพาะ session ที่แอปเห็นว่ามีงานหลังเปิดแอป ถ้าเครื่องมี Stop hook แบบเก่าที่ทำเรื่องนี้อยู่แล้ว แอปจะปล่อยให้ hook ทำ
- **5-HOUR LIMIT** อ่าน % ที่ใช้ไปของ 5-hour window จาก Anthropic ทุกนาที (ใช้ login ของ Claude Code บนเครื่อง อ่านอย่างเดียว ไม่ refresh token) เมื่อเหลือไม่เกินค่าที่ตั้ง (ค่าเริ่มต้น 5%) session ที่กำลังทำงานจะถูกขอให้เขียน handoff note ลง `handoffs/<session-id>.md` ในโฟลเดอร์ของ Claude Code แล้วได้ `/compact` เมื่อหยุดทำงาน (หรือหลังรอ 10 นาที) session ที่ idle ไม่ถูกแตะ
- **TERMINALS** สถานะสิทธิ์ Automation ของแต่ละ terminal, tmux และปุ่มเปิด Automation Settings ถ้าถูกบล็อก

### Triggers
รายการเหตุการณ์ทั้งหมด แบ่งตามหมวด แต่ละแถวมี:

| ส่วน | ทำอะไร |
|---|---|
| สวิตช์ | เปิด/ปิด trigger นั้น |
| chip เสียง (สีม่วง) | เลือกเสียงเดียวแบบเร็วๆ หรือ **Follow pack** ให้ pack เป็นคนเลือก |
| ▶ | ฟังตัวอย่าง (เล่นได้แม้ Listening ปิดอยู่) |
| ⚙ (slider) | เปิดหน้ารายละเอียด: ใส่หลายเสียง, เลือก Rotate/Shuffle, ปรับ volume เฉพาะ trigger |

- **Turn on recommended** เปิดชุดที่แนะนำ (ไม่ต้องขอ permission)
- ปุ่ม ⋯ มี Turn everything on/off, หัวหมวดมี Turn all on/off ของหมวดนั้น
- ช่องค้นหา + filter All / On / Off
- ดับเบิลคลิกแถวเพื่อเปิดหน้ารายละเอียด

**ใส่หลายเสียงให้ trigger เดียว:** ⚙ → เลือก *My own sounds* → *Add sound* หลายครั้ง → เลือก *Rotate in order* (เล่นวนตามลำดับ) หรือ *Shuffle* (สุ่ม ไม่ซ้ำกับครั้งก่อน)

### Sound Packs
pack คือ "เครื่องดนตรี" ที่เล่นทุก trigger ซึ่งตั้งเป็น Follow pack แต่ละ trigger มีท่วงทำนอง (motif) ของตัวเอง เช่น เสียบสาย = เสียงไล่ขึ้น, ถอดสาย = ไล่ลง ทุก pack จึงสื่อความหมายเหมือนกันแต่คนละสำเนียง

| Pack | สไตล์ |
|---|---|
| Crystal | เสียงแก้ว/ระฆังกังวาน (ค่าเริ่มต้น) |
| Arcade | square wave แบบเกม 8-bit |
| Marimba | เสียงไม้ ระนาด สั้นๆ อบอุ่น |
| Cosmic | sine ลอยๆ มี vibrato |
| Soft Keys | คลิกเบาๆ เหมาะกับเสียงพิมพ์ |
| macOS Classic | เสียง alert ที่มีอยู่แล้วใน Mac |

เสียงใน synth pack ถูกสร้างด้วยโค้ดตอนรัน (ไม่มีไฟล์เสียงในแอป) และแต่ละเสียงมี 2 takes ที่จะสลับกันเล่น

**เป็น game master — สร้าง pack ของตัวเอง:**
1. Sound Packs → **New pack** → เลือก pack ตั้งต้น
2. ตั้งชื่อ แล้วเลือกเสียง override ทีละ trigger (trigger ที่ไม่ได้ override ใช้เสียงจาก pack ตั้งต้น)
3. กด **Use** เพื่อใช้ pack นั้น
4. **⋯ → Export…** ได้โฟลเดอร์ `.soundpack` (มี `pack.json` + ไฟล์เสียงที่ใช้) ส่งให้คนอื่นได้ · **Import…** เพื่อนำเข้า

ลำดับการเลือกเสียง: เสียงที่ตั้งให้ trigger เอง → override ของ custom pack → เสียงของ pack ตั้งต้น

### My Sounds
- **Import…** หรือลากไฟล์มาวาง รองรับ WAV, AIFF, MP3, M4A, CAF, AAC, FLAC (ยาวไม่เกิน 30 วินาที, ไม่เกิน 25 MB)
- ไฟล์ถูก copy เข้าแอป ย้าย/ลบต้นฉบับได้เลย
- ⋯ → Rename / Delete (ลบแล้ว trigger ที่ใช้เสียงนั้นจะกลับไปใช้เสียงของ pack)

### Activity
ประวัติ event ล่าสุด 200 รายการ: เกิดอะไร, ตอนไหน, เล่นเสียงอะไร หรือถูกข้ามเพราะอะไร (Quiet hours, ไม่มีเสียง ฯลฯ)
event ถี่ๆ (กดคีย์, คลิก, ปรับ volume, สลับแอป) ไม่ถูกบันทึก

### Settings
- Listening, Master volume, **Launch at login**
- **Responsiveness**
  - *Instant sounds*: output พร้อมเล่นตลอดขณะใช้เครื่อง (พักเองเมื่อไม่ได้ใช้ ไม่กันเครื่อง sleep)
  - *One sound per moment*: event ที่เกิดพร้อมกันเล่นแค่ตัวแรก
- **macOS sounds → Replace macOS sounds** (เปิดเป็นค่าเริ่มต้น): ถ้า trigger เปิดอยู่และ macOS มีเสียงของตัวเองในจังหวะเดียวกัน แอปจะ mute เสียง macOS ให้ จะได้ไม่มีเสียงระบบดังก่อนหรือดังทับ
  | trigger ที่เปิด | เสียง macOS ที่ถูก mute |
  |---|---|
  | Charger connected | charging chime |
  | Screenshot taken, Trash changed | interface sound effects (shutter, Trash, Finder) — ถ้ายังได้ยิน ให้ log out/in ใหม่ |
  | Volume changed | volume change feedback |

  ปิด trigger, ปิด Listening หรือ Quit แอป = macOS ได้เสียงคืน (คืนค่าเดิมที่จำไว้)
- **Hide floating screenshot thumbnail**: ไม่ใช่เสียง แต่ถ้าเปิดไว้ macOS เขียนไฟล์ช้า ~5 วินาที เสียง screenshot เลยช้าตาม
- **Quiet hours** ช่วงเวลาที่ไม่เล่นเสียง (ข้ามเที่ยงคืนได้ เช่น 22:00–07:00)
- เกณฑ์ battery low / critical, เวลาที่ถือว่า "ไม่อยู่หน้าเครื่อง"
- Permissions: ปุ่มเปิด System Settings + Recheck
- Reset all settings

## Triggers ทั้งหมด

| หมวด | Triggers |
|---|---|
| Power | Charger connected/disconnected, Battery fully charged, Battery low, Battery critical, Low Power Mode on/off |
| System | You log in, Switched back to you / to another user, Mac sleeps/wakes, Shut down or restart, Lid closed/opened, Mac heating up / cooled down |
| Screen & Display | Screen locked/unlocked, Screen saver starts/stops, Display sleeps/wakes, Display connected/disconnected, Dark/Light mode, Space changed |
| Apps | App launched, App quit, Switched app |
| Devices | USB connected/disconnected, Disk mounted/ejected, Bluetooth connected/disconnected, Audio output changed |
| Audio | Volume changed, Muted, Unmuted |
| Network | Internet connected/lost, Network changed (Wi-Fi ↔ Ethernet) |
| Keyboard & Mouse | Key typed, Return, Delete, Space bar, Mouse click, Right click, Caps Lock on/off |
| Files & Clipboard | Screenshot taken, Download finished, Copied to clipboard, Trash changed |
| Time & Activity | Every hour, Every half hour, You stepped away, Welcome back |

## Permissions

| Trigger | ต้องการ |
|---|---|
| Keyboard & Mouse | **Input Monitoring** — System Settings → Privacy & Security → Input Monitoring → เปิด System Controller (ดูแค่ key code ไม่เก็บสิ่งที่พิมพ์) |
| Lock keyboard / Screen saver | **Accessibility** — System Settings → Privacy & Security → Accessibility → เปิด System Controller (ต้องใช้เพราะ lock หยุด key ไม่ใช่แค่ฟัง) |
| Claude sessions, Dev | **Automation** ของ iTerm2 / Terminal — แอปขอเองตอนเปิด (หรือตอน terminal เปิด) แก้ได้ที่ Privacy & Security → Automation |
| 5-hour limit | login ของ Claude Code บนเครื่อง (รัน `claude` แล้ว login ครั้งเดียว) |
| Bluetooth | ขอสิทธิ์ Bluetooth ครั้งแรกที่เปิด trigger |
| Download finished | ขอสิทธิ์โฟลเดอร์ Downloads ครั้งแรก |
| Screenshot taken | ขอสิทธิ์โฟลเดอร์ Desktop (หรือโฟลเดอร์ที่เก็บ screenshot) ครั้งแรก. ถ้าไม่อนุญาต ยังทำงานผ่าน Spotlight แต่ช้ากว่า |
| Trash changed | **Full Disk Access** |

monitor แต่ละตัวเริ่มทำงานเฉพาะเมื่อมี trigger ของมันเปิดอยู่ ถ้าไม่เปิด trigger ที่ต้องขอสิทธิ์ แอปก็จะไม่ขอ

## ข้อจำกัดที่รู้

- **Mac goes to sleep / Lid closed / Shut down**: เครื่องอาจหลับหรือปิดก่อนเสียงเล่นจบ
- **Lid** ใช้ได้เฉพาะ MacBook, **Battery** ใช้ได้เฉพาะเครื่องที่มีแบต (Mac ที่ไม่มีจะขึ้นเตือนในแถว trigger)
- **Screenshot taken** ดังเมื่อไฟล์ถูกเขียน ถ้าเปิด floating thumbnail ไว้จะช้า ~5 วินาที (ซ่อนได้ใน Settings) และไม่ดังเมื่อ capture ลง clipboard
- **Instant sounds** ทำให้ output device ทำงานขณะใช้เครื่อง ถ้า AirPods สลับมาที่ Mac เองบ่อยเกินไป ให้ปิด option นี้
- **Display connected** นับจำนวนจอ ถ้าปิดฝาแล้วใช้จอนอก จอในเครื่องจะนับเป็น disconnected
- **Trash changed** ต้องให้ Full Disk Access ไม่งั้นแอปขึ้นเตือนในแถว trigger
- **Claude sessions** ข้อความจาก transcript มาเป็นก้อนเมื่อข้อความหรือ tool call เสร็จ ข้อความ realtime ต้องอ่านจากหน้าจอ terminal ซึ่งทำได้กับ iTerm2, Terminal และ tmux เท่านั้น (Ghostty, Warp ฯลฯ สั่งงานจากภายนอกไม่ได้ จึงส่ง `/compact` หรือ handoff ไม่ได้ด้วย)

## ข้อมูลเก็บที่ไหน

```
~/Library/Application Support/SoundControl/
├── config.json        # การตั้งค่าเสียงทั้งหมด (ถ้าไฟล์เสีย จะ rename เป็น config.corrupt-<time>.json แล้วใช้ค่าเริ่มต้น)
├── app.json           # settings ของทั้งแอป (คีย์ลัดเปิด popup)
├── screensaver.json   # widget, mascot, dimming, stay lit, คีย์ลัด, session ที่ pin, มุมที่แสดง
├── limit-guard.json   # 5-hour limit
└── Sounds/            # ไฟล์เสียงที่ import (<uuid>.<ext>)

~/.claude/ (หรือ $CLAUDE_CONFIG_DIR)
├── idle-compact.json  # Auto /compact when idle
└── handoffs/          # handoff note ที่ session เขียนก่อน /compact
```

ถอนการติดตั้ง: ปิด *Hide floating screenshot thumbnail* (ถ้าเปิดไว้) → Quit (คืนเสียง macOS ให้อัตโนมัติ) → ลบ `/Applications/System Controller.app` และโฟลเดอร์ `SoundControl` ด้านบน

## Development

```bash
swift build                          # debug build
swift run SoundControl               # รันจาก terminal (launch at login ใช้ไม่ได้ในโหมดนี้)
swift test --enable-code-coverage    # unit tests (Swift Testing)
```

โครงสร้าง:

```
Sources/
├── SoundControlCore/   # logic ล้วน, value types, Swift 6 strict concurrency, มี test ครบ
│   ├── TriggerID.swift, TriggerCatalog.swift   # รายการ trigger + metadata
│   ├── Motif.swift, Synth.swift                # ท่วงทำนอง + synthesizer
│   ├── SoundRef.swift, SoundPack.swift         # ตัวอ้างอิงเสียง, pack สำเร็จรูป/custom
│   ├── AppConfig.swift                         # config + immutable updates
│   ├── SoundResolver.swift, PlaybackGate.swift # เลือกเสียง, กฎว่าจะเล่นหรือไม่
│   ├── Trackers.swift                          # battery/idle/clock/download state machines
│   ├── ConfigStore.swift, PackArchive.swift, ActivityLog.swift
│   ├── ScreenSaverSettings.swift, KeyShortcut.swift      # screen saver
│   ├── ClaudeSession.swift, ClaudeTranscript.swift       # session + ข้อความจาก transcript
│   ├── TerminalScreen.swift, ClaudeUsage.swift           # ตัดหน้าจอ terminal, นับ token
│   └── LimitGuard.swift, IdleCompactor.swift             # handoff ก่อน limit, /compact เมื่อ idle
└── SoundControl/       # แอป
    ├── AppModel.swift                          # state กลาง
    ├── Audio/                                  # AVAudioEngine + buffer cache
    ├── Monitors/                               # ตัวฟัง event ของระบบ (IOKit, CoreAudio, NSWorkspace, …)
    ├── Services/                               # import เสียง, pack, login item, คีย์ลัด, Claude sessions, terminal
    └── Views/                                  # SwiftUI
scripts/build-app.sh                            # สร้าง .app + icon + codesign
```

เพิ่ม trigger ใหม่: เพิ่ม case ใน `TriggerID` → ใส่ข้อมูลใน `TriggerCatalog` → ให้ monitor ตัวใดตัวหนึ่ง emit มันและใส่ลง `triggers` set ของ monitor นั้น (test `everyTriggerRegistered` จะฟ้องถ้าลืมข้อ 2)
