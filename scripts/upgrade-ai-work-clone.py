#!/usr/bin/env python3
"""Back up and reconcile only a new AI migration clone; never mutate the source DB.

Requires Docker, a verified current server JAR and DB_PASSWORD in the environment.
Failed clones and backups are retained. Do not promote a clone without passed=true.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import uuid


def run(*args, data=None):
    result = subprocess.run(list(args), input=data, text=True, encoding="utf-8",
                            capture_output=True, timeout=300)
    if result.returncode:
        # Do not copy raw stderr: a driver error may contain a connection string.
        raise RuntimeError("Operation failed: " + args[0] + " " + args[1])
    return result.stdout


def upgrade(args):
    root = Path(__file__).resolve().parents[1]
    jar = root / "server/target/collaboration-server-1.0.0.jar"
    if not jar.is_file() or not os.environ.get("DB_PASSWORD"):
        raise ValueError("Build the current server JAR and supply DB_PASSWORD through the environment")
    for value in (args.source_database, args.database_user):
        if not re.fullmatch(r"[A-Za-z0-9_]+", value):
            raise ValueError("Invalid database identifier")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.source_container):
        raise ValueError("Invalid container")
    suffix = uuid.uuid4().hex[:12]
    clone = "workpanel_ai_upgrade_" + suffix
    out = (args.output_directory or root / "output/ai-work-migration-upgrade" / suffix).resolve()
    out.mkdir(parents=True, exist_ok=False)
    report = {"passed": False, "sourceDatabase": args.source_database, "clone": clone,
              "container": args.source_container, "sourceUnchanged": True}

    def query(database, sql):
        return run("docker", "exec", "-i", args.source_container, "psql", "-XqAt",
                   "-v", "ON_ERROR_STOP=1", "-U", args.database_user, "-d", database, data=sql).strip()

    def history(database):
        return json.loads(query(database, "SELECT coalesce(json_agg(h),'[]') FROM "
                                "(SELECT * FROM flyway_schema_history ORDER BY installed_rank) h"))

    def fingerprint(database, columns):
        result = {}
        for table, fields in columns.items():
            if not re.fullmatch(r"[a-z_][a-z0-9_]*", table) or any(not re.fullmatch(r"[a-z_][a-z0-9_]*", f) for f in fields):
                raise ValueError("Unexpected schema identifier")
            projection = ",".join('t."' + f + '"' for f in fields)
            result[table] = json.loads(query(database, "SELECT json_build_object('rows',count(*),'sha',"
                "md5(coalesce(string_agg(hash,'' ORDER BY hash),''))) FROM "
                '(SELECT md5(row_to_json(r)::text) AS hash FROM (SELECT ' + projection +
                ' FROM public."' + table + '" t) r) h'))
        return result

    def sequences(database):
        names = json.loads(query(database, "SELECT coalesce(json_agg(sequencename),'[]') FROM pg_sequences WHERE schemaname='public'"))
        result = {}
        for name in names:
            if not re.fullmatch(r"[a-z_][a-z0-9_]*", name):
                raise ValueError("Unexpected sequence identifier")
            result[name] = json.loads(query(database, 'SELECT row_to_json(s) FROM (SELECT last_value,is_called FROM public."' + name + '") s'))
        return result

    try:
        backup_in_container = "/tmp/ai-lineage-" + suffix + ".dump"
        run("docker", "exec", args.source_container, "pg_dump", "-U", args.database_user,
            "-d", args.source_database, "-Fc", "-f", backup_in_container)
        backup = out / "database.dump"
        run("docker", "cp", args.source_container + ":" + backup_in_container, str(backup))
        if backup.stat().st_size < 1000:
            raise RuntimeError("Backup unexpectedly small")
        report.update(backup=str(backup), backupSha256=hashlib.sha256(backup.read_bytes()).hexdigest(),
                      jarSha256=hashlib.sha256(jar.read_bytes()).hexdigest())
        run("docker", "exec", args.source_container, "createdb", "-U", args.database_user, "-T", "template0", clone)
        run("docker", "exec", args.source_container, "pg_restore", "-U", args.database_user,
            "-d", clone, "--exit-on-error", backup_in_container)
        report["historyBefore"] = history(clone)
        columns = json.loads(query(clone, "SELECT json_object_agg(table_name,fields) FROM "
            "(SELECT table_name,json_agg(column_name ORDER BY ordinal_position) fields FROM information_schema.columns "
            "WHERE table_schema='public' AND table_name<>'flyway_schema_history' GROUP BY table_name) c"))
        report["businessBefore"] = fingerprint(clone, columns)
        report["sequencesBefore"] = sequences(clone)
        output = run("docker", "run", "--rm", "--network", "container:" + args.source_container,
            "--volume", str(root) + ":/workspace:ro", "--env", "DB_PASSWORD",
            "--env", "DB_USER=" + args.database_user,
            "--env", "DB_URL=jdbc:postgresql://127.0.0.1:5432/" + clone,
            "maven:3.9.9-eclipse-temurin-21", "java", "-Dloader.main=cn.workpanel.tools.AiWorkMigrationUpgrade",
            "-cp", "/workspace/server/target/collaboration-server-1.0.0.jar",
            "org.springframework.boot.loader.launch.PropertiesLauncher", "--restored-clone")
        (out / "flyway.log").write_text(output, encoding="utf-8")
        report["historyAfter"] = history(clone)
        report["businessAfter"] = fingerprint(clone, columns)
        report["sequencesAfter"] = sequences(clone)
        if report["businessBefore"] != report["businessAfter"] or report["sequencesBefore"] != report["sequencesAfter"]:
            raise RuntimeError("Business content changed; clone cannot be promoted")
        report["passed"] = True
    finally:
        (out / "result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"passed": True, "clone": clone, "report": str(out / "result.json"),
                      "businessTablesUnchanged": len(columns), "sourceUnchanged": True}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-container", required=True)
    parser.add_argument("--source-database", default="workpanel")
    parser.add_argument("--database-user", default="workpanel")
    parser.add_argument("--output-directory", type=Path)
    upgrade(parser.parse_args())
