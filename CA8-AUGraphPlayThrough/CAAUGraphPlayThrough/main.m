//
//  main.m
//  CAAUGraphPlayThrough
//
//  Created by Perrin Cloutier on 4/22/18.
//  Copyright © 2018 Perrin Cloutier. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <CoreAudio/CoreAudio.h>
#include "CARingBuffer.h"
#import <ApplicationServices/ApplicationServices.h>


 #define PART_II

#pragma mark user-data struct
typedef struct MyAUGraphPlayer {
    AudioStreamBasicDescription streamFormat;
    AUGraph graph;
    AudioUnit inputUnit;
    AudioUnit outputUnit;
#ifdef PART_II
    AudioUnit speechUnit;
#endif
    AudioBufferList *inputBuffer;
    CARingBuffer *ringBuffer;
    Float64 firstInputSampleTime;
    Float64 firstOutputSampleTime;
    Float64 inToOutSampleTimeOffset;
} MyAUGraphPlayer;



#pragma mark - render procs -

OSStatus InputRenderProc(void *inRefCon,
                         AudioUnitRenderActionFlags *ioActionFlags,
                         const AudioTimeStamp *inTimeStamp,
                         UInt32 inBusNumber,
                         UInt32 inNumberFrames,
                         AudioBufferList * ioData) {
    
    MyAUGraphPlayer *player = (MyAUGraphPlayer*) inRefCon;
    
    // Logging time stamps from input AUHAL and calculating time stamp offset
    // Have we ever logged input timing? (for offset calculation)
    if (player->firstInputSampleTime < 0.0) {
        player->firstInputSampleTime = inTimeStamp->mSampleTime;
        if ((player->firstOutputSampleTime > 0.0) &&
            (player->inToOutSampleTimeOffset < 0.0)) {
            player->inToOutSampleTimeOffset =
            player->firstInputSampleTime - player->firstOutputSampleTime;
        }
    }
    // Retrieving captured samples from input AUHAL
    OSStatus inputProcErr = noErr;
    inputProcErr = AudioUnitRender(player->inputUnit,
                                   ioActionFlags,
                                   inTimeStamp,
                                   inBusNumber,
                                   inNumberFrames,
                                   player->inputBuffer);
    // Storing captured samples to a CARingBuffer
    if (! inputProcErr) {
        inputProcErr = player->ringBuffer->Store(player->inputBuffer,
                                                 inNumberFrames,
                                                 inTimeStamp->mSampleTime);
    }
    return inputProcErr;
}

OSStatus GraphRenderProc(void *inRefCon,
                         AudioUnitRenderActionFlags *ioActionFlags,
                         const AudioTimeStamp *inTimeStamp,
                         UInt32 inBusNumber,
                         UInt32 inNumberFrames,
                         AudioBufferList * ioData) {
    
    MyAUGraphPlayer *player = (MyAUGraphPlayer*) inRefCon;
    // Have we ever logged output timing? (for offset calculation)
    if (player->firstOutputSampleTime < 0.0) {
        player->firstOutputSampleTime = inTimeStamp->mSampleTime;
        if ((player->firstInputSampleTime > 0.0) &&
            (player->inToOutSampleTimeOffset < 0.0)) {
            player->inToOutSampleTimeOffset =
            player->firstInputSampleTime - player->firstOutputSampleTime;
        }
    }
    // Copy samples out of ring buffer
    OSStatus outputProcErr = noErr;
    outputProcErr = player->ringBuffer->Fetch(ioData,
                                              inNumberFrames,
                                              inTimeStamp->mSampleTime +
                                              player->inToOutSampleTimeOffset);
    return outputProcErr;
}

