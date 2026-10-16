package cn.workpanel.module.organization;

import cn.workpanel.ApiError;
import cn.workpanel.module.review.domain.ReviewPolicy;
import org.junit.jupiter.api.Test;
import java.util.Map;
import static org.junit.jupiter.api.Assertions.*;

class ReviewPolicyTest {
    @Test void rejectsSelfAndTerminalRequests() {
        assertThrows(ApiError.class, () -> ReviewPolicy.request("u", "u", "PENDING"));
        assertThrows(ApiError.class, () -> ReviewPolicy.request("r", "u", "APPROVED"));
        assertDoesNotThrow(() -> ReviewPolicy.request("r", "u", "PENDING"));
    }
    @Test void validatesDecisionAndRejectionReason() {
        assertTrue(ReviewPolicy.decision(Map.of("approve", true)));
        assertThrows(ApiError.class, () -> ReviewPolicy.decision(Map.of("approve", "true")));
        assertThrows(ApiError.class, () -> ReviewPolicy.decision(Map.of("approve", false, "reason", 1)));
        assertThrows(ApiError.class, () -> ReviewPolicy.decision(Map.of("approve", true, "extra", true)));
        assertThrows(ApiError.class, () -> ReviewPolicy.reason(false, " \t\n"));
        assertDoesNotThrow(() -> ReviewPolicy.reason(false, "驳回原因"));
    }
}
