//
//  TCSoundManager.h
//  TwilioSDK
//
//  Created by Rob Simutis on 1/3/12.
//  Copyright (c) 2012 Twilio. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

// Enum representing the known set of resources managed and known by this class.
typedef enum ETCSound
{
	eTCSound_Outgoing = 0,
	eTCSound_Incoming,
	eTCSound_Disconnected,
	eTCSound_Zero,
	eTCSound_One,
	eTCSound_Two,
	eTCSound_Three,
	eTCSound_Four,
	eTCSound_Five,
	eTCSound_Six,
	eTCSound_Seven,
	eTCSound_Eight,
	eTCSound_Nine,
	eTCSound_Star,
	eTCSound_Hash,
	
	eTCSound_First = eTCSound_Outgoing,
	eTCSound_Last = eTCSound_Hash,
	eTCSound_Count = eTCSound_Last - eTCSound_First + 1,
	
} ETCSound;

typedef int32_t TCSoundToken;
#define TC_INVALID_SOUND_TOKEN 1


/** The TCSoundManager singleton handles audio resource playback for the Twilio Client library
	for Connection events.  The resources that can be played are specified by 
	one of the values from the ETCSound enum.
 
    Multiple sounds can be queued up, and may be queued from any thread.
 
	For performance it's best to initialize the singleton (by calling sharedInstance)
	well-prior to the point any sound needs to be played.
 
	If none of the underlying sound assets listed above can be found on-disk,
    the audio stack will not be spun up.
 */
@interface TCSoundManager : NSObject
{
	AVQueuePlayer* player;
	NSMutableDictionary* cachedAssets;
	BOOL didOverrideAudioRoute; // YES if one of our items caused an audio route override (e.g. to the speaker)
								// to take place, which means we'll have to reset that after playing the item
								// if the next item also doesn't play through the speaker.  This lets the calling
								// application continue to keep the route overridden, and not have our code disable the speaker
}

+(TCSoundManager*)sharedInstance;
-(void)shutdown;
// TODO: memory warning callback?

/**
 *  Queue up a sound resource for asynchronous playback at the next available opportunity.
 *  @return A token representing an instance of the sound to be played.  This token can be used
 *          in conjunction with [TCSoundManager stopPlaying] to halt the instance from being played
 *          or stop playback if it's the current sound playing.
 */
-(TCSoundToken)playSound:(ETCSound)sound; // does not loop

/**
 *  Queue up a sound resource for asynchronous playback at the next available opportunity.
 *  If loop is YES, the sound will loop if specified up to the maximum number of times specified.
 *  The sound will play at least once.
 *
 *  @return A token representing an instance of the sound to be played.  This token can be used
 *          in conjunction with [TCSoundManager stopPlaying] to halt the instance from being played
 *          or stop playback if it's the current sound playing.
 */
-(TCSoundToken)playSound:(ETCSound)sound throughSpeaker:(BOOL)throughSpeaker loop:(BOOL)loop maxNumberLoops:(NSUInteger)maxLoops;

/**
 *  Queue up a sound resource for asynchronous playback at the next available opportunity.
 *
 *  If loop is YES, the sound will loop if specified up to the maximum number of times specified.
 *  The sound will play at least once.
 *
 *  An optional completion block can be specified that will be invoked when the sound stops playing,
 *  either from reaching the final loop or as a result of a call to [TCSoundManager stopPlaying:].
 *
 *  @return A token representing an instance of the sound to be played.  This token can be used
 *          in conjunction with [TCSoundManager stopPlaying] to halt the instance from being played
 *          or stop playback if it's the current sound playing.
 */
-(TCSoundToken)playSound:(ETCSound)sound throughSpeaker:(BOOL)throughSpeaker loop:(BOOL)loop maxNumberLoops:(NSUInteger)maxLoops completion:(void (^)(void))completion;

/**
 *  Halt playback of a sound instance based on a token.
 *  The completion block for the sound instance will be invoked, if one was specified in playSound:loop:maxNumberLoops:completion.
 */
-(void)stopPlaying:(TCSoundToken)token;

@end