#pragma mark - utility functions -
static void CheckError(OSStatus error, const char *operation) {
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




void CreateInputUnit (MyAUGraphPlayer *player) {
    
    // Generates a description that matches audio HAL
    AudioComponentDescription inputcd = {0};
    inputcd.componentType = kAudioUnitType_Output;
    inputcd.componentSubType = kAudioUnitSubType_HALOutput;
    inputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    AudioComponent comp = AudioComponentFindNext(NULL, &inputcd);
    
    if (comp == NULL) {
        printf ("Can't get output unit");
        exit (-1);
    }
    CheckError(AudioComponentInstanceNew(comp,
                                         &player->inputUnit),
               "Couldn't open component for inputUnit");
    
    // Enabling I/O on Input AUHAL
    UInt32 disableFlag = 0;
    UInt32 enableFlag = 1;
    AudioUnitScope outputBus = 0;
    AudioUnitScope inputBus = 1;
    
    CheckError (AudioUnitSetProperty(player->inputUnit,
                                     kAudioOutputUnitProperty_EnableIO,
                                     kAudioUnitScope_Input,
                                     inputBus,
                                     &enableFlag,
                                     sizeof(enableFlag)),
                "Couldn't enable input on I/O unit");
    
    CheckError (AudioUnitSetProperty(player->inputUnit,
                                     kAudioOutputUnitProperty_EnableIO,
                                     kAudioUnitScope_Output,
                                     outputBus,
                                     &disableFlag,
                                     sizeof(enableFlag)),
                "Couldn't disable output on I/O unit");
    
    // Getting the default audio input device
    AudioDeviceID defaultDevice = kAudioObjectUnknown;
    UInt32 propertySize = sizeof (defaultDevice);
    AudioObjectPropertyAddress defaultDeviceProperty;
    defaultDeviceProperty.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    defaultDeviceProperty.mScope = kAudioObjectPropertyScopeGlobal;
    defaultDeviceProperty.mElement = kAudioObjectPropertyElementMaster;
    
    CheckError (AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                           &defaultDeviceProperty,
                                           0,
                                           NULL,
                                           &propertySize,
                                           &defaultDevice),
                "Couldn't get default input device");
    
    // Setting the current device of the AUHAL
    CheckError(AudioUnitSetProperty(player->inputUnit,
                                    kAudioOutputUnitProperty_CurrentDevice,
                                    kAudioUnitScope_Global,
                                    outputBus,
                                    &defaultDevice,
                                    sizeof(defaultDevice)),
               "Couldn't set default device on I/O unit");
    
    // Getting the ASBD for from the input AUHAL
    propertySize = sizeof (AudioStreamBasicDescription);
    CheckError(AudioUnitGetProperty(player->inputUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Output,
                                    inputBus,
                                    &player->streamFormat,
                                    &propertySize),
               "Couldn't get ASBD from input unit");
    
    // Adopting the hardware input sample rate
    AudioStreamBasicDescription deviceFormat;
    CheckError(AudioUnitGetProperty(player->inputUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Input,
                                    inputBus,
                                    &deviceFormat,
                                    &propertySize),
               "Couldn't get ASBD from input unit");
    player->streamFormat.mSampleRate = deviceFormat.mSampleRate;
    
    // Calculating capture buffer size for an I/O Unit
    UInt32 bufferSizeFrames = 0;
    propertySize = sizeof(UInt32);
    CheckError (AudioUnitGetProperty(player->inputUnit,
                                     kAudioDevicePropertyBufferFrameSize,
                                     kAudioUnitScope_Global,
                                     0,
                                     &bufferSizeFrames,
                                     &propertySize),
                "Couldn't get buffer frame size from input unit");
    UInt32 bufferSizeBytes = bufferSizeFrames * sizeof(Float32);
    
    // Creating an AudioBufferList to receive capture data
    // Allocate an AudioBufferList plus enough space for
    // array of AudioBuffers
    UInt32 propsize = offsetof(AudioBufferList,
                               mBuffers[0]) + (sizeof(AudioBuffer) *
                                                                player->streamFormat.mChannelsPerFrame);// malloc buffer lists
    player->inputBuffer = (AudioBufferList *)malloc(propsize);
    player->inputBuffer->mNumberBuffers = player->streamFormat.mChannelsPerFrame;
    
    // Pre-malloc buffers for AudioBufferLists
    for(UInt32 i =0; i< player->inputBuffer->mNumberBuffers ; i++) {
        player->inputBuffer->mBuffers[i].mNumberChannels = 1;
        player->inputBuffer->mBuffers[i].mDataByteSize = bufferSizeBytes;
        player->inputBuffer->mBuffers[i].mData = malloc(bufferSizeBytes);
    }
    // Alloc ring buffer that will hold data between the
    // two audio devices
    player->ringBuffer = new CARingBuffer();
    player->ringBuffer->Allocate(player->streamFormat.mChannelsPerFrame,
                                 player->streamFormat.mBytesPerFrame,
                                 bufferSizeFrames * 3);
    
    // Setting up an inpu callback on an AUHAL
    // Set render proc to supply samples from input unit
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = InputRenderProc;
    callbackStruct.inputProcRefCon = player;
    CheckError(AudioUnitSetProperty(player->inputUnit,
                                    kAudioOutputUnitProperty_SetInputCallback,
                                    kAudioUnitScope_Global,
                                    0,
                                    &callbackStruct,
                                    sizeof(callbackStruct)),
               "Couldn't set input callback");
    
    // Initializing input AUHAL and offset time counters
    CheckError(AudioUnitInitialize(player->inputUnit),
               "Couldn't initialize input unit");
    player->firstInputSampleTime = -1;
    player->inToOutSampleTimeOffset = -1;
    printf ("Bottom of CreateInputUnit()\n");
}

     void CreateMyAUGraph(MyAUGraphPlayer *player) {
       
        // Create a new AUGraph
        CheckError(NewAUGraph(&player->graph),
                   "NewAUGraph failed");
         
        // Generate a description that matches default output
        AudioComponentDescription outputcd = {0};
        outputcd.componentType = kAudioUnitType_Output;
        outputcd.componentSubType = kAudioUnitSubType_DefaultOutput;
        outputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
        AudioComponent comp = AudioComponentFindNext(NULL, &outputcd);
        if (comp == NULL) {
            printf ("Can't get output unit"); exit (-1);
        }
         
        // Adds a node with above description to the graph
        AUNode outputNode;
        CheckError(AUGraphAddNode(player->graph,
                                  &outputcd,
                                  &outputNode),
                   "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed");
#ifdef PART_II
         // Creating a Stereo Mixer Unit in an AUGraph
         // Add a mixer to the graph
         AudioComponentDescription mixercd = {0};
         mixercd.componentType = kAudioUnitType_Mixer;
         mixercd.componentSubType = kAudioUnitSubType_StereoMixer;
         mixercd.componentManufacturer = kAudioUnitManufacturer_Apple;
         AUNode mixerNode;
         CheckError(AUGraphAddNode(player->graph,
                                   &mixercd,
                                   &mixerNode),
                    "AUGraphAddNode[kAudioUnitSubType_StereoMixer] failed");
         // Add the speech synthesizer to the graph
         AudioComponentDescription speechcd = {0};
         speechcd.componentType = kAudioUnitType_Generator;
         speechcd.componentSubType = kAudioUnitSubType_SpeechSynthesis;
         speechcd.componentManufacturer = kAudioUnitManufacturer_Apple;
         AUNode speechNode;
         CheckError(AUGraphAddNode(player->graph,
                                   &speechcd,
                                   &speechNode),
                    "AUGraphAddNode[kAudioUnitSubType_AudioFilePlayer] failed");
         
         //Getting Default Output, Speech Synthesis, and Mixer Audio Units from Enclosing AUNodes
         // Opening the graph opens all contained audio
         // units but does not allocate any resources yet
         CheckError(AUGraphOpen(player->graph),
                    "AUGraphOpen failed");
         // Get the reference to the AudioUnit objects for the
         // various nodes
         CheckError(AUGraphNodeInfo(player->graph,
                                    outputNode,
                                    NULL,
                                    &player->outputUnit),
                    "AUGraphNodeInfo failed");
         CheckError(AUGraphNodeInfo(player->graph,
                                    speechNode,
                                    NULL,
                                    &player->speechUnit),
                    "AUGraphNodeInfo failed");
         AudioUnit mixerUnit;
         CheckError(AUGraphNodeInfo(player->graph,
                                    mixerNode,
                                    NULL,
                                    &mixerUnit),
                    "AUGraphNodeInfo failed");
         
         // Set ASBDs here
         UInt32 propertySize = sizeof (AudioStreamBasicDescription);
         CheckError(AudioUnitSetProperty(player->outputUnit,
                                         kAudioUnitProperty_StreamFormat,
                                         kAudioUnitScope_Input,
                                         0,
                                         &player->streamFormat,
                                         propertySize),
                    "Couldn't set stream format on output unit");
         
         CheckError(AudioUnitSetProperty(mixerUnit,
                                         kAudioUnitProperty_StreamFormat,
                                         kAudioUnitScope_Input,
                                         0,
                                         &player->streamFormat,
                                         propertySize),
                    "Couldn't set stream format on mixer unit bus 0");
         
         CheckError(AudioUnitSetProperty(mixerUnit,
                                         kAudioUnitProperty_StreamFormat,
                                         kAudioUnitScope_Input,
                                         1,
                                         &player->streamFormat,
                                         propertySize),
                    "Couldn't set stream format on mixer unit bus 1");
         // Connecting Speech Synthesis, Stereo Mixer, and Default Output Units
         // Connections
         // Mixer output scope / bus 0 to outputUnit input scope / bus 0
         // Mixer input scope / bus 0 to render callback
         // (from ringbuffer, which in turn is from inputUnit)
         // Mixer input scope / bus 1 to speech unit output scope / bus 0
         CheckError(AUGraphConnectNodeInput(player->graph,
                                            mixerNode,
                                            0,
                                            outputNode,
                                            0),
                    "Couldn't connect mixer output(0) to outputNode (0)");
         
         CheckError(AUGraphConnectNodeInput(player->graph,
                                            speechNode,
                                            0,
                                            mixerNode,
                                            1),
                    "Couldn't connect speech synth unit output (0) to mixer input (1)");
         
         AURenderCallbackStruct callbackStruct;
         callbackStruct.inputProc = GraphRenderProc;
         callbackStruct.inputProcRefCon = player;
         CheckError(AudioUnitSetProperty(mixerUnit,
                                         kAudioUnitProperty_SetRenderCallback,
                                         kAudioUnitScope_Global,
                                         0,
                                         &callbackStruct,
                                         sizeof(callbackStruct)),
                    "Couldn't set render callback on mixer unit");
#else
        // Opening the graph opens all contained audio units
        // but does not allocate any resources yet
        CheckError(AUGraphOpen(player->graph),
                   "AUGraphOpen failed");
         
        // Get the reference to the AudioUnit object for the
        // output graph node
        CheckError(AUGraphNodeInfo(player->graph,
                                   outputNode,
                                   NULL,
                                   &player->outputUnit),
                   "AUGraphNodeInfo failed");
         
        // Set the stream format on the output unit's input scope
        UInt32 propertySize = sizeof (AudioStreamBasicDescription);
        CheckError(AudioUnitSetProperty(player->outputUnit,
                                        kAudioUnitProperty_StreamFormat,
                                        kAudioUnitScope_Input,
                                        0,
                                        &player->streamFormat,
                                        propertySize),
                   "Couldn't set stream format on output unit");
        AURenderCallbackStruct callbackStruct;
        callbackStruct.inputProc = GraphRenderProc;
        callbackStruct.inputProcRefCon = player;
        CheckError(AudioUnitSetProperty(player->outputUnit,
                                        kAudioUnitProperty_SetRenderCallback,
                                        kAudioUnitScope_Global,
                                        0,
                                        &callbackStruct,
                                        sizeof(callbackStruct)),
                   "Couldn't set render callback on output unit");
#endif
        // Now initialize the graph (causes resources to be allocated)
        CheckError(AUGraphInitialize(player->graph),
                   "AUGraphInitialize failed");
        player->firstOutputSampleTime = -1;
    }


