package cn.workpanel;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.junit.jupiter.api.Assertions.*;

class AsyncTimeoutErrorTest {
    @Test void sseTimeoutDoesNotWriteJsonIntoEventStream() {
        var response = new MockHttpServletResponse();
        response.setContentType("text/event-stream;charset=UTF-8");
        assertNull(new Errors().timeout(new MockHttpServletRequest(), response));
        assertEquals(0, response.getContentAsByteArray().length);
        assertEquals(200, response.getStatus());
    }

    @Test void ordinaryAsyncTimeoutRemainsAnExplicitFailure() {
        var response = new Errors().timeout(new MockHttpServletRequest(), new MockHttpServletResponse());
        assertNotNull(response);
        assertEquals(503, response.getStatusCode().value());
        assertEquals("REQUEST_TIMEOUT", ((java.util.Map<?,?>)response.getBody()).get("code"));
    }
}
