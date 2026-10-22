package cn.workpanel.shared.application;

import cn.workpanel.ApiError;
import java.util.*;

/** AI用途的共同限值与格式契约；普通附件上传保留原有兼容范围。 */
public final class AiFilePolicy {
    private AiFilePolicy(){}
    public static final int TEXT=10000,FILES=5,FILE_BYTES=10*1024*1024,TOTAL_BYTES=30*1024*1024;
    public static final int PDF_PAGES=50,IMAGE_PIXELS=20000000,RENDER_PIXELS=16000000,CELLS=50000;
    public static final int ZIP_ENTRIES=20000,EXPANDED_BYTES=100*1024*1024,PARTS=50000,TEXT_CHARS=500000;
    public static final List<String> FORMATS=List.of("png","jpg","jpeg","pdf","docx","xlsx");
    public static Map<String,Object> limits(){return Map.ofEntries(Map.entry("text",TEXT),Map.entry("files",FILES),Map.entry("fileBytes",FILE_BYTES),Map.entry("totalBytes",TOTAL_BYTES),Map.entry("formats",FORMATS),Map.entry("pdfPages",PDF_PAGES),Map.entry("imagePixels",IMAGE_PIXELS),Map.entry("renderPixels",RENDER_PIXELS),Map.entry("spreadsheetCells",CELLS),Map.entry("zipEntries",ZIP_ENTRIES),Map.entry("expandedBytes",EXPANDED_BYTES),Map.entry("extractedParts",PARTS),Map.entry("extractedCharacters",TEXT_CHARS));}
    /** 真实签名和文件名须同时允许；OOXML内部类型由隔离解析器进一步验证。 */
    public static String validate(String filename,byte[] bytes){
        size(bytes.length);String name=Objects.toString(filename,"").toLowerCase(Locale.ROOT);int dot=name.lastIndexOf('.');String extension=dot<0?"":name.substring(dot+1);
        if(!FORMATS.contains(extension))throw error("UNSUPPORTED_FILE");
        String type=signature(bytes),expected=switch(extension){case "jpg","jpeg"->"JPEG";case "png"->"PNG";case "pdf"->"PDF";default->"OOXML";};
        if(!type.equals(expected))throw error("FILE_TYPE_MISMATCH");if(Set.of("PNG","JPEG").contains(type))imageDimensions(bytes);return extension.equals("docx")?"DOCX":extension.equals("xlsx")?"XLSX":type;
    }
    /** 只读图像头尺寸，先于像素解码、缓存和OCR调用执行。 */
    public static void imageDimensions(byte[] bytes){
        try(var input=javax.imageio.ImageIO.createImageInputStream(new java.io.ByteArrayInputStream(bytes))){var readers=javax.imageio.ImageIO.getImageReaders(input);if(!readers.hasNext())throw error("FILE_UNREADABLE");var reader=readers.next();try{reader.setInput(input);long pixels=(long)reader.getWidth(0)*reader.getHeight(0);if(pixels<1||pixels>IMAGE_PIXELS)throw error("FILE_LIMIT");}finally{reader.dispose();}}
        catch(ApiError e){throw e;}catch(Exception e){throw error("FILE_UNREADABLE");}
    }
    public static void size(long bytes){if(bytes<1||bytes>FILE_BYTES)throw error("FILE_LIMIT");}
    public static String signature(byte[] b){
        if(b.length>=8&&b[0]==(byte)0x89&&b[1]=='P'&&b[2]=='N'&&b[3]=='G'&&b[4]==13&&b[5]==10&&b[6]==26&&b[7]==10)return "PNG";
        if(b.length>=3&&b[0]==(byte)0xff&&b[1]==(byte)0xd8&&b[2]==(byte)0xff)return "JPEG";
        if(b.length>=5&&b[0]=='%'&&b[1]=='P'&&b[2]=='D'&&b[3]=='F'&&b[4]=='-')return "PDF";
        if(b.length>=4&&b[0]=='P'&&b[1]=='K'&&b[2]==3&&b[3]==4)return "OOXML";return "UNKNOWN";
    }
    public static ApiError error(String code){return switch(code){
        case "UNSUPPORTED_FILE"->new ApiError(415,code,"请添加 PNG、JPEG、PDF、Word 或 Excel 文件");
        case "FILE_TYPE_MISMATCH"->new ApiError(415,code,"文件格式与名称不一致，请重新导出后添加");
        case "FILE_LIMIT"->ApiError.bad(code,"材料超出处理范围，请缩小或拆分后重试");
        case "FILE_UNSAFE"->new ApiError(422,code,"材料含有宏、外部链接或嵌入对象，请移除后重新导出");
        case "FILE_ENCRYPTED"->new ApiError(422,code,"请先解除文件加密，再添加材料");
        default->new ApiError(422,"FILE_UNREADABLE","材料暂时无法读取，请换一份完整文件");
    };}
}
