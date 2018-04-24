//
//  main.m
//  CAToneFileGenerator
//
//  Created by Perrin Cloutier on 4/12/18.
//  Copyright © 2018 Perrin Cloutier. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

/* The second example from Learning Core Audio, ARC disabled, change the frequency in Hz in the argument via the scheme.
 Build and run this program with Xcode.To find the file that was written, open the
 Organizer, go to the Projects tab, select the CAToneFileGenerator project, and click
 the round arrow next to the Derived Data path.This opens a Finder window with the
 project metadata and products, in which you’ll find the path Build/Products/Debug.
 Inside this folder, you should see the CAToneFileGenerator executable and a sound file
 with a name representing the frequency you set as an argument to the executable, as in
 880.000-square.aif. */

/* #define a sample rate of 44,100 samples per second, or 44.1 kHz, the same as
with CD audio. */
#define SAMPLE_RATE 44100

/* Next, #define how many seconds of audio you want to create. */
#define DURATION 5.0

/* Put the filename in a #define’d format string so you can change the name later.
 The first example creates square waves, the simplest kind of wave form, so incorporate
 “square” in the filename.*/
//#define FILENAME_FORMAT @"%0.3f-square.aif"    // use this line for square wave
//#define FILENAME_FORMAT @"%0.3f-saw.aif"       // use this line for saw wave
#define FILENAME_FORMAT @"%0.3f-sine.aif"        // use this line for sine wave

