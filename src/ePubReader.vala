/* Copyright 2017 Siddhartha Das (bablu.boy@gmail.com)
*
* This file is part of Bookworm and is used for parsing EPUB file formats
*
* Bookworm is free software: you can redistribute it
* and/or modify it under the terms of the GNU General Public License as
* published by the Free Software Foundation, either version 3 of the
* License, or (at your option) any later version.
*
* Bookworm is distributed in the hope that it will be
* useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
* Public License for more details.
*
* You should have received a copy of the GNU General Public License along
* with Bookworm. If not, see http://www.gnu.org/licenses/.
*/

using Gee;
public class BookwormApp.ePubReader {

  public static BookwormApp.Book parseEPubBook (owned BookwormApp.Book aBook){
    //Only parse the eBook if it has not been parsed already
    if(!aBook.getIsBookParsed()){
      debug ("Starting to parse EPub Book located at:"+aBook.getBookLocation());
      //Extract the content of the EPub
      string extractionLocation = extractEBook(aBook.getBookLocation());
      if("false" == extractionLocation){ //handle error condition
        aBook.setIsBookParsed(false);
        aBook.setParsingIssue(BookwormApp.Constants.TEXT_FOR_EXTRACTION_ISSUE);
        return aBook;
      }else{
        aBook.setBookExtractionLocation(extractionLocation);
      }
      //Check if the EPUB mime type is correct
      bool isEPubFormat = isEPubFormat(extractionLocation);
      if(!isEPubFormat){ //handle error condition
        aBook.setIsBookParsed(false);
        aBook.setParsingIssue(BookwormApp.Constants.TEXT_FOR_MIMETYPE_ISSUE);
        return aBook;
      }
      //Determine the location of OPF File
      string locationOfOPFFile = getOPFFileLocation(extractionLocation);
      if("false" == locationOfOPFFile){ //handle error condition
        aBook.setIsBookParsed(false);
        aBook.setParsingIssue(BookwormApp.Constants.TEXT_FOR_CONTENT_ISSUE);
        return aBook;
      }
      string baseLocationOfContents = locationOfOPFFile.replace(File.new_for_path(locationOfOPFFile).get_basename(), "");
      aBook.setBaseLocationOfContents(baseLocationOfContents);

      //Determine Manifest contents
      ArrayList<string> manifestItemsList = parseManifestData(locationOfOPFFile);
      if("false" == manifestItemsList.get(0)){
        aBook.setIsBookParsed(false);
        aBook.setParsingIssue(BookwormApp.Constants.TEXT_FOR_CONTENT_ISSUE);
        return aBook;
      }

      //Determine Spine contents
      ArrayList<string> spineItemsList = parseSpineData(locationOfOPFFile);
      if("false" == spineItemsList.get(0)){
        aBook.setIsBookParsed(false);
        aBook.setParsingIssue(BookwormApp.Constants.TEXT_FOR_CONTENT_ISSUE);
        return aBook;
      }

      //Match Spine with Manifest to populate content list for EPub Book
      aBook = getContentList(aBook, manifestItemsList, spineItemsList);
      if(aBook.getBookContentList().size < 1){
        aBook.setIsBookParsed(false);
        aBook.setParsingIssue(BookwormApp.Constants.TEXT_FOR_CONTENT_ISSUE);
        return aBook;
      }

      //Try to determine Book Cover Image if it is not already available
      if(!aBook.getIsBookCoverImagePresent()){
        aBook = setCoverImage(aBook, manifestItemsList);
      }

      //Determine Book Meta Data like Title, Author, etc
      aBook = setBookMetaData(aBook, locationOfOPFFile);

      aBook.setIsBookParsed(true);
      debug ("Sucessfully parsed EPub Book located at:"+aBook.getBookLocation());
    }
    return aBook;
  }

