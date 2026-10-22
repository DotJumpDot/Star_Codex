- 2026-10-22 — Card date precision (follow-up to the freshness fix; emu
  verified: slow-manga cards now read "16 ชั่วโมงที่แล้ว" exactly where
  the site's grid says 16 hours, order included). ts chapterdates are
  DATE-ONLY ("ตุลาคม 21, 2026" — probed live: all 364 rows carry no clock
  time), and the old parser anchored them at UTC midnight = 07:00 Thai,
  overstating every fresh chapter by ~13 h ("1 วันที่แล้ว" for a 16 h-old
  chapter). parseSiteDate now (a) parses RELATIVE stamps
  ("16 ชั่วโมงที่แล้ว" / "3 days ago" — previously → null stamp) and
  (b) anchors date-only strings at local 20:00 (Thai scanlation drops
  cluster in the evening; the site's own 16 h grid label back-solves to
  ≈19:16 posting). Known bound: morning drops may understate by up to
  ~12 h — they stay in the hours bucket. 236 tests green.
