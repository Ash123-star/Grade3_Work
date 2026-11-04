package cn.workpanel.module.dashboard.application;

import cn.workpanel.*;
import cn.workpanel.module.dashboard.domain.CompanyItemPolicy;
import cn.workpanel.module.dashboard.infrastructure.CompanyItemRepository;
import cn.workpanel.module.review.application.ReviewApplicationService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

@Service
public class CompanyItemApplicationService {
    private final CompanyItemRepository repository;
    private final ReviewApplicationService reviews;
    public CompanyItemApplicationService(CompanyItemRepository repository,ReviewApplicationService reviews) { this.repository=repository;this.reviews=reviews; }
    @Transactional
    public Map<String,Object> revise(Actor actor,Map<String,Object> body) {
        if(!actor.global()||!actor.status().equals("ACTIVE")||actor.mustChange()) throw ApiError.forbidden();
        Db.fields(body,"id","version","reason","title","text","pinned","archived","position");
        CompanyItemPolicy.validate(body);String reason=CompanyItemPolicy.reason(body);
        String id=Db.str(body,"id");int version=Db.version(body);Object before=Map.of();
        if(id.isBlank()){if(version!=0)throw ApiError.conflict();id=Db.id();}
        else {before=repository.current(actor.company(),id);if(((Number)((Map<?,?>)before).get("version")).intValue()!=version)throw ApiError.conflict();}
        var candidate=new LinkedHashMap<String,Object>();
        for(String key:List.of("title","text","pinned","archived","position")) if(body.containsKey(key))candidate.put(key,body.get(key));
        return reviews.create(actor,"COMPANY_ITEM",id,version,before,candidate,reason);
    }
}
