package cn.workpanel.module.aiwork.infrastructure;

import cn.workpanel.*;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.poi.xwpf.usermodel.*;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.apache.poi.ss.usermodel.CellType;
import java.io.*;
import java.nio.file.*;
import java.util.*;

/** 仅替换服务端白名单占位符，未知字段/公式保留，不执行宏、链接或计算。 */
public final class TemplateRenderer {
    private TemplateRenderer(){}
    public static void main(String[] args){
        try{if(args.length!=3)System.exit(2);var fields=new ObjectMapper().readValue(Files.readAllBytes(Path.of(args[2])),new TypeReference<Map<String,String>>(){});
            Files.write(Path.of(args[1]),render(Files.readAllBytes(Path.of(args[0])),fields,Path.of(args[1]).getParent()));
        }catch(Throwable error){System.exit(3);}
    }
    static byte[] render(byte[] bytes,Map<String,String> fields,Path directory)throws Exception{
        if(!Set.of("姓名","部门","日期","事由").containsAll(fields.keySet()))throw ApiError.bad("INVALID_FIELD","模板字段无效");
        var parsed=DocumentParser.parse(bytes,directory);String type=Db.str(parsed,"type");var output=new ByteArrayOutputStream();
        if("DOCX".equals(type))try(var doc=new XWPFDocument(new ByteArrayInputStream(bytes))){
            fill(doc,fields);for(var header:doc.getHeaderList())fill(header,fields);for(var footer:doc.getFooterList())fill(footer,fields);doc.write(output);
        }else if("XLSX".equals(type))try(var book=new XSSFWorkbook(new ByteArrayInputStream(bytes))){
            for(var sheet:book)for(var row:sheet)for(var cell:row)if(cell.getCellType()==CellType.STRING)cell.setCellValue(replace(cell.getStringCellValue(),fields));book.write(output);
        }else throw ApiError.bad("INVALID_TEMPLATE","这份材料不支持预填，请下载原件");
        cn.workpanel.shared.application.AiFilePolicy.size(output.size());return output.toByteArray();
    }
    private static void fill(IBody body,Map<String,String> fields){
        for(var paragraph:body.getParagraphs()){
            // Word 可把一个占位符拆成多段格式；按原始字符范围替换并保留其他段落格式。
            var nodes=new ArrayList<org.openxmlformats.schemas.wordprocessingml.x2006.main.CTText>();
            for(var run:paragraph.getRuns())nodes.addAll(run.getCTR().getTList());
            String text=nodes.stream().map(org.openxmlformats.schemas.wordprocessingml.x2006.main.CTText::getStringValue).reduce("",String::concat);
            var replacements=new ArrayList<int[]>();var values=new ArrayList<String>();var matcher=java.util.regex.Pattern.compile("\\{\\{(姓名|部门|日期|事由)}}").matcher(text);
            while(matcher.find())if(fields.containsKey(matcher.group(1))){replacements.add(new int[]{matcher.start(),matcher.end()});values.add(fields.get(matcher.group(1)));}
            for(int i=replacements.size()-1;i>=0;i--){int[] range=replacements.get(i);int offset=0;
                for(var node:nodes){String value=node.getStringValue();int end=offset+value.length();if(offset<range[1]&&end>range[0]){int start=Math.max(0,range[0]-offset),stop=Math.min(value.length(),range[1]-offset);node.setStringValue(value.substring(0,start)+(range[0]>=offset?values.get(i):"")+value.substring(stop));}offset=end;}
            }
        }
        for(var table:body.getTables())for(var row:table.getRows())for(var cell:row.getTableCells())fill(cell,fields);
    }
    public static String replace(String text,Map<String,String> fields){
        var matcher=java.util.regex.Pattern.compile("\\{\\{(姓名|部门|日期|事由)}}").matcher(text);var result=new StringBuffer();
        while(matcher.find())matcher.appendReplacement(result,java.util.regex.Matcher.quoteReplacement(fields.getOrDefault(matcher.group(1),matcher.group())));matcher.appendTail(result);return result.toString();
    }
}
