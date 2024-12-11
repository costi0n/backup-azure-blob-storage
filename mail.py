
#!/usr/bin/env python3

import sys
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime

# Configurazione SMTP
SMTP_SERVER = "smtp.example.com"
SMTP_PORT = 587
SMTP_USER = "user@example.com"
SMTP_PASS = "password"
FROM_EMAIL = "backup@example.com"
TO_EMAIL = "admin@example.com"
EMAIL_SUBJECT = "Report Backup"  # Oggetto specifico

def send_email(subject, to_email, plain_message, html_message):
    try:
        # Creazione del messaggio multipart (testo + HTML)
        msg = MIMEMultipart("alternative")
        msg['From'] = FROM_EMAIL
        msg['To'] = to_email
        msg['Subject'] = subject

        # Aggiungere il testo semplice e il messaggio HTML
        part1 = MIMEText(plain_message, 'plain')
        part2 = MIMEText(html_message, 'html')
        msg.attach(part1)
        msg.attach(part2)

        # Connetti al server SMTP e invia l'email
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.starttls()  # Attiva TLS
            server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
        print("Email inviata con successo.")
    except Exception as e:
        print(f"Errore nell'invio dell'email: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    # Leggi il messaggio dal pipe
    input_message = sys.stdin.read()

    # Formatta la data e l'ora attuali
    now = datetime.now()
    formatted_date = now.strftime("%Y-%m-%d")
    formatted_time = now.strftime("%H:%M:%S")

    # Corpo del messaggio testo semplice
    plain_message = (
        f"Report backup del {formatted_date} ore {formatted_time}\n"
        "--------------------------------------------\n"
        f"{input_message}\n"
        "--------------------------------------------\n"
        "Grazie,\nIl tuo sistema di backup"
    )

    # Corpo del messaggio HTML
    html_message = f"""
    <html>
    <body>
        <p><strong>Report backup del {formatted_date} ore {formatted_time}</strong></p>
        <hr>
        <pre>{input_message}</pre>
        <hr>
        <p>Grazie,<br>Il tuo sistema di backup</p>
    </body>
    </html>
    """

    # Invia l'email
    send_email(EMAIL_SUBJECT, TO_EMAIL, plain_message, html_message)

if __name__ == "__main__":
    main()
