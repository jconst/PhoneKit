//
//  TCSoundManager.m
//  TwilioSDK
//
//  Created by Rob Simutis on 1/3/12.
//  Copyright (c) 2012 Twilio. All rights reserved.
//

#import "TCSoundManager.h"
#import <AudioToolbox/AudioServices.h>
#import <libkern/OSAtomic.h>

// Subclass of AVPlayerItem that allows us to annotate more info about the item
// (and not have to cache in a Dictionary or NSArray separately, have locks, etc.)
@interface TCPlayerItem : AVPlayerItem 
{
    BOOL _loop;
	BOOL _throughSpeaker;
	NSUInteger _maxNumberLoops;
	NSUInteger _loopCount;
	TCSoundToken _token; // unique ID that can be used safely beyond the lifetime
						 // of this object (in case it stops playing normally
						 // before a call to [TCSoundManager stopPlaying:])
	void (^_completion)(); // block to call when the item has finished playing
}

@property (assign) BOOL loop;
@property (assign) BOOL throughSpeaker;
@property (assign) NSUInteger maxNumberLoops;
@property (assign) NSUInteger loopCount;
@property (assign) TCSoundToken token;
@property (copy) void (^completion)();

+(TCPlayerItem*)tcPlayerItemWithAsset:(AVAsset*)asset;

@end

@implementation TCPlayerItem

@synthesize loop = _loop;
@synthesize throughSpeaker = _throughSpeaker;
@synthesize maxNumberLoops = _maxNumberLoops;
@synthesize loopCount = _loopCount;
@synthesize token = _token;
@synthesize completion = _completion;

// Override to ensure we create the right type of subclass when this method is called.
+(TCPlayerItem*)tcPlayerItemWithAsset:(AVAsset*)asset
{
	TCPlayerItem* item = [[TCPlayerItem alloc] initWithAsset:asset];
	return [item autorelease];
}

-(void)dealloc
{
#ifdef DEBUG
	NSLog(@"TCPlayerItem: dealloc");
#endif
	[_completion release];
	[super dealloc];
}

@end
	
// TODO: need to guarantee proper alignment for OSAtomicAdd32
static int32_t sTokenCount = TC_INVALID_SOUND_TOKEN;

static TCSoundManager *instance = nil;


@interface TCSoundManager (Private)

-(void)play:(TCPlayerItem*)item; // workhorse method
-(NSURL*)soundResourceForSound:(ETCSound)sound;
-(AVAsset*)assetForSound:(ETCSound)sound; // caches an autoreleased asset.
									// may return nil
-(void)playerItemDidReachEnd:(NSNotification*)notification;
-(void)configurePlayer;
-(void)destroyPlayer;

+(NSString*)etcSound2ResouceName:(ETCSound)sound;
+(ETCSound)resourceName2ETCSound:(NSString*)name;

@end

@implementation TCSoundManager

-(id)init
{
	if ( self = [super init] )
	{
		// First check to see if any of the sound resources we recognize are
		// present.  If they're not, don't bother spinning up the audio session
		// or player.
		BOOL doStartAudioComponents = NO;
		for ( ETCSound sound = eTCSound_First; sound < eTCSound_Last; sound++ )
		{
			if ( [self soundResourceForSound:sound] )
			{
				doStartAudioComponents = YES;
				break;
			}
		}
		
		if ( doStartAudioComponents )
		{

			// NOTE: We don't initialize the AudioSession here because we don't want to 
			// take over the callback or delegate from the parent application, but we 
			// do need them to be sure to initialize the session before
			// Twilio Client is loaded.
			NSError* error = nil;
			[[AVAudioSession sharedInstance] setActive:YES error:&error];
			if ( error )
			{
				NSLog(@"Error starting AudioSession for %@.  Twilio Client sounds may not be emitted.  Error code: %d; " \
					   "Error domain: %@;  Error description: %@",
					  NSStringFromClass([self class]), 
					  [error code],
					  [error domain],
					  [error localizedDescription]);
			}
			
			[self configurePlayer];
			
			// register for the notification that a given item has ended playback (allows us to loop if necessary)
			[[NSNotificationCenter defaultCenter] addObserver:self
													 selector:@selector(playerItemDidReachEnd:)
														 name:AVPlayerItemDidPlayToEndTimeNotification
													   object:nil];
			
			// we preload the incoming, outgoing, and disconnected sounds
			// as early as possible.  the rest are cached on-demand.
			cachedAssets = [[NSMutableDictionary alloc] initWithCapacity:eTCSound_Count];
			[self assetForSound:eTCSound_Incoming];
			[self assetForSound:eTCSound_Outgoing];
			[self assetForSound:eTCSound_Disconnected];
		}
        else
        {
            NSLog(@"TCSoundManager: init, skipping configuration");
        }
	}
    
	return self;
}

