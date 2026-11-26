package cn.workpanel.module.commerce;

import cn.workpanel.module.commerce.domain.CommerceImportParser;
import cn.workpanel.module.commerce.domain.CommerceImportRejected;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.Instant;

import static org.junit.jupiter.api.Assertions.*;

class CommerceImportParserTest {
    private final CommerceImportParser parser = new CommerceImportParser(new ObjectMapper());

    private static final String ORDER = """
            {"externalOrderId":"order-1","status":"PAID","currency":"CNY","amount":"0.1234",
             "orderedAt":"2026-11-24T00:00:00+08:00","sourceUpdatedAt":"2026-11-24T00:00:01.000001+08:00"}
            """;

    @Test
    void parsesExactAmountAndShanghaiOffset() {
        var order = parse("{\"orders\":[" + ORDER + "]}").orders().getFirst().snapshot();
        assertEquals(new BigDecimal("0.1234"), order.amount());
        assertEquals(Instant.parse("2026-11-23T16:00:00Z"), order.orderedAt());
        assertEquals(Instant.parse("2026-11-23T16:00:01.000001Z"), order.sourceUpdatedAt());
        assertNull(order.externalMemberId());
    }

    @Test
    void rejectsMalformedJsonDuplicateKeysAndUnknownFields() {
        assertThrows(CommerceImportRejected.class, () -> parse("[]"));
        assertThrows(CommerceImportRejected.class, () -> parse("{\"orders\":[],\"orders\":[]}"));
        assertThrows(CommerceImportRejected.class, () -> parse("{\"orders\":[" + ORDER + "]} {}"));
        var error = assertThrows(CommerceImportRejected.class,
                () -> parse("{\"orders\":[" + ORDER.replace("\"status\"", "\"unexpected\"") + "]}"));
        assertEquals("orders", error.section);
        assertEquals(1, error.row);
    }

    @Test
    void rejectsAmountAndTimestampOutsideSupportedFormatAtField() {
        for (String value : new String[]{"\"-1\"", "\"1e3\"", "\"1.12345\"", "0.1234", "\"1000000000000000\""}) {
            var error = assertThrows(CommerceImportRejected.class,
                    () -> parse("{\"orders\":[" + ORDER.replace("\"0.1234\"", value) + "]}"));
            assertEquals("amount", error.field);
        }
        var beforeOrder = ORDER.replace("2026-11-24T00:00:01.000001+08:00", "2026-11-23T23:59:59+08:00");
        var error = assertThrows(CommerceImportRejected.class, () -> parse("{\"orders\":[" + beforeOrder + "]}"));
        assertEquals("sourceUpdatedAt", error.field);
        var missingOffset = ORDER.replace("2026-11-24T00:00:00+08:00", "2026-11-24T00:00:00");
        assertEquals("orderedAt",
                assertThrows(CommerceImportRejected.class, () -> parse("{\"orders\":[" + missingOffset + "]}")).field);
    }

    @Test
    void rejectsDuplicateBusinessIdAtSecondRow() {
        var error = assertThrows(CommerceImportRejected.class, () -> parse("{\"orders\":[" + ORDER + "," + ORDER + "]}"));
        assertEquals("externalOrderId", error.field);
        assertEquals(2, error.row);
    }

    @Test
    void rejectsEmptyAndOversizedRecordSets() {
        assertThrows(CommerceImportRejected.class, () -> parse("{\"members\":[],\"orders\":[]}"));
        var tooMany = "{\"orders\":[" + "{},".repeat(500) + "{}]}";
        var error = assertThrows(CommerceImportRejected.class, () -> parse(tooMany));
        assertEquals("file", error.section);
        assertNull(error.row);
    }

    private cn.workpanel.module.commerce.domain.CommerceImport parse(String source) {
        return parser.parse(source.getBytes(StandardCharsets.UTF_8));
    }
}
