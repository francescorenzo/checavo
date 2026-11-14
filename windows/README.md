# CheCavo per Windows

Tre progetti, tutti in sola lettura e senza rete:

- `Core`: le letture di Windows (porte USB-C, monitor, batteria) e i verdetti, condivisi.
- `CheCavo`: l'app, una finestra con le grafiche del Mac (spina, schede con le icone, misuratore dei
  watt). In cima c'è il chip del cavo: su Windows non si legge, e l'app lo dice prima di tutto. Sotto
  c'è quello che Windows vede (dati, video, audio, ricarica); a sinistra le prove possibili, con
  quello che si vedrà in ciascuna. Rilegge ogni 2 secondi. La finestra è larga e bassa (1180 punti):
  sta intera in un Full HD al 150%, e scorre solo sugli schermi più piccoli.
- `Sonda`: il programma da console che ha registrato cosa Windows vede delle porte USB-C (5 passi,
  log `CheCavo-sonda-<data>.txt` sulla Scrivania, senza nome utente, nome del PC e numeri di serie).

Tutto usa le chiamate di Windows (IOCTL, SetupAPI, QueryDisplayConfig, registro, registri eventi),
senza lanciare PowerShell né altri programmi, e gli exe non sono compressi: sono le due cose che
facevano scattare l'antivirus sulla sonda 0.1.

Test (dal Mac): `dotnet test windows/Tests`

Costruire l'app (due exe autonomi da circa 140 MB, x64 e ARM; WPF non si può ridurre col trim):

    for r in x64 arm64; do dotnet publish windows/CheCavo -c Release -r win-$r --self-contained \
      -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=none \
      -o build/windows/app-$r && cp build/windows/app-$r/CheCavo.exe build/windows/CheCavo-$r.exe; done

Prova a secco della sonda (dal Mac le sezioni Windows scrivono «(solo su Windows)»):
`dotnet run --project windows/Sonda -- --automatico --cartella /tmp/prova`

Costruire la sonda:

    for r in x64 arm64; do dotnet publish windows/Sonda -c Release -r win-$r --self-contained \
      -p:PublishSingleFile=true -p:PublishTrimmed=true \
      -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=none -o build/windows/win-$r; done
