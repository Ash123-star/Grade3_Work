package cn.workpanel.module.aiwork.infrastructure;

import cn.workpanel.ApiError;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.apache.poi.xwpf.usermodel.XWPFDocument;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.apache.poi.ss.usermodel.CellType;
import java.io.*;
import java.nio.file.Path;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class TemplateRendererTest {
    @TempDir Path directory;
    @Test void wordSplitRunsTablesAndHeadersPreserveUnknownFields()throws Exception{
        byte[] input;try(var doc=new XWPFDocument();var out=new ByteArrayOutputStream()){
            var p=doc.createParagraph();p.createRun().setText("申请人：{{姓");p.createRun().setText("名}}；{{审核人}}；{{事由}}");
            doc.createTable(1,1).getRow(0).getCell(0).setText("部门：{{部门}}");
            doc.createHeader(org.apache.poi.wp.usermodel.HeaderFooterType.DEFAULT).createParagraph().createRun().setText("日期：{{日期}}");doc.write(out);input=out.toByteArray();
        }
        byte[] rendered=TemplateRenderer.render(input,Map.of("姓名","小李","部门","设计部","日期","2026-10-21","事由","保留{{姓名}}与$符号"),directory);
        try(var doc=new XWPFDocument(new ByteArrayInputStream(rendered))){
            assertEquals("申请人：小李；{{审核人}}；保留{{姓名}}与$符号",doc.getParagraphs().getFirst().getText());
            assertEquals("部门：设计部",doc.getTables().getFirst().getRow(0).getCell(0).getText());
            assertTrue(doc.getHeaderList().getFirst().getText().contains("日期：2026-10-21"));
        }
    }
    @Test void workbookOnlyFillsStringCellsAndLeavesFormulasForHumanReview()throws Exception{
        byte[] input;try(var book=new XSSFWorkbook();var out=new ByteArrayOutputStream()){
            var row=book.createSheet("申请").createRow(0);row.createCell(0).setCellValue("{{姓名}}：{{审核人}}");row.createCell(1).setCellFormula("1+1");book.write(out);input=out.toByteArray();
        }
        try(var book=new XSSFWorkbook(new ByteArrayInputStream(TemplateRenderer.render(input,Map.of("姓名","小李"),directory)))){
            assertEquals("小李：{{审核人}}",book.getSheetAt(0).getRow(0).getCell(0).getStringCellValue());
            assertEquals(CellType.FORMULA,book.getSheetAt(0).getRow(0).getCell(1).getCellType());
            assertEquals("1+1",book.getSheetAt(0).getRow(0).getCell(1).getCellFormula());
        }
    }
    @Test void rejectsInvalidFieldsAndBrokenDocuments(){
        assertThrows(ApiError.class,()->TemplateRenderer.render(new byte[]{1},Map.of("审核人","管理员"),directory));
        assertThrows(Exception.class,()->TemplateRenderer.render(new byte[]{1},Map.of("姓名","小李"),directory));
        assertEquals("小李/{{姓名}}/{{审核人}}",TemplateRenderer.replace("{{姓名}}/{{事由}}/{{审核人}}",Map.of("姓名","小李","事由","{{姓名}}")));
    }
}
