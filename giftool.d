#!/usr/bin/env rdmd

import std.stdio;
import std.conv;
import std.getopt;

enum GifBlockType
{
   Header,
   GlobalColorTable,
   GraphicsControlExtension,
   ApplicationExtension,
   CommentExtension,
   PlainTextExtension,
   TableBasedImage,
}

enum ubyte ImageSeparator = 0x2C;
enum ubyte ExtensionIntroducer = 0x21;
enum ubyte GraphicControlLabel = 0xF9;
enum ubyte CommentLabel = 0xFE;
enum ubyte PlainTextLabel = 0x01;
enum ubyte ApplicationExtensionLabel = 0xFF;
enum ubyte TrailerByte = 0x3B;

alias void function(GifBlockType, size_t, size_t, void*) GifCallback;

uint ColorCount(ubyte tableSize)
{
   return 2 ^^ (tableSize + 1);
}

struct HeaderBlock
{
   string signature;
   string gifVersion;

   ushort canvasWidth;
   ushort canvasHeight;
   ubyte bgColorIndex;
   ubyte aspectRatio;

   ubyte colorTableFlag;
   ubyte colorResolution;
   ubyte sortFlag;
   ubyte colorTableSize;
}

struct ColorTableBlock
{
   ubyte[] table;
}

struct GraphicsControlExtensionBlock
{
   ubyte extensionIntroducer;
   ubyte graphicControlLabel;
   ubyte blockByteSize;

   ubyte reserved;
   ubyte disposalMethod;
   bool userInputFlag;
   bool transparentColorFlag;

   ushort delayTime;
   ubyte transparentColorIndex;
   ubyte blockTerminator;
}

struct ApplicationExtensionBlock
{
   ubyte extensionIntroducer;
   ubyte label;

   ubyte blockByteSize;

   string applicationIdentifier;
   ubyte[3] authCode;

   ubyte[] data;
}

struct TableBasedImageBlock
{
   ushort imageSeparator;

   ushort left;
   ushort top;
   ushort width;
   ushort height;

   bool localColorTableFlag;
   bool interlaceFlag;
   bool sortFlag;
   ubyte reserved;
   ubyte localColorTableSize;

   ColorTableBlock colorTable;

   ubyte blocksRead;
}

