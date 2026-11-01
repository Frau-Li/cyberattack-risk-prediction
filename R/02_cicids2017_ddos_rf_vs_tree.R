if (!require("randomForest")) install.packages("randomForest")
if (!require("rpart")) install.packages("rpart")
if (!require("rpart.plot")) install.packages("rpart.plot")
if (!require("pROC")) install.packages("pROC")
if (!require("ggplot2")) install.packages("ggplot2")

library(randomForest)
library(rpart)
library(rpart.plot)
library(pROC)
library(ggplot2)

# --- KONFIGURACJA ---
# Wpisz tutaj ścieżkę do swojego pliku (np. tego z DDoS)
FILE_PATH <- "data/CIC-IDS2017/Friday-WorkingHours-Afternoon-DDos.pcap_ISCX.csv"

# --- 1. WCZYTANIE DANYCH ---
message(">>> Wczytywanie danych...")
df <- read.csv(FILE_PATH, stringsAsFactors = FALSE)

# Czyszczenie
colnames(df) <- trimws(colnames(df)) # Usuń spacje z nazw kolumn
is.na(df) <- do.call(cbind, lapply(df, is.infinite)) # Zamień Inf na NA
df <- na.omit(df) # Usuń NA

# Sprawdzenie etykiety
if("Label" %in% colnames(df)){
  df$Label <- as.factor(df$Label)
} else {
  stop("Błąd: Nie znaleziono kolumny 'Label'.")
}

# Usuwanie kolumn identyfikacyjnych
cols_to_remove <- c("Destination Port", "Flow ID", "Source IP", "Source Port", 
                    "Destination IP", "Timestamp")
df <- df[, !(names(df) %in% cols_to_remove)]

# --- 2. PODZIAŁ DANYCH (Metoda bez pakietu caret) ---
# Jeśli zbiór jest duży, bierzemy próbkę (np. 20%) dla szybkości
set.seed(123)
if(nrow(df) > 50000) {
  message(">>> Pobieranie próbki danych (20%)...")
  sample_rows <- sample(nrow(df), 0.2 * nrow(df))
  df_work <- df[sample_rows, ]
} else {
  df_work <- df
}

message(">>> Podział na trening (70%) i test (30%)...")
# Ręczny podział danych
sample_size <- floor(0.7 * nrow(df_work))
train_ind <- sample(seq_len(nrow(df_work)), size = sample_size)

trainSet <- df_work[train_ind, ]
testSet  <- df_work[-train_ind, ]

message(paste("Treningowe:", nrow(trainSet), "| Testowe:", nrow(testSet)))

# --- 3. MODEL RANDOM FOREST ---
message("\n>>> Trenowanie Random Forest...")
rf_model <- randomForest(Label ~ ., data = trainSet, ntree = 50, importance = TRUE)

# Predykcja
rf_pred <- predict(rf_model, testSet)
rf_prob <- predict(rf_model, testSet, type = "prob")

# --- 4. WYNIKI I MACIERZ POMYŁEK (Ręcznie obliczana) ---
message("\n--- WYNIKI ---")
cm <- table(Reference = testSet$Label, Prediction = rf_pred)
print(cm)

# Obliczanie dokładności (Accuracy)
accuracy <- sum(diag(cm)) / sum(cm)
message(paste("Accuracy (Dokładność):", round(accuracy * 100, 2), "%"))

# --- 5. MODEL DRZEWA DECYZYJNEGO (Porównanie) ---
message("\n>>> Trenowanie Drzewa Decyzyjnego...")
tree_model <- rpart(Label ~ ., data = trainSet, method = "class")
tree_pred <- predict(tree_model, testSet, type = "class")
cm_tree <- table(Reference = testSet$Label, Prediction = tree_pred)
acc_tree <- sum(diag(cm_tree)) / sum(cm_tree)

message(paste("Accuracy Drzewa:", round(acc_tree * 100, 2), "%"))

# --- 6. GENEROWANIE WYKRESÓW ---

# A. Ważność cech
png("Wykres_Waznosci.png", width = 800, height = 600)
varImpPlot(rf_model, main = "Ważność Cech - Wykrywanie Ataku")
dev.off()

# B. Krzywa ROC
if(length(levels(df_work$Label)) == 2) {
  png("Wykres_ROC.png", width = 600, height = 600)
  target_class <- levels(df_work$Label)[2] # Np. DDoS
  roc_obj <- roc(testSet$Label, rf_prob[, target_class])
  plot(roc_obj, col="blue", lwd=2, main=paste("ROC Curve -", target_class))
  text(0.5, 0.5, paste("AUC =", round(auc(roc_obj), 4)), cex=1.2)
  dev.off()
}

# C. Drzewo
png("Wykres_Drzewa.png", width = 800, height = 600)
rpart.plot(tree_model, main = "Drzewo Decyzyjne")
dev.off()

