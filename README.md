# Backup Script per Azure Blob Storage

## Descrizione

Questo progetto contiene due script Bash per la gestione dei backup e del ripristino di una directory locale verso Azure Blob Storage utilizzando **rclone**.

1. **`backup_script.sh`**:
   - Crea backup automatici completi (full) e incrementali.
   - Gestisce la rotazione dei backup, mantenendo uno storico di 14 giorni.
   - Invia notifiche email in caso di errori.

2. **`restore_script.sh`**:
   - Ripristina lo stato dei dati a una data specifica combinando backup completi e incrementali.
   - Mostra i backup disponibili se non viene fornita una data.

---

## Funzionalità principali

### `backup_script.sh`

- **Backup completi**: Una copia completa della directory sorgente viene eseguita ogni Domenica.
- **Backup incrementali**: Negli altri giorni vengono salvati solo i cambiamenti rispetto al backup precedente.
- **Rotazione dei backup remoti**: I backup più vecchi di 14 giorni vengono eliminati da Azure Blob Storage.
- **Log dettagliati**: Ogni operazione viene registrata in log compatibili con **logrotate**.
- **Notifiche via email**: Errori di upload o pulizia vengono notificati tramite email.

### `restore_script.sh`

- **Ripristino flessibile**: Permette di ripristinare lo stato dei dati a una data specifica.
- **Identificazione automatica dei backup**: Trova il full backup più recente e gli incrementali necessari.
- **Gestione degli errori**: Se mancano incrementali o full backup, segnala l’impossibilità di completare il ripristino.
- **Elenco dei backup**: Mostra i backup disponibili se non viene fornita una data.

---

## Requisiti

- **Bash** (supporto per `set -euo pipefail`)
- **rclone**: Configurato con un remote chiamato `azure` per comunicare con Azure Blob Storage.
- **tar** e **gzip**: Per creare e gestire archivi compressi.
- **mail** o **mailx**: Per inviare notifiche via email.
- **cron**: Per schedulare il backup.
- **logrotate**: Per la gestione dei file di log.

---

## Installazione dei prerequisiti

### 1. Aggiorna il sistema
```bash
sudo apt update && sudo apt upgrade -y
```

### 2. Installa gli strumenti necessari
```bash
sudo apt install -y bash tar gzip mailutils cron logrotate curl unzip
```

### 3. Installa rclone
```bash
curl https://rclone.org/install.sh | sudo bash
```
Dopo l'installazione, configura un remote chiamato `azure`:
```bash
rclone config
```
Segui le istruzioni per configurare l'accesso ad Azure Blob Storage.

### 4. Configura logrotate
Crea un file di configurazione per gestire i log dello script:
```bash
sudo nano /etc/logrotate.d/backup_script
```
Inserisci il seguente contenuto:
```
/var/log/backup_script.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    create 0640 root root
}
```

### 5. Crea le directory necessarie
Assicurati che le directory specificate nello script esistano:
```bash
sudo mkdir -p /srv/samba/share /srv/snapshot /tmp/backup
```

### 6. Rendi gli script eseguibili
Copia gli script nel sistema e rendili eseguibili:
```bash
chmod +x backup_script.sh restore_script.sh
```

---

## Configurazione degli Script

### `backup_script.sh`

Modifica i seguenti parametri nella sezione di configurazione dello script:

| Variabile        | Descrizione                                                                 | Valore di Default                  |
|-------------------|-----------------------------------------------------------------------------|------------------------------------|
| `SOURCE_DIR`      | Directory sorgente da sottoporre a backup.                                 | `/srv/samba/share`                |
| `SNAPSHOT_FILE`   | File utilizzato per il tracking dei backup incrementali.                   | `/srv/snapshot/snapshot.dat`      |
| `TMP_DIR`         | Directory temporanea per archivi locali.                                   | `/tmp/backup`                     |
| `REMOTE`          | Remote rclone configurato per il backup.                                   | `azure:nasbackup/backups`         |
| `RETENTION_DAYS`  | Numero di giorni di storico da mantenere su Azure.                         | `14`                              |
| `MAIL_TO`         | Indirizzo email per le notifiche in caso di errore.                        | `admin@example.com`               |

### `restore_script.sh`

Non sono richieste configurazioni particolari. Lo script usa il remote `azure` e funziona con i file creati da `backup_script.sh`.

---

## Utilizzo

### `backup_script.sh`

#### Esecuzione Manuale

Per eseguire lo script manualmente:
```bash
./backup_script.sh
```

#### Schedulazione con Cron

