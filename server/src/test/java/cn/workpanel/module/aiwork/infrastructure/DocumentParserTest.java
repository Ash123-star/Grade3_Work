package cn.workpanel.module.aiwork.infrastructure;

import cn.workpanel.*;
import cn.workpanel.shared.application.AiFilePolicy;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.pdfbox.pdmodel.*;
import org.apache.pdfbox.pdmodel.font.*;
import org.apache.poi.xwpf.usermodel.XWPFDocument;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import java.io.*;
import java.nio.file.Path;
import java.util.*;
import java.util.zip.*;
import static org.junit.jupiter.api.Assertions.*;

/** 使用真实文档和隔离子进程，不以解析Mock代替限额验证。 */
class DocumentParserTest {
    @TempDir Path folder;
    @Test void signaturesNamesAndByteBoundariesMustAgree(){
        byte[] png=Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4l8AAAAASUVORK5CYII=");assertEquals("PNG",AiFilePolicy.validate("图片.PNG",png));
        assertEquals("FILE_TYPE_MISMATCH",assertThrows(ApiError.class,()->AiFilePolicy.validate("假.pdf",png)).code);
        assertEquals("UNSUPPORTED_FILE",assertThrows(ApiError.class,()->AiFilePolicy.validate("旧.doc",png)).code);
        assertThrows(ApiError.class,()->AiFilePolicy.validate("假.png",new byte[]{(byte)137,80,78,71,0,0,0,0}));
        AiFilePolicy.size(AiFilePolicy.FILE_BYTES);assertThrows(ApiError.class,()->AiFilePolicy.size(0));assertThrows(ApiError.class,()->AiFilePolicy.size(AiFilePolicy.FILE_BYTES+1));
    }
    @Test void imageDimensionLimitIsCheckedWithoutDecodingPixels(){
        byte[] png=Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4l8AAAAASUVORK5CYII=");
        java.nio.ByteBuffer.wrap(png).putInt(16,5000).putInt(20,4000);assertEquals("PNG",AiFilePolicy.validate("尺寸.png",png));
        java.nio.ByteBuffer.wrap(png).putInt(16,5001);assertEquals("FILE_LIMIT",assertThrows(ApiError.class,()->AiFilePolicy.validate("尺寸.png",png)).code);
    }
    @Test void actualDocxAndFormulaWorkbookKeepEvidence()throws Exception{
        var bytes=new ByteArrayOutputStream();try(var doc=new XWPFDocument()){doc.createParagraph().createRun().setText("成本：10元");doc.write(bytes);}
        var word=DocumentParser.parse(bytes.toByteArray(),folder);assertEquals("DOCX",word.get("type"));assertTrue(word.toString().contains("段落1"));
        bytes.reset();try(var book=new XSSFWorkbook()){book.createSheet("成本").createRow(0).createCell(0).setCellFormula("1+1");book.write(bytes);}
        var sheet=DocumentParser.parse(bytes.toByteArray(),folder);assertEquals(true,sheet.get("unverifiable"));assertTrue(sheet.toString().contains("成本!A1"));
    }
    @Test void pdfPageLimitAcceptsFiftyAndRejectsFiftyOne()throws Exception{
        assertEquals("PDF",DocumentParser.parse(pdf(50),folder).get("type"));assertEquals("FILE_LIMIT",assertThrows(ApiError.class,()->DocumentParser.parse(pdf(51),folder)).code);
    }
    @Test void cellLimitAcceptsFiftyThousandAndRejectsNext()throws Exception{
        try(var book=new XSSFWorkbook()){var sheet=book.createSheet();for(int r=0;r<500;r++){var row=sheet.createRow(r);for(int c=0;c<100;c++)row.createCell(c).setCellValue("x");}
            var bytes=new ByteArrayOutputStream();book.write(bytes);assertEquals(AiFilePolicy.CELLS,((List<?>)DocumentParser.parse(bytes.toByteArray(),folder).get("parts")).size());
            sheet.createRow(500).createCell(0).setCellValue("x");bytes.reset();book.write(bytes);assertEquals("FILE_LIMIT",assertThrows(ApiError.class,()->DocumentParser.parse(bytes.toByteArray(),folder)).code);
        }
    }
    @Test void macroEmbeddedExternalAndTraversalPackagesAreRejected()throws Exception{
        for(String name:List.of("word/vbaProject.bin","word/embeddings/object.bin","word/activeX/object.xml","../escape","C:/escape","word\\escape"))assertEquals("FILE_UNSAFE",assertThrows(ApiError.class,()->DocumentParser.parse(zip(Map.of(name,new byte[]{1})),folder)).code,name);
        var rels="<Relationships><Relationship TargetMode=\"External\" Target=\"https://example.invalid\"/></Relationships>".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        assertEquals("FILE_UNSAFE",assertThrows(ApiError.class,()->DocumentParser.parse(zip(Map.of("_rels/.rels",rels)),folder)).code);
        var dtd="<!DOCTYPE x [<!ENTITY x SYSTEM 'file:///invalid'>]><x>&x;</x>".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        assertThrows(Exception.class,()->DocumentParser.parse(zip(Map.of("_rels/.rels",dtd)),folder));
    }
    @Test void expandedAndEntryLimitsCannotBeHiddenByCompression()throws Exception{
        assertEquals("FILE_LIMIT",assertThrows(ApiError.class,()->DocumentParser.parse(zip(Map.of("large",new byte[AiFilePolicy.EXPANDED_BYTES+1])),folder)).code);
        var entries=new LinkedHashMap<String,byte[]>();for(int i=0;i<=AiFilePolicy.ZIP_ENTRIES;i++)entries.put("entry-"+i,new byte[0]);assertEquals("FILE_LIMIT",assertThrows(ApiError.class,()->DocumentParser.parse(zip(entries),folder)).code);
    }
    @Test void isolatedParserReturnsClassifiedErrorsAndReadsActualDocument()throws Exception{
        var parser=new ParserProcess(new Db(null,new ObjectMapper()));
        assertEquals("FILE_LIMIT",assertThrows(ApiError.class,()->parser.parse(pdf(51),b->Map.of())).code);
        assertEquals("PDF",parser.parse(pdf(1),b->Map.of()).get("type"));
    }
    byte[] pdf(int count)throws Exception{try(var doc=new PDDocument()){for(int i=0;i<count;i++){var page=new PDPage();doc.addPage(page);try(var content=new PDPageContentStream(doc,page)){content.beginText();content.setFont(new PDType1Font(Standard14Fonts.FontName.HELVETICA),12);content.showText("Evidence 10");content.endText();}}var bytes=new ByteArrayOutputStream();doc.save(bytes);return bytes.toByteArray();}}
    byte[] zip(Map<String,byte[]> entries)throws Exception{var bytes=new ByteArrayOutputStream();try(var zip=new ZipOutputStream(bytes)){for(var entry:entries.entrySet()){zip.putNextEntry(new ZipEntry(entry.getKey()));zip.write(entry.getValue());zip.closeEntry();}}return bytes.toByteArray();}
}
