package cn.workpanel.module.dashboard.infrastructure;

import cn.workpanel.Db;
import org.springframework.stereotype.Repository;
import java.util.Map;

@Repository
public class CompanyItemRepository {
    private final Db db;
    public CompanyItemRepository(Db db) { this.db=db; }
    public Map<String,Object> current(String company,String id) { return db.one("SELECT * FROM dashboard_items WHERE id=? AND company_id=? AND kind='COMPANY'",id,company); }
}
