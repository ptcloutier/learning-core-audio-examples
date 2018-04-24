//
//  main.m
//  CAAudioQueuePlayback
//
//  Created by Perrin Cloutier on 4/15/18.
//  Copyright © 2018 Perrin Cloutier. All rights reserved.
//
#import <CoreFoundation/CoreFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

/* Audio queue-based playback program from Learning Core Audio. ARC disabled. */

// grab an audio file from the file system to use in playback
#define kPlaybackFileLocation CFSTR("/Users/perrincloutier/Library/Developer/Xcode/DerivedData/CAAudioQueueRecorder-gxckrnwmbfecgvdnwritgvhsjnre/Build/Products/Debug/output.caf")
#define kNumberPlaybackBuffers 3


#pragma mark user info struct
typedef struct MyPlayer {
    AudioFileID playbackFile;
    SInt64 packetPosition;
    UInt32 numPacketsToRead;
    AudioStreamPacketDescription *packetDescs;
    Boolean isDone;
} MyPlayer;


#pragma mark utility functions


static void CheckError(OSStatus error, const char *operation)
{
    if (error == noErr) return;
    char errorString[20];
    // See if it appears to be a 4-char-code
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) &&
        isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else
        // No, format it as an integer
        sprintf(errorString, "%d", (int)error);
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    exit(1);
}


static void MyCopyEncoderCookieToQueue(AudioFileID theFile,
                                       AudioQueueRef queue ) {
    UInt32 propertySize;
    OSStatus result = AudioFileGetPropertyInfo (theFile,
                                                kAudioFilePropertyMagicCookieData,
                                                &propertySize,
                                                NULL);
    if (result == noErr && propertySize > 0)
    {
        Byte* magicCookie = (UInt8*)malloc(sizeof(UInt8) * propertySize);
        CheckError(AudioFileGetProperty (theFile,
                                         kAudioFilePropertyMagicCookieData,
                                         &propertySize,
                                         magicCookie),
                   "Get cookie from file failed");
        CheckError(AudioQueueSetProperty(queue,
                                         kAudioQueueProperty_MagicCookie,
                                         magicCookie,
                                         propertySize),
                   "Set cookie on queue failed");
        free(magicCookie);
    }
}


void CalculateBytesForTime (AudioFileID inAudioFile,
                            AudioStreamBasicDescription inDesc,
                            Float64 inSeconds,
                            UInt32 *outBufferSize,
                            UInt32 *outNumPackets)
{
    // first get the maximum packet size for the file’s encoding type, which is available from the audio file property kAudioFilePropertyPacketSizeUpperBound.
    UInt32 maxPacketSize;
    UInt32 propSize = sizeof(maxPacketSize);
    CheckError(AudioFileGetProperty(inAudioFile,
                                    kAudioFilePropertyPacketSizeUpperBound,
                                    &propSize,
                                    &maxPacketSize),
               "Couldn't get file's max packet size");
    // set up two constants as fail-safe values:a maxBufferSize of 64 KB and a minBufferSize of 16 KB.
    static const int maxBufferSize = 0x10000;
    static const int minBufferSize = 0x4000;
    // If the ASBD tells how many frames are in a packet, calculating the buffer size is simple:You can calculate how many packets elapse in the given number of seconds and multiply that by the maximum packet size to get a sufficiently large buffer.
    if (inDesc.mFramesPerPacket) {
        Float64 numPacketsForTime = inDesc.mSampleRate /
        inDesc.mFramesPerPacket * inSeconds;
        *outBufferSize = numPacketsForTime * maxPacketSize;
    }
    // On the other hand, if you don’t have an mFramesPerPacket value, you need to pick an arbitrarily “large enough” value, which is the greater of maxBufferSize and maxPacketSize. In the absolute worst case, at least the buffer will be large enough to hold one packet
    else {
        *outBufferSize = maxBufferSize > maxPacketSize ?
        maxBufferSize : maxPacketSize;
    }
    // few boundary checks. If the calculated buffer size (outBufferSize) is larger than both the maxBufferSize and the maxPacketSize, you clamp it to the maxBufferSize.You also must check to see that it’s not smaller than the minBufferSize.
    if (*outBufferSize > maxBufferSize &&
        *outBufferSize > maxPacketSize)
        *outBufferSize = maxBufferSize;
    else {
        if (*outBufferSize < minBufferSize)
            *outBufferSize = minBufferSize;
    }
//    with an outBufferSize calculated, you can divide it by the maxPacketSize to figure out how many packets can be safely read from the file on each callback
    *outNumPackets = *outBufferSize / maxPacketSize;
}

