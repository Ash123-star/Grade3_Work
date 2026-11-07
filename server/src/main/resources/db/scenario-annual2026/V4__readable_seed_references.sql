-- Only the optional annual fixture is repaired. Published migrations stay unchanged.
-- Resolve references inside the same company; leave identifiers/relations intact.
CREATE FUNCTION pg_temp.readable_annual_content(company text, content text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE ref text; label text; result text := content;
BEGIN
    IF content IS NULL THEN RETURN content; END IF;
    FOR ref IN SELECT DISTINCT m[1] FROM regexp_matches(content, '\[(annual-[a-z0-9-]+)\]', 'g') AS m LOOP
        SELECT title INTO label FROM tasks WHERE company_id=company AND id=ref;
        IF label IS NULL THEN
            SELECT name INTO label FROM users WHERE company_id=company AND id=ref;
        END IF;
        IF label IS NOT NULL THEN result := replace(result, '['||ref||']', '「'||label||'」'); END IF;
    END LOOP;
    RETURN result;
END $$;

UPDATE tasks SET body=jsonb_set(body,'{content}',to_jsonb(pg_temp.readable_annual_content(company_id,body->>'content')))
WHERE company_id IN ('annual-cm','annual-peer') AND id LIKE 'annual-%'
  AND body->>'content' LIKE '%交付可复核清单与差异记录。%[annual-%';

-- 派发事件和历史评论为只追加证据，不改写，也不禁用保护触发器。

UPDATE review_requests SET candidate=jsonb_set(candidate,'{content}',to_jsonb(pg_temp.readable_annual_content(company_id,candidate->>'content')))
WHERE company_id IN ('annual-cm','annual-peer') AND target_id LIKE 'annual-%'
  AND candidate->>'content' LIKE '%交付可复核清单与差异记录。%[annual-%';

UPDATE review_requests SET before_value=jsonb_set(before_value,'{content}',to_jsonb(pg_temp.readable_annual_content(company_id,before_value->>'content')))
WHERE company_id IN ('annual-cm','annual-peer') AND target_id LIKE 'annual-%'
  AND before_value->>'content' LIKE '%交付可复核清单与差异记录。%[annual-%';

DROP FUNCTION pg_temp.readable_annual_content(text,text);
