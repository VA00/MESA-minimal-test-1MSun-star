# MESA: minimalny przykład ewolucji gwiazdy o masie 1 M☉

Absolutnie minimalna konfiguracja programu [MESA](https://docs.mesastar.org) (r24.08.1): ewolucja gwiazdy
podobnej do Słońca od jednorodnego obłoku H/He (pre-MS) do stygnącego białego karła. Ok. 14 000 kroków,
od ok. 1 godziny (szybki komputer) do kilku godzin.

*Minimal MESA setup: evolution of a 1 Msun star from a homogeneous H/He cloud to a cooling white dwarf.
Installation instructions (in Polish) for Linux, macOS, Windows WSL and native Windows.*

## Instrukcja

**[doc/MESA_instrukcja.pdf](doc/MESA_instrukcja.pdf)** (źródło: `doc/MESA_instrukcja.tex`):

- pracownia komputerowa Fort OA (MESA zainstalowana w `/opt/MESA`),
- Linux (Ubuntu), macOS (Apple Silicon),
- Windows: WSL (zalecane) oraz natywnie w PowerShell 7, bez WSL (eksperymentalnie, na razie bez wykresów),
- uruchomienie przykładu, szybki test, animacje, tabela benchmarków.

## Szybki start (MESA już zainstalowana)

Linux, macOS, WSL:

```bash
git clone https://github.com/VA00/MESA-minimal-test-1MSun-star.git
cd MESA-minimal-test-1MSun-star
./mk
./rn
```

Windows natywnie (PowerShell 7):

```powershell
. C:\MESA\MESA-minimal-test-1MSun-star\windows\mesa_env.ps1
cd C:\MESA\MESA-minimal-test-1MSun-star
./mk
./rn
```

Restart od ostatniego zdjęcia: `./re`, od wybranego: `./re x500`.

Wyniki: `LOGS/` (dane ewolucji), `photos/` (zdjęcia do restartów), `png/` (wykresy pgstar).
Animacje z wykresów: `./parallel_movie_encode.sh` lub `ffmpeg` (rozdział „Animacje” w instrukcji).

## Zawartość

| plik / katalog | opis |
|---|---|
| `inlist`, `inlist.pgstar`, `history_columns.list` | ustawienia modelu i wizualizacji |
| `src/`, `make/` | `run_star_extras.f90`, `run.f90`, makefile |
| `mk`, `rn`, `re`, `clean`, `parallel_movie_encode.sh` | skrypty dla Linuksa, macOS, WSL |
| `mk.ps1`, `rn.ps1`, `re.ps1`, `clean.ps1` | to samo dla Windows (PowerShell 7) |
| `windows/` | instalacja MESA natywnie pod Windows (MSYS2/gfortran, bez WSL) |
| `doc/` | instrukcja (LaTeX i PDF) |
| `Changelog` | historia zmian |
