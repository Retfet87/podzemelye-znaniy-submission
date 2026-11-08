"""Настоящий bootstrap с подставным MAX; используется только тестами поставки."""
import os
import time
from unittest.mock import patch
from app import bootstrap
from scripts.smoke_test import OfflineMAX

class Client(OfflineMAX):
    def __init__(self, token, context):
        super().__init__()
        self.ready = False
    def get_updates(self, marker):
        if not self.ready:
            print("OFFLINE_READY", flush=True)
            self.ready = True
        time.sleep(0.2)
        return [], marker

if __name__ == "__main__":
    config = {"DATABASE_URL": os.environ["TEST_DATABASE_URL"],
              "MAX_BOT_TOKEN": "offline-test-no-network"}
    with patch.object(bootstrap, "load_config", return_value=config), patch.object(bootstrap, "MaxClient", Client):
        raise SystemExit(bootstrap.main())
