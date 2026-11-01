# =======================================================================
# PRACA MAGISTERSKA: Analiza pełnego zbioru CIC-IDS2017
# =======================================================================

# --- 1. ŁADOWANIE BIBLIOTEK ---
# Jeśli którejś brakuje, wpisz w konsoli: install.packages("nazwa")
library(tidyverse)
library(caret)
library(randomForest)

# --- 2. WCZYTANIE I POŁĄCZENIE WSZYSTKICH PLIKÓW (5 DNI) ---
# Wpisz ścieżkę do FOLDERU, w którym znajdują się ROZPAKOWANE pliki CSV z CIC-IDS2017
# Używaj ukośników '/' !
folder_path <- "data/CIC-IDS2017"

# Pobranie listy plików CSV w folderze
file_list <- list.files(path = folder_path, pattern = "*.csv", full.names = TRUE)

print("KROK 1: Wczytywanie i łączenie plików... (To może potrwać kilka minut, bądź cierpliwa)")

# Wczytanie wszystkich plików i złączenie ich w jedną ogromną tabelę
df_all <- file_list %>%
  lapply(read.csv, stringsAsFactors = FALSE, check.names = FALSE) %>%
  bind_rows()

print(paste("Załadowano łącznie:", nrow(df_all), "wierszy!"))

# --- 3. CZYSZCZENIE I PRZETWARZANIE DANYCH (PREPROCESSING) ---
print("KROK 2: Czyszczenie danych (Usuwanie IP, naprawa błędów, konwersja typów)...")

# A. Usunięcie spacji z nazw kolumn
colnames(df_all) <- trimws(colnames(df_all))

# B. Usunięcie kolumn, które powodują przeuczenie (chcemy badać zachowanie, nie IP)
cols_to_remove <- c("Flow ID", "Source IP", "Source Port", "Destination IP", "Destination Port", "Timestamp")
df_all <- df_all %>% select(-any_of(cols_to_remove))

# C. Ekstrakcja etykiety (Target) i zmiana nazwy na "Class"
names(df_all)[names(df_all) == "Label"] <- "Class"
label_col <- df_all$Class
df_all$Class <- NULL

# D. Zabezpieczenie przed błędami generatora CICFlowMeter ("Infinity" i "NaN")
# Zmieniamy wszystko na wartości liczbowe, błędy staną się NA
df_all[] <- lapply(df_all, function(x) as.numeric(as.character(x)))
df_all$Class <- as.factor(label_col)

# E. Usunięcie wierszy z błędami (NA)
df_all <- na.omit(df_all)

# --- 4. PRÓBKOWANIE (DOWNSAMPLING) - WERSJA DPLYR ---
print("KROK 3: Redukcja wielkości zbioru do analizy ML (Wersja bez Caret)...")

set.seed(123) # Dla powtarzalności wyników

# Warstwowe losowanie 5% danych za pomocą biblioteki dplyr (zachowuje proporcje klas)
df_sampled <- df_all %>%
  group_by(Class) %>%
  sample_frac(0.05) %>%
  ungroup()

print("Rozkład klas (typów ataków) w próbce użytej do uczenia:")
print(table(df_sampled$Class))

# --- 5. PODZIAŁ NA TRENING (70%) I TEST (30%) - WERSJA BAZOWA R ---
print("KROK 4: Dzielenie danych na treningowe i testowe...")

set.seed(123)
# Zwykłe losowanie indeksów do zbioru treningowego (70%)
train_size <- floor(0.7 * nrow(df_sampled))
train_indices <- sample(seq_len(nrow(df_sampled)), size = train_size)

dataTrain <- df_sampled[train_indices, ]
dataTest  <- df_sampled[-train_indices, ]

# Konwersja etykiet na factor (wymóg dla algorytmu Random Forest)
dataTrain$Class <- as.factor(dataTrain$Class)
dataTest$Class <- as.factor(dataTest$Class)

# --- 6. UCZENIE MASZYNOWE (MODEL RANDOM FOREST) ---
print("KROK 5: Trenowanie Lasu Losowego... (Teraz możesz iść na kawę ☕)")
# 1. Usuwamy "puste" klasy ze zbioru treningowego (pozbywamy się rzadkich ataków, których tu nie ma)
dataTrain$Class <- droplevels(dataTrain$Class)

