// Pokémon icons and music for the importer (Importer.cs calls these).
//
// Icons: a/0/9/3 holds X/Y's 40×30 menu icons. Each entry is a BCLIM whose image data is X/Y's
// own palette format: u16 2, u16 color count, that many RGBA5551 colors, then one palette index per
// pixel (4 bits, or 8 when there are more than 16 colors), in 8×8 Morton-order tiles over a
// 64×32 texture. Entries are sorted by the game's internal Pokémon number (pmNNNN, the prefix of a
// model's textures; Gen 1–5 match the National Dex, Kalos doesn't), with every form side by side.
// importer/README.md explains how the indices in Importer.PokemonList were found.
//
// Music: romfs/sound/*.aac are plain ADTS AAC files (48 kHz stereo). Godot can't play AAC, so they're
// converted to MP3 with Windows' own Media Foundation (AAC decoder + MP3 encoder, both built in
// since Windows 8): no extra programs for players to install.

using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

static class Icons
{
    /// One icon as a 40×30 bitmap.
    public static Bitmap Decode(byte[] d)
    {
        if (BitConverter.ToUInt16(d, 0) != 2) throw new Exception("not an X/Y palette icon");
        int n = BitConverter.ToUInt16(d, 2);
        var palette = new Color[n];
        for (int k = 0; k < n; k++)
        {
            int v = BitConverter.ToUInt16(d, 4 + 2 * k);
            palette[k] = Color.FromArgb((v & 1) != 0 ? 255 : 0, (v >> 11 & 31) * 255 / 31, (v >> 6 & 31) * 255 / 31, (v >> 1 & 31) * 255 / 31);
        }
        int data = 4 + 2 * n;
        var bmp = new Bitmap(40, 30, PixelFormat.Format32bppArgb);
        int j = 0;
        for (int ty = 0; ty < 32; ty += 8)
            for (int tx = 0; tx < 64; tx += 8)
                for (int k = 0; k < 64; k++, j++)
                {
                    int x = tx + (k & 1 | k >> 1 & 2 | k >> 2 & 4);
                    int y = ty + (k >> 1 & 1 | k >> 2 & 2 | k >> 3 & 4);
                    int idx = n > 16 ? d[data + j] : (d[data + j / 2] >> ((j & 1) * 4)) & 15;
                    if (x < 40 && y < 30 && idx < n) bmp.SetPixel(x, y, palette[idx]);
                }
        return bmp;
    }
}

static class Music
{
    /// Converts one AAC file to a 192 kb/s MP3.
    public static void ToMp3(string aac, string mp3)
    {
        Check(MFCreateSourceReaderFromURL(aac, IntPtr.Zero, out IMFSourceReader reader));
        try
        {
            // Decode to 16-bit PCM.
            Check(MFCreateMediaType(out IMFMediaType pcm));
            pcm.SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
            pcm.SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
            pcm.SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
            Check(reader.SetCurrentMediaType(FIRST_AUDIO_STREAM, IntPtr.Zero, pcm));
            Check(reader.GetCurrentMediaType(FIRST_AUDIO_STREAM, out IMFMediaType decoded));
            decoded.GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, out int rate);
            decoded.GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, out int channels);

