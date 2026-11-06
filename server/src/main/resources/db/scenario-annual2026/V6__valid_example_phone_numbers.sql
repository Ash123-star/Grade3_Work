-- 保留已发布 V5；将它生成的 000 示例号修正为符合现有资料校验的虚构演示号。
-- 仅匹配 V5 的精确格式，不覆盖其他手机号；唯一键冲突时整批回滚。
UPDATE users SET phone='1990000'||right(phone,4),version=version+1
WHERE company_id IN ('annual-cm','annual-peer') AND id LIKE 'annual-%'
  AND phone ~ '^0002026[0-9]{4}$';

INSERT INTO audit_records(company_id,actor_id,type,object_id,before_value,after_value,reason)
VALUES('annual-cm','annual-founder','ANNUAL_EXAMPLE_PHONE_FORMAT_ALIGNED','annual-cm','{}',
       '{"seedSource":"annual-2026-v6","fictional":true}',
       '仅将V5生成的虚构示例号对齐现有手机号格式校验，避免资料编辑被示例值阻塞；不表示真实联系方式');