  public static string extractEBook(string eBookLocation){
        string extractionLocation = "false";
        debug("Initiated process for content extraction of ePub Book located at:"+eBookLocation);
        //create a location for extraction of eBook based on local storage prefference
        if(BookwormApp.Bookworm.settings == null){
            BookwormApp.Bookworm.settings = BookwormApp.Settings.get_instance();
        }
        if(BookwormApp.Bookworm.settings.is_local_storage_enabled){
            extractionLocation = BookwormApp.Bookworm.bookworm_config_path + "/books/" + File.new_for_path(eBookLocation).get_basename();
        }else{
            extractionLocation = BookwormApp.Constants.EBOOK_EXTRACTION_LOCATION + File.new_for_path(eBookLocation).get_basename();
        }
        //check and create directory for extracting contents of ebook
        BookwormApp.Utils.fileOperations("CREATEDIR", extractionLocation, "", "");
        //unzip eBook contents into extraction location
        BookwormApp.Utils.execute_sync_command("unzip -o \"" + eBookLocation + "\" -d \""+ extractionLocation +"\"");
        debug("eBook contents extracted sucessfully into location:"+extractionLocation);
        return extractionLocation;
  }

  public static bool isEPubFormat (string extractionLocation){
        bool ePubFormat = false;
        debug("Checking if mime type is valid ePub for contents at:"+extractionLocation);
        string ePubMimeContents = BookwormApp.Utils.fileOperations(
                                                                "READ", 
                                                                extractionLocation, 
                                                                BookwormApp.Constants.EPUB_MIME_SPECIFICATION_FILENAME, 
                                                                "");
        if("false" == ePubMimeContents){
            //Mime Content File was not found at expected location
            warning("Mime Content file could not be located at expected location:"+
                            extractionLocation+"/"+
                            BookwormApp.Constants.EPUB_MIME_SPECIFICATION_FILENAME);
            return false;
        }
        debug(  "Mime Contents found in file :"+
                        extractionLocation+"/"+
                        BookwormApp.Constants.EPUB_MIME_SPECIFICATION_FILENAME+
                        " is:"+ ePubMimeContents);
        if(ePubMimeContents.strip() != BookwormApp.Constants.EPUB_MIME_SPECIFICATION_CONTENT){
            debug(  "Mime Contents in file :"+extractionLocation+"/"+
                            BookwormApp.Constants.EPUB_MIME_SPECIFICATION_FILENAME+" is not :"+
                            BookwormApp.Constants.EPUB_MIME_SPECIFICATION_CONTENT+". No further parsing will be done.");
            return false;
        }else{
            //mime content is as expected
            ePubFormat = true;
        }
        debug("Sucessfully validated MIME type....");
        return ePubFormat;
  }

