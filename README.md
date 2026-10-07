# Black Meridian — Operation 2027

Strzelanka FPP w Godocie: solo przeciw botom albo PvP 1 na 1 (GD-Sync), samoloty, balistyka, rany.

## Wymagania

- **Godot 4.7** (minimum 4.5 — wtyczka GD-Sync używa funkcji ze zmienną liczbą argumentów,
  na Godocie 4.4 i starszym wtyczka się nie wczyta). Wersja standardowa, nie .NET.

## Najszybciej: start.bat

Pobierz repozytorium (git clone albo Code → Download ZIP) i uruchom **`start.bat`**.
Przy pierwszym uruchomieniu sam pobierze Godota 4.7.2 (ok. 86 MB, z oficjalnego GitHuba
Godota) do folderu gry, zaimportuje zasoby i włączy grę. Kolejne uruchomienia startują od razu.

## Pierwsze uruchomienie w edytorze

1. Sklonuj repozytorium i otwórz `project.godot` w Godocie 4.7.
2. Poczekaj, aż edytor zaimportuje zasoby (pierwszy raz trwa chwilę).
   Jeśli pojawi się komunikat o wtyczce GD-Sync, zamknij edytor i otwórz projekt ponownie —
   wtyczka startuje dopiero po zakończonym imporcie.
3. Uruchom grę (F5) albo `start.bat` (popraw w nim ścieżkę do Godota).

## Gra przez internet (GD-Sync)

Klucze API nie są w repozytorium (`addons/GD-Sync/keys.cfg` jest w `.gitignore`).
Bez kluczy działa gra w sieci lokalnej / na jednym komputerze.

Żeby grać online: utwórz konto na gd-sync.com, wygeneruj klucze i zapisz je w pliku
`addons/GD-Sync/keys.cfg`:

```
[keys]

publicKey="TWÓJ_PUBLIC_KEY"
privateKey="TWÓJ_PRIVATE_KEY"
```

Obaj gracze muszą mieć te same klucze. W menu: jeden klika „Stwórz grę online”, drugi
wpisuje ten sam kod gry i klika „Dołącz online”.
