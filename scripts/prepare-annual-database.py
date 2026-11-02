"""Linux/root运维工具：备份systemd当前数据库，在同一PG实例建空库并准备切换配置。

不会停止服务、替换JAR、删除旧库或自动切换；完成后按部署文档执行重启。
sudo python3 scripts/prepare-annual-database.py --new-db workpanel_annual2026
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit, urlunsplit, unquote


def command(args, **kwargs):
    return subprocess.check_output(args, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--new-db', required=True)
    parser.add_argument('--source-url', help='已人工确认的原JDBC连接地址，不含密码')
    parser.add_argument('--source-user', help='已人工确认的原数据库用户名')
    parser.add_argument('--source-password-file', help='可选：root持有且权限0600的原数据库密码文件，不在命令行传密码')
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit('请用sudo运行，以读取现有服务连接并写入root-only配置。')
    if not re.fullmatch(r'workpanel_annual2026(?:_[a-z0-9_]{1,30})?', args.new_db):
        raise SystemExit('新库名必须为workpanel_annual2026或带小写后缀；不接受任意删除/覆盖目标。')
    settings = Path('/etc/collaboration-annual2026.env')
    override = Path('/etc/systemd/system/collaboration-server.service.d/zzzz-annual2026.conf')
    if settings.exists() or override.exists():
        raise SystemExit('年度切换配置已存在，请核对原执行结果，不自动覆盖或重复建库。')
    pid = command(['systemctl', 'show', 'collaboration-server', '--property=MainPID', '--value'], text=True).strip()
    if not pid.isdigit() or pid == '0':
        raise SystemExit('原后端必须运行，才能确定实际连接。')
    env = dict(entry.decode().split('=', 1)
               for entry in Path(f'/proc/{pid}/environ').read_bytes().split(b'\0') if b'=' in entry)
    launch = Path(f'/proc/{pid}/cmdline').read_bytes().decode().replace('\0', ' ')
    advanced = launch + ' ' + env.get('JAVA_TOOL_OPTIONS', '') + ' ' + env.get('JDK_JAVA_OPTIONS', '')
    if env.get('SPRING_APPLICATION_JSON') or 'spring.datasource' in advanced or 'spring.config' in advanced:
        raise SystemExit('存在额外Spring配置或命令行数据库覆盖，无法可靠推断连接，请先由运维核对。')
    url = args.source_url or env.get('SPRING_DATASOURCE_URL') or env.get('DB_URL')
    if not url or not url.startswith('jdbc:postgresql://'):
        raise SystemExit('进程未提供显式数据库地址。核对原服务连接后，用--source-url和--source-user指定原库；不会自动采用默认库。')
    if args.source_url and not args.source_user:
        raise SystemExit('显式指定--source-url时必须同时指定--source-user。')
    parsed = urlsplit(url[5:])
    if parsed.hostname not in ('localhost', '127.0.0.1', '::1') or parsed.query or parsed.username:
        raise SystemExit('仅支持本机映射、无内嵌凭据/附加参数的数据库地址；请人工按原部署创建空库。')
    source_db = unquote(parsed.path.lstrip('/'))
    if not source_db or source_db == args.new_db:
        raise SystemExit('原库名无效或与新库相同，停止。')
    user = args.source_user or env.get('SPRING_DATASOURCE_USERNAME') or env.get('DB_USER', 'workpanel')
    password = env.get('SPRING_DATASOURCE_PASSWORD') or env.get('DB_PASSWORD', '')
    if args.source_password_file:
        secret_file = Path(args.source_password_file)
        metadata = secret_file.stat()
        if not secret_file.is_file() or metadata.st_uid != 0 or metadata.st_mode & 0o077:
            raise SystemExit('密码文件必须是root持有且无组/其他用户权限的普通文件。')
        password = secret_file.read_text().rstrip('\r\n')

    def env_line(key, value):
        if any(char in value for char in ('\n', '\r', '\0')):
            raise SystemExit('环境配置含换行或NUL，拒绝写入。')
        return key + '="' + value.replace('\\', '\\\\').replace('"', '\\"') + '"\n'

    # 在备份或建库前完成环境值校验；显式用户名也必须用于新服务连接。
    username_config = env_line('DB_USER', user) + env_line('SPRING_DATASOURCE_USERNAME', user)
    password_config = (env_line('DB_PASSWORD', password) + env_line('SPRING_DATASOURCE_PASSWORD', password)
                       if args.source_password_file else '')
    ids = command(['docker', 'ps', '-q'], text=True).split()
    containers = json.loads(command(['docker', 'inspect', *ids], text=True)) if ids else []
    matches = [c['Name'].lstrip('/') for c in containers
               if any(p.get('HostPort') == str(parsed.port or 5432)
                      for p in c['NetworkSettings']['Ports'].get('5432/tcp') or [])]
    if len(matches) != 1:
        raise SystemExit('无法唯一定位原PostgreSQL容器，停止；不会选择另一套数据库。')
    container = matches[0]
    process_env = dict(os.environ, PGPASSWORD=password)
    base = ['docker', 'exec', '-i', '-e', 'PGPASSWORD', container]

    def sql(text, database='postgres'):
        return command(base + ['psql', '-X', '-U', user, '-d', database,
                              '-v', 'ON_ERROR_STOP=1', '-At'], input=text.encode(), env=process_env).decode().strip()

    # 通过原连接验证，并在备份前核对目标未存在。所有标识符有明确引用。
    if sql('SELECT current_database();', source_db) != source_db:
        raise SystemExit('原库连接核对失败。')
    if sql("SELECT 1 FROM pg_database WHERE datname='" + args.new_db + "';"):
        raise SystemExit('目标库已存在，拒绝覆盖；请核对或使用新的后缀。')
    now = dt.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup = Path('/root') / f'workpanel-before-annual-{now}.dump'
    with os.fdopen(os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as output:
        subprocess.run(base + ['pg_dump', '-U', user, '-d', source_db, '-Fc'],
                       env=process_env, stdout=output, check=True)
    sql('CREATE DATABASE "' + args.new_db + '" OWNER "' + user.replace('"', '""') + '" TEMPLATE template0;')
    new_url = 'jdbc:' + urlunsplit((parsed.scheme, parsed.netloc, '/' + args.new_db, '', ''))
    # 同时覆盖两个常见Spring连接变量，用户名/密码与Redis等仍沿用原服务。
    content = (f'DB_URL={new_url}\nSPRING_DATASOURCE_URL={new_url}\n' + username_config + password_config +
               'SESSION_HOURS=168\nSCENARIO_DATA_ENABLED=true\n'
               'SCENARIO_DATASET=annual-2026\nSCENARIO_PASSWORD=test12345678\n'
               'NEO4J_URI=\nAI_MEMORY_EXTRACT_ENABLED=false\n'
               'ADMIN_ACCOUNT=sysadmin\nADMIN_PASSWORD=test12345678\nADMIN_PHONE=13900000001\n')
    with os.fdopen(os.open(settings, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
        output.write(content)
    override.parent.mkdir(parents=True, exist_ok=True)
    with override.open('x') as output:
        output.write('[Service]\nEnvironmentFile=/etc/collaboration-annual2026.env\n')
    print('原数据库：', container, source_db)
    print('备份文件：', backup)
    print('新空库：', args.new_db)
    print('切换配置已准备，服务尚未切换。替换新版JAR后daemon-reload并重启。')
    print('需回退时移走zzzz-annual2026.conf并daemon-reload/restart，旧库未修改。')


if __name__ == '__main__':
    main()
