#!/usr/bin/env bash
#
# Nome Script: backup_script.sh
# Descrizione:
#   Questo script esegue un backup di una cartella locale verso Azure Blob Storage.
#   Crea un backup completo settimanale (domenica) e incrementale negli altri giorni.
#   La prima volta che viene eseguito, se non trova lo snapshot, esegue comunque un full backup.
#   Mantiene uno storico dei backup fino a 14 giorni su Azure, eliminando i più vecchi.
#   In caso di errore, invia una notifica email.
#
# Data: 2024-12-10
# Autore: Costinel Ghita 
#
# Funzionalità principali:
# - Alla prima esecuzione (quando lo snapshot non esiste) esegue un full backup.
# - Backup full la Domenica, incrementali gli altri giorni.
# - Creazione archivi compressi con tar e snapshot per incrementali.
# - Upload su Azure Blob Storage tramite rclone.
# - Rotazione dei backup remoti in base alla data (14 giorni).
# - Log dettagliato, compatibile con logrotate.
# - Invio email di notifica in caso di errori.
#
# Requisiti:
# - rclone configurato con un remote "azure"
# - tar, gzip, mail (o mailx), cron per la schedulazione, logrotate per la gestione log.
#

set -euo pipefail

# Configurazioni
SOURCE_DIR="/srv/samba/share"
SNAPSHOT_FILE="/srv/snapshot/snapshot.dat"
TMP_DIR="/tmp/backup"
REMOTE="azure:nasbackup/backups"
RETENTION_DAYS=14
MAIL_TO="admin@example.com"

LOG_FILE="/var/log/backup.log"
exec >>"$LOG_FILE" 2>&1

TAR_BIN=$(command -v tar)
RCLONE_BIN=$(command -v rclone)
MAIL_BIN=$(command -v mail)

# Verifica requisiti base
if [ ! -d "$SOURCE_DIR" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERRORE: La directory $SOURCE_DIR non esiste." >&2
    exit 1
fi

if [ -z "$RCLONE_BIN" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERRORE: rclone non trovato nel PATH." >&2
    exit 1
fi

if [ -z "$MAIL_BIN" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] AVVISO: mail o mailx non trovati nel PATH. Non sarà possibile inviare notifiche via email." >&2
fi

mkdir -p "$TMP_DIR"

# Determina il giorno della settimana
# 0 = Domenica, 1 = Lunedì, ... 6 = Sabato
DAY_OF_WEEK=$(date +%w)
DATE_STR=$(date +%Y%m%d)

# Logica full/incrementale
if [ ! -f "$SNAPSHOT_FILE" ]; then
    BACKUP_TYPE="full"
    ARCHIVE_NAME="full-${DATE_STR}.tar.gz"
else
    if [ "$DAY_OF_WEEK" -eq 0 ]; then
        BACKUP_TYPE="full"
        ARCHIVE_NAME="full-${DATE_STR}.tar.gz"
        rm -f "$SNAPSHOT_FILE"
    else
        BACKUP_TYPE="incr"
        ARCHIVE_NAME="incr-${DATE_STR}.tar.gz"
    fi
fi

ARCHIVE_PATH="${TMP_DIR}/${ARCHIVE_NAME}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Inizio backup $BACKUP_TYPE per $SOURCE_DIR"

# Esegui il backup con tar incrementale usando -C e basename/dirname
# In questo modo la directory "share" sarà la radice del tar, evitando /srv/samba nel percorso
$TAR_BIN --listed-incremental="$SNAPSHOT_FILE" \
    -czf "$ARCHIVE_PATH" \
    -C "$(dirname "$SOURCE_DIR")" \
    "$(basename "$SOURCE_DIR")"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup $BACKUP_TYPE creato: $ARCHIVE_PATH"

# Upload su Azure Blob con rclone
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Upload su $REMOTE..."
if ! $RCLONE_BIN copy "$ARCHIVE_PATH" "$REMOTE"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERRORE: Upload fallito" >&2
    if [ -n "$MAIL_BIN" ]; then
        echo "Backup $BACKUP_TYPE del $DATE_STR FALLITO (upload)" | $MAIL_BIN -s "Backup Fallito" "$MAIL_TO"
    fi
    exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Upload completato con successo."

# Pulizia remota dei backup più vecchi di RETENTION_DAYS
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pulizia backup remoti più vecchi di ${RETENTION_DAYS} giorni..."
if ! $RCLONE_BIN delete --min-age "${RETENTION_DAYS}d" "$REMOTE"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERRORE: Pulizia remota non riuscita" >&2
    if [ -n "$MAIL_BIN" ]; then
        echo "Backup $BACKUP_TYPE del $DATE_STR completato ma pulizia remota fallita." | $MAIL_BIN -s "Backup - Errore Pulizia" "$MAIL_TO"
    fi
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pulizia completata o non necessaria."

# Pulizia locale del file creato
rm -f "$ARCHIVE_PATH"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup $BACKUP_TYPE completato con successo."