-(void)dealloc
{
#ifdef DEBUG
	NSLog(@"TCSoundManager: dealloc");
#endif
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	 
	[self destroyPlayer];

	[cachedAssets removeAllObjects];
	[cachedAssets release];
	[super dealloc];
}

// Token used in conjunction with dispatch_once for thread-safe singleton creation
static dispatch_once_t sSMDispatchOnceToken = NULL;

-(void)shutdown
{
#ifdef DEBUG
	NSLog(@"TCSoundManager: destroyed");
#endif
    [instance release];
    instance = nil;
	sSMDispatchOnceToken = NULL; // reset the token so the singleton can get rebuilt
}

+(TCSoundManager*)sharedInstance
{
#ifdef DEBUG
	NSLog(@"TCSoundManager: sharedInstance: %p", instance);
#endif
    dispatch_once(&sSMDispatchOnceToken, ^(void)
    {
        instance = [[TCSoundManager alloc] init];
    });

	return instance;
}

#pragma mark - 
#pragma mark KVO Callbacks

-(void)configurePlayer
{
#ifdef DEBUG
	NSLog(@"TCSoundManager: player configured");
#endif
	if ( ![NSThread isMainThread] ) // must register/unregister KVO on the main thread
	{
		[self performSelectorOnMainThread:_cmd withObject:nil waitUntilDone:NO];
		return;
	}
	player = [[AVQueuePlayer alloc] initWithItems:[NSArray array]];
	player.actionAtItemEnd = AVPlayerActionAtItemEndNone; // we manage playback internally to handle looping cases.
	
	// Monitor changes to the player's status -- if it ever fails, we need to tear it down and rebuild a new one.
	[player addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];   
	// Monitor changes to the current item so we can enable playback through speaker if necessary
	[player addObserver:self forKeyPath:@"currentItem" options:NSKeyValueObservingOptionNew context:nil];   
}