  public static string getOPFFileLocation(string extractionLocation){
        string locationOfOPFFile = "false";
        //read the META-INF/container.xml file
        string metaInfContents = BookwormApp.Utils.fileOperations("READ", 
                                                                            extractionLocation, 
                                                                            BookwormApp.Constants.EPUB_META_INF_FILENAME, "");
        if("false" == metaInfContents){
            //META-INF/container.xml File was not found at expected location
            warning("META-INF/container.xml file could not be located at expected location:"+
                            extractionLocation+"/"+
                            BookwormApp.Constants.EPUB_META_INF_FILENAME);
            return "false";
        }
        //locate the content of first occurence of "rootfiles"
        int startPosOfRootFiles = metaInfContents.index_of("<rootfiles>")+("<rootfiles>").length;
        int endPosOfRootFiles = metaInfContents.index_of("</rootfiles>",startPosOfRootFiles+1);
        if((startPosOfRootFiles - +("<rootfiles>").length) != -1 && endPosOfRootFiles != -1 && endPosOfRootFiles>startPosOfRootFiles){
            string rootfiles = metaInfContents.slice(startPosOfRootFiles, endPosOfRootFiles);
            //locate the content of "rootfile" tag
            int startPosOfRootFile = rootfiles.index_of("<rootfile")+("<rootfile").length;
            int endPosOfRootFile = rootfiles.index_of(">",startPosOfRootFile+1);
            if((startPosOfRootFile - +("<rootfile").length) != -1 && endPosOfRootFile != -1 && endPosOfRootFile>startPosOfRootFile){
                string rootfile = rootfiles.slice(startPosOfRootFile, endPosOfRootFile);
                //locate the content of "full-path" id
                int startPosOfContentOPFFile = rootfile.index_of("full-path=\"")+("full-path=\"").length;
                int endPosOfContentOPFFile = rootfile.index_of("\"", startPosOfContentOPFFile+1);
                if((   startPosOfContentOPFFile - ("full-path=\"").length) != -1 && 
                        endPosOfContentOPFFile != -1 && 
                        endPosOfContentOPFFile > startPosOfContentOPFFile)
                {
                    string ContentOPFFilePath = rootfile.slice(startPosOfContentOPFFile,endPosOfContentOPFFile);
                    debug(  "CONTENT.OPF file relative path [Fetched from file:"+ 
                                    extractionLocation+"/"+
                                    BookwormApp.Constants.EPUB_META_INF_FILENAME+"] is:"+ 
                                    ContentOPFFilePath);
                    locationOfOPFFile = extractionLocation + "/" + ContentOPFFilePath;
                }else{
                    warning("Parsing of META-INF/container.xml file at location:"+
                    extractionLocation+"/"+BookwormApp.Constants.EPUB_META_INF_FILENAME+
                    " has problems[startPosOfContentOPFFile="+startPosOfContentOPFFile.to_string()+
                    ", endPosOfContentOPFFile="+endPosOfContentOPFFile.to_string()+"].");
                    return "false";
                }
            }else{
                warning("Parsing of META-INF/container.xml file at location:"+
                extractionLocation+"/"+BookwormApp.Constants.EPUB_META_INF_FILENAME+
                " has problems[startPosOfRootFile="+startPosOfRootFile.to_string()+
                ", endPosOfRootFile="+endPosOfRootFile.to_string()+"].");
                return "false";
            }
        }else{
            warning("Parsing of META-INF/container.xml file at location:"+
            extractionLocation+"/"+BookwormApp.Constants.EPUB_META_INF_FILENAME+
            " has problems[startPosOfRootFiles="+startPosOfRootFiles.to_string()+
            ", endPosOfRootFiles="+endPosOfRootFiles.to_string()+"].");
            return "false";
        }
        debug ("Sucessfully determined absolute path to OPF File as : "+locationOfOPFFile);
        return locationOfOPFFile;
  }

  public static ArrayList<string> parseManifestData (string locationOfOPFFile){
    ArrayList<string> manifestItemsList = new ArrayList<string> ();
    //read contents from content.opf file
    string OpfContents = BookwormApp.Utils.fileOperations("READ_FILE", locationOfOPFFile, "", "");
    if("false" == OpfContents){
      //OPF Contents could not be read from file
      warning("OPF contents could not be read from file:"+locationOfOPFFile);
      manifestItemsList.add("false");
      return manifestItemsList;
    }
    try{
        string manifestData = BookwormApp.Utils.extractXMLTag(OpfContents, "<manifest", "</manifest>");
        string[] manifestList = BookwormApp.Utils.multiExtractBetweenTwoStrings (manifestData, "<item", ">");
        foreach(string manifestItem in manifestList){
            debug("Manifest Item="+manifestItem);
            manifestItemsList.add(manifestItem);
        }
        if(manifestItemsList.size < 1){
            //OPF Contents could not be read from file
            warning("OPF contents could not be read from file:"+locationOfOPFFile);
            manifestItemsList.add("false");
            return manifestItemsList;
        }
        debug("Completed extracting [no. of manifest items="+manifestItemsList.size.to_string()+"] manifest data from OPF File:"+locationOfOPFFile);
    }catch (Error e) {
        warning("Error in parsing manifest data ["+OpfContents+"] :"+ e.message );    
    }
    return manifestItemsList;
  }