/+
   Gradually reads through given file and calls back as it encounters sections
   of the GIF.

   GIF89a grammar excerpt:
   (http://www.w3.org/Graphics/GIF/spec-gif89a.txt)

   <GIF Data Stream> ::=     Header <Logical Screen> <Data>* Trailer

   <Logical Screen> ::=      Logical Screen Descriptor [Global Color Table]

   <Data> ::=                <Graphic Block>  |
                             <Special-Purpose Block>

   <Graphic Block> ::=   [Graphic Control Extension] <Graphic-Rendering Block>

   <Graphic-Rendering Block> ::=  <Table-Based Image>  |
                                  Plain Text Extension

   <Table-Based Image> ::=   Image Descriptor [Local Color Table] Image Data

   <Special-Purpose Block> ::=    Application Extension  |
                                  Comment Extension
 +/
class GifReader
{
   File input;
   GifCallback callback;

   this(ref File input, GifCallback callback)
   {
      this.input = input;

      if (callback == null)
      {
         // Default callback when not provided.
         callback = (type, start, end, dataPtr)
         {
            writefln("Encountered block of type %u", type);
         };
      }

      this.callback = callback;

      this.ReadHeader();
      this.ReadGlobalColorTable();

      bool didReadBlock;

      do
      {
         didReadBlock = this.ReadNextBlock();
      } while (didReadBlock);
   }

   private bool ReadNextBlock()
   {
      ubyte[1] blockPreamble;
      size_t position = this.input.tell();
      this.input.rawRead(blockPreamble);
      ubyte nextByte = blockPreamble[0];

      if (nextByte == ImageSeparator)
      {
         this.input.seek(position);
         this.ReadTableBasedImage();
         return true;
      }
      else if (nextByte == ExtensionIntroducer)
      {
         ubyte[1] extensionLabel;
         this.input.rawRead(extensionLabel);
         ubyte label = extensionLabel[0];

         switch (label)
         {
            case GraphicControlLabel:
            this.input.seek(position);
            this.ReadGraphicsControlExtension();
            return true;
            break;

            case ApplicationExtensionLabel:
            this.input.seek(position);
            this.ReadApplicationExtension();
            return true;
            break;

            case CommentLabel:
            this.input.seek(position);
            writefln("HRRRRR CommentLabel");
            return true;
            break;

            case PlainTextLabel:
            this.input.seek(position);
            writefln("HRRRRR PlainTextLabel");
            return true;
            break;

            default:
            writefln("Unexpected extension label 0x%X", label);
            return false;
            break;
         }
      }
      else if (nextByte == TrailerByte)
      {
         writefln("Trailer byte.");
         return false;
      }

      return false;
   }

   private HeaderBlock* header;
   public ColorTableBlock* globalColorTable;

   private void ReadHeader()
   {
      HeaderBlock headerBlock;

      size_t start = this.input.tell();

      char[3] sig;
      this.input.rawRead(sig);
      headerBlock.signature = to!string(sig);

      char[3] vers;
      this.input.rawRead(vers);
      headerBlock.gifVersion = to!string(vers);

      // Logical screen descriptor.
      ubyte[7] screen;
      this.input.rawRead(screen);

      headerBlock.canvasWidth = cast(ushort) (screen[1] << 8 | screen[0]);
      headerBlock.canvasHeight = cast(ushort) (screen[3] << 8 | screen[2]);

      ubyte packed = screen[4];
      headerBlock.colorTableFlag =  (0b10000000 & packed) >> 7;
      headerBlock.colorResolution = (0b01110000 & packed) >> 4;
      headerBlock.sortFlag =        (0b00001000 & packed) >> 3;
      headerBlock.colorTableSize =  (0b00000111 & packed);

      headerBlock.bgColorIndex = screen[5];
      headerBlock.aspectRatio = screen[6];

      this.header = &headerBlock;

      size_t end = this.input.tell();

      this.callback(GifBlockType.Header, start, end, &headerBlock);
   }

   private void ReadGlobalColorTable()
   {
      if (this.header.colorTableFlag == 0)
      {
         // There is no global color table.
         this.globalColorTable = null;
         return;
      }

      size_t start = this.input.tell();

      ColorTableBlock globalColorTable;
      globalColorTable.table.length = 3 * ColorCount(this.header.colorTableSize);
      this.input.rawRead(globalColorTable.table);

      size_t end = this.input.tell();

      this.callback(GifBlockType.GlobalColorTable, start, end,
       &globalColorTable);
   }

   private void ReadGraphicsControlExtension()
   {
      GraphicsControlExtensionBlock extension;

      size_t start = this.input.tell();

      ubyte[8] data;
      this.input.rawRead(data);

      extension.extensionIntroducer = data[0];
      extension.graphicControlLabel = data[1];
      extension.blockByteSize = data[2];

      ubyte packed = data[3];
      extension.reserved =             (0b11100000 & packed) >> 5;
      extension.disposalMethod =       (0b00011100 & packed) >> 2;
      extension.userInputFlag =        (0b00000010 & packed) >> 1;
      extension.transparentColorFlag = (0b00000001 & packed);

      extension.delayTime = (data[4] << 8) | data[5];
      extension.transparentColorIndex = data[6];
      extension.blockTerminator = data[7];

      size_t end = this.input.tell();

      this.callback(GifBlockType.GraphicsControlExtension, start, end,
       &extension);
   }

   private void ReadApplicationExtension()
   {
      ApplicationExtensionBlock extension;

      size_t start = this.input.tell();

      ubyte[14] data;
      this.input.rawRead(data);

      extension.extensionIntroducer = data[0];
      extension.label = data[1];
      extension.blockByteSize = data[2];

      extension.applicationIdentifier = cast(string)(data[3..11]);
      extension.authCode = data[11..14];

      while (true)
      {
         ubyte[1] dataChunk;
         this.input.rawRead(dataChunk);
         ubyte blockSize = dataChunk[0];

         if (blockSize == 0)
         {
            // End of stream.
            break;
         }

         auto block = new ubyte[blockSize];
         this.input.rawRead(block);
         extension.data ~= block;
      }

      size_t end = this.input.tell();

      this.callback(GifBlockType.ApplicationExtension, start, end,
       &extension);
   }

   private void ReadTableBasedImage()
   {
      TableBasedImageBlock block;

      ubyte[10] data;
      size_t start = this.input.tell();
      this.input.rawRead(data);
      block.imageSeparator = data[0];

      block.left = data[1] | data[2] << 8;
      block.top = data[3] | data[4] << 8;
      block.width = data[5] | data[6] << 8;
      block.height = data[7] | data[8] << 8;

      ubyte packed = data[9];
      block.localColorTableFlag = (packed & 0b10000000) >> 7;
      block.interlaceFlag =       (packed & 0b01000000) >> 6;
      block.sortFlag =            (packed & 0b00100000) >> 5;
      block.reserved =            (packed & 0b00011000) >> 3;
      block.localColorTableSize = (packed & 0b00000111);

      if (block.localColorTableFlag)
      {
         block.colorTable.table.length = 3 *
          ColorCount(block.localColorTableSize);

         this.input.rawRead(block.colorTable.table);
      }

      // Now we're at the image data blocks. Just fast-forward past them for
      // now.

      ubyte[1] minimumCodeSize;
      this.input.rawRead(minimumCodeSize);

      block.blocksRead = 0;

      while (true)
      {
         ubyte[1] blockSize;
         this.input.rawRead(blockSize);

         if (blockSize[0] == 0)
         {
            break;
         }

         auto dataBlock = new ubyte[blockSize[0]];
         this.input.rawRead(dataBlock);
         block.blocksRead++;
      }

      size_t end = this.input.tell();

      this.callback(GifBlockType.TableBasedImage, start, end, &block);
   }

   @property
   public uint[] GlobalColors()
   {
      uint[] colors;

      auto table = this.globalColorTable.table;
      uint colorCount = ColorCount(this.header.colorTableSize);

      for (int i = 0; i < colorCount * 3; i += 3)
      {
         ubyte red = table[i + 0];
         ubyte green = table[i + 1];
         ubyte blue = table[i + 2];

         colors ~= (red << 16) | (green << 8) | blue;
      }

      return colors;
   }
}

void FoundBlock(GifBlockType blockType, size_t start, size_t end, void* data)
{
   writefln("Block type %s from 0x%X to 0x%X (length 0x%X bytes)",
    blockType, start, end, end - start);

   if (!verbose)
   {
      return;
   }

   switch (blockType)
   {
      case GifBlockType.Header:
      auto header = cast(HeaderBlock*)(data);
      writefln("%s %s", header.signature, header.gifVersion);

      writefln("Dimensions: %d x %d", header.canvasWidth, header.canvasHeight);

      writefln("Global color table flag: %d", header.colorTableFlag);
      writefln("Color resolution: 0b%b (%d bits/pixel)", header.colorResolution,
       header.colorResolution + 1);
      writefln("Sort flag: %d", header.sortFlag);
      writefln("Global color table size: %d (%d)",
       header.colorTableSize, ColorCount(header.colorTableSize));
      writefln("BG color index: %d", header.bgColorIndex);
      writefln("Pixel aspect ratio: %d", header.aspectRatio);
      writeln();
      break;

      case GifBlockType.GlobalColorTable:

      break;

      case GifBlockType.GraphicsControlExtension:
      auto block = cast(GraphicsControlExtensionBlock*)(data);
      writefln("\nGraphics Control Extension:");
      writefln("Extension intro: 0x%X", block.extensionIntroducer);
      writefln("Graphic control label: 0x%X", block.graphicControlLabel);
      writefln("Block byte size: %d", block.blockByteSize);
      writefln("'reserved': %d", block.reserved);
      writefln("Disposal method: %d", block.disposalMethod);
      writefln("User input flag %d", block.userInputFlag);
      writefln("Transparent color flag: %d", block.transparentColorFlag);
      writefln("Delay time: %d", block.delayTime);
      writefln("Transparent color index: %d", block.transparentColorIndex);
      writefln("Block teminator: %d", block.blockTerminator);
      writeln();
      break;

      case GifBlockType.ApplicationExtension:
      auto block = cast(ApplicationExtensionBlock*)(data);
      writefln("\nExtension intro: 0x%X", block.extensionIntroducer);
      writefln("Label: 0x%X", block.label);
      writefln("Block byte size: %d", block.blockByteSize);

      writefln("Application identifier: '%s'", block.applicationIdentifier);
      writefln("Auth code: '%s'", cast(string)(block.authCode));
      writefln("Data length: %d", block.data.length);
      writeln();
      break;

      case GifBlockType.TableBasedImage:
      auto block = cast(TableBasedImageBlock*)(data);

      writefln("\nImage separator: 0x%X", block.imageSeparator);
      writefln("Image position: %d, %d", block.left, block.top);
      writefln("Image size: %d x %d", block.width, block.height);

      writefln("Local color table flag: %d", block.localColorTableFlag);
      writefln("Interlace flag: %d", block.interlaceFlag);
      writefln("Sort flag: %d", block.sortFlag);
      writefln("'reserved': %d", block.reserved);
      writefln("Local color table size: %d", block.localColorTableSize);

      writefln("Image data blocks read: %d", block.blocksRead);
      writeln();

      break;

      default:
      assert(false, "Invalid GifBlockType.");
      break;
   }
}

bool showHelp = false;
bool verbose = false;

void main(string[] args)
{
   getopt(args,
    "help|h", &showHelp,
    "verbose|v", &verbose);

   if (showHelp)
   {
      writefln("giftool");
      writefln("Usage:");
      writefln("--help -h: Show help.");
      writefln("--verbose -v: Show more stuff.");
      writefln("\nExamples:");
      writefln("\t./giftool < joker1.gif");
      writefln("\t./giftool --verbose < joker1.gif");
      return;
   }

   auto reader = new GifReader(stdin, &FoundBlock);
}
