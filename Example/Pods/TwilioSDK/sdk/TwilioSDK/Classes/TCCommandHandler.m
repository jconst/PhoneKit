//
//  CommandHandler.m
//  TwilioSDK
//
//  Created by Rob Simutis on 12/19/11.
//  Copyright (c) 2011 Twilio. All rights reserved.
//

#import "TCCommandHandler.h"
#import "TCStackTrace.h"
#import <pjsua.h>

@interface TCCommandHandler (Private)

-(void)threadMain:(id)object;

@end



@implementation TCCommandHandler

static TCCommandHandler* instance = nil;

+(TCCommandHandler*)sharedInstance
{
    if ( !instance )
    {
        instance = [[TCCommandHandler alloc] init];
    }
    return instance;
}

-(id)init
{
    if ( self = [super init] )
    {
        semaphore = dispatch_semaphore_create(0);
        
        commandQ = dispatch_queue_create("com.twilio.TCCommandHandler.commandQ", NULL);
        
        commands = [[NSMutableArray alloc] initWithCapacity:10]; // it is unlikely to ever grow to be this big, but just in case...
        
        if ( semaphore && commandQ && commandQ )
        {
#ifdef DEBUG
            NSLog(@"Allocating NSThread for CommandHandler");
#endif
            commandThread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain:) object:nil];
            [commandThread start];
        }
        else
        {
            NSLog(@"Unable to allocate CommandHandler barrier objects. " \
                   "Please file a bug report.  Commands will be handled in the main thread.");
        }
    }
    return self;
}

-(void)dealloc
{
	if ( semaphore )
		dispatch_release(semaphore);
    
    if ( commandQ )
        dispatch_release(commandQ);

	if ( threadDesc )
		free(threadDesc);
    
	[commandThread release];
    [commands removeAllObjects];
    [commands release];
    [super dealloc];
}

-(void)shutdown
{
    [commandThread cancel];
    
    // ick, this is weird and might cause strange, subtle bugs
    [instance release];
    instance = nil;
}
                 
-(void)threadMain:(id)object
{
#ifdef DEBUG
    NSLog(@"Entering CommandHandler thread");
#endif

    if ( !pj_thread_is_registered() )
    {
        threadDesc = calloc(1 /* count */, sizeof(pj_thread_desc));
        if (threadDesc) 
        {
			pj_thread_t* pjthread = NULL;
            pj_status_t status = pj_thread_register("CommandHandler", *(pj_thread_desc*)threadDesc, &pjthread);
            if (status != PJ_SUCCESS)
            {
                NSLog(@"CommandHandler: Thread registration returned error code %d. " \
                    "Twilio Client APIs will be executed in the main thread. " \
                    "Please file an error report with this description.", status);
                dispatch_release(semaphore); // turn off semaphore so the commands execute in the main thread.
                semaphore = NULL;
				
				free(threadDesc); // release the tiny bit of memory we allocated above.
				threadDesc = NULL;
				
				[commandThread cancel]; // tear the thread down so we don't continue to consume resources.
            }
            // impl note: the pj_thread_t object is actually the same as the pj_thread_desc object,
            // just returned as a pointer-to-a-pointer.  we'll be fine as long as we keep the 
            // threadDesc around for the life of the thread.
        }
    }
    
    while ( (![commandThread isCancelled]) && semaphore && threadDesc) // thread still alive, not cancelled
    {
        __block TCCommand *activeCommand = nil;
        
        if ( [commands count] == 0 )
        {
#ifdef DEBUG
            NSLog(@"Waiting for commands...");
#endif
            
            int output = dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            if ( output != 0 )
            {
#ifdef DEBUG
                NSLog(@"Couldn't wait got %d", output);
#endif
                
            }
        }
        else
        {
            dispatch_sync(commandQ, ^(void) {
                activeCommand = [commands objectAtIndex:0];
                if ( activeCommand ) {
                    [activeCommand retain];
                    [commands removeObjectAtIndex:0];
                }
            });
        }
        
        if ( activeCommand )
        {
#ifdef DEBUG
            NSLog(@"Running a command");
#endif
            dispatch_sync(commandQ, ^(void) {
                // The types of commands we run are not expected to allocate much memory
                // and also will not execute frequently during a call, so we don't need
                // to flush after each one.
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                
                [activeCommand run];
                [activeCommand release];
                
                [pool release];
            });
        }
    }
}

-(void)postCommand:(TCCommand*)command
{
    __block TCCommand *passCommand = nil;
    // quick-exit if for any reason a nil command was passed in.
    if ( !command )
    {
#ifdef DEBUG
        NSLog(@"nil command passed in; being ignored: %@", [TCStackTrace getStacktrace]);
#endif
        return;
    }
        
    // We should always be careful with passed in values.
    passCommand = [command retain];
    
#ifdef DEBUG
    NSLog( @"Received command of type %@", NSStringFromClass([command class]) );
#endif
    
    // If the commandThread is running (hasn't been killed prematurely),
    // the semaphore could be created, and the command queue has been
    // created then add the command to the command queue, and post to the
    // semaphore so the commandThread will resume execution and process
    // the command.
    if ( [commandThread isExecuting] && semaphore && commandQ )
    {
        dispatch_async(commandQ, ^(void) {
            [commands addObject:passCommand];
            [passCommand release];
            dispatch_semaphore_signal(semaphore);
        });
        
#ifdef DEBUG
        NSLog(@"Command added to aux queue");
#endif
    }
    else
    {
        // Fallback.  If semaphore couldn't be created, don't start a thread, just
        // execute in the main thread which we know is registered with PJSIP
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            // The types of commands we run are not expected to allocate much memory
            // and also will not execute frequently during a call, so we don't need
            // to flush after each one.
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            
            [passCommand run];
            [passCommand release];
            
            [pool release];
        });
#ifdef DEBUG
        NSLog(@"Command running on main queue");
#endif
    }
}

                 
@end
