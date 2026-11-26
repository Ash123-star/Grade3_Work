package cn.workpanel.module.organization.application;
import cn.workpanel.*;import cn.workpanel.module.organization.domain.ContractDates;import org.springframework.stereotype.Service;import org.springframework.beans.factory.annotation.Value;import org.springframework.scheduling.annotation.Scheduled;import org.springframework.transaction.annotation.Transactional;import java.time.*;
@Service public class ContractReminders {
 private final Db db;private final HrAccess access;private final boolean enabled;
 public ContractReminders(Db db,HrAccess access,@Value("${app.jobs-enabled}")boolean enabled){this.db=db;this.access=access;this.enabled=enabled;}
 @Scheduled(fixedDelay=60000) @Transactional public void scheduled(){if(enabled)scan(ContractDates.today());}
 @Transactional public int scan(LocalDate today){return scan(today,null);}
 @Transactional public int scan(LocalDate today,String companyScope){int count=0;for(int days:new int[]{30,7,0})for(var c:db.rows("SELECT * FROM employee_contracts WHERE ends_on=? AND (?::text IS NULL OR company_id=?) FOR UPDATE SKIP LOCKED",java.sql.Date.valueOf(today.plusDays(days)),companyScope,companyScope))for(var r:db.rows("SELECT user_id FROM contract_recipients WHERE contract_id=?",c.get("id"))){String company=Db.str(c,"company_id"),user=Db.str(r,"user_id");if(!access.allowed(company,user,false))continue;String key="contract:"+c.get("id")+":"+c.get("version")+":"+days+":"+user;count+=db.update("INSERT INTO outbox_events(id,company_id,recipient_id,type,object_id,body,dedup_key) VALUES (?,?,?,'CONTRACT_EXPIRY',?,'{}',?) ON CONFLICT(dedup_key) DO NOTHING",Db.id(),company,user,c.get("id"),key);}return count;}
}
