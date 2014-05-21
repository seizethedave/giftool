#!/usr/bin/env rdmd

import std.stdio;
import std.conv;

enum GifBlockType
{
   Header,
   GlobalColorTable,
   GraphicsControlExtension
}

alias void function(GifBlockType, void*) GifCallback;

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
         callback = (type, dataPtr)
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

   private void ReadHeader()
   {
      HeaderBlock headerBlock;

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

      this.callback(GifBlockType.Header, &headerBlock);
   }

   public ulong globalColorTableOffset;
   public ubyte[] globalColorTable;

   private void ReadGlobalColorTable()
   {
      if (this.header.colorTableFlag == 0)
      {
         // There is no global color table.
         this.globalColorTableOffset = 0L;
         return;
      }

      this.globalColorTableOffset = this.input.tell();
      this.globalColorTable.length = 3 * this.header.GlobalColorCount;
      this.input.rawRead(this.globalColorTable);
   }

   public ulong graphicsControlExtensionOffset;

   public ubyte extensionIntroducer;
   public ubyte graphicControlLabel;
   public ubyte blockByteSize;

   public ubyte reserved;
   public ubyte disposalMethod;
   public bool userInputFlag;
   public bool transparentColorFlag;

   public ushort delayTime;
   public ubyte transparentColorIndex;
   public ubyte blockTerminator;

   private void ReadGraphicsControlExtension()
   {
      this.graphicsControlExtensionOffset = this.input.tell();

      ubyte[8] extension;
      this.input.rawRead(extension);

      this.extensionIntroducer = extension[0];
      this.graphicControlLabel = extension[1];
      this.blockByteSize = extension[2];

      ubyte packed = extension[3];
      this.reserved =             (0b11100000 & packed) >> 5;
      this.disposalMethod =       (0b00011100 & packed) >> 2;
      this.userInputFlag =        (0b00000010 & packed) >> 1;
      this.transparentColorFlag = (0b00000001 & packed);

      this.delayTime = (extension[4] << 8) | extension[5];
      this.transparentColorIndex = extension[6];
      this.blockTerminator = extension[7];
   }

   @property
   public uint[] GlobalColors()
   {
      uint[] colors;

      for (int i = 0; i < this.header.GlobalColorCount * 3; i += 3)
      {
         ubyte red = this.globalColorTable[i + 0];
         ubyte green = this.globalColorTable[i + 1];
         ubyte blue = this.globalColorTable[i + 2];

         colors ~= (red << 16) | (green << 8) | blue;
      }

      return colors;
   }
}

void FoundBlock(GifBlockType blockType, void* data)
{
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
   }
}

void main()
{
   auto reader = new GifReader(stdin, &FoundBlock);

   writefln("Size of GCT buffer: %d", reader.globalColorTable.length);

   /*
   writefln("Colors:");

   foreach (color; reader.GlobalColors)
   {
      writefln("\t#%x", color);
   }
   */

   writefln("\nGraphics Control Extension:");
   writefln("GCE offset: 0x%X", reader.graphicsControlExtensionOffset);
   writefln("Extension intro: 0x%X", reader.extensionIntroducer);
   writefln("Graphic control label: 0x%X", reader.graphicControlLabel);
   writefln("Block byte size: %d", reader.blockByteSize);
   writefln("'reserved': %d", reader.reserved);
   writefln("Disposal method: %d", reader.disposalMethod);
   writefln("User input flag %d", reader.userInputFlag);
   writefln("Transparent color flag: %d", reader.transparentColorFlag);
   writefln("Delay time: %d", reader.delayTime);
   writefln("Transparent color index: %d", reader.transparentColorIndex);
   writefln("Block teminator: %d", reader.blockTerminator);
}

