package cn.workpanel.module.commerce.domain;

import cn.workpanel.ApiError;

/** 对用户可见的导入失败位置，行号从 1 开始。 */
public final class CommerceImportRejected extends ApiError {
    public final String section;
    public final Integer row;
    public final String field;

    public CommerceImportRejected(int status, String code, String message, String section, Integer row, String field) {
        super(status, code, message);
        this.section = section;
        this.row = row;
        this.field = field;
    }

    public static CommerceImportRejected invalid(String section, Integer row, String field, String message) {
        return new CommerceImportRejected(400, "INVALID_COMMERCE_FILE", message, section, row, field);
    }

    public static CommerceImportRejected conflict(String section, int row, String field, String message) {
        return new CommerceImportRejected(409, "COMMERCE_SNAPSHOT_CONFLICT", message, section, row, field);
    }
}