#pragma mark playback callback function
static void MyAQOutputCallback(void *inUserData,
                               AudioQueueRef inAQ,
                               AudioQueueBufferRef inCompleteAQBuffer)
{
    MyPlayer *aqp = (MyPlayer*)inUserData;
    if (aqp->isDone) return;
    UInt32 numBytes;
    UInt32 nPackets = aqp->numPacketsToRead;
    CheckError(AudioFileReadPackets(aqp->playbackFile,
                                    false,
                                    &numBytes,
                                    aqp->packetDescs,
                                    aqp->packetPosition,
                                    &nPackets,
                                    inCompleteAQBuffer->mAudioData),
               "AudioFileReadPackets failed");
    if (nPackets > 0) {
        inCompleteAQBuffer->mAudioDataByteSize = numBytes;
        AudioQueueEnqueueBuffer(inAQ,
                                inCompleteAQBuffer,
                                (aqp->packetDescs ? nPackets : 0),
                                aqp->packetDescs);
        aqp->packetPosition += nPackets;
    } else {
        CheckError(AudioQueueStop(inAQ,
                                  false),
                   "AudioQueueStop failed");
        aqp->isDone = true;
    }
}


#pragma mark main function
int main(int argc, const char *argv[])
{
    MyPlayer player = {0};
    // Open an audio file
    CFURLRef myFileURL = CFURLCreateWithFileSystemPath(
                                                       kCFAllocatorDefault,
                                                       kPlaybackFileLocation,
                                                       kCFURLPOSIXPathStyle,
                                                       false);
    CheckError(AudioFileOpenURL(myFileURL,
                                kAudioFileReadPermission,
                                0,
                                &player.playbackFile),
               "AudioFileOpenURL failed");
    CFRelease(myFileURL);
    // Set up format
    AudioStreamBasicDescription dataFormat;
    UInt32 propSize = sizeof(dataFormat);
    CheckError(AudioFileGetProperty(player.playbackFile, kAudioFilePropertyDataFormat,
                                    &propSize, &dataFormat),
               "Couldn't get file's data format");
    // Set up queue
    AudioQueueRef queue;
    CheckError(AudioQueueNewOutput(&dataFormat,
                                   MyAQOutputCallback,
                                   &player,
                                   NULL,
                                   NULL,
                                   0,
                                   &queue),
               "AudioQueueNewOutput failed");
    UInt32 bufferByteSize;
    CalculateBytesForTime(player.playbackFile,
                          dataFormat,
                          0.5,
                          &bufferByteSize,
                          &player.numPacketsToRead);
    bool isFormatVBR = (dataFormat.mBytesPerPacket == 0 ||
                        dataFormat.mFramesPerPacket == 0);
    if (isFormatVBR)
        player.packetDescs = (AudioStreamPacketDescription*)
        malloc(sizeof(AudioStreamPacketDescription) *
               player.numPacketsToRead);
    else
        player.packetDescs = NULL;
    MyCopyEncoderCookieToQueue(player.playbackFile, queue);
    AudioQueueBufferRef buffers[kNumberPlaybackBuffers];
    player.isDone = false;
    player.packetPosition = 0;
    int i;
    for (i = 0; i < kNumberPlaybackBuffers; ++i) {
        CheckError(AudioQueueAllocateBuffer(queue,
                                            bufferByteSize,
                                            &buffers[i]),
                   "AudioQueueAllocateBuffer failed");
        MyAQOutputCallback(&player, queue, buffers[i]);
        if (player.isDone)
            break;
    }
    // Start queue
    CheckError(AudioQueueStart(queue,
                               NULL),
               "AudioQueueStart failed");
    printf("Playing...\n");
    do
    {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode,
                           0.25,
                           false);
    } while (!player.isDone);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 2, false);
    // Clean up queue when finished
    player.isDone = true;
    CheckError(AudioQueueStop(queue,
                              TRUE),
               "AudioQueueStop failed");
    AudioQueueDispose(queue, TRUE);
    AudioFileClose(player.playbackFile);
    return 0;
}
