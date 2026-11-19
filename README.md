# maxdash

Aplikasi dash untuk **Yamaha XMAX 2024**: navigasi belokan demi belokan, nama jalan, rambu batas kecepatan,
perawatan motor, kalkulator bensin (sisa bensin + sisa jarak), beberapa tampilan dash (Peta + Data /
Speedometer / Musik), dan pengaturan. Bahasa Indonesia sepenuhnya.

> Status: **draf awal** — desain (mockup) sudah dibuat, kode aplikasi iOS menyusul (Milestone 1).
> Proyek independen, tidak berafiliasi dengan Yamaha, Garmin, atau Apple.

## Versi

**0.1.0** (lihat file [VERSION](VERSION)). Aturan update: digit terakhir bertambah setiap ada perubahan,
contoh `0.1.0` → `0.1.1`.

## Struktur

| Folder | Isi |
|---|---|
| `design/` | Mockup HTML/CSS (buka `design/index.html` di browser). Tab ponsel + layar dash 480×234. |
| `app/` | Kode aplikasi iOS (Swift) + project.yml (XcodeGen) + Info.plist + test protokol Link A. |
| `docs/` | Catatan build & pemakaian. |
| `.github/workflows/` | Build IPA otomatis di Mac cloud (untuk build dari Windows). |

## Melihat desain

Buka `design/index.html` di browser. Warna diubah di `design/tokens.css`.

## Build & install (iPhone + Windows)

Lihat [docs/BUILD.md](docs/BUILD.md). Ringkas: akun GitHub gratis → build di Mac cloud (GitHub Actions) →
pasang ke iPhone via Sideloadly.

## Lisensi & disclaimer

Proyek pribadi, non-komersial. Risiko pemakaian ditanggung sendiri. Patuhi hukum lalu lintas setempat dan
syarat layanan peta/musik yang dipakai. Jangan mengutak-atik ponsel saat berkendara.