  public static ArrayList<string> parseSpineData (string locationOfOPFFile){
    ArrayList<string> spineItemsList = new ArrayList<string> ();
    //read contents from content.opf file
    string OpfContents = BookwormApp.Utils.fileOperations("READ_FILE", locationOfOPFFile, "", "");
    if("false" == OpfContents){
      //OPF Contents could not be read from file
      warning("OPF contents could not be read from file:"+locationOfOPFFile);
      spineItemsList.add("false");
      return spineItemsList;
    }
    try{  
        string spineData = BookwormApp.Utils.extractXMLTag(OpfContents, "<spine", "</spine>");
        //check TOC id in Spine data and add as first item to Spine List
        int startTOCPosition = spineData.index_of("toc=\"");
        int endTOCPosition = spineData.index_of("\"", startTOCPosition+("toc=\"").length+1);
        if(startTOCPosition != -1 && endTOCPosition != -1 && endTOCPosition>startTOCPosition) {
          spineItemsList.add(spineData.slice(startTOCPosition, endTOCPosition));
          debug("TOC ID="+spineData.slice(startTOCPosition, endTOCPosition));
        }
        string[] spineList = BookwormApp.Utils.multiExtractBetweenTwoStrings (spineData, "<itemref", ">");
        foreach(string spineItem in spineList){
          debug("Spine Item="+spineItem);
          spineItemsList.add(spineItem);
        }
        if(spineItemsList.size < 1){
          //OPF Contents could not be read from file
          warning("OPF contents could not be read from file:"+locationOfOPFFile);
          spineItemsList.add("false");
          return spineItemsList;
        }
        debug("Completed extracting [no. of spine items="+spineItemsList.size.to_string()+"] spine data from OPF File:"+locationOfOPFFile);
    }catch (Error e) {
        warning ("Error in parsing spine data["+OpfContents+"] : "+e.message);
    }
    return spineItemsList;
  }

