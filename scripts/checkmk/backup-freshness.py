#!/usr/bin/env python3
"""Checkmk local check for completed AWS Backup recovery points. No object contents are read."""
import datetime
import json
import subprocess
import sys


def age_hours(value, now):
    if isinstance(value, (float, int)):
        created = datetime.datetime.fromtimestamp(value, datetime.timezone.utc)
    else:
        created = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    age = (now - created).total_seconds() / 3600
    if age < -5 / 60:
        raise ValueError("Recovery point is in the future; verify time synchronization")
    return max(0, age)


def check(config, recovery_points, now):
    lines = []
    for name, resource_arn in config["resources"].items():
        # Completion is required; a running or failed job does not establish recoverability.
        completed = [point for point in recovery_points
                     if point.get("ResourceArn") == resource_arn and point.get("Status") == "COMPLETED"]
        if not completed:
            lines.append(f'2 "Backup {name}" - No completed recovery point in the selected vault')
            continue
        age = min(age_hours(point["CreationDate"], now) for point in completed)
        state = 2 if age >= config["critical_hours"] else 1 if age >= config["warning_hours"] else 0
        lines.append(f'{state} "Backup {name}" age_hours={age:.1f};{config["warning_hours"]};{config["critical_hours"]} '
                     f'Newest completed recovery point is {age:.1f} hours old; restore success requires a separate test')
    return lines


def check_jobs(config, jobs):
    lines = []
    for name, resource_arn in config["resources"].items():
        matching = [job for job in jobs if job.get("ResourceArn") == resource_arn]
        if not matching:
            lines.append(f'3 "Backup job {name}" - No matching job returned; verify backup assignment')
            continue
        latest = max(matching, key=lambda job: str(job["CreationDate"]))
        state = latest.get("State", "UNKNOWN")
        severity = 2 if state in {"FAILED", "ABORTED", "EXPIRED"} else 1 if state == "PARTIAL" else 0 if state in {"COMPLETED", "CREATED", "PENDING", "RUNNING"} else 3
        if state == "COMPLETED" and latest.get("MessageCategory") not in {None, "SUCCESS"}:
            severity = 1
        lines.append(f'{severity} "Backup job {name}" - Latest backup job state: {state}; freshness is checked separately')
    return lines


def main():
    try:
        with open("/etc/check_mk/strathost-backups.json", encoding="utf-8") as file:
            config = json.load(file)
        if not 0 < config["warning_hours"] < config["critical_hours"] or not config["resources"]:
            raise ValueError("Invalid thresholds or empty inventory")
        if any(not name.replace("-", "").replace("_", "").isalnum() for name in config["resources"]):
            raise ValueError("Invalid check name")
        result = subprocess.run([
            "aws", "backup", "list-recovery-points-by-backup-vault", "--backup-vault-name", config["vault"],
            "--region", "eu-west-1", "--output", "json", "--no-cli-pager"
        ], check=True, capture_output=True, text=True, timeout=45)
        points = json.loads(result.stdout)["RecoveryPoints"]
        print("\n".join(check(config, points, datetime.datetime.now(datetime.timezone.utc))))
        result = subprocess.run([
            "aws", "backup", "list-backup-jobs", "--by-backup-vault-name", config["vault"],
            "--region", "eu-west-1", "--output", "json", "--no-cli-pager"
        ], check=True, capture_output=True, text=True, timeout=45)
        print("\n".join(check_jobs(config, json.loads(result.stdout)["BackupJobs"])))
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        # Avoid logging credentials or full AWS responses; failed collection is never silently OK.
        print('3 "AWS Backup collection" - Configuration, instance-role permissions or AWS CLI collection failed')


if __name__ == "__main__":
    main()
