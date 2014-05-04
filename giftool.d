#!/usr/bin/env rdmd

import std.stdio;
import std.conv;

class GifReader
{
   File input;

   public string signature;
   public string gifVersion;

   public ushort canvasWidth;
   public ushort canvasHeight;
   public ubyte bgColorIndex;
   public ubyte aspectRatio;

   public ubyte colorTableFlag;
   public ubyte colorResolution;
   public ubyte sortFlag;
   public ubyte colorTableSize;

   public ubyte[] globalColorTable;

   this(ref File input)
   {
      this.input = input;
      this.ReadHeader();
      this.ReadGlobalColorTable();
      this.ReadGraphicsControlExtension();
   }

   private void ReadHeader()
   {
      char[3] sig;
      this.input.rawRead(sig);
      this.signature = to!string(sig);

      char[3] vers;
      this.input.rawRead(vers);
      this.gifVersion = to!string(vers);

      // Logical screen descriptor.
      ubyte[7] screen;
      this.input.rawRead(screen);

      this.canvasWidth = cast(ushort) (screen[1] << 8 | screen[0]);
      this.canvasHeight = cast(ushort) (screen[3] << 8 | screen[2]);

      ubyte packed = screen[4];
      this.colorTableFlag =  (0b10000000 & packed) >> 7;
      this.colorResolution = (0b01110000 & packed) >> 4;
      this.sortFlag =        (0b00001000 & packed) >> 3;
      this.colorTableSize =  (0b00000111 & packed);

      this.bgColorIndex = screen[5];
      this.aspectRatio = screen[6];
   }

   private void ReadGlobalColorTable()
   {
      if (this.colorTableFlag == 0)
      {
         // There is no global color table.
         return;
      }

      this.globalColorTable.length = 3 * this.GlobalColorCount;
      this.input.rawRead(this.globalColorTable);
   }

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
   public uint GlobalColorCount()
   {
      return 2 ^^ (this.colorTableSize + 1);
   }

   @property
   public uint[] GlobalColors()
   {
      uint[] colors;

      for (int i = 0; i < this.GlobalColorCount * 3; i += 3)
      {
         ubyte red = this.globalColorTable[i + 0];
         ubyte green = this.globalColorTable[i + 1];
         ubyte blue = this.globalColorTable[i + 2];

         colors ~= (red << 16) | (green << 8) | blue;
      }

      return colors;
   }
}

void main()
{
   auto reader = new GifReader(stdin);

   writefln("%s %s", reader.signature, reader.gifVersion);

   writefln("Dimensions: %d x %d", reader.canvasWidth, reader.canvasHeight);

   writefln("Global color table flag: %d", reader.colorTableFlag);
   writefln("Color resolution: 0b%b (%d bits/pixel)", reader.colorResolution,
    reader.colorResolution + 1);
   writefln("Sort flag: %d", reader.sortFlag);
   writefln("Global color table size: %d (%d)",
    reader.colorTableSize, reader.GlobalColorCount);
   writefln("BG color index: %d", reader.bgColorIndex);
   writefln("Pixel aspect ratio: %d", reader.aspectRatio);

   writefln("Size of GCT buffer: %d", reader.globalColorTable.length);

   /*
   writefln("Colors:");

   foreach (color; reader.GlobalColors)
   {
      writefln("\t#%x", color);
   }
   */

   writefln("\nGraphics Control Extension:");
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

