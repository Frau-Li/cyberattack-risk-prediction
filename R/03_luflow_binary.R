# =======================================================================
# PRACA MAGISTERSKA: Analiza zbioru LUFlow (10 dni połączonych)
# =======================================================================

library(tidyverse)
library(randomForest)

# --- 1. WCZYTANIE I POŁĄCZENIE PLIKÓW ---
# Wpisz ścieżkę do folderu, w którym masz 10 plików z LUFlow (pamiętaj o ukośnikach '/')
folder_path_lu <- "data/LUFlow"

print("KROK 1: Wczytywanie i łączenie 10 dni zbioru LUFlow...")
file_list_lu <- list.files(path = folder_path_lu, pattern = "*.csv", full.names = TRUE)

df_lu_all <- file_list_lu %>%
  lapply(read.csv, stringsAsFactors = FALSE) %>%
  bind_rows()

print(paste("Udało się! Załadowano łącznie:", nrow(df_lu_all), "wierszy."))

# --- 2. CZYSZCZENIE I PREPROCESSING ---
print("KROK 2: Czyszczenie danych (Usuwanie IP, czasów, filtrowanie klas)...")

# A. Usunięcie kolumn identyfikacyjnych (zapobiega przeuczeniu)
cols_to_drop_lu <- c("src_ip", "dest_ip", "time_start", "time_end")
df_lu_all <- df_lu_all %>% select(-any_of(cols_to_drop_lu))

# B. Zmiana nazwy kolumny celu
names(df_lu_all)[names(df_lu_all) == "label"] <- "Class"

# C. Filtrowanie klas: Zostawiamy tylko pewny ruch (benign i malicious), wyrzucamy "outlier"
df_lu_all <- df_lu_all %>% filter(Class %in% c("benign", "malicious"))

# D. Zabezpieczenie nazw kolumn i konwersja do numeryków
names(df_lu_all) <- make.names(names(df_lu_all))
label_col_lu <- df_lu_all$Class
df_lu_all$Class <- NULL

# Zamiana na liczby (błędy staną się NA)
df_lu_all[] <- lapply(df_lu_all, function(x) as.numeric(as.character(x)))
df_lu_all$Class <- as.factor(label_col_lu)

# E. Ostateczne czyszczenie nieskończoności (Inf) i braków (NA)
df_lu_all <- df_lu_all %>%
  mutate_if(is.numeric, ~ifelse(is.infinite(.), NA, .)) %>%
  drop_na()

print("Rozkład klas po wyczyszczeniu i odrzuceniu outlierów:")
print(table(df_lu_all$Class))

# --- 3. PRÓBKOWANIE (OCHRONA PAMIĘCI RAM) ---
print("KROK 3: Losowanie próbki do treningu (aby nie zawiesić komputera)...")

set.seed(123)
# 10 dni to wciąż ogromna liczba danych. Losujemy 10% zachowując proporcje klas.
# (Jeśli masz mocny komputer, możesz zmienić 0.10 na 0.20 lub więcej)
df_lu_sampled <- df_lu_all %>%
  group_by(Class) %>%
  sample_frac(0.10) %>%
  ungroup()

print(paste("Do treningu i testów użyjemy:", nrow(df_lu_sampled), "wierszy."))

# --- 4. PODZIAŁ NA ZBIÓR TRENINGOWY I TESTOWY (70/30) ---
print("KROK 4: Dzielenie danych...")
set.seed(123)

train_size_lu <- floor(0.7 * nrow(df_lu_sampled))
train_indices_lu <- sample(seq_len(nrow(df_lu_sampled)), size = train_size_lu)

dataTrain_lu <- df_lu_sampled[train_indices_lu, ]
dataTest_lu  <- df_lu_sampled[-train_indices_lu, ]

# Upewnienie się, że etykiety to czyste faktory
dataTrain_lu$Class <- droplevels(as.factor(dataTrain_lu$Class))
valid_classes_lu <- levels(dataTrain_lu$Class)
dataTest_lu <- dataTest_lu[dataTest_lu$Class %in% valid_classes_lu, ]
dataTest_lu$Class <- factor(dataTest_lu$Class, levels = valid_classes_lu)

# --- 5. TRENOWANIE MODELU RANDOM FOREST ---
print("KROK 5: Trenowanie modelu (To może chwilę potrwać ☕)...")
rf_model_lu <- randomForest(Class ~ ., data = dataTrain_lu, ntree = 50, importance = TRUE)
print("Zakończono trenowanie!")

# --- 6. EWALUACJA (BEZ PAKIETU CARET) ---
print("KROK 6: Ocena skuteczności i predykcja...")
predictions_lu <- predict(rf_model_lu, dataTest_lu)

cm_table_lu <- table(Predykcja = predictions_lu, Rzeczywistosc = dataTest_lu$Class)
print("--- Macierz Pomyłek (LUFlow) ---")
print(cm_table_lu)

accuracy_lu <- sum(diag(cm_table_lu)) / sum(cm_table_lu)
print(paste("Ogólna Dokładność (Accuracy):", round(accuracy_lu * 100, 2), "%"))

# --- 7. WIZUALIZACJE DO PRACY MAGISTERSKIEJ ---
print("KROK 7: Generowanie wykresów...")

# Heatmapa (Macierz Pomyłek)
cm_df_lu <- as.data.frame(cm_table_lu)
plot_cm <- ggplot(data = cm_df_lu, aes(x = Rzeczywistosc, y = Predykcja)) +
  geom_tile(aes(fill = Freq), color = "white") +
  geom_text(aes(label = Freq), vjust = 0.5, size = 5) +
  scale_fill_gradient(low = "white", high = "#27ae60") +
  theme_minimal() +
  labs(title = "Macierz Pomyłek - Klasyfikacja Binarna (LUFlow)",
       x = "Rzeczywista Klasa",
       y = "Klasa Przewidziana",
       fill = "Ilość") +
  theme(plot.title = element_text(face = "bold", hjust = 0.5))
print(plot_cm)

# Kluczowy wykres do opisania w pracy:
varImpPlot(rf_model_lu, 
           sort = TRUE, 
           main = "Istotność Cech Telemetrycznych (LUFlow)",
           pch = 19, col = "darkgreen")

print("Gotowe! Możesz skopiować wyniki i przejść do opisywania.")

