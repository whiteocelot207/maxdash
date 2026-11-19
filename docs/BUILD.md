# Build & install maxdash (iPhone + Windows)

Apple hanya menyediakan alat build di macOS, jadi dari Windows kita memakai **Mac cloud (GitHub Actions)**
untuk build, lalu **Sideloadly** untuk memasang ke iPhone.

> Dengan **Apple ID gratis**: aplikasi berhenti bisa dibuka setelah **7 hari** dan harus dipasang ulang.
> Maksimal **3 aplikasi** per device. Sideloadly bisa menandatangani ulang otomatis selama PC nyala.

## Langkah

1. **Buat akun GitHub gratis** di github.com (kalau belum punya).
2. **Install GitHub Desktop** (desktop.github.com) — cara tanpa terminal untuk mengunggah kode.
3. Buat repository **publik** baru (mis. `maxdash`), lalu unggah folder `app/` dan `.github/` ke sana.
   (Repo publik dapat menit build macOS gratis; repo privat kuotanya lebih kecil.)
4. Di GitHub, buka tab **Actions**. Setiap `push` akan menjalankan workflow **build-ipa**:
   - **Vector tests** (CRC, frame, command, handshake, share-link) — harus hijau. **Jangan ke motor sebelum ini hijau.**
   - **Build aplikasi** (unsigned) dan memaketkan `Maxdash.ipa`.
5. Unduh artefak **Maxdash-ipa** dari hasil run, lalu ekstrak.
6. Di Windows, install **iTunes** dan **iCloud** dari apple.com (bukan versi Microsoft Store), lalu **Sideloadly** dari sideloadly.io.
7. Colok iPhone, buka Sideloadly, seret `Maxdash.ipa`, masukkan Apple ID, klik **Start**.
8. Di iPhone: **Settings › General › VPN & Device Management › Trust**; lalu
   **Settings › Privacy & Security › Developer Mode › aktifkan**.

## Mengubah versi

Aturan: digit terakhir bertambah setiap ada perubahan (0.1.0 → 0.1.1).
Ubah `VERSION`, `app/project.yml` (`MARKETING_VERSION`), dan baris versi di `app/Sources/ContentView.swift`
(Settings › Tentang) agar tetap sama.

## Uji vektor secara lokal (opsional, tanpa Xcode)

Algoritma Link A & parser tautan bisa diuji di Windows tanpa Xcode memakai Node.js:

```sh
node app/tools/verify_vectors.mjs
```

Ini menjalankan kode referensi (identik dengan Swift) terhadap semua vektor di `app/Tests`.
Hasil harus "49 lulus, 0 gagal". Uji Swift yang sebenarnya (XCTest) berjalan otomatis di GitHub Actions.

## Yang belum ada di Milestone 1

Renderer JPEG peta, streaming frame ke dash, rute/posisi GPS, dan background. Itu menyusul setelah
Milestone 1 (protokol + share target) lulus uji.