#ifdef PART_II
void PrepareSpeechAU(MyAUGraphPlayer *player)
{
    SpeechChannel chan;
    UInt32 propsize = sizeof(SpeechChannel);
    CheckError(AudioUnitGetProperty(player->speechUnit,
                                    kAudioUnitProperty_SpeechChannel,
                                    kAudioUnitScope_Global,
                                    0,
                                    &chan,
                                    &propsize),
               "AudioFileGetProperty[kAudioUnitProperty_SpeechChannel] failed");
    SpeakCFString(chan,
                  CFSTR("Please purchase as many copies of our\
                        Core Audio book as you possibly can"),
                  NULL);
}
#endif
int main (int argc, const char * argv[]) {
    
    MyAUGraphPlayer player = {0};
    
    // Create the input unit
    CreateInputUnit(&player);
    
    // Build a graph with output unit
    CreateMyAUGraph(&player);
    
    
#ifdef PART_II
    // Configure the speech synthesizer
    PrepareSpeechAU(&player);

#endif
    // Start playing
    CheckError (AudioOutputUnitStart(player.inputUnit),
                "AudioOutputUnitStart failed");
    CheckError(AUGraphStart(player.graph),
               "AUGraphStart failed");
    // And wait
    printf("Capturing, press <return> to stop:\n");
    getchar();
    // cleanup
    AUGraphStop (player.graph);
    AUGraphUninitialize (player.graph);
    AUGraphClose(player.graph);
}