int main (int argc, const char * argv[]) {
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    if (argc < 2) {
        printf ("Usage: CAToneFileGenerator n\n(where n is tone in Hz)");
        return -1;
    }
    /* As in the previous chapter’s example, you take a command-line argument here.
     This time, it’s a floating point number for the tone frequency you want to generate.
     If you want to run this from Xcode (instead of the command line), go to the
     Scheme editor, as before, and add an argument.You could use 261.626 for the note
     that’s middle C on a piano, or 440 for the A above that (which is known as middle
     A or concert A). */
    double hz = atof(argv[1]);
    
    
    assert (hz > 0);
    NSLog (@"generating %f hz tone", hz);
    NSString *fileName = [NSString stringWithFormat:
                          FILENAME_FORMAT, hz];
    
    NSString *filePath = [[[NSFileManager defaultManager] currentDirectoryPath]
                          stringByAppendingPathComponent: fileName];
    /* These two lines create the path to a file, using the FILENAME_FORMAT and the frequency
     to create a name, such as 261.626-square.aif.They then make an NSURL
     because the Audio File Services functions take URLs, not file paths. */
    
    NSURL *fileURL = [NSURL fileURLWithPath: filePath];
    // Prepare the format
    /* To create an audio file, you must provide a description of the audio that the file
     contains.You do this with what might be the most important and commonly used
     data structure in Core Audio, AudioStreamBasicDescription.This struct
     defines the most universal traits of a stream of audio: how many channels it has,
     the format it’s in, the bit rate, and so on. */
    AudioStreamBasicDescription asbd;
   
    /* In some cases, Core Audio fills in some of the fields for an AudioStreamBasicDescription
     that you don’t (or can’t) know when you’re writing the code.To do
     this, the field must be initialized to 0.As a common practice, always blank out the
     fields of an ASBD with memset() before you set any of them. */
    
    memset(&asbd, 0, sizeof(asbd));
    
    /* The next eight lines use individual fields of the AudioStreamBasicDescription
     to describe the data you’re going to write to the file. Here, they describe a stream
     that’s one-channel (mono) PCM, at a data rate of 44,100.You use 16-bit samples
     (again, the same as a CD), so each frame will have 2 bytes (one channel × 2 bytes
     of sample data). LPCM doesn’t use packets—they’re useful only for variable bit
     rate formats—so the bytesPerFrame and bytesPerPacket are equal.The other
     field to note is mFormatFlags, whose contents vary based on the format you’re
     using. For PCM, you must indicate whether your samples are big-endian (the high
     bits of a byte or word are numerically more significant than the lower ones) or
     vice versa. Here you’ll write to an AIFF file, which can take only big-endian
     PCM, so you need to set that in your ASBD.You also need to indicate the
     numeric format of the samples (kAudioFormatFlagIsSignedInteger), and you
     pass in a third flag to indicate that your sample values use all the bits available in
     each byte (kAudioFormatFlagIsPacked). mFormatFlags is a bit field, so you
     combine these behavior flags with the arithmetic OR operator (|). */
    
    asbd.mSampleRate = SAMPLE_RATE;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsBigEndian |
    kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    asbd.mBitsPerChannel = 16;
    asbd.mChannelsPerFrame = 1;
    asbd.mFramesPerPacket = 1;
    
    asbd.mBytesPerFrame = 2;
    asbd.mBytesPerPacket = 2;
    // Set up the file
    AudioFileID audioFile;
    OSStatus audioErr = noErr;
    
    /* You can now ask Core Audio to create an AudioFileID, ready for writing at the
        URL you’ve set up.The AudioFileCreateWithURL() function takes a URL
        (notice that you again use toll-free bridging to cast from a Cocoa NSURL to a Core
         Foundation CFURLRef), a constant to describe the AIFF file format, a pointer to
        the AudioStreamBasicDescription describing the audio data, behavior flags (in this case, indicating your desire to overwrite an existing file of the same name), and a pointer to populate with the created AudioFileID. */
    audioErr = AudioFileCreateWithURL((CFURLRef)fileURL,
                                      kAudioFileAIFFType,
                                      &asbd,
                                      kAudioFileFlags_EraseFile,
                                      &audioFile);
    assert (audioErr == noErr);
    /* You’re nearly ready to start writing samples. Before going into a loop to do so,
        you calculate how many samples you’ll need for DURATION seconds of sound at
            SAMPLE_RATE samples per second.Along with a counter variable, sampleCount,
            you set up bytesToWrite as a local variable only because the call to write the
            samples requires a pointer to this UInt32; you can’t just put the value into the
    parameter directly */
    long maxSampleCount = SAMPLE_RATE * DURATION;
    long sampleCount = 0;
    UInt32 bytesToWrite = 2;
    /* You need to keep track of how many samples are in a wavelength so you can calculate
     the values for samples that make up a wave*/
    double wavelengthInSamples = SAMPLE_RATE / hz;
    while (sampleCount < maxSampleCount) {
        for (int i=0; i<wavelengthInSamples; i++) {
            // Square wave
            SInt16 sample;
            /* For this first example, you’ll write one of the simplest waves, the square wave.The
             samples for this are trivial: For the first half of the wavelength, you provide a maximum
             value, and for the rest of the wavelength, you use a minimum value. So only
             two possible sample values ever are used: one high and one low. For the 16-bit
             signed integers, you’ll use the C constants that represent the maximum and minimum
             values, SHRT_MAX and SHRT_MIN.*/
            if (i < wavelengthInSamples/2) {
                /* You declared the audio format as big-endian signed integers in the
                AudioStreamBasicDescription, so you have to be careful to keep the 2-byte
                samples in that format. Modern Macs run on little-endian Intel CPUs, and the
                iPhone’s ARM processor is also little-endian, so you need to swap bytes from the
                CPU’s representation to big-endian.The Core Foundation function
                CFSwapInt16HostToBig() does this for you.This call also works on a big-endian
                    CPU, such as the PowerPC on older Macs, because it would just realize that the
                    host’s format is big-endian and would not do anything. */
//                sample = CFSwapInt16HostToBig (SHRT_MAX); //   use this line for square wave

//                sample = CFSwapInt16HostToBig (((i / wavelengthInSamples) * SHRT_MAX *2) - SHRT_MAX); // use this line for saw wave
                sample = CFSwapInt16HostToBig ((SInt16) SHRT_MAX *
                                               sin (2 * M_PI *
                                                    (i / wavelengthInSamples))); // use this line for sine wave
            } else {
                sample = CFSwapInt16HostToBig (SHRT_MIN);
            }
            /* Having calculated your sample, you write it to the file with AudioFileWriteBytes().This
            call takes five parameters: the AudioFileID to write to, a caching
            flag, the offset in the audio data that you’re writing to, the number of bytes you’re
            writing, and a pointer to the bytes to be written.You get to use this function
            because you have constant bit rate data; in more general cases, such as when writing
            compressed formats, you must use the more complex
            AudioFileWritePackets(). */
            audioErr = AudioFileWriteBytes(audioFile,
                                           false,
                                           sampleCount*2,
                                           &bytesToWrite,
                                           &sample);
            assert (audioErr == noErr);
            /* Increment sampleCount so that you’re writing your new data further and further
             into the file. */
            sampleCount++;
        }
    }
    /* Finally, call AudioFileClose() to finish and close the file. */
    audioErr = AudioFileClose(audioFile);
    assert (audioErr == noErr);
    NSLog (@"wrote %ld samples", sampleCount);
    [pool drain];
    return 0;
    
  
}