-(void)destroyPlayer
{
#ifdef DEBUG
	NSLog(@"TCSoundManager: player destroyed");
#endif
	if ( ![NSThread isMainThread] ) // must register/unregister KVO on the main thread
	{
		[self performSelectorOnMainThread:_cmd withObject:nil waitUntilDone:NO];
		return;
	}
	[player removeObserver:self forKeyPath:@"status"];
	
	// run all of the items completion blocks, if any exist.
	NSArray* items = player.items;
	for ( TCPlayerItem* item in items )
	{
		if ( item.completion )
			item.completion();
	}
	
	[player removeAllItems]; // stop playback of any items left in the queue
	[player release];
	player = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
#ifdef DEBUG
	if ( object == player )
		NSLog(@"Player status: %d", player.status);
	else if ( [(id)object isKindOfClass:[TCPlayerItem class]] )
		NSLog(@"Item status: %d", ((TCPlayerItem*)object).status);
#endif
	
	if ( [keyPath isEqualToString:@"status"] && object == player )
	{
		// If the player status is failed, we need to rebuild a new player
		// TODO: should probably put a retry limit on this...
		if ( player.status == AVPlayerStatusFailed )
		{
			// Note: we don't configure the player with the previous items (if any)
			// to prevent potential looping in case the player failed on a particular
			// bad item.  Just lose the current items, and go on.
			NSLog(@"Audio playback failed due to error." \
				   "Error code: %d; Error domain: %@; Error description: \"%@\"",
				  [player.error code],
				  [player.error domain],
				  [player.error localizedDescription]);
			NSLog(@"Rebuilding audio player");

			[self destroyPlayer];
			[self configurePlayer];
		}
		// else if we're ready to play with items on the queue and the player is paused, play it.
		else if ( player.status == AVPlayerStatusReadyToPlay && 
				  [[player items] count] > 0 &&
				  player.rate == 0.0 /* paused */
				 )
		{
			// If the status is ready to play and there are items on the queue, 
			// start playback.  for consistency this is done on the main thread.
			[player performSelectorOnMainThread:@selector(play) withObject:nil waitUntilDone:NO];
		}
	}
	else if ( [keyPath isEqualToString:@"status"] && [object isKindOfClass:[TCPlayerItem class]])
	{
		// If the item status is failed, boot it from the queue if it's on it.
		TCPlayerItem* item = (TCPlayerItem*)object;
		if ( item.status == AVPlayerItemStatusFailed )
		{
			AVAsset* asset = item.asset;
			if ( [asset isKindOfClass:[AVURLAsset class]] )
			{
				NSLog(@"Playback of resource %@ failed due to error." \
					  "Error code: %d; Error domain: %@; Error description: \"%@\"",
					  [((AVURLAsset*)asset).URL relativeString],
					  [item.error code],
					  [item.error domain],
					  [item.error localizedDescription]);
			}

			// item failed to load, skip it.
			if ( player.currentItem == item )
			{
				[item removeObserver:self forKeyPath:@"status"];
				[player advanceToNextItem];
			}
            
            // Yes, we should call the completion block if this fails.
            if ( item.completion )
				item.completion();
		}
	}
	else if ( [keyPath isEqualToString:@"currentItem"] )
	{
		NSError *error;
        BOOL success;
		TCPlayerItem *item = (TCPlayerItem *)player.currentItem;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        
		if ( item.throughSpeaker ) // may be nil, but that's okay.
		{
			// only route through the speaker if the route description says "speaker",
			// otherwise something like headphones are connected, so we don't want to override.
            NSString *route = [[[session currentRoute].outputs objectAtIndex:0] portName];
            
			if ( route &&
				([route rangeOfString:@"Speaker"].length > 0 ||
				 [route rangeOfString:@"ReceiverAndMicrophone"].length > 0 ) )
			{
                success = [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
#if DEBUG
				if ( !success )
					NSLog(@"AVAudioSession error overrideOutputAudioPort:%@", error);
				else
					didOverrideAudioRoute = YES;
#else
				if ( success )
					didOverrideAudioRoute = YES;
#endif
				
			}
		}
		else if ( didOverrideAudioRoute ) // item should not be played through speaker, and we overrode the route, so turn off
            // (this lets developers override the route on their own, and we won't turn it off.)
            
		{
			// TODO: there's still a condition here where a developer can override the audio route,
			// then we play a sound "through the speaker", and then un-override the route.
			// Unfortunately we can't "get" the value of kAudioSessionProperty_OverrideAudioRoute,
			// so there's no way for us to know if the route was overridden before we started monkeying
			// with things.  This is an apple limitation; for now, developers, if they want more control
			// over this, will have to handle connection sounds on their own.
			success = [session overrideOutputAudioPort:AVAudioSessionPortOverrideNone error:&error];
#if DEBUG
            if ( !success )
                NSLog(@"AVAudioSession error overrideOutputAudioPort:%@", error);
            else
                didOverrideAudioRoute = NO;
#else
            if ( success )
                didOverrideAudioRoute = NO;
#endif
        }
	}
}

#pragma mark -
#pragma mark Playback Control

-(void)play:(TCPlayerItem*)item
{
    NSError *error = nil;
    
	// AVQueuePlayer likes everything to be accessed from the main thread,
	// though playback happens asynchronously
	if ( ![NSThread isMainThread] )
	{
		[self performSelectorOnMainThread:_cmd withObject:item waitUntilDone:NO];
		return;
	}
    
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if ( error )
    {
        NSLog(@"Error starting AudioSession for %@.  Twilio Client sounds may not be emitted.  Error code: %d; " \
              "Error domain: %@;  Error description: %@",
              NSStringFromClass([self class]),
              [error code],
              [error domain],
              [error localizedDescription]);
    }
    
#if DEBUG
    NSLog(@"TCSoundManager: attempting to play item\n");
#endif
    
	// This is a nasty, nasty hack, but if "too many" items get queued
	// up, the audio player stops playing, even though the rate is 1.0.
	// "Pause and resume" when this happens seems to shake things loose.
	// (The player is in the state of ReadyToPlay when this bug happens).
	if ( [[player items] count] > 5 )
		[player pause];

	if ( [player canInsertItem:item afterItem:nil] )
	{
		[item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];   

		[player insertItem:item afterItem:nil];
		
		// Ticket #8800: After the app has been backgrounded, the device powered down,
		// and then the app brough back to the foreground, the player may not play an item even 
		// though the rate is 1.0 and there's no error reported.  
		// Forcing a play here every time through seems to remedy this.
		if ( player.status == AVPlayerStatusReadyToPlay ) // if not ready to play, playback will happen when it /is/ ready in the KVO callback.
		{
#if DEBUG
            NSLog(@"TCSoundManager: playing item\n");
#endif
			[player play];	
		}
	}
    else
    {
        NSLog(@"TCSoundManager: cannot insert item into player: %@ queue\n", player);
    }
}

/*
 * Callback when each item is done playing.
 * Handle looping, cleanup, and calling completion blocks
 * as applicable.
 */
-(void)playerItemDidReachEnd:(NSNotification*)notification
{
	TCPlayerItem* item = (TCPlayerItem*)[player currentItem];
#ifdef DEBUG
	NSLog(@"TCSoundManager: playerItemDidReachEnd: %X", (int)item);
#endif
	// loop if necessary
	BOOL doLoop = NO;
	if ( item.loop )
	{
		if ( item.maxNumberLoops ) // if we're to loop, only loop if we haven't exceeded the max number of loops (if set)
			doLoop = ++item.loopCount < item.maxNumberLoops;
		else
			doLoop = YES;
	}

	if ( !doLoop )
	{
		[item removeObserver:self forKeyPath:@"status"];
		
		// we're finished, so call the completion block if any
		if ( item.completion )
			item.completion();

		[player advanceToNextItem];
	}
	else
	{
		// reset the time on the item to replay
		CMTime time = [item currentTime];
		time.value = 0;
		[item seekToTime:time];
	}
}

-(TCSoundToken)playSound:(ETCSound)sound 
{
	return [self playSound:sound throughSpeaker:NO loop:NO maxNumberLoops:0 /* doesn't matter */];
}

-(TCSoundToken)playSound:(ETCSound)sound throughSpeaker:(BOOL)throughSpeaker loop:(BOOL)loop maxNumberLoops:(NSUInteger)maxLoops 
{
	return [self playSound:sound throughSpeaker:throughSpeaker loop:loop maxNumberLoops:maxLoops completion:NULL];
}

-(TCSoundToken)playSound:(ETCSound)sound throughSpeaker:(BOOL)throughSpeaker loop:(BOOL)loop maxNumberLoops:(NSUInteger)maxLoops completion:(void (^)(void))completion
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
		
	AVAsset* asset = [self assetForSound:sound];
	TCSoundToken token = TC_INVALID_SOUND_TOKEN;
	
	if ( asset )
	{
		TCPlayerItem* item = [TCPlayerItem tcPlayerItemWithAsset:asset]; // autoreleased
		item.loop = loop;
		item.maxNumberLoops = maxLoops;
		token = OSAtomicAdd32(1 /* amount */, &sTokenCount);;
		item.token = token;
		item.completion = completion;
		item.throughSpeaker = throughSpeaker;
		
		[self play:item];
	}
	else if ( completion ) // sound isn't loaded, just run the completion proc
	{
		completion();
	}
	
	[pool release];

	return token;
}

