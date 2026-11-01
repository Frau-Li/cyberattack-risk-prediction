# Predykcja ryzyka cyberataków na podstawie telemetrii sieciowej

**Cyberattack Risk Prediction Based on Network Telemetry Data Analysis**

Praca magisterska · Informatyka, specjalizacja cyberbezpieczeństwo · Collegium Da Vinci, Poznań 2026
Autorka: **[FrauLi](https://github.com/Frau-Li)** · Język: **R** · Model: **Random Forest**

> 🇬🇧 *English summary below.*

---

## Problem

Ponad 90% ruchu w internecie jest dziś szyfrowane (TLS 1.3), więc klasyczne systemy wykrywania intruzów, które zaglądają do treści pakietów (DPI), coraz częściej są „ślepe”. Praca sprawdza, czy da się skutecznie wykrywać ataki **wyłącznie na podstawie metadanych przepływów** — rozmiarów pakietów, czasów, portów i entropii — bez czytania ich zawartości.

## Podejście

Ten sam model (Las Losowy, 50 drzew) przetestowano w dwóch środowiskach, tak by jedyną różnicą był **charakter cech telemetrycznych**:

| | CIC-IDS2017 | LUFlow |
|---|---|---|
| Paradygmat | klasyczny, wolumetryczno-czasowy | lekka telemetria + **entropia** |
| Liczba cech | ~80 | 11 |
| Zadanie | 14 klas (rodzaje ataków) | binarne: benign / malicious |
| Ruch tła | syntetyczny (B-Profile) | rzeczywisty (honeypoty) |
| Próbka | warstwowa, 5% | warstwowa, 10% (506 433 przepływów) |

Pipeline: wczytanie i połączenie wielu dni ruchu → usunięcie identyfikatorów (IP, czas — ochrona przed przeuczeniem) → czyszczenie `Inf`/`NA` → próbkowanie warstwowe → podział 70/30 → Random Forest → macierz pomyłek, Precision/Recall/F1, ROC/AUC, ranking ważności cech.

## Wyniki

| Miara | CIC-IDS2017 | LUFlow |
|---|---|---|
| **Accuracy** | 99,52% | **99,72%** |
| Precision | — | 99,92% |
| Recall | — | 99,16% |
| F1-score | — | 99,54% |
| **Odsetek fałszywych alarmów (FPR)** | 0,197% | **0,034%** |

**Najważniejsze wnioski**

- 🎯 **Telemetria wystarcza** do wykrycia niemal wszystkich ataków wolumetrycznych i skanowania (DDoS, DoS Hulk, PortScan — skuteczność bliska 100%), bez inspekcji treści pakietów.
- 📉 **Entropia ~6× zmniejsza liczbę fałszywych alarmów** — to realnie odciąża analityków SOC (problem *alert fatigue*), mimo że accuracy rośnie tylko o 0,2 p.p.
- 🔑 **Najsilniejsze cechy:** w CIC-IDS2017 — rozkład rozmiarów pakietów i `Init_Win_bytes_forward`; w LUFlow — port docelowy oraz **zagregowana entropia przepływu** (`total_entropy`). Entropia chwilowa sama w sobie jest zbyt zaszumiona.
- 🧱 **Granica podejścia:** ataki na aplikacje webowe (Brute Force, XSS) w warstwie L3/L4 wyglądają jak zwykły ruch HTTP(S) — do nich potrzebna jest analiza warstwy aplikacji.

**Kierunek rozwoju:** architektura hybrydowa — lekki detektor telemetryczny, który tylko w sytuacjach granicznych uruchamia kosztowną inspekcję DPI.

## Struktura repozytorium

```
R/
├── 01_cicids2017_multiclass.R      # pełny CIC-IDS2017 (5 dni), klasyfikacja 14 klas, ważność cech
├── 02_cicids2017_ddos_rf_vs_tree.R # scenariusz DDoS: Random Forest vs drzewo decyzyjne, krzywa ROC
└── 03_luflow_binary.R              # LUFlow (10 dni), klasyfikacja binarna, ważność cech
data/
└── README.md                       # skąd pobrać zbiory danych
```

## Uruchomienie

1. Pobierz zbiory danych zgodnie z [`data/README.md`](data/README.md).
2. Zainstaluj pakiety R:
   ```r
   install.packages(c("tidyverse", "randomForest", "rpart", "rpart.plot", "pROC", "caret"))
   ```
3. Uruchom skrypty z katalogu głównego repozytorium, np. `source("R/03_luflow_binary.R")`.

Pełne zbiory mają miliony wierszy — skrypty losują próbkę (5–20%), żeby zmieścić się w pamięci zwykłego laptopa. Wyniki są powtarzalne (`set.seed(123)`).

## Ograniczenia

Jeden algorytm (proof of concept, nie porównanie modeli), eksperyment offline na historycznych danych, pominięte bardzo rzadkie ataki (np. Heartbleed, Infiltration), a porównanie zbiorów obciąża różnica zadań (14 klas vs 2).

---

## 🇬🇧 English summary

With over 90% of web traffic now encrypted, intrusion detection can no longer rely on reading packet contents. This master’s thesis tests whether **flow metadata alone** is enough. The same Random Forest (50 trees, R) was evaluated on two telemetry paradigms: classic time-volumetric statistics (**CIC-IDS2017**, ~80 features, 14 classes) and lightweight telemetry with **entropy** (**LUFlow**, 11 features, real honeypot traffic, binary).

**Results:** 99.52% vs **99.72%** accuracy; on LUFlow precision 99.92%, recall 99.16%, F1 99.54%. Most importantly, the entropy-based setup cut the **false-positive rate nearly sixfold** (0.197% → 0.034%), which directly reduces alert fatigue in a SOC. Destination port and aggregated flow entropy were the strongest predictors. The main limit is application-layer attacks (web brute force, XSS), which look like normal HTTPS at L3/L4 — pointing to a hybrid design where telemetry triggers DPI only for borderline cases.
