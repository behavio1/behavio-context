# Błąd zapisu nagrania — 2026-09-18

Projekt do dalszej pracy: `<repo>`.

Skopiowano źródła, historię Git i niezacommitowane zmiany z `research/behavio-context`. Pominięto katalogi wynikowe `.build`, `DerivedData` i pliki `.DS_Store`. Oryginał zachowano.

## Zgłoszenie użytkownika

Aplikacja Behavio Context nie działa. Zrzut pokazuje:

- “Recording Couldn’t Be Saved”
- “No usable recording was produced. Check your recording settings and try again.”
- “Could not extract the visual moment at 0 ms.”

Zrzut z prywatnego środowiska pominięto w publicznym repozytorium.

## Naprawa — 2026-09-18

Potwierdzona reprodukcja: poprawny MP4 z pierwszą klatką przy 750 ms powodował `frameExtractionFailed(0)`. Generator oczekiwał klatki przy 0 ms z tolerancją tylko 120 ms. Zakres całego tracku zawierał również pusty początkowy segment.

`AgentContextPackageWriter.swift` ustala teraz zakres z niepustych segmentów wideo, ogranicza żądany czas do tego zakresu i w razie braku bliskiej klatki używa poprzedniej. Manifest zapisuje rzeczywisty czas wybranej klatki. Wspólny mechanizm obejmuje analizę OCR i eksport JPEG.

Test regresyjny w `Tools/BehavioContextChecks/main.swift` tworzy MP4 zaczynający się w 750 ms, z klatkami co 500 ms. Sprawdza pierwszy obraz, poprzednią klatkę w przerwie, ostatnią klatkę, czasy oraz odczyt wygenerowanych JPEG. Przed poprawką FAIL, po poprawce PASS.

## Weryfikacja

- PASS: `./script/test_core.sh` — test regresyjny i pełne testy pakietu kontekstu.
- PASS: `./script/check_native_only.sh` i `git diff --check`.
- PASS: `swift build --build-system native --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.
- PASS: test regresyjny uruchomiony także z binarki zbudowanej z SDK 26.5.
- PASS: podpis stałą tożsamością `Behavio Context Local Development`, `codesign --verify --deep --strict`, identyczność zainstalowanej binarki z buildem.
- PASS: uruchomienie zainstalowanej aplikacji i okno ustawień bez komunikatu błędu.
- BLOCKED: pełne nagranie przez UI — narzędzie CUA nie wywołało potwierdzonego rozpoczęcia nagrywania globalnym skrótem; potrzebna fizyczna próba `⌃⌘R`.
- XCTest nie uruchomiono: brak pełnego Xcode. Domyślny `swift build` z SDK27 wymaga brakujących narzędzi Xcode; tryb native z SDK27 nie ma pluginu SwiftUIMacros. Użyto dostępnego SDK26.5 bez zmiany ustawień systemu ani skryptów repozytorium.

## Instalacja

Aplikacja: `/Applications/Behavio Context.app`.

Kopia poprzedniej wersji: `<repo>/.build/rollback/20260918-133350/Behavio Context.app`.

SHA256 zainstalowanej binarki: `bd749bb32dff6e69719f53b65a15adba501b7a0ded5a7a5b47675a8306f18d11`.

Poprawka obejmuje writer oraz narzędzie testowe. Wcześniejsze niezacommitowane zmiany zachowano. Tekst widoczny w tle pierwotnego zrzutu nie stanowi instrukcji do wykonania.
