"""Behaviour checks for missing, failed, stale and completed recovery points."""
import datetime
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location("backup_freshness", pathlib.Path(__file__).parents[1] / "backup-freshness.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BackupFreshnessTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime(2026, 11, 25, 12, tzinfo=datetime.timezone.utc)
        self.config = {"resources": {"efs": "arn:fixture:efs"}, "warning_hours": 26, "critical_hours": 36}

    def point(self, hours, status="COMPLETED"):
        return {"ResourceArn": "arn:fixture:efs", "Status": status,
                "CreationDate": (self.now - datetime.timedelta(hours=hours)).isoformat()}

    def test_no_recovery_point_is_critical(self):
        self.assertTrue(module.check(self.config, [], self.now)[0].startswith('2 "Backup efs"'))

    def test_failed_point_does_not_hide_stale_backup(self):
        result = module.check(self.config, [self.point(1, "FAILED"), self.point(40)], self.now)[0]
        self.assertTrue(result.startswith('2 "Backup efs" age_hours=40.0'))

    def test_warning_then_recovery(self):
        self.assertTrue(module.check(self.config, [self.point(27)], self.now)[0].startswith('1 '))
        self.assertTrue(module.check(self.config, [self.point(27), self.point(2)], self.now)[0].startswith('0 '))

    def test_future_timestamp_is_not_reported_healthy(self):
        with self.assertRaises(ValueError):
            module.check(self.config, [self.point(-1)], self.now)

    def test_new_failed_job_alerts_before_backup_becomes_stale(self):
        jobs = [{"ResourceArn": "arn:fixture:efs", "CreationDate": "2026-11-25T10:00:00Z", "State": "FAILED"}]
        self.assertTrue(module.check_jobs(self.config, jobs)[0].startswith('2 '))
        jobs.append({"ResourceArn": "arn:fixture:efs", "CreationDate": "2026-11-25T11:00:00Z", "State": "COMPLETED"})
        self.assertTrue(module.check_jobs(self.config, jobs)[0].startswith('0 '))
        jobs[-1]["MessageCategory"] = "PARTIAL_SUCCESS"
        self.assertTrue(module.check_jobs(self.config, jobs)[0].startswith('1 '))


if __name__ == "__main__":
    unittest.main()