Per automatizzare il backup, aggiungi una voce al crontab. Ad esempio:
```bash
0 2 * * * /path/to/backup_script.sh >> /var/log/backup_script.log 2>&1
```
Questo comando eseguirà lo script ogni giorno alle 2:00, registrando l'output in un file di log.

### `restore_script.sh`

#### Mostrare i backup disponibili

Esegui lo script senza argomenti per visualizzare i backup presenti su Azure Blob Storage:
```bash
./restore_script.sh
```
Questo mostrerà un elenco dei file disponibili (full e incrementali) e istruzioni su come effettuare un restore.

#### Ripristinare a una data specifica

Per ripristinare lo stato dei dati a una data specifica:
```bash
./restore_script.sh <DATA_YYYYMMDD> <DIRECTORY_RIPRISTINO>
```
Esempio:
```bash
./restore_script.sh 20241215 /restore/dir
```
Questo ripristinerà i dati alla data 15 Dicembre 2024 (se i backup necessari sono disponibili).

---

## Dettagli Operativi

### `backup_script.sh`

1. **Backup Completo**:
   - Eseguito al primo avvio e ogni Domenica.
   - Archivia la directory sorgente in un file compresso chiamato `full-YYYYMMDD.tar.gz`.
   - Eliminando il file snapshot.dat, lo script procederà come al primo avvio, eseguendo di conseguenza un backup completo (full backup).

2. **Backup Incrementale**:
   - Eseguito nei giorni feriali.
   - Utilizza un file di snapshot per salvare solo i cambiamenti rispetto al backup completo.

3. **Upload**:
   - Utilizza **rclone** per copiare gli archivi compressi su Azure Blob Storage.

4. **Rotazione dei Backup**:
   - Elimina backup più vecchi di 14 giorni su Azure Blob Storage.

5. **Notifiche di Errore**:
   - Invio email all'indirizzo configurato in caso di errori durante upload o pulizia.

### `restore_script.sh`

1. **Identificazione del Full Backup**:
   - Trova il full backup più recente con data minore o uguale a quella specificata.

2. **Individuazione degli Incrementali**:
   - Cerca tutti gli incrementali con data compresa tra quella del full e la data specificata.

3. **Download ed Estrazione**:
   - Scarica il full backup e gli incrementali individuati.
   - Estrae prima il full, poi gli incrementali in ordine cronologico.

4. **Gestione dei Buchi nella Sequenza**:
   - Se manca un incrementale necessario, lo script effettua un restore parziale fino all’ultimo backup disponibile.

---

## Troubleshooting

### Problemi Comuni

1. **Errore: `rclone not found`**
   - **Causa**: `rclone` non è installato o non configurato.
   - **Soluzione**: Assicurati di aver installato `rclone` utilizzando il comando:
     ```bash
     curl https://rclone.org/install.sh | sudo bash
     ```
     Configura il remote `azure` con:
     ```bash
     rclone config
     ```

2. **Errore: Notifiche email non inviate**
   - **Causa**: `mail` o `mailx` non è configurato correttamente.
   - **Soluzione**:
     - Verifica che il pacchetto `mailutils` sia installato:
       ```bash
       sudo apt install mailutils
       ```
     - Assicurati che il sistema sia configurato per inviare email (es. configurando Postfix o un altro MTA).

3. **Backup non schedulato**
   - **Causa**: Lo script non è stato aggiunto correttamente al crontab.
   - **Soluzione**: Verifica il contenuto del crontab con:
     ```bash
     crontab -l
     ```
     Assicurati che il comando contenga il percorso assoluto dello script, ad esempio:
     ```bash
     0 2 * * * /path/to/backup_script.sh >> /var/log/backup_script.log 2>&1
     ```

### Restore con file mancanti

1. **Mancanza di incrementali intermedi**
   - **Comportamento**: Lo script procederà con il restore parziale fino all’ultimo incrementale disponibile. Tuttavia, non sarà possibile ottenere lo stato esatto della data richiesta.
   - **Soluzione**: Verifica la presenza di tutti gli incrementali con:
     ```bash
     rclone lsf azure:nasbackup/backups
     ```
     Identifica eventuali file mancanti e assicurati che il backup sia completo in futuro.

2. **Full backup non disponibile**
   - **Comportamento**: Se manca il full backup richiesto, lo script non può eseguire il restore.
   - **Soluzione**: Assicurati che i full backup vengano eseguiti regolarmente e che non vengano accidentalmente eliminati. Controlla la logica dello script di backup e verifica la presenza dei full nel container.


