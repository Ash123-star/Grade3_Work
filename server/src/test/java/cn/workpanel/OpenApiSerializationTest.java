package cn.workpanel;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
class OpenApiSerializationTest {
 @Test void reviewReferenceMapsSurviveOpenApiRoundTrip() throws Exception {
  var mapper=io.swagger.v3.core.util.Json31.mapper();
  var configuration=new OpenApi();
  var api=configuration.initialContract();
  var plain=new com.fasterxml.jackson.databind.ObjectMapper();
  api=plain.readValue(plain.writeValueAsString(api),io.swagger.v3.oas.models.OpenAPI.class);
  configuration.reviewDetailContract().customise(api);
  var copy=mapper.readValue(mapper.writeValueAsString(api),io.swagger.v3.oas.models.OpenAPI.class);
  var reference=(io.swagger.v3.oas.models.media.Schema<?>)copy.getComponents().getSchemas().get("ReviewDetail").getProperties().get("display_references");
  var people=(io.swagger.v3.oas.models.media.Schema<?>)reference.getProperties().get("people");
  assertEquals(java.util.Set.of("string"),((io.swagger.v3.oas.models.media.Schema<?>)people.getAdditionalProperties()).getTypes());
 }
}
