package cn.workpanel.module.organization.application;

import cn.workpanel.Db;
import cn.workpanel.module.organization.domain.ContractDates;
import cn.workpanel.module.organization.infrastructure.HrRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;

@Service
public class ContractReminders {
    private final HrRepository repo;
    private final HrAccess access;
    private final boolean enabled;

    public ContractReminders(HrRepository repo, HrAccess access, @Value("${app.jobs-enabled}") boolean enabled) {
        this.repo = repo;
        this.access = access;
        this.enabled = enabled;
    }

    @Scheduled(fixedDelay = 60000)
    @Transactional
    public void scheduled() {
        if (enabled) scan(ContractDates.today());
    }

    @Transactional
    public int scan(LocalDate today) {
        return scan(today, null);
    }

    @Transactional
    public int scan(LocalDate today, String companyScope) {
        int count = 0;
        for (int days : new int[]{30, 7, 0}) {
            for (var contract : repo.lockExpiring(today.plusDays(days), companyScope)) {
                String id = Db.str(contract, "id");
                String company = Db.str(contract, "company_id");
                for (String user : repo.recipients(id)) {
                    if (!access.allowed(company, user, false)) continue;
                    String key = "contract:" + id + ":" + contract.get("version") + ":" + days + ":" + user;
                    count += repo.queueReminder(company, user, id, key);
                }
            }
        }
        return count;
    }
}