-(void)stopPlaying:(TCSoundToken)token
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

	if ( token != TC_INVALID_SOUND_TOKEN )
	{
		TCPlayerItem* item = nil;
		for ( TCPlayerItem* tmpItem in [player items] ) // TODO: thread safety iterating through this list that may change??
		{
			if ( tmpItem.token == token )
			{
				item = [tmpItem retain]; // retain until we're done with it.
				break;
			}
		}
		
		if ( item )
		{
			[player removeItem:item];

			// removing an item does not cause AVPlayerItemDidPlayToEndTimeNotification
			// to fire and cause the completion to execute, so do that here.
			if ( item.completion )
				item.completion();
			
			[item release];
		}
	}
	
	[pool release];
}

#pragma mark -
#pragma mark Obtaining Sound Assets

-(AVAsset*)assetForSound:(ETCSound)sound
{
	// Use the enum as a key to the cached assets dict.
	// If there's no object for the key, then look up the asset
	// using its string name.
	// Otherwise look up the URL of the asset, and create an AVAsset object
	// if the URL is non-nil.
	// If the asset can't be found then add NSNull to the dictionary
	// as a flag so we don't keep trying to look up the sound.
	
	NSNumber* key = [NSNumber numberWithInt:sound];
	id asset = [cachedAssets objectForKey:key]; // one of nil (not looked up yet), 
												// AVAsset* (valid asset), 
												// NSNull (failed to load asset)
	
	if ( !asset ) // TODO: synchronize on the cached assets
	{
		NSURL* url = [self soundResourceForSound:sound];
		if ( url ) // asset found
		{
			if ( [[AVAsset class] respondsToSelector:@selector(assetWithURL:)] ) // iOS 5 and later
				asset = [AVAsset assetWithURL:url];
			else
				asset = [AVURLAsset URLAssetWithURL:url options:nil];
		}
		else // not found, so insert [NSNull null] so we don't keep attempting to look up the asset.
			asset = [NSNull null];
		
		[cachedAssets setObject:asset forKey:key];
	}
	
	return (asset != [NSNull null]) ? (AVAsset*)asset : nil;
}

