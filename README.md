# CheCavo

Colleghi un cavo USB-C e CheCavo ti dice a cosa serve: **ricarica**, **video**, **audio** e **dati**, in italiano semplice. È gratuita, per **Mac** e **Windows**.

Ogni risposta dice anche quanto è sicura: *dichiarato dal chip*, *provato adesso*, *dedotto* oppure *non si può sapere*.

## Scarica

👉 **[Scarica l'ultima versione](https://github.com/francescorenzo/checavo/releases/latest)**

| Computer | File da scaricare |
|---|---|
| Mac con chip Apple (M1, M2, M3, M4…) | `CheCavo-0.1.dmg` |
| PC Windows normale (Intel o AMD) | `CheCavo-0.1-Windows-x64.exe` |
| PC Windows con processore ARM (Snapdragon) | `CheCavo-0.1-Windows-ARM64.exe` ⚠️ **mai provata** |

Se non sai quale PC Windows hai, quasi certamente è il primo (x64).

📖 Come aprirla, come leggere i risultati e le domande frequenti: **[la guida](https://github.com/francescorenzo/checavo/wiki)**.

## Prima di usarla: i limiti, detti chiari

CheCavo l'ho costruita con l'aiuto di Claude Code per le mie esigenze e l'ho provata con i miei cavi su **due computer soltanto**. Su altri modelli può comportarsi diversamente.

- **Provata su:** un MacBook Pro M3 con macOS 27 e un mini PC Windows x64.
- **La versione Windows per PC ARM non è mai stata provata su un PC ARM.** È costruita dallo stesso codice di quella x64, ma potrebbe non partire o dare letture sbagliate. Se hai un PC ARM e la provi, raccontami com'è andata.
- **Mac:** servono macOS 14 o successivo e un chip Apple. Sui Mac Intel l'app si apre, ma per ora non legge i cavi.
- **Windows:** il chip del cavo (l'e-marker) **non si legge**, perché Windows non passa quei dati alle app. CheCavo te lo dice in cima alla finestra e ti mostra quello che Windows vede davvero: i watt che entrano, un monitor collegato, la velocità di un disco o di un telefono.
- **Cavi senza chip:** molti cavi non hanno l'e-marker. CheCavo lo dice, ma cosa reggono i fili si scopre solo provando, oppure con un tester per cavi USB-C.
- **Il chip dice quello che ci ha scritto il produttore.** Esistono cavi economici con un chip che promette più di quanto i fili reggano.
- **L'app non è firmata** da uno sviluppatore registrato, quindi la prima volta Mac e Windows ti avvisano (vedi sotto).

## La prima apertura

**Mac**
1. Apri il file `.dmg` e trascina CheCavo nella cartella Applicazioni.
2. Aprila: macOS la blocca.
3. Vai in **Impostazioni di Sistema › Privacy e sicurezza**, scorri in basso e premi **«Apri comunque»**. Su macOS 15 e successivi il clic destro › Apri non basta più.

**Windows**
1. Fai doppio clic sul file `.exe`: non c'è niente da installare.
2. Se compare la schermata blu di **SmartScreen**, premi **«Ulteriori informazioni»** e poi **«Esegui comunque»**.

## Cosa fa e cosa non fa

- **Legge e basta.** Non cambia niente nel computer né nel cavo.
- **Non usa la rete.** Non manda dati da nessuna parte.
- Il pulsante **«Copia dati grezzi»** copia i dati tecnici della porta **senza nomi, nomi del computer né numeri di serie**. Se l'app ti dà un risultato strano, incollali in una [segnalazione](https://github.com/francescorenzo/checavo/issues) o nei commenti del video: mi aiuti a migliorarla.

## Il codice

- `Sources/`, `Tests/`: l'app per Mac in Swift (SwiftUI, IOKit). Si costruisce senza Xcode con `./scripts/build-app.sh` (l'app) e `./scripts/build-dmg.sh` (il file `.dmg`); i test con `./scripts/test.sh`.
- `windows/`: l'app per Windows in C# (.NET 10, WPF). Come costruirla e provarla è scritto in [windows/README.md](windows/README.md).
- `fixtures/`: i dati veri di un cavo, usati dai test.

## Licenza

[MIT](LICENSE): puoi usare, copiare, modificare e ridistribuire CheCavo, anche dentro altri programmi, a patto di lasciare il testo della licenza con il mio nome. Il programma è dato **così com'è, senza garanzie**.

Creata da Francesco Renzo con Claude Code.
