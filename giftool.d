#!/usr/bin/env rdmd

import std.stdio;
import std.conv;
import std.getopt;

enum GifBlockType
{
   Header,
   GlobalColorTable,
   GraphicsControlExtension
}

alias void function(GifBlockType, size_t, size_t, void*) GifCallback;

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

   @property
   public uint GlobalColorCount()
   {
      return 2 ^^ (this.colorTableSize + 1);
   }
}

struct GlobalColorTableBlock
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

/+
   Gradually reads through given file and calls back as it encounters sections
   of the GIF.
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
      this.ReadGraphicsControlExtension();
   }

   private HeaderBlock* header;
   public GlobalColorTableBlock* globalColorTable;

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

      GlobalColorTableBlock globalColorTable;
      globalColorTable.table.length = 3 * this.header.GlobalColorCount;
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

   @property
   public uint[] GlobalColors()
   {
      uint[] colors;

      auto table = this.globalColorTable.table;

      for (int i = 0; i < this.header.GlobalColorCount * 3; i += 3)
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
   writefln("Block type %s from 0x%X to 0x%X (length 0x%X)",
    blockType, start, end, end-start);

   if (!verbose)
   {
      return;
   }

   switch (blockType)
   {
      case GifBlockType.Header:
      HeaderBlock* header = cast(HeaderBlock*)(data);
      writefln("%s %s", header.signature, header.gifVersion);

      writefln("Dimensions: %d x %d", header.canvasWidth, header.canvasHeight);

      writefln("Global color table flag: %d", header.colorTableFlag);
      writefln("Color resolution: 0b%b (%d bits/pixel)", header.colorResolution,
       header.colorResolution + 1);
      writefln("Sort flag: %d", header.sortFlag);
      writefln("Global color table size: %d (%d)",
       header.colorTableSize, header.GlobalColorCount);
      writefln("BG color index: %d", header.bgColorIndex);
      writefln("Pixel aspect ratio: %d", header.aspectRatio);
      break;

      case GifBlockType.GlobalColorTable:

      break;

      case GifBlockType.GraphicsControlExtension:
      GraphicsControlExtensionBlock* block =
       cast(GraphicsControlExtensionBlock*)(data);
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
      break;

      default:
      static assert(false);
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
