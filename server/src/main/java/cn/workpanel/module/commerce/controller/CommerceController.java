package cn.workpanel.module.commerce.controller;

import cn.workpanel.Actor;
import cn.workpanel.module.commerce.application.CommerceService;
import cn.workpanel.module.commerce.application.CommerceService.OrderFilter;
import cn.workpanel.module.commerce.domain.CommerceImport.OrderStatus;
import cn.workpanel.module.commerce.domain.CommerceImportRejected;
import cn.workpanel.module.commerce.dto.CommerceViews.ImportFailure;
import cn.workpanel.module.commerce.dto.CommerceViews.ImportReceipt;
import cn.workpanel.module.commerce.dto.CommerceViews.MemberView;
import cn.workpanel.module.commerce.dto.CommerceViews.OrderView;
import cn.workpanel.module.commerce.dto.CommerceViews.Overview;
import cn.workpanel.shared.api.ApiContracts.ErrorResponse;
import cn.workpanel.shared.api.ApiContracts.PageResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import org.springdoc.core.annotations.ParameterObject;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.BindException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.multipart.support.MissingServletRequestPartException;

import java.io.IOException;
import java.time.LocalDate;

@RestController
@RequestMapping(value = "/api/commerce", produces = MediaType.APPLICATION_JSON_VALUE)
@Tag(name = "commerce", description = "二期商城文件导入与经营概览")
public class CommerceController {
    private final CommerceService commerce;

    public CommerceController(CommerceService commerce) {
        this.commerce = commerce;
    }

