//
//  main.m
//  CAMetadata
//
//  Created by Perrin Cloutier on 4/12/18.
//  Copyright © 2018 Perrin Cloutier. All rights reserved.
//
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

/* First example from Learning Core Audio, ARC disabled, path to random music file supplied in scheme */

int main (int argc, const char * argv[]) {
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    if (argc < 2) {
        printf ("Usage: CAMetadata /full/path/to/audiofile\n");
        return -1;
    }
    /* 1. As in any C program, the main() method accepts a count of arguments (argc)
       and an array of plain C-string arguments.The first string is the executable name, so
       you must look to see if there’s a second argument that provides the path to an
       audio file. If there isn’t, you print a message and terminate.*/
    NSString *audioFilePath = [[NSString stringWithUTF8String:argv[1]]
                               stringByExpandingTildeInPath];
    /*2. If there’s a path, you need to convert it from a plain C string to the NSString/CFStringRef representation that Apple’s various frameworks use. Specifying the UTF-8 encoding for this conversion lets you pass in paths that use non-Western characters, in case (like us) you listen to music from all over the world. By using stringByExpandingTildeInPath, you accept the tilde character as a shortcut to the user’s home directory, as in ~/Music/...*/
    NSURL *audioURL = [NSURL fileURLWithPath:audioFilePath];
    /* 3. The Audio File APIs work with URL representations of file paths, so you must
     convert the file path to an NSURL.*/
    AudioFileID audioFile;
    /* 4. Core Audio uses the AudioFileID type to refer to audio file objects, so you
    declare a reference as a local variable. */
    OSStatus theErr = noErr;
    /* 5. 5. Most Core Audio functions signal success or failure through their return value,
     which is of type OSStatus.Any status other than noErr (which is 0) signals an
     error.You need to check this return value on every Core Audio call because an
     error early on usually makes subsequent calls meaningless. For example, if you can’t
     create the AudioFileID object, trying to get properties from the file that object
     was supposed to represent will always fail. In this example, we’ve used an
     assert() to terminate the program instantly if we ever get an error, in callouts 7,
     10, 13, and 17. Of course, your application will probably want to handle errors
     with somewhat less brutality */
    theErr = AudioFileOpenURL((__bridge CFURLRef)audioURL,
                              kAudioFileReadPermission,
                              0,
                              &audioFile);
    /* 6. Here’s the first Core Audio function call: AudioFileOpenURL. It takes four parameters,
     a CFURLRef, a file permissions flag, a file type hint, and a pointer to receive
     the created AudioFileID object.You do a toll-free cast of the NSURL to a
     CFURLRef to match the first parameter’s defined type. For the file permissions, you
     pass a constant to indicate read permission.You don’t have a hint to provide, so
     you pass 0 to make Core Audio figure it out for itself. Finally, you use the &
     (“address of”) operator to provide a pointer to receive the AudioFileID object
     that gets created. */
    assert (theErr == noErr);
    /* 7. If AudioFileOpenURL returned an error, die.*/
    UInt32 dictionarySize = 0;
    /* 8. To get the file’s metadata, you will be asking for a metadata property,
     kAudioFilePropertyInfoDictionary. But that call requires allocating memory
     for the returned metadata in advance. So here, we declare a local variable to
     receive the size we’ll need to allocate. */
    
    theErr = AudioFileGetPropertyInfo (audioFile,
                                       kAudioFilePropertyInfoDictionary,
                                       &dictionarySize,
                                       0);
    /* 9. To get the needed size, call AudioFileGetPropertyInfo, passing in the
     AudioFileID, the property you want information about, a pointer to receive the
     result, and a pointer to a flag variable that indicates whether the property is writeable
     (because we don’t care, we pass in 0).*/
    assert (theErr == noErr);
    /* 10. If AudioFileGetPropertyInfo failed, terminate*/
    CFDictionaryRef dictionary;
    /* 11. The call to get a property from an audio file populates different types, based on
     the property itself. Some properties are numeric; some are strings.The documentation
     and the Core Audio header files describe these values.Asking for
     kAudioFilePropertyInfoDictionary results in a dictionary, so we set up a
     local variable instance of type CFDictionaryRef (which can be cast to an
     NSDictionary if needed).*/
    theErr = AudioFileGetProperty (audioFile,
                                   kAudioFilePropertyInfoDictionary,
                                   &dictionarySize,
                                   &dictionary);
    /* 12. You’re finally ready to request the property. Call AudioFileGetProperty, passing
     in the AudioFileID, the property constant, a pointer to the size you’re prepared
     to accept (set up in callouts 8–10 with the AudioFileGetPropertyInfo call) and
     a pointer to receive the value (set up on the previous line).*/
    assert (theErr == noErr);
    /* 13. Again, check the return value and fail if it’s anything other than noErr */
    NSLog (@"dictionary: %@", dictionary);
    /* 14. Let’s see what you got.As in any Core Foundation or Cocoa object, you can use
     "%@" in a format string to get a string representation of the dictionary.*/
    CFRelease (dictionary);
    /* 15. Core Foundation doesn’t offer autorelease, so the CFDictionaryRef received in
     callout 12 has a retain count of 1. CFRelease() releases your interest in the
     object.*/
    theErr = AudioFileClose (audioFile);
    /* 16. The AudioFileID also needs to be cleaned up but isn’t a Core Foundation
     object, per se; therefore, it doesn’t get CFRelease()’d. Instead, it has its own endof-life
     function: AudioFileClose(). */
    
    assert (theErr == noErr);
    /* 17. AudioFileClose() is another Core Audio call, so you should continue to check
     return codes, though it’s arguably meaningless here because you’re two lines away
     from terminating anyway */
    [pool drain];
    return 0;
}