            // Encode to MP3 in an .mp3 file.
            Check(MFCreateAttributes(out IMFAttributes attrs, 1));
            attrs.SetGUID(MF_TRANSCODE_CONTAINERTYPE, MFTranscodeContainerType_MP3);
            if (File.Exists(mp3)) File.Delete(mp3);
            Check(MFCreateSinkWriterFromURL(mp3, IntPtr.Zero, attrs, out IMFSinkWriter writer));
            Check(MFCreateMediaType(out IMFMediaType outType));
            outType.SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
            outType.SetGUID(MF_MT_SUBTYPE, MFAudioFormat_MP3);
            outType.SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, rate);
            outType.SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels);
            outType.SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 24000); // 192 kb/s
            Check(writer.AddStream(outType, out int stream));
            Check(writer.SetInputMediaType(stream, decoded, null));
            Check(writer.BeginWriting());
            while (true)
            {
                Check(reader.ReadSample(FIRST_AUDIO_STREAM, 0, out _, out int flags, out _, out IntPtr sample));
                if (sample != IntPtr.Zero)
                {
                    Check(writer.WriteSample(stream, sample));
                    Marshal.Release(sample);
                }
                if ((flags & END_OF_STREAM) != 0) break;
            }
            Check(writer.Finalize_());
            Marshal.ReleaseComObject(writer);
        }
        finally
        {
            Marshal.ReleaseComObject(reader);
        }
    }

    public static void Start() => Check(MFStartup(0x00020070, 0));
    public static void Stop() => MFShutdown();

    static void Check(int hr)
    {
        if (hr < 0) Marshal.ThrowExceptionForHR(hr);
    }

    // --- Media Foundation interop (only the calls used above; unused slots keep the vtable order) ----

    const int FIRST_AUDIO_STREAM = unchecked((int)0xFFFFFFFD);
    const int END_OF_STREAM = 0x2;
    static readonly Guid MF_MT_MAJOR_TYPE = new Guid("48eba18e-f8c9-4687-bf11-0a74c9f96a8f");
    static readonly Guid MF_MT_SUBTYPE = new Guid("f7e34c9a-42e8-4714-b74b-cb29d72c35e5");
    static readonly Guid MFMediaType_Audio = new Guid("73647561-0000-0010-8000-00aa00389b71");
    static readonly Guid MFAudioFormat_PCM = new Guid("00000001-0000-0010-8000-00aa00389b71");
    static readonly Guid MFAudioFormat_MP3 = new Guid("00000055-0000-0010-8000-00aa00389b71");
    static readonly Guid MF_MT_AUDIO_NUM_CHANNELS = new Guid("37e48bf5-645e-4c5b-89de-ada9e29b696a");
    static readonly Guid MF_MT_AUDIO_SAMPLES_PER_SECOND = new Guid("5faeeae7-0290-4c31-9e8a-c534f68d9dba");
    static readonly Guid MF_MT_AUDIO_AVG_BYTES_PER_SECOND = new Guid("1aab75c8-cfef-451c-ab95-ac034b8e1731");
    static readonly Guid MF_MT_AUDIO_BITS_PER_SAMPLE = new Guid("f2deb57f-40fa-4764-aa33-ed4f2d1ff669");
    static readonly Guid MF_TRANSCODE_CONTAINERTYPE = new Guid("150ff23f-4abc-478b-ac4f-e1916fba1cca");
    static readonly Guid MFTranscodeContainerType_MP3 = new Guid("e438b912-83f1-4de6-9e3a-9ffbc6dd24d1");

    [DllImport("mfplat.dll")] static extern int MFStartup(int version, int flags);
    [DllImport("mfplat.dll")] static extern int MFShutdown();
    [DllImport("mfplat.dll")] static extern int MFCreateMediaType(out IMFMediaType type);
    [DllImport("mfplat.dll")] static extern int MFCreateAttributes(out IMFAttributes attrs, int size);
    [DllImport("mfreadwrite.dll", CharSet = CharSet.Unicode)]
    static extern int MFCreateSourceReaderFromURL(string url, IntPtr attributes, out IMFSourceReader reader);
    [DllImport("mfreadwrite.dll", CharSet = CharSet.Unicode)]
    static extern int MFCreateSinkWriterFromURL(string url, IntPtr byteStream, IMFAttributes attributes, out IMFSinkWriter writer);

    [ComImport, Guid("2cd2d921-c447-44a7-a13c-4adabfc247e3"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFAttributes
    {
        void GetItem(); void GetItemType(); void CompareItem(); void Compare();
        [PreserveSig] int GetUINT32([MarshalAs(UnmanagedType.LPStruct)] Guid key, out int value);
        void GetUINT64(); void GetDouble(); void GetGUID(); void GetStringLength(); void GetString();
        void GetAllocatedString(); void GetBlobSize(); void GetBlob(); void GetAllocatedBlob(); void GetUnknown();
        void SetItem(); void DeleteItem(); void DeleteAllItems();
        [PreserveSig] int SetUINT32([MarshalAs(UnmanagedType.LPStruct)] Guid key, int value);
        void SetUINT64(); void SetDouble();
        [PreserveSig] int SetGUID([MarshalAs(UnmanagedType.LPStruct)] Guid key, [MarshalAs(UnmanagedType.LPStruct)] Guid value);
        void SetString(); void SetBlob(); void SetUnknown(); void LockStore(); void UnlockStore();
        void GetCount(); void GetItemByIndex(); void CopyAllItems();
    }

    [ComImport, Guid("44ae0fa8-ea31-4109-8d2e-4cae4997c555"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFMediaType
    {
        void GetItem(); void GetItemType(); void CompareItem(); void Compare();
        [PreserveSig] int GetUINT32([MarshalAs(UnmanagedType.LPStruct)] Guid key, out int value);
        void GetUINT64(); void GetDouble(); void GetGUID(); void GetStringLength(); void GetString();
        void GetAllocatedString(); void GetBlobSize(); void GetBlob(); void GetAllocatedBlob(); void GetUnknown();
        void SetItem(); void DeleteItem(); void DeleteAllItems();
        [PreserveSig] int SetUINT32([MarshalAs(UnmanagedType.LPStruct)] Guid key, int value);
        void SetUINT64(); void SetDouble();
        [PreserveSig] int SetGUID([MarshalAs(UnmanagedType.LPStruct)] Guid key, [MarshalAs(UnmanagedType.LPStruct)] Guid value);
        void SetString(); void SetBlob(); void SetUnknown(); void LockStore(); void UnlockStore();
        void GetCount(); void GetItemByIndex(); void CopyAllItems();
        void GetMajorType(); void IsCompressedFormat(); void IsEqual(); void GetRepresentation(); void FreeRepresentation();
    }

    [ComImport, Guid("70ae66f2-c809-4e4f-8915-bdcb406b7993"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFSourceReader
    {
        void GetStreamSelection(); void SetStreamSelection(); void GetNativeMediaType();
        [PreserveSig] int GetCurrentMediaType(int stream, out IMFMediaType type);
        [PreserveSig] int SetCurrentMediaType(int stream, IntPtr reserved, IMFMediaType type);
        void SetCurrentPosition();
        [PreserveSig] int ReadSample(int stream, int control, out int actualStream, out int flags, out long timestamp, out IntPtr sample);
        void Flush(); void GetServiceForStream(); void GetPresentationAttribute();
    }

    [ComImport, Guid("3137f1cd-fe5e-4805-a5d8-fb477448cb3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMFSinkWriter
    {
        [PreserveSig] int AddStream(IMFMediaType type, out int stream);
        [PreserveSig] int SetInputMediaType(int stream, IMFMediaType type, IMFAttributes encodingParameters);
        [PreserveSig] int BeginWriting();
        [PreserveSig] int WriteSample(int stream, IntPtr sample);
        void SendStreamTick(); void PlaceMarker(); void NotifyEndOfSegment(); void Flush();
        [PreserveSig] int Finalize_();
        void GetServiceForStream(); void GetStatistics();
    }
}
