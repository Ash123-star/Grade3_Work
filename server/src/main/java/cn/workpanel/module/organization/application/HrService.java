package cn.workpanel.module.organization.application;

import cn.workpanel.*;
import cn.workpanel.module.organization.domain.ContractDates;
import cn.workpanel.module.organization.infrastructure.HrRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;

@Service
public class HrService {
    private final HrRepository repo;
    private final HrAccess access;

    public HrService(HrRepository repo, HrAccess access) {
        this.repo = repo;
        this.access = access;
    }

    public List<Map<String, Object>> reminders(Actor request) {
        return repo.reminders(access.require(request, false));
    }

    public Map<String, Object> me(Actor request) {
        Actor actor = access.require(request, false);
        return Map.of("admin", actor.admin(), "manage", access.allowed(actor.company(), actor.id(), true));
    }

    public List<Map<String, Object>> people(Actor request, int cursor, int limit) {
        Business.page(cursor, limit);
        return repo.people(access.require(request, false), cursor, limit);
    }

    @Transactional
    public void grant(Actor request, String id, Map<String, Object> body) {
        Actor actor = access.require(request, true);
        actor.requireAdmin();
        Db.fields(body, "access", "version");
        String level = Db.required(body, "access");
        if (!Set.of("NONE", "READ", "MANAGE").contains(level))
            throw ApiError.bad("INVALID_ACCESS", "请选择权限");
        int version = Db.version(body);
        repo.lockPendingReminders(actor.company(), id);
        repo.lockEmployee(actor.company(), id, true);
        access.require(actor, true).requireAdmin();
        Db.conflict(repo.saveGrant(actor.company(), id, level, version));
        if (level.equals("NONE")) repo.discardReminders(actor.company(), id);
        repo.audit(actor, "HR_GRANT_CHANGED", id, Map.of("access", level), "人事授权");
    }

    @Transactional
    public void duties(Actor request, String id, Map<String, Object> body) {
        Actor actor = access.require(request, true);
        Db.fields(body, "duties", "version");
        String text = Db.required(body, "duties");
        if (text.length() > 4000) throw ApiError.bad("INVALID_DUTIES", "职责最多4000字");
        int version = Db.version(body);
        for (String person : new TreeSet<>(List.of(actor.id(), id))) repo.lockEmployee(actor.company(), person, false);
        access.require(actor, true);
        Db.conflict(repo.saveDuties(actor.company(), id, text, version));
        repo.audit(actor, "EMPLOYEE_DUTIES_UPDATED", id, Map.of("version", version + 1), "工作职责");
    }

    public Map<String, Object> list(Actor request, int cursor, int limit) {
        Actor actor = access.require(request, false);
        Business.page(cursor, limit);
        return Map.of("items", repo.contracts(actor, cursor, limit), "total", repo.contractCount(actor.company()));
    }

    public List<Map<String, Object>> history(Actor request, String id) {
        Actor actor = access.require(request, false);
        repo.contract(actor, id, false);
        return repo.versions(id);
    }

    public Map<String, Object> get(Actor request, String id) {
        return detail(access.require(request, false), id);
    }

    private Map<String, Object> detail(Actor actor, String id) {
        var contract = repo.contract(actor, id, false);
        contract.put("recipients", repo.recipients(id));
        return contract;
    }

    @Transactional
    public Map<String, Object> save(Actor request, String id, Map<String, Object> body) {
        Actor actor = access.require(request, true);
        Db.fields(body, "employeeId", "title", "startsOn", "endsOn", "attachmentId", "recipients", "version");
        int version = Db.version(body);
        String employee = Db.required(body, "employeeId");
        String title = Db.required(body, "title");
        String attachment = Db.required(body, "attachmentId");
        if (title.length() > 200) throw ApiError.bad("INVALID_TITLE", "标题最多200字");
        var start = ContractDates.date(body, "startsOn");
        var end = ContractDates.date(body, "endsOn");
        if (end.isBefore(start)) throw ApiError.bad("INVALID_CONTRACT_DATE", "到期日不能早于开始日");

        if (!(body.get("recipients") instanceof List<?> raw) || raw.isEmpty() || raw.size() > 50)
            throw ApiError.bad("INVALID_RECIPIENTS", "请选择1至50名授权接收人");
        var recipients = new TreeSet<String>();
        for (Object value : raw) {
            if (!(value instanceof String user) || !access.allowed(actor.company(), user, false))
                throw invalidRecipient();
            recipients.add(user);
        }

        // User locks precede attachment locks and serialize writes with grant revocation.
        var people = new TreeSet<>(recipients);
        people.add(actor.id());
        people.add(employee);
        for (String person : people) repo.lockEmployee(actor.company(), person, false);
        access.require(actor, true);
        for (String recipient : recipients)
            if (!access.allowed(actor.company(), recipient, false)) throw invalidRecipient();

        if (id == null) {
            if (version != 0) throw ApiError.conflict();
            id = Db.id();
            repo.lockEligibleAttachment(actor, attachment);
            if (repo.attachmentInUse(attachment))
                throw ApiError.bad("ATTACHMENT_IN_USE", "附件已被使用，请重新上传合同专用附件");
            repo.createContract(actor, id, employee, title, start, end, attachment);
        } else {
            var old = repo.contract(actor, id, true);
            if (((Number) old.get("version")).intValue() != version) throw ApiError.conflict();
            if (!attachment.equals(old.get("attachment_id")))
                throw ApiError.bad("CONTRACT_ATTACHMENT_IMMUTABLE", "合同附件归档后不可替换，请归档新合同");
            Db.conflict(repo.updateContract(actor, id, employee, title, start, end, version));
        }
        repo.replaceRecipients(id, recipients);
        var saved = detail(actor, id);
        repo.saveVersion(actor, id, version + 1, saved);
        repo.audit(actor, "CONTRACT_ARCHIVED", id, Map.of("version", version + 1), "合同归档/修订");
        return saved;
    }

    private static ApiError invalidRecipient() {
        return ApiError.bad("INVALID_RECIPIENTS", "接收人必须为有效授权人员");
    }
}
