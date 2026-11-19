# Build & install maxdash (iPhone + Windows)

Apple hanya menyediakan alat build di macOS, jadi dari Windows kita memakai **Mac cloud (GitHub Actions)**
untuk build, lalu **Sideloadly** untuk memasang ke iPhone.

> Dengan **Apple ID gratis**: aplikasi berhenti bisa dibuka setelah **7 hari** dan harus dipasang ulang.
> Maksimal **3 aplikasi** per device. Sideloadly bisa menandatangani ulang otomatis selama PC nyala.

## Langkah

1. **Buat akun GitHub gratis** di github.com (kalau belum punya).
2. **Install GitHub Desktop** (desktop.github.com) — cara tanpa terminal untuk mengunggah kode.
3. Buat repository **publik** baru (mis. `maxdash`), lalu unggah **isi** folder `maxdash-app`
   (`app/`, `.github/`, `VERSION`, `design/`, `docs/`) ke **root** repo — sehingga `app/` dan
   `.github/` berada langsung di root (repo publik dapat menit build macOS gratis; privat kuotanya lebih kecil).
4. Di GitHub, buka tab **Actions**. Setiap `push` akan menjalankan workflow **build-ipa**:
   - **Vector tests** (CRC, frame, command, handshake, share-link) — harus hijau. **Jangan ke motor sebelum ini hijau.**
   - **Build aplikasi** (unsigned) dan memaketkan `Maxdash.ipa`.
5. Unduh artefak **Maxdash-ipa** dari hasil run, lalu ekstrak.
6. Di Windows, install **iTunes** dan **iCloud** dari apple.com (bukan versi Microsoft Store), lalu **Sideloadly** dari sideloadly.io.
7. Colok iPhone, buka Sideloadly, seret `Maxdash.ipa`, masukkan Apple ID, klik **Start**.
8. Di iPhone: **Settings › General › VPN & Device Management › Trust**; lalu
   **Settings › Privacy & Security › Developer Mode › aktifkan**.

## Versi (otomatis)

**Tidak perlu mengubah tag manual.** Setiap kali Anda **push ke `main`**, workflow otomatis:
1. Membaca tag terakhir (mis. `v0.1.0`).
2. Menambah **digit terakhir** (patch): `0.1.0` → `0.1.1` → `0.1.2` …
3. Build + test vektor.
4. Membuat **GitHub Release** baru (tag `vX.Y.Z`) berisi `Maxdash.ipa` + `source.json`.

Push pertama (belum ada tag) membuat `0.1.0`. Build manual (`workflow_dispatch`) tidak menaikkan versi
dan tidak membuat rilis (hanya untuk coba-coba).

> Karena tiap push ke `main` = rilis baru, editan kecil sekalipun menambah patch. Kalau ingin menahan rilis,
> cukup jangan push ke `main` dulu.

## Rilis & LiveContainer

Setiap push ke `main` menghasilkan **GitHub Release** otomatis berisi:
- `Maxdash.ipa`
- `source.json` (format AltStore, kompatibel LiveContainer) dengan `version`, `versionDate`,
  `downloadURL` (menunjuk IPA rilis tersebut), dan `size`.

**URL source untuk LiveContainer (stabil, selalu rilis terbaru):**

```
https://github.com/whiteocelot207/maxdash/releases/latest/download/source.json
```

> Ganti `whiteocelot207/maxdash` jika Anda memakai repo lain.

Tambahkan di LiveContainer: tab **Sources › (+)** → tempel URL di atas → **Add** →
buka source → **Install** pada maxdash. LiveContainer akan mengunduh `Maxdash.ipa`
sesuai `downloadURL` di `source.json`.

## Uji vektor secara lokal (opsional, tanpa Xcode)

Algoritma Link A & parser tautan bisa diuji di Windows tanpa Xcode memakai Node.js:

```sh
node app/tools/verify_vectors.mjs
```

Ini menjalankan kode referensi (identik dengan Swift) terhadap semua vektor di `app/Tests`.
Hasil harus "49 lulus, 0 gagal". Uji Swift yang sebenarnya (XCTest) berjalan otomatis di GitHub Actions.

## Yang belum / perlu uji

Renderer JPEG masih versi dasar (rute + posisi + kecepatan); panel data (baterai, suhu, tegangan,
bensin) menyusul setelah Link B / input manual. **Belum diuji di motor** — wajib lewat build GitHub
dan uji di XMAX sebelum dipakai berkendara.