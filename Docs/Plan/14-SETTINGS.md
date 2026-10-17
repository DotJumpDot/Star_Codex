# 14 — Settings Screen + About

Bottom-nav item (gear). Simple `ListView` of grouped sections. Everything
persists to the `settings` table (02) via `settings_dao`; in-memory mirror
in a Riverpod `SettingsNotifier` (fires on change; readers/engines re-read).

## Sections & items

**ทั่วไป (General)**
- ภาษา / Language: ไทย (default) | English — hot-applies (rebuilds MaterialApp
  locale; no restart needed ideally; restart-accepting fallback is ok v1).
- ธีม: ดำ (dark, default) | ดำสนิท (OLED black) | สว่าง (light).

**การอ่าน (Reading)**
- โหมดอ่านเริ่มต้น: อัตโนมัติ (auto, default) | เลื่อนแนวตั้ง | พลิกหน้า.
- จำนวนหน้าที่โหลดล่วงหน้า (prefetch): slider 2–12, default 6.
- เปิดหน้าจอค้างขณะอ่าน: switch, default ON.
- ไปตอนถัดไปอัตโนมัติ: switch, default ON (webtoon + paged).
- อ่านจากขวาไปซ้าย (RTL): switch, default OFF (paged mode only).

**นิยาย (Novel)**
- ขนาดตัวอักษร: stepper 14–30 (default 18).
- ระยะบรรทัด: stepper 1.4–2.2 (default 1.7).
- พื้นหลัง: ดำ | น้ำตาลเหลือง | ขาว.

**ดาวน์โหลด & พื้นที่ (Storage)**
- ดาวน์โหลดผ่าน Wi-Fi เท่านั้น: switch, default ON.
- งบแคชอ่าน (cache budget): choices 2/5/10 GB, default 5 GB.
- โควตาดาวน์โหลดรวม: choices 20/50/100/200 GB + custom dialog, default
  100 GB (decision S4).
- ใช้พื้นที่ตอนนี้: readout — cache X GB (evictable) + pinned Y GB + DB Z MB.
- ล้างแคชที่ยังไม่ปักหมุด (clear unpinned cache now) — with confirm + result toast.
- ลบประวัติการค้นหา.

**แหล่งอ่าน (Sources)**
- List of 5 sources: switch enabled/disabled + "ทดสอบการเชื่อมต่อ" per source
  (runs `latest(page:1)` and reports ok/err + ms).
- Reordering: up/down arrows (affects source priority tiebreaks in 07 §4).

**เกี่ยวกับ (About)**
- Version + build date (from pubspec + const), "สำหรับใช้ส่วนตัวเท่านั้น"
  (personal-use note, decision D6), link to Docs/, licenses (flutter's
  showLicensePage), "สร้างจากแผนใน Docs/Plan".

## Conventions

- Every change writes through `settings_dao` immediately (no Save button).
- Reader/prefetch changes apply to currently-open readers next open (no
  live-retune needed v1 — simpler).
- Storage readout uses `blobs` SUMs + db file size (`File.stat`).

## Definition of Done

- [ ] Every control round-trips: change → restart app → value persists.
- [ ] Language toggle flips all UI strings incl. reader chrome.
- [ ] Cache-limit change to 2 GB triggers janitor on next run; readout
  numbers add up (cache + pinned + db ≈ app dir size on disk).
- [ ] Source disable removes it from browse chips, search, and source
  fallback chain until re-enabled.
