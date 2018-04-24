//
//  main.m
//  CAStreamFormatTester
//
//  Created by Perrin Cloutier on 4/12/18.
//  Copyright © 2018 Perrin Cloutier. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>


int main (int argc, const char * argv[]) {
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    /* The third exercise from Learning Core Audio, ARC disabled.
     To use the property called kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
     you have to pass Core Audio a structure called
     AudioFileTypeAndFormatID (getting this property seems to be the only use for
     the struct).This structure has two members, a file type and a data format, both of
     which you can set with Core Audio constants found in the documentation or the
     AudioFile.h and AudioFormat.h headers. For starters, let’s use an AIFF file with
     PCM, as you created in the previous chapter. */
    
    AudioFileTypeAndFormatID fileTypeAndFormat;
    fileTypeAndFormat.mFileType = kAudioFileCAFType; //kAudioFileWAVEType //kAudioFileAIFFType;
    fileTypeAndFormat.mFormatID = kAudioFormatMPEG4AAC;//kAudioFormatLinearPCM;
    
    /* As before, you prepare an OSStatus to receive result codes from your Core Audio
     calls.You also prepare a UInt32 to hold the size of the info you’re interested in,
     which you have to negotiate before actually retrieving the info. */
    OSStatus audioErr = noErr;
    UInt32 infoSize = 0;
    /* Just as when you retrieved an audio file’s property in Listing 1.1, getting a global
     info property requires you to query in advance for the size of the property and to
     store the size in a pointer to a UInt32.The global info calls take a specifier, which
     acts like an argument to the property call and depends on the property you’re asking
     for (the docs for the properties describe what kind of specifier, if any, they
     expect). In the case of kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
     you provide the AudioFileTypeAndFormatID.*/
    audioErr = AudioFileGetGlobalInfoSize(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
                                          sizeof (fileTypeAndFormat),
                                          &fileTypeAndFormat,
                                          &infoSize);
    if (audioErr != noErr) {
        UInt32 err4cc = CFSwapInt32HostToBig(audioErr);
        NSLog (@"audioErr = %4.4s", (char*)&err4cc);
    }
    assert (audioErr == noErr);
    /* The AudioFileGetGlobalInfoSize calls tells you how much data you’ll receive
     when you actually get the global property, so you need to malloc some memory
     to hold the property. */
    AudioStreamBasicDescription *asbds = malloc (infoSize);
    
    /* With everything set up, you call AudioFileGetGlobalInfo to get the
    kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat, passing
    in the AudioFileTypeAndFormatID and the size of the buffer you’ve set up,
    along with a pointer to the buffer itself. */
    audioErr = AudioFileGetGlobalInfo(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
                                      sizeof (fileTypeAndFormat),
                                      &fileTypeAndFormat,
                                      &infoSize,
                                      asbds);
    assert (audioErr == noErr);
    /* The docs tell you that the property call provides an array of AudioStreamBasicDescriptions,
    so you can figure out the length of the array by dividing
    the data size by the size of an ASBD.That enables you to set up a for loop to
        investigate the ASBDs. */
    int asbdCount = infoSize / sizeof (AudioStreamBasicDescription);
    
    for (int i=0; i<asbdCount; i++) {
        UInt32 format4cc = CFSwapInt32HostToBig(asbds[i].mFormatID);
        /* The docs stated that the three ASBD fields that get filled in are mFormatID,
        mFormatFlags, and mBitsPerChannel. It’s handy to log the format ID, but to
        make it legible, you have to convert it out of the four-character code numeric format
         and into a readable four-character string.You do this with an endian swap because the
         UInt32 representation will reorder the bits from their original pseudostring representation */
        NSLog (@"%d: mFormatId: %4.4s, mFormatFlags: %d, mBitsPerChannel: %d",
               i, /* To pretty print the mFormatId’s endian-swapped representation, you can use the
                   format string %4.4s to force NSLog (or printf) to treat the pointer as an array of
                   8-bit characters that is exactly four characters long.The mFormatFlags and
                   mBitsPerChannel members are a bit field and numeric value, so just print them
                   as ints for now. */
               (char*)&format4cc,
               asbds[i].mFormatFlags,
               asbds[i].mBitsPerChannel);
    }
    /* Because you malloc()’d memory to hold the ASBD array, you need to be sure to
    free() it when you’re done with it so you don’t leak. */
    free (asbds);
    [pool drain];
    return 0;
}