  public static BookwormApp.Book getContentList (owned BookwormApp.Book aBook, ArrayList<string> manifestItemsList, ArrayList<string> spineItemsList){
    StringBuilder bufferForSpineData = new StringBuilder("");
    StringBuilder bufferForLocationOfContentData = new StringBuilder("");
    //extract location of ncx file if present on the first index of the Spine List
    if(spineItemsList.get(0).contains("toc=\"")){
      int tocRefStartPos = spineItemsList.get(0).index_of("toc=\"")+("toc=\"").length;
      if((tocRefStartPos-("toc=\"").length) != -1){
        bufferForSpineData.assign(spineItemsList.get(0).slice(tocRefStartPos, spineItemsList.get(0).length));
      }else{
        bufferForSpineData.assign("");
      }
      if(bufferForSpineData.str.length > 0){
        //loop over manifest data to get location of TOC file
        foreach(string manifestItem in manifestItemsList){
          if(manifestItem.index_of("id=\""+bufferForSpineData.str+"\"") != -1){
            int startPosOfNCXContentItem = manifestItem.index_of("href=")+("href=").length+1 ;
            int endPosOfNCXContentItem = manifestItem.index_of("\"", startPosOfNCXContentItem+1);
            if(startPosOfNCXContentItem != -1 && endPosOfNCXContentItem != -1 && endPosOfNCXContentItem>startPosOfNCXContentItem){
              bufferForLocationOfContentData.assign(manifestItem.slice(startPosOfNCXContentItem, endPosOfNCXContentItem));
              debug("SpineData="+bufferForSpineData.str+" | Location Of NCX ContentData="+bufferForLocationOfContentData.str);
              //Read ncx file
              string navigationData = BookwormApp.Utils.fileOperations("READ_FILE", (BookwormApp.Utils.getFullPathFromFilename(aBook.getBaseLocationOfContents(),bufferForLocationOfContentData.str.strip())).strip(), "", "");
              string[] navPointList = BookwormApp.Utils.multiExtractBetweenTwoStrings(navigationData, "<navPoint", "</navPoint>");
              if(navPointList.length > 0){
                foreach(string navPointItem in navPointList){
                    string tocText  = "";
                    try{
                        tocText = BookwormApp.Utils.decodeHTMLChars(BookwormApp.Utils.extractXMLTag(navPointItem, "<text>", "</text>"));
                    } catch(Error e) {
                        warning ("Error in parsing ToC text ["+navPointItem+"] : "+e.message);  
                    }
                    int tocNavStartPoint = navPointItem.index_of("src=\"");
                    int tocNavEndPoint = navPointItem.index_of("\"", tocNavStartPoint+("src=\"").length);
                    if(tocNavStartPoint != -1 && tocNavEndPoint != -1 && tocNavEndPoint>tocNavStartPoint){
                        string tocNavLocation = navPointItem.slice(tocNavStartPoint+("src=\"").length, tocNavEndPoint).strip();
                        if(tocNavLocation.index_of("#") != -1){
        				    tocNavLocation = tocNavLocation.slice(0, tocNavLocation.index_of("#"));
        				}
                        tocNavLocation = BookwormApp.Utils.getFullPathFromFilename(aBook.getBaseLocationOfContents(), tocNavLocation);
                        if(tocNavLocation.length>0){
                            debug("tocText="+tocText+", tocNavLocation="+tocNavLocation);
                            HashMap<string,string> TOCMapItem = new HashMap<string,string>();
                            TOCMapItem.set(tocNavLocation, tocText);
                            aBook.setTOC(TOCMapItem);
                        }
                    }
                }
              }
            }
            break;
          }
        }
      }
    }
    // Clear the content list of any previous items
    aBook.clearBookContentList();
    //loop over remaning spine items(ncx file will be ignored as it will not have a prefix of idref)
    foreach(string spineItem in spineItemsList){
      int startPosOfSpineItem = spineItem.index_of("idref=")+("idref=").length+1;
      int endPosOfSpineItem = spineItem.index_of("\"", startPosOfSpineItem+1);
      if(startPosOfSpineItem != -1 && endPosOfSpineItem != -1 && endPosOfSpineItem>startPosOfSpineItem){
        bufferForSpineData.assign(spineItem.slice(startPosOfSpineItem, endPosOfSpineItem));
      }else{
        bufferForSpineData.assign("");//clear spine buffer if the data does not contain idref
      }
      if(bufferForSpineData.str.length > 0){
        //loop over manifest items to match the spine item
        foreach(string manifestItem in manifestItemsList){
          if(manifestItem.contains("id=\""+bufferForSpineData.str+"\"")){
            int startPosOfContentItem = manifestItem.index_of("href=")+("href=").length+1 ;
            int endPosOfContentItem = manifestItem.index_of("\"", startPosOfContentItem+1);
            if(startPosOfContentItem != -1 && endPosOfContentItem != -1 && endPosOfContentItem>startPosOfContentItem){
              bufferForLocationOfContentData.assign(manifestItem.slice(startPosOfContentItem, endPosOfContentItem));
              debug("SpineData="+bufferForSpineData.str+" | LocationOfContentData="+bufferForLocationOfContentData.str);
              aBook.setBookContentList(aBook.getBaseLocationOfContents()+bufferForLocationOfContentData.str);
            }
            break;
          }
        }
      }
    }
    return aBook;
  }

