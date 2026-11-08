"""Минимальные контракты поставки; никаких запросов к настоящему MAX."""
import importlib
import os
import pkgutil
import ssl
import unittest
from pathlib import Path
from unittest.mock import patch
from app import bootstrap
from app.config import max_tls_context
from app.db import Database
from app.handlers import Deps, build_router
from scripts.smoke_test import OfflineMAX

class DeliveryTests(unittest.TestCase):
    def test_all_modules_resources_and_handlers(self):
        import app
        for module in pkgutil.walk_packages(app.__path__, "app."):
            importlib.import_module(module.name)
        context=max_tls_context({"MAX_CA_FILE":"certificates/russian_trusted_root_ca.pem"})
        self.assertEqual(context.verify_mode,ssl.CERT_REQUIRED)
        self.assertTrue(context.check_hostname)
        from PIL import Image
        with Image.open(Path("assets/welcome.png")) as image:
            image.verify()
        router=build_router(Deps.create(OfflineMAX(),Database(os.environ["TEST_DATABASE_URL"])))
        self.assertEqual({type(h).__name__ for h in router.handlers},
                         {"AdminHandler","CommunityHandler","HomeworkHandler","RegistrationHandler",
                          "CalendarHandler","ScheduleHandler","QuestionsHandler"})
    def test_missing_token_never_creates_transport(self):
        with patch.object(bootstrap,"load_config",return_value={}), patch.object(bootstrap,"MaxClient") as client:
            self.assertEqual(bootstrap.main(),1)
            client.assert_not_called()
    def test_migrations_and_no_polling_lease_left(self):
        db=Database(os.environ["TEST_DATABASE_URL"])
        db.check_schema()
        with db.connect() as conn:
            self.assertEqual(conn.execute("SELECT count(*) FROM schema_migrations").fetchone(),(7,))
            self.assertEqual(conn.execute("SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND classid=17181017 AND objsubid=2 AND granted").fetchone(),(0,))
