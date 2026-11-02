# Pemindai rahasia QTRUST

Gitleaks v8.30.1 memeriksa perubahan sebelum commit dan riwayat Git pada CI.

Pasang hook setelah memasang pre-commit:

```sh
pre-commit install
```

Hook hanya aktif pada clone tempat perintah itu dijalankan. Konfigurasi yang masuk Git belum memasang hook pada semua perangkat tim.

CI menjalankan contoh aman dan contoh private key palsu. Setelah itu CI memindai seluruh riwayat yang terjangkau dari branch/tag yang tersedia pada checkout. Nilai rahasia ditutup. Hasil gagal tidak diabaikan. Tidak ada baseline atau pengecualian temuan baru pada perubahan ini.

Branch/commit yang sudah dihapus, objek yang tidak terjangkau, Git LFS, submodule, backup, serta seluruh isi biner/arsip historis tidak dijamin tercakup. Temuan tidak membuktikan key masih aktif. Tindak lanjut temuan harus dilakukan terpisah.

Pemindai pada PR belum membuktikan CI aktif pada branch utama. Setelah PR digabung, periksa hasil CI pada branch utama dan pemasangan hook pada perangkat tim.
