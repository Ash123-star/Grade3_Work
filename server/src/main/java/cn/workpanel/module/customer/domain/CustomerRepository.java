package cn.workpanel.module.customer.domain;

import cn.workpanel.Actor;
import java.time.LocalDate;
import java.util.*;

/** All customer reads and writes are company-scoped; no cross-company lookup. */
public interface CustomerRepository {
    Actor current(Actor actor);
    Map<String,Object> list(Actor actor,String search,String kind,int cursor,int limit);
    Map<String,Object> get(Actor actor,String id);
    Map<String,Object> byExternal(Actor actor,String externalId);
    Map<String,Object> create(Actor actor,CustomerDraft draft);
    Map<String,Object> update(Actor actor,String id,CustomerDraft draft);
    Map<String,Object> membership(Actor actor,String customerId);
    Map<String,Object> upsertMembership(Actor actor,String customerId,MembershipDraft draft);
    List<Map<String,Object>> benefits(Actor actor,String customerId);
    Map<String,Object> createBenefit(Actor actor,String customerId,BenefitDraft draft);
    Map<String,Object> benefit(Actor actor,String customerId,String benefitId,boolean lock);
    Map<String,Object> benefitById(Actor actor,String benefitId,boolean lock);
    Map<String,Object> redemptionByKey(Actor actor,String benefitId,String eventKey);
    List<Map<String,Object>> redemptions(Actor actor,String benefitId);
    Map<String,Object> insertRedemption(Actor actor,String customerId,String benefitId,String eventKey,String note);
    long redemptionCount(Actor actor,String benefitId);
    List<Map<String,Object>> progress(Actor actor,String customerId);
    Map<String,Object> addProgress(Actor actor,String customerId,String stage,String note);
    void audit(Actor actor,String type,String id,Object before,Object after,String reason);
}