  public static BookwormApp.Book setCoverImage (owned BookwormApp.Book aBook, ArrayList<string> manifestItemsList){
    debug("Initiated process for cover image extraction of eBook located at:"+aBook.getBookExtractionLocation());
    string bookCoverLocation = "";
    //determine the location of the book's cover image
    for (int i = 0; i < manifestItemsList.size; i++) {
        if (manifestItemsList[i].down().contains("media-type=\"image") && manifestItemsList[i].down().contains("cover")) {
            int startIndexOfCoverLocation = manifestItemsList[i].index_of("href=\"")+6;
            int endIndexOfCoverLocation = manifestItemsList[i].index_of("\"", startIndexOfCoverLocation+1);
            if(startIndexOfCoverLocation != -1 && endIndexOfCoverLocation != -1 && endIndexOfCoverLocation > startIndexOfCoverLocation){
              bookCoverLocation = aBook.getBaseLocationOfContents() + manifestItemsList[i].slice(startIndexOfCoverLocation, endIndexOfCoverLocation);
            }
            break;
        }
    }
    //check if cover was not found and assign flag
    if(bookCoverLocation == null || bookCoverLocation.length < 1){
      aBook.setIsBookCoverImagePresent(false);
      debug("Cover image not found for book located at:"+aBook.getBookExtractionLocation());
    }else{
      //copy cover image to bookworm cover image cache
      aBook = BookwormApp.Utils.setBookCoverImage(aBook, bookCoverLocation);
    }
    return aBook;
  }

  public static BookwormApp.Book setBookMetaData(owned BookwormApp.Book aBook, string locationOfOPFFile){
    debug("Initiated process for finding meta data of eBook located at:"+aBook.getBookExtractionLocation());
    string OpfContents = BookwormApp.Utils.fileOperations("READ_FILE", locationOfOPFFile, "", "");
    //determine the title of the book from contents if it is not already available
    if(aBook.getBookTitle() != null && aBook.getBookTitle().length < 1){
      if(OpfContents.contains("<dc:title") && OpfContents.contains("</dc:title>")){
        int startOfTitleText = OpfContents.index_of(">", OpfContents.index_of("<dc:title"));
        int endOfTittleText = OpfContents.index_of("</dc:title>", startOfTitleText);
        if(startOfTitleText != -1 && endOfTittleText != -1 && endOfTittleText > startOfTitleText){
          string bookTitle = BookwormApp.Utils.decodeHTMLChars(OpfContents.slice(startOfTitleText+1, endOfTittleText));
          aBook.setBookTitle(bookTitle);
          debug("Determined eBook Title as:"+bookTitle);
        }
      }
    }
    //If the book title has still not been determined, use the file name as book title
    if(aBook.getBookTitle() != null && aBook.getBookTitle().length < 1){
      string bookTitle = File.new_for_path(aBook.getBookExtractionLocation()).get_basename();
      if(bookTitle.last_index_of(".") != -1){
        bookTitle = bookTitle.slice(0, bookTitle.last_index_of("."));
      }
      aBook.setBookTitle(bookTitle);
      debug("File name set as Title:"+bookTitle);
    }

    //determine the author of the book
    if(OpfContents.contains("<dc:creator") && OpfContents.contains("</dc:creator>")){
      int startOfAuthorText = OpfContents.index_of(">", OpfContents.index_of("<dc:creator"));
      int endOfAuthorText = OpfContents.index_of("</dc:creator>", startOfAuthorText);
      if(startOfAuthorText != -1 && endOfAuthorText != -1 && endOfAuthorText > startOfAuthorText){
        string bookAuthor = BookwormApp.Utils.decodeHTMLChars(OpfContents.slice(startOfAuthorText+1, endOfAuthorText));
        aBook.setBookAuthor(bookAuthor);
        debug("Determined eBook Author as:"+bookAuthor);
      }else{
        aBook.setBookAuthor(BookwormApp.Constants.TEXT_FOR_UNKNOWN_TITLE);
        debug("Could not determine eBook Author, default Author set");
      }
    }else{
      aBook.setBookAuthor(BookwormApp.Constants.TEXT_FOR_UNKNOWN_TITLE);
      debug("Could not determine eBook Author, default title set");
    }

    return aBook;
  }
}