    /** 当前公司 ACTIVE ADMIN 上传 JSON。文件指纹幂等，sourceUpdatedAt 为源版本，错误定位到记录。 */
    @Operation(operationId = "importCommerceFile", summary = "导入商城文件",
            description = "已改初始密码的在职管理员专用。multipart 字段 file，UTF-8 JSON，最多 1 MiB、500 条。"
                    + "相同文件返回原回执，源更新时间防旧快照覆盖。只提交全部通过校验的批次。")
    @ApiResponse(responseCode = "200", description = "导入回执或相同文件的原回执",
            content = @Content(schema = @Schema(implementation = ImportReceipt.class)))
    @ApiResponse(responseCode = "400", description = "文件或记录无效",
            content = @Content(schema = @Schema(implementation = ImportFailure.class)))
    @ApiResponse(responseCode = "403", description = "无商城权限")
    @ApiResponse(responseCode = "409", description = "源版本或订单身份冲突",
            content = @Content(schema = @Schema(implementation = ImportFailure.class)))
    @ApiResponse(responseCode = "413", description = "文件超过限制",
            content = @Content(schema = @Schema(implementation = ImportFailure.class)))
    @PostMapping(value = "/imports", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<ImportReceipt> importFile(HttpServletRequest request, @RequestPart("file") MultipartFile file) {
        try (var stream = file.getInputStream()) {
            return uncached(commerce.importFile(Actor.current(request), stream));
        } catch (IOException e) {
            throw CommerceImportRejected.invalid("file", null, null, "无法读取导入文件");
        }
    }

    /** 当前公司 ACTIVE ADMIN 查询导入凭据。不存在或跨公司返回 404。只读。 */
    @Operation(operationId = "getCommerceImport", summary = "回查商城导入凭据",
            description = "返回本公司批次的时间、文件指纹、处理计数。只读，无版本或幂等键参数。")
    @ApiResponse(responseCode = "200", description = "导入来源", useReturnTypeSchema = true)
    @ApiResponse(responseCode = "404", description = "批次不可见或不存在")
    @GetMapping("/imports/{id}")
    public ResponseEntity<ImportReceipt> getImport(HttpServletRequest request, @PathVariable String id) {
        return uncached(commerce.receipt(Actor.current(request), id));
    }

    /** 当前公司 ACTIVE ADMIN 查询精确金额分组。与订单列表共用过滤条件。只读。 */
    @Operation(operationId = "getCommerceOverview", summary = "查询商城经营概览",
            description = "按下单日及筛选范围，分订单状态和币种返回原始金额与条数。金额使用十进制字符串。"
                    + "客户或会员只能选一个。无版本或幂等键参数。")
    @ApiResponse(responseCode = "200", description = "订单金额分组和订单总数", useReturnTypeSchema = true)
    @ApiResponse(responseCode = "400", description = "查询参数无效")
    @ApiResponse(responseCode = "403", description = "无商城权限")
    @ApiResponse(responseCode = "404", description = "客户不可见或不存在")
    @GetMapping("/overview")
    public ResponseEntity<Overview> overview(HttpServletRequest request, @ParameterObject OrderParameters params) {
        return uncached(commerce.overview(Actor.current(request), params.filter()));
    }

    /** 当前公司 ACTIVE ADMIN 分页读取同范围订单和来源。游标为偏移，末页为空。只读。 */
    @Operation(operationId = "listCommerceOrders", summary = "分页查询商城订单",
            description = "与概览使用相同筛选条件；每条订单返回原始金额、导入凭据及文件行。无版本或幂等键参数。")
    @ApiResponse(responseCode = "200", description = "商城订单分页", useReturnTypeSchema = true)
    @ApiResponse(responseCode = "400", description = "查询参数无效")
    @ApiResponse(responseCode = "403", description = "无商城权限")
    @ApiResponse(responseCode = "404", description = "客户不可见或不存在")
    @GetMapping("/orders")
    public ResponseEntity<PageResponse<OrderView>> orders(
            HttpServletRequest request, @ParameterObject OrderParameters params,
            @RequestParam(defaultValue = "0") int cursor, @RequestParam(defaultValue = "20") int limit) {
        return uncached(commerce.orders(Actor.current(request), params.filter(), cursor, limit));
    }

    /** 当前公司 ACTIVE ADMIN 分页读取外部商城会员。未绑定客户返回空页。只读。 */
    @Operation(operationId = "listCommerceMembers", summary = "分页查询商城会员",
            description = "按外部会员 ID 或 C 的统一客户 ID 精确筛选。无版本或幂等键参数。")
    @ApiResponse(responseCode = "200", description = "商城会员分页", useReturnTypeSchema = true)
    @ApiResponse(responseCode = "400", description = "查询参数无效")
    @ApiResponse(responseCode = "403", description = "无商城权限")
    @ApiResponse(responseCode = "404", description = "客户不可见或不存在")
    @GetMapping("/members")
    public ResponseEntity<PageResponse<MemberView>> members(HttpServletRequest request,
            @RequestParam(required = false) String customerId, @RequestParam(required = false) String externalMemberId,
            @RequestParam(defaultValue = "0") int cursor, @RequestParam(defaultValue = "20") int limit) {
        return uncached(commerce.members(Actor.current(request), customerId, externalMemberId, cursor, limit));
    }

    @ExceptionHandler(CommerceImportRejected.class)
    ResponseEntity<ImportFailure> importFailure(CommerceImportRejected error, HttpServletRequest request) {
        return ResponseEntity.status(error.status).cacheControl(CacheControl.noStore())
                .body(new ImportFailure(error.code, error.getMessage(), String.valueOf(request.getAttribute("traceId")),
                        error.section, error.row, error.field));
    }

    @ExceptionHandler(MissingServletRequestPartException.class)
    ResponseEntity<ImportFailure> missingFile(HttpServletRequest request) {
        return importFailure(CommerceImportRejected.invalid("file", null, null, "请选择商城导入文件"), request);
    }

    @ExceptionHandler(BindException.class)
    ResponseEntity<ErrorResponse> invalidFilter(HttpServletRequest request) {
        return ResponseEntity.badRequest().cacheControl(CacheControl.noStore())
                .body(new ErrorResponse("INVALID_COMMERCE_FILTER", "日期或订单状态格式无效",
                        String.valueOf(request.getAttribute("traceId"))));
    }

    public record OrderParameters(
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
            String customerId, String externalMemberId, String externalOrderId, OrderStatus status, String currency) {
        OrderFilter filter() {
            return new OrderFilter(from, to, customerId, externalMemberId, externalOrderId, status, currency);
        }
    }

    private static <T> ResponseEntity<T> uncached(T body) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(body);
    }
}
