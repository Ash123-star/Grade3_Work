"""Keep deletion markers outside database backups and replay before restarting API.

Uses the database container's local psql authentication; never reads or prints credentials.
The marker file contains identifiers/timestamps only and must be backed up separately.
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def docker(*args, data=None):
    result = subprocess.run(["docker", *args], input=data, text=True,
                            encoding="utf-8", capture_output=True, timeout=120)
    if result.returncode:
        raise RuntimeError("Container operation failed; inspect container/database logs")
    return result.stdout


def validate(value):
    if not isinstance(value, dict) or value.get("format") != 1:
        raise ValueError("Unsupported deletion marker format")
    rows = value.get("markers")
    if not isinstance(rows, list) or len(rows) > 1_000_000:
        raise ValueError("Invalid deletion marker list")
    unique = {}
    for row in rows:
        if not isinstance(row, dict) or set(row) != {"company_id", "id", "deleted_at"}:
            raise ValueError("Invalid deletion marker")
        for key in ("company_id", "id"):
            if not isinstance(row[key], str) or not 1 <= len(row[key]) <= 200 or any(ord(c) < 32 for c in row[key]):
                raise ValueError("Invalid resource identifier")
        if not isinstance(row["deleted_at"], str) or not 1 <= len(row["deleted_at"]) <= 64:
            raise ValueError("Invalid deletion time")
        stamp = dt.datetime.fromisoformat(row["deleted_at"].replace("Z", "+00:00"))
        if stamp.tzinfo is None or stamp > dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=5):
            raise ValueError("Invalid deletion time")
        key = (row["company_id"], row["id"])
        if key not in unique or stamp < dt.datetime.fromisoformat(unique[key]["deleted_at"].replace("Z", "+00:00")):
            unique[key] = row
    return list(unique.values())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("export", "apply"))
    parser.add_argument("--container", required=True, help="Database container")
    parser.add_argument("--database", default="workpanel")
    parser.add_argument("--user", default="workpanel")
    parser.add_argument("--file", type=Path, required=True)
    parser.add_argument("--api-container", help="Stopped API container, required when applying")
    args = parser.parse_args()

    def psql(sql):
        return docker("exec", "-i", args.container, "psql", "-X", "-qAt",
                      "-v", "ON_ERROR_STOP=1", "-U", args.user, "-d", args.database, data=sql)

    if args.file.exists() and args.file.stat().st_size > 200 * 1024 * 1024:
        raise ValueError("Deletion marker file too large")
    if args.mode == "export":
        previous = validate(json.loads(args.file.read_text(encoding="utf-8"))) if args.file.exists() else []
        current = json.loads(psql("SELECT coalesce(json_agg(m),'[]') FROM (SELECT company_id,id,deleted_at FROM ai_work_items WHERE deleted_at IS NOT NULL) m;"))
        rows = validate({"format": 1, "markers": previous + current})
        args.file.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=".deletion-markers-", dir=args.file.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as target:
                json.dump({"format": 1, "markers": rows}, target, ensure_ascii=False)
                target.flush()
                os.fsync(target.fileno())
            os.replace(temporary, args.file)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        print(json.dumps({"exported": len(rows)}))
        return

    rows = validate(json.loads(args.file.read_text(encoding="utf-8")))
    if not args.api_container:
        raise ValueError("Applying requires --api-container while API is stopped")
    state = json.loads(docker("inspect", args.api_container))[0]["State"]
    if state["Running"] or state.get("Restarting"):
        raise ValueError("Stop the API container before applying deletion markers")
    payload = json.dumps(rows, ensure_ascii=True).replace("'", "''")
    sql = """BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='90s';
SET LOCAL standard_conforming_strings=on;
LOCK TABLE ai_work_items,ai_work_steps IN EXCLUSIVE MODE;
CREATE TEMP TABLE replay_markers ON COMMIT DROP AS
SELECT * FROM jsonb_to_recordset('%s'::jsonb) AS m(company_id text,id text,deleted_at timestamptz);
UPDATE ai_work_items w SET deleted_at=least(coalesce(w.deleted_at,m.deleted_at),m.deleted_at),
 state='CANCELLED',title='Deleted item',result='{}',error_code=NULL,version=version+1
FROM replay_markers m WHERE w.company_id=m.company_id AND w.id=m.id AND w.deleted_at IS NULL;
UPDATE ai_work_steps s SET state=CASE WHEN s.state IN ('PENDING','RUNNING','WAITING','FAILED') THEN 'CANCELLED' ELSE s.state END,
 fence=fence+1,lease_until=NULL,payload='{}',result='{}'
FROM replay_markers m WHERE s.company_id=m.company_id AND s.work_id=m.id;
DELETE FROM ai_work_messages x USING replay_markers m WHERE x.company_id=m.company_id AND x.work_id=m.id;
DELETE FROM ai_work_confirmations x USING replay_markers m WHERE x.company_id=m.company_id AND x.work_id=m.id;
DELETE FROM ai_work_plans x USING replay_markers m WHERE x.company_id=m.company_id AND x.work_id=m.id;
DELETE FROM ai_file_extractions x USING attachment_bindings b,replay_markers m
 WHERE x.company_id=m.company_id AND b.company_id=m.company_id AND x.attachment_id=b.attachment_id AND b.resource_type='WORK' AND b.resource_id=m.id;
UPDATE attachments f SET data=''::bytea,expires_at=now()
 WHERE f.task_id IS NULL AND EXISTS(SELECT 1 FROM attachment_bindings b JOIN replay_markers m ON m.company_id=b.company_id AND m.id=b.resource_id WHERE b.company_id=f.company_id AND b.attachment_id=f.id AND b.resource_type='WORK')
 AND NOT EXISTS(SELECT 1 FROM attachment_bindings b WHERE b.company_id=f.company_id AND b.attachment_id=f.id AND b.resource_type IN ('DELIVERY','PROCEDURE'))
 AND NOT EXISTS(SELECT 1 FROM users u WHERE u.company_id=f.company_id AND u.profile->>'avatarAttachmentId'=f.id)
 AND NOT EXISTS(SELECT 1 FROM attachment_bindings b JOIN ai_work_items w ON w.company_id=b.company_id AND w.id=b.resource_id WHERE b.company_id=f.company_id AND b.attachment_id=f.id AND b.resource_type='WORK' AND w.deleted_at IS NULL);
SELECT json_build_object('matched',count(*)) FROM replay_markers m JOIN ai_work_items w ON w.company_id=m.company_id AND w.id=m.id;
COMMIT;
""" % payload
    print(psql(sql).strip())


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, KeyError, OSError, subprocess.TimeoutExpired):
        print("Deletion marker operation failed; verify inputs and maintenance state", file=sys.stderr)
        sys.exit(1)
