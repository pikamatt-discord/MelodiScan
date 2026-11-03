import logging
import os
from pathlib import Path

logger = logging.getLogger(__name__)

SERVICE_ACCOUNT_PATH = Path(
    os.getenv(
        "GOOGLE_APPLICATION_CREDENTIALS",
        "/run/secrets/firebase/service-account.json",
    )
)


def send_task_notification(
    task_id: str,
    status: str,
    title: str,
    token: str | None,
    error_summary: str | None = None,
) -> None:
    if not token:
        return
    if not SERVICE_ACCOUNT_PATH.is_file():
        logger.warning(
            "Cannot notify completion of task %s: Firebase service account is not configured.",
            task_id,
        )
        return

    try:
        import firebase_admin
        from firebase_admin import credentials, messaging

        try:
            firebase_app = firebase_admin.get_app()
        except ValueError:
            firebase_app = firebase_admin.initialize_app(
                credentials.Certificate(str(SERVICE_ACCOUNT_PATH))
            )

        succeeded = status == "STATUS_COMPLETED"
        message = messaging.Message(
            notification=messaging.Notification(
                title="Partition prête" if succeeded else "Échec de l’analyse",
                body=(
                    f"{title} est prête à être écoutée."
                    if succeeded
                    else error_summary or "Ouvrez MelodiScan pour consulter les détails."
                ),
            ),
            data={
                "task_id": task_id,
                "status": status,
                "title": title,
            },
            token=token,
        )
        messaging.send(message, app=firebase_app)
    except Exception:
        logger.exception("Firebase push notification failed for task %s.", task_id)
