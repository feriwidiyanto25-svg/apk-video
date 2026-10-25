# 🎬 Shorts & Reels Video Creator (Zero-Budget Cloud Architecture)

Aplikasi pembuat konten **YouTube Shorts**, **Facebook Reels**, dan **TikTok** otomatis (format vertikal 9:16) dengan:
* **Audio Voiceover Alami (Edge-TTS)**: Suara Bahasa Indonesia resmi (*Gadis* & *Ardi*) tanpa kuota & 100% gratis.
* **Auto Dynamic Subtitles (Karaoke-Style)**: Subtitle animasi per kata di tengah layar dengan kontras tinggi.
* **Zero-Database & Zero-Install**: Seluruh proses render video dan build APK dikerjakan di awan (**GitHub Actions & GitHub Releases**), tidak membebani memori laptop/PC.

---

## 📁 Struktur Proyek

```
apk-video/
├── .github/workflows/
│   ├── render_job.yml      # Otomatisasi render video 9:16 di Ubuntu Cloud Runner
│   └── build_apk.yml       # Otomatisasi compile Flutter menjadi file installer .apk
├── engine/
│   ├── requirements.txt    # Library Python untuk runner GitHub
│   └── render_engine.py    # Mesin pembuat video (Edge-TTS + Karaoke .ass + FFmpeg)
├── mobile_app/             # Aplikasi Mobile Android (Flutter)
└── README.md
```

---

## 🚀 Langkah 1: Hubungkan ke GitHub Repository Anda

Buka terminal di folder ini (`e:\apk-video`), lalu jalankan perintah berikut untuk mengunggah kode ke GitHub:

```powershell
# 1. Inisialisasi Git
git init
git add .
git commit -m "feat: inisialisasi Shorts Creator engine & mobile app"

# 2. Ganti nama branch utama ke 'main'
git branch -M main

# 3. Hubungkan ke repository GitHub Anda (buat repo baru di github.com jika belum ada)
git remote add origin https://github.com/USERNAME-ANDA/NAMA-REPO-ANDA.git

# 4. Unggah ke GitHub
git push -u origin main
```

---

## 📱 Langkah 2: Mengunduh File Installer APK ke HP Android

Anda **TIDAK PERLU menginstal Flutter atau Android Studio di laptop**. GitHub Actions yang akan meng-compile APK untuk Anda:

1. Buka repository Anda di browser: `https://github.com/USERNAME-ANDA/NAMA-REPO-ANDA`
2. Klik tab **Actions** di bagian atas.
3. Pilih alur kerja **Build Android APK** di bilah kiri.
4. Klik tombol **Run workflow** $\rightarrow$ **Run workflow**.
5. Tunggu sekitar 4–6 menit hingga proses selesai.
6. Setelah selesai, buka menu **Releases** (di halaman utama repository sebelah kanan):
   * Unduh file **`app-release.apk`**.
   * Pindahkan ke HP Android Anda (atau buka GitHub langsung dari browser HP Anda) dan pasang (install) aplikasinya!

---

## ⚙️ Langkah 3: Pengaturan di Aplikasi Mobile

Setelah aplikasi terpasang di HP Anda:
1. Buka tab **Pengaturan** di dalam aplikasi.
2. Isi data berikut:
   * **GitHub Repository**: `USERNAME-ANDA/NAMA-REPO-ANDA`
   * **GitHub Personal Access Token**: Masukkan token yang memiliki izin `repo` dan `workflow`.
   * **Google Gemini API Key** *(Opsional)*: Jika Anda ingin AI otomatis membuat naskah dari topik singkat.
3. Klik **Simpan Pengaturan**.

---

## 🎥 Cara Membuat Video dari HP

1. Buka tab **Buat Video**.
2. Masukkan naskah atau ketik ide topik konten Anda.
3. Pilih karakter suara narator (*Gadis* untuk suara ceria/ramah atau *Ardi* untuk suara tegas/berita).
4. Pilih foto atau video latar dari galeri HP Anda (aplikasi otomatis menyesuaikan format menjadi vertikal 9:16).
5. Klik **Mulai Buat Video Shorts**.
6. Aplikasi akan mengunggah bahan mentah dan memicu GitHub Actions.
7. Buka tab **Riwayat**: status video akan terpantau (*Sedang Merender di Cloud...* $\rightarrow$ *Selesai*).
8. Ketuk video yang sudah selesai untuk **memutar pratinjau**, **menyimpan ke galeri HP**, atau **langsung membagikannya ke YouTube Shorts / Reels**.
