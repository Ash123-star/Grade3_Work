package cn.workpanel.module.delivery;

import cn.workpanel.ApiError;
import cn.workpanel.module.delivery.domain.DeliveryPolicy;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class DeliveryPolicyTest {
    @Test void validatesCalendarDateAndCanonicalizesParticipants() {
        var input = new HashMap<String, Object>(Map.of("kind", "SALON", "title", " Salon ", "businessDate", "2028-02-29",
                "ownerId", "owner", "participants", List.of("z", "a")));
        var draft = DeliveryPolicy.draft(input);
        assertEquals("Salon", draft.title());
        assertEquals(List.of("a", "z"), draft.participants());
        assertEquals(List.of("a", "owner", "z"), draft.employees());
        for (var ids : List.of(List.of("owner"), List.of("a", "a"), List.of(" "))) {
            input.put("participants", ids);
            assertThrows(ApiError.class, () -> DeliveryPolicy.draft(input));
        }
        input.put("participants", List.of());
        input.put("businessDate", "2026-02-29");
        assertThrows(ApiError.class, () -> DeliveryPolicy.draft(input));
    }

    @Test void deliveryRequiresFinishedActivityAndCannotBeRepeated() {
        var scheduled = Map.<String, Object>of("activityStatus", "SCHEDULED", "deliveryStatus", "PENDING");
        var ended = Map.<String, Object>of("activityStatus", "ENDED", "deliveryStatus", "PENDING");
        var delivered = Map.<String, Object>of("activityStatus", "ENDED", "deliveryStatus", "DELIVERED");
        assertDoesNotThrow(() -> DeliveryPolicy.transition("END_ACTIVITY", scheduled));
        assertDoesNotThrow(() -> DeliveryPolicy.transition("CONFIRM_DELIVERY", ended));
        assertThrows(ApiError.class, () -> DeliveryPolicy.transition("CONFIRM_DELIVERY", scheduled));
        assertThrows(ApiError.class, () -> DeliveryPolicy.transition("CONFIRM_DELIVERY", delivered));
        assertThrows(ApiError.class, () -> DeliveryPolicy.transition("END_ACTIVITY", ended));
    }
}
