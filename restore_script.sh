#!/usr/bin/env bash
#
# Nome Script: restore_script.sh
# Descrizione:
#   Questo script consente di ripristinare i dati da un set di backup full e incrementali
#   memorizzati su Azure Blob Storage.
#
# Data: 2024-12-11
# Autore: Costinel Ghita <costinel@netcare.it>
#
# Funzionamento:
#   1. Data una data di riferimento (YYYYMMDD) e una directory di destinazione, lo script
#      trova il full backup più recente uguale o precedente a tale data.
#   2. Trova tutti gli incrementali successivi a quel full e fino alla data di restore inclusa.
#   3. Scarica full e incrementali da Azure Blob Storage.
#   4. Estrae prima il full, poi gli incrementali in ordine cronologico, ricostruendo lo stato
#      dei dati alla data specificata.
#
# Presupposti:
#   - I full backup hanno nome: full-YYYYMMDD.tar.gz
#   - Gli incrementali hanno nome: incr-YYYYMMDD.tar.gz
#   - Lo script di backup utilizza tar con --listed-incremental.
#
# Requisiti:
#   - rclone configurato con un remote "azure" (stesso remote usato per i backup).
#   - tar installato.
#
# Esempio di utilizzo:
#   ./restore_script.sh 20241215 /restore/dir
#   Questo tenterà di ripristinare lo stato dei dati al 15 Dicembre 2024.
#
# Note:
#   - Se non viene trovato nessun full backup antecedente o uguale alla data specificata,
#     lo script non può procedere.
#   - Se esistono incrementali con la stessa data del full, verranno applicati
#     (questa logica può essere adattata in base alle necessità).
#

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Utilizzo: $0 <DATA_YYYYMMDD> <DIRECTORY_RIPRISTINO>"
    exit 1
fi

RESTORE_DATE="$1"
RESTORE_DIR="$2"

# Verifica formato della data (semplice check sulla lunghezza e presenza di soli numeri)
if ! [[ "$RESTORE_DATE" =~ ^[0-9]{8}$ ]]; then
    echo "ERRORE: La data deve essere nel formato YYYYMMDD, ricevuto: $RESTORE_DATE"
    exit 1
fi

# Controlla e crea la directory di restore se non esiste
if [ ! -d "$RESTORE_DIR" ]; then
    echo "La directory $RESTORE_DIR non esiste, la creo..."
    mkdir -p "$RESTORE_DIR"
fi

TMP_DIR="/tmp/restore_$$"
mkdir -p "$TMP_DIR"

REMOTE="azure:nasbackup/backups"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Inizio procedura di restore alla data $RESTORE_DATE"

# Recupera lista dei backup dal remote
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Recupero lista backup da Azure..."
BACKUPS=$(rclone lsf "$REMOTE")

# Filtra i file per separare full e incrementali
FULL_BACKUPS=$(echo "$BACKUPS" | grep '^full-[0-9]\{8\}\.tar\.gz$' || true)
INCR_BACKUPS=$(echo "$BACKUPS" | grep '^incr-[0-9]\{8\}\.tar\.gz$' || true)

# Trova il full backup più recente <= RESTORE_DATE
# Logica:
# - Per ogni full backup FB, estrai la data FB_DATE.
# - Se FB_DATE <= RESTORE_DATE e FB_DATE è maggiore della precedente full trovata, aggiorna LAST_FULL.
LAST_FULL=""
for FB in $FULL_BACKUPS; do
    FB_DATE=$(echo "$FB" | sed -E 's/full-([0-9]{8})\.tar\.gz/\1/')
    if [ "$FB_DATE" -le "$RESTORE_DATE" ]; then
        if [ -z "$LAST_FULL" ]; then
            LAST_FULL="$FB"
        else
            OLD_DATE=$(echo "$LAST_FULL" | sed -E 's/full-([0-9]{8})\.tar\.gz/\1/')
            if [ "$FB_DATE" -gt "$OLD_DATE" ]; then
                LAST_FULL="$FB"
            fi
        fi
    fi
done

if [ -z "$LAST_FULL" ]; then
    echo "ERRORE: Non è stato trovato alcun full backup antecedente o uguale alla data $RESTORE_DATE."
    echo "Impossibile procedere al restore."
    exit 1
fi

FULL_DATE=$(echo "$LAST_FULL" | sed -E 's/full-([0-9]{8})\.tar\.gz/\1/')

# Trova tutti gli incrementali >= FULL_DATE e <= RESTORE_DATE
# Cambiata la condizione per includere anche un incrementale con la stessa data del full.
RESTORE_INCR=()
for IB in $INCR_BACKUPS; do
    IB_DATE=$(echo "$IB" | sed -E 's/incr-([0-9]{8})\.tar\.gz/\1/')
    if [ "$IB_DATE" -ge "$FULL_DATE" ] && [ "$IB_DATE" -le "$RESTORE_DATE" ]; then
        RESTORE_INCR+=("$IB")
    fi
done

# Ordina gli incrementali per data
if [ ${#RESTORE_INCR[@]} -gt 1 ]; then
    RESTORE_INCR=($(printf '%s\n' "${RESTORE_INCR[@]}" | sort))
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Full backup individuato: $LAST_FULL"
if [ ${#RESTORE_INCR[@]} -gt 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Incrementali da applicare nell'ordine: ${RESTORE_INCR[*]}"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Nessun incrementale da applicare."
fi

# Download del full backup
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Scarico il full backup..."
rclone copy "$REMOTE/$LAST_FULL" "$TMP_DIR"

# Download degli incrementali, se presenti
if [ ${#RESTORE_INCR[@]} -gt 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Scarico incrementali..."
    for IB in "${RESTORE_INCR[@]}"; do
        rclone copy "$REMOTE/$IB" "$TMP_DIR"
    done
fi

# Estrazione del full
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Estrazione full backup..."
# Per il restore non usiamo lo snapshot file del backup, ma /dev/null
# così da non aggiornarne lo stato. Estraiamo i dati così come sono.
tar --listed-incremental=/dev/null -xzf "$TMP_DIR/$LAST_FULL" -C "$RESTORE_DIR"

# Estrazione incrementali in ordine
if [ ${#RESTORE_INCR[@]} -gt 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Estrazione incrementali..."
    for IB in "${RESTORE_INCR[@]}"; do
        tar --listed-incremental=/dev/null -xzf "$TMP_DIR/$IB" -C "$RESTORE_DIR"
    done
fi

# Pulizia della directory temporanea
rm -rf "$TMP_DIR"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restore completato con successo nella directory $RESTORE_DIR."
echo "I dati dovrebbero riflettere lo stato al $RESTORE_DATE."