# 2. Sprawdzamy, jakie klasy zostały w zbiorze treningowym
valid_classes <- levels(dataTrain$Class)
print(paste("Klasy, na których trenujemy model:", paste(valid_classes, collapse=", ")))

# 3. Usuwamy ze zbioru testowego przypadki tych rzadkich ataków, 
# których model nie miał szansy się nauczyć (inaczej program wyrzuci błąd przy testowaniu)
dataTest <- dataTest[dataTest$Class %in% valid_classes, ]

# 4. Ujednolicamy definicje klas w zbiorze testowym, by idealnie pasowały do treningowego
dataTest$Class <- factor(dataTest$Class, levels = valid_classes)
print("Ostateczne czyszczenie nieskończoności (Inf) i braków danych (NA)...")

# 1. Zamiana nieskończoności na NA i usunięcie wszystkich wierszy z błędami (Trening)
dataTrain <- dataTrain %>%
  mutate_if(is.numeric, ~ifelse(is.infinite(.), NA, .)) %>%
  drop_na()

# 2. To samo dla zbioru testowego
dataTest <- dataTest %>%
  mutate_if(is.numeric, ~ifelse(is.infinite(.), NA, .)) %>%
  drop_na()

# 3. Zabezpieczenie przed pustymi klasami (na wypadek, gdyby usunięcie błędów usunęło jakąś rzadką klasę)
dataTrain$Class <- droplevels(dataTrain$Class)
valid_classes <- levels(dataTrain$Class)
dataTest <- dataTest[dataTest$Class %in% valid_classes, ]
dataTest$Class <- factor(dataTest$Class, levels = valid_classes)

# 4. START TRENOWANIA!
print("Uruchamiam Random Forest...")
rf_model <- randomForest(Class ~ ., data = dataTrain, ntree = 50, importance = TRUE)

# Używamy ntree=50 (50 drzew) dla optymalnego czasu.
print("Zakończono trenowanie!")
print(rf_model)

# --- 7. EWALUACJA MODELU NA ZBIORZE TESTOWYM ---
print("KROK 6: Predykcja i generowanie wyników...")
predictions <- predict(rf_model, dataTest)

# Generowanie Macierzy Pomyłek i statystyk (Accuracy, Sensitivity itp.)
# 1. Tworzenie macierzy pomyłek za pomocą bazowej funkcji 'table'
cm_table <- table(Predykcja = predictions, Rzeczywistosc = dataTest$Class)

print("--- Macierz Pomyłek ---")
print(cm_table)

# 2. Obliczenie ogólnej dokładności (Accuracy)
# (Suma poprawnych trafień na przekątnej podzielona przez wszystkie przypadki)
accuracy <- sum(diag(cm_table)) / sum(cm_table)
print(paste("Ogólna Dokładność (Accuracy):", round(accuracy * 100, 2), "%"))

# 3. Wizualizacja Macierzy Pomyłek (do pracy magisterskiej)
# Zamieniamy tabelę na format zrozumiały dla ggplot2
cm_df <- as.data.frame(cm_table)

# Rysujemy elegancki wykres kafelkowy (Heatmap)
ggplot(data = cm_df, aes(x = Rzeczywistosc, y = Predykcja)) +
  geom_tile(aes(fill = Freq), color = "white") +
  geom_text(aes(label = Freq), vjust = 0.5, size = 4) +
  scale_fill_gradient(low = "white", high = "#2c3e50") +
  theme_minimal() +
  labs(title = "Macierz Pomyłek - Model Klasyfikacji CIC-IDS2017",
       x = "Rzeczywista Klasa Ataku",
       y = "Klasa Przewidziana przez Model",
       fill = "Liczba \nprzypadków") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 10),
        axis.text.y = element_text(size = 10),
        plot.title = element_text(face = "bold", hjust = 0.5))


# --- 8. WIZUALIZACJA DO PRACY MAGISTERSKIEJ ---
# Generowanie kluczowego wykresu, który wkleisz do pracy:
print("KROK 7: Generowanie wykresu ważności cech...")
varImpPlot(rf_model, 
           sort = TRUE, 
           n.var = 15, 
           main = "Top 15 Najważniejszych Cech Telemetrycznych (CIC-IDS2017)",
           pch = 19, col = "darkblue")



print("Koniec! Wyniki są gotowe do opisania w pracy.")

