//
//  AppDelegate.h
//  CA10-iOSBackgroundingTone
//
//  Created by Perrin Cloutier on 4/27/18.
//  Copyright © 2018 Perrin Cloutier. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>

@interface CH10_iOSBackgroundingToneAppDelegate : NSObject <UIApplicationDelegate>

@property (nonatomic, retain) UIWindow *window;

@property (nonatomic, assign) AudioStreamBasicDescription streamFormat;
@property (nonatomic, assign) UInt32 bufferSize;
@property (nonatomic, assign) double currentFrequency;
@property (nonatomic, assign) double startingFrameCount;
@property (nonatomic, assign) AudioQueueRef    audioQueue;

-(OSStatus) fillBuffer: (AudioQueueBufferRef) buffer;

@end