-(NSURL*)soundResourceForSound:(ETCSound)sound
{
	// first try .wav, then .caf.  For hardware performance we just support
	// wav or caf files.
	NSString* soundFileName = [TCSoundManager etcSound2ResouceName:sound];
	NSURL* url = [[NSBundle mainBundle] URLForResource:soundFileName withExtension:@"wav"];
	if ( !url )
		url = [[NSBundle mainBundle] URLForResource:soundFileName withExtension:@"caf"];
	return url;
}

+(NSString*)etcSound2ResouceName:(ETCSound)sound
{
	switch (sound)
	{
		case eTCSound_Outgoing:
			return @"outgoing";
		case eTCSound_Incoming:
			return @"incoming";
		case eTCSound_Disconnected:
			return @"disconnect";
		case eTCSound_Zero:
			return @"dtmf_0";
		case eTCSound_One:
			return @"dtmf_1";
		case eTCSound_Two:
			return @"dtmf_2";
		case eTCSound_Three:
			return @"dtmf_3";
		case eTCSound_Four:
			return @"dtmf_4";
		case eTCSound_Five:
			return @"dtmf_5";
		case eTCSound_Six:
			return @"dtmf_6";
		case eTCSound_Seven:
			return @"dtmf_7";
		case eTCSound_Eight:
			return @"dtmf_8";
		case eTCSound_Nine:
			return @"dtmf_9";
		case eTCSound_Star:
			return @"dtmf_star";
		case eTCSound_Hash:
			return @"dtmf_hash";
		default:
			return nil;
	}
}
				  
+(ETCSound)resourceName2ETCSound:(NSString*)name
{
	if ( [name isEqualToString:@"outgoing"] )
		return eTCSound_Outgoing;
	else if ( [name isEqualToString:@"incoming"] )
		return eTCSound_Incoming;
	else if ( [name isEqualToString:@"disconnect"] )
		return eTCSound_Disconnected;
	else if ( [name isEqualToString:@"dtmf_0"] )
		return eTCSound_Zero;
	else if ( [name isEqualToString:@"dtmf_1"] )
		return eTCSound_One;
	else if ( [name isEqualToString:@"dtmf_2"] )
		return eTCSound_Two;
	else if ( [name isEqualToString:@"dtmf_3"] )
		return eTCSound_Three;
	else if ( [name isEqualToString:@"dtmf_4"] )
		return eTCSound_Four;
	else if ( [name isEqualToString:@"dtmf_5"] )
		return eTCSound_Five;
	else if ( [name isEqualToString:@"dtmf_6"] )
		return eTCSound_Six;
	else if ( [name isEqualToString:@"dtmf_7"] )
		return eTCSound_Seven;
	else if ( [name isEqualToString:@"dtmf_8"] )
		return eTCSound_Eight;
	else if ( [name isEqualToString:@"dtmf_9"] )
		return eTCSound_Nine;
	else if ( [name isEqualToString:@"dtmf_star"] )
		return eTCSound_Star;
	else 
		return eTCSound_Hash;
}

@end
