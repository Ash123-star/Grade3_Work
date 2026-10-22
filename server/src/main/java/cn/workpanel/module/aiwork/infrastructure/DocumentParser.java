package cn.workpanel.module.aiwork.infrastructure;

import cn.workpanel.*;
import cn.workpanel.shared.application.AiFilePolicy;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.cos.*;
import org.apache.pdfbox.pdmodel.encryption.InvalidPasswordException;
import org.apache.pdfbox.text.PDFTextStripper;
import org.apache.pdfbox.rendering.PDFRenderer;
import org.apache.poi.xwpf.usermodel.XWPFDocument;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.apache.poi.ss.usermodel.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
import javax.xml.stream.*;

/** 独立受限 JVM 入口；不启动 Spring，不读取服务器配置和凭据，不执行公式、宏或链接。 */
public final class DocumentParser {
    private DocumentParser(){}
    public static void main(String[] args){
        try{
            if(args.length!=2)System.exit(2);
            var result=parse(Files.readAllBytes(Path.of(args[0])),Path.of(args[1]).getParent());
            Files.writeString(Path.of(args[1]),new ObjectMapper().writeValueAsString(result));
        }catch(Throwable error){
            // 仅持久白名单错误码，不输出文件内容、路径或第三方异常。
            String code=error instanceof ApiError api?api.code:error instanceof InvalidPasswordException?"FILE_ENCRYPTED":"FILE_UNREADABLE";
            try{Files.writeString(Path.of(args[1]),new ObjectMapper().writeValueAsString(Map.of("errorCode",code)));}catch(Exception ignored){}
            System.exit(3);
        }
    }
    static Map<String,Object> parse(byte[] bytes,Path folder)throws Exception{
        AiFilePolicy.size(bytes.length);var parts=new ArrayList<Map<String,Object>>();var scanned=new ArrayList<String>();boolean uncertain=false;String type;
        String signature=AiFilePolicy.signature(bytes);
        if(signature.equals("PDF")){
            type="PDF";try(var pdf=Loader.loadPDF(bytes)){if(pdf.isEncrypted())throw AiFilePolicy.error("FILE_ENCRYPTED");if(pdf.getNumberOfPages()>AiFilePolicy.PDF_PAGES)throw AiFilePolicy.error("FILE_LIMIT");safePdf(pdf.getDocumentCatalog().getCOSObject(),Collections.newSetFromMap(new IdentityHashMap<>()));for(int i=1;i<=pdf.getNumberOfPages();i++){
                var stripper=new PDFTextStripper();stripper.setStartPage(i);stripper.setEndPage(i);String text=stripper.getText(pdf).trim();
                if(text.isBlank()){
                    // 渲染尺寸有界，扫描页再交给相同 OCR 适配器，保留页码。
                    var page=pdf.getPage(i-1).getCropBox();if(page.getWidth()<=0||page.getHeight()<=0)throw new IOException();float dpi=Math.min(144f,(float)Math.sqrt(AiFilePolicy.RENDER_PIXELS/(double)(page.getWidth()*page.getHeight()))*72f);
                    var image=new PDFRenderer(pdf).renderImageWithDPI(i-1,dpi);String name="page-"+i+".png";javax.imageio.ImageIO.write(image,"png",folder.resolve(name).toFile());image.flush();scanned.add(name);
                }else add(parts,part("第"+i+"页",text));
            }if(pdf.getSignatureDictionaries().size()>0){uncertain=true;parts.add(Map.of("locator","签章","text","签章真实性需要人工核对","unverifiable",true));}}
        }else if(signature.equals("OOXML")){
            var entries=zip(bytes);
            if(entries.contains("word/document.xml")&&entries.contains("xl/workbook.xml"))throw AiFilePolicy.error("FILE_TYPE_MISMATCH");
            if(!entries.contains("[Content_Types].xml")||!entries.contains("_rels/.rels"))throw new IOException();
            if(entries.contains("word/document.xml")){
                type="DOCX";try(var doc=new XWPFDocument(new ByteArrayInputStream(bytes))){int i=0;for(var p:doc.getParagraphs())add(parts,part("段落"+(++i),p.getText()));for(var table:doc.getTables())for(var row:table.getRows())for(var cell:row.getTableCells())add(parts,part("表格"+(++i),cell.getText()));}
            }else if(entries.contains("xl/workbook.xml")){
                type="XLSX";try(var book=new XSSFWorkbook(new ByteArrayInputStream(bytes))){int count=0;var format=new DataFormatter(Locale.CHINA);for(var sheet:book)for(var row:sheet)for(var cell:row){if(++count>AiFilePolicy.CELLS)throw AiFilePolicy.error("FILE_LIMIT");boolean formula=cell.getCellType()==CellType.FORMULA;uncertain|=formula;add(parts,Map.of("locator",sheet.getSheetName()+"!"+cell.getAddress(),"text",formula?"公式需要人工核对":format.formatCellValue(cell),"unverifiable",formula));}}
            }else throw new IOException("format");
        }else throw AiFilePolicy.error("UNSUPPORTED_FILE");
        if(parts.size()>AiFilePolicy.PARTS||parts.stream().mapToLong(p->Db.str(p,"text").length()).sum()>AiFilePolicy.TEXT_CHARS)throw AiFilePolicy.error("FILE_LIMIT");
        return Map.of("type",type,"parts",parts,"scanned",scanned,"unverifiable",uncertain);
    }
    private static Map<String,Object> part(String where,String text){return Map.of("locator",where,"text",text,"unverifiable",false);}
    private static void add(List<Map<String,Object>> parts,Map<String,Object> part){if(parts.size()>=AiFilePolicy.PARTS||Db.str(part,"text").length()>AiFilePolicy.TEXT_CHARS)throw AiFilePolicy.error("FILE_LIMIT");parts.add(part);}
    private static void safePdf(COSBase object,Set<COSBase> seen){
        if(object==null||!seen.add(object))return;if(seen.size()>200000)throw AiFilePolicy.error("FILE_LIMIT");
        if(object instanceof COSObject ref)safePdf(ref.getObject(),seen);
        else if(object instanceof COSArray array)for(var item:array)safePdf(item,seen);
        else if(object instanceof COSDictionary dictionary){
            for(var key:dictionary.keySet()){if(Set.of("JS","JavaScript","AA","OpenAction","EmbeddedFiles","RichMedia","XFA").contains(key.getName()))throw AiFilePolicy.error("FILE_UNSAFE");safePdf(dictionary.getItem(key),seen);}
            if(Set.of("JavaScript","Launch","SubmitForm","ImportData","GoToR","URI").contains(dictionary.getNameAsString(COSName.S,"")))throw AiFilePolicy.error("FILE_UNSAFE");
        }
    }
    private static Set<String> zip(byte[] bytes)throws IOException{
        var names=new HashSet<String>();long total=0;try(var in=new ZipInputStream(new ByteArrayInputStream(bytes))){ZipEntry e;byte[] buffer=new byte[8192];while((e=in.getNextEntry())!=null){String name=e.getName(),lower=name.toLowerCase(Locale.ROOT);
            if(names.size()>=AiFilePolicy.ZIP_ENTRIES)throw AiFilePolicy.error("FILE_LIMIT");
            if(!names.add(name)||name.contains("..")||name.contains("\\")||name.startsWith("/")||name.contains(":"))throw AiFilePolicy.error("FILE_UNSAFE");
            if(lower.matches(".*(vbaproject|/embeddings/|/activex/|/externallinks/|\\.exe$|\\.dll$|\\.js$|\\.vbs$|\\.ps1$|\\.bat$|\\.cmd$|\\.html?$).*"))throw AiFilePolicy.error("FILE_UNSAFE");
            ByteArrayOutputStream xml=name.endsWith(".rels")||name.equals("[Content_Types].xml")?new ByteArrayOutputStream():null;
            int n;while((n=in.read(buffer))!=-1){total+=n;if(total>AiFilePolicy.EXPANDED_BYTES)throw AiFilePolicy.error("FILE_LIMIT");if(xml!=null){if(xml.size()+n>2*1024*1024)throw AiFilePolicy.error("FILE_LIMIT");xml.write(buffer,0,n);}}
            if(xml!=null)safeXml(xml.toByteArray());
        }}return names;
    }
    private static void safeXml(byte[] bytes)throws IOException{
        var factory=XMLInputFactory.newFactory();factory.setProperty(XMLInputFactory.SUPPORT_DTD,false);factory.setProperty("javax.xml.stream.isSupportingExternalEntities",false);factory.setXMLResolver((publicId,systemId,base,namespace)->{throw new XMLStreamException();});
        try{var xml=factory.createXMLStreamReader(new ByteArrayInputStream(bytes));try{while(xml.hasNext()){int event=xml.next();if(event==XMLStreamConstants.DTD||event==XMLStreamConstants.ENTITY_REFERENCE)throw AiFilePolicy.error("FILE_UNSAFE");if(event==XMLStreamConstants.START_ELEMENT)for(int i=0;i<xml.getAttributeCount();i++){String value=xml.getAttributeValue(i);if("TargetMode".equals(xml.getAttributeLocalName(i))&&"External".equalsIgnoreCase(value)||value.toLowerCase(Locale.ROOT).contains("macroenabled")||value.toLowerCase(Locale.ROOT).contains("vbaproject"))throw AiFilePolicy.error("FILE_UNSAFE");}}}finally{xml.close();}}catch(XMLStreamException e){throw new IOException();}
    }
}
