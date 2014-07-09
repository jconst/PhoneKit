//
//  Commands.h
//  TwilioSDK
//
//  Created by Rob Simutis on 12/19/11.
//  Copyright (c) 2011 Twilio. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TCConnectionInternal.h"
#import "TCDeviceInternal.h"

/**
 *  Abstract superclass for a command object that should perform
 *  an operation for the specified TCConnection.
 *
 *  A subclass should be used (or created, if necessary) for
 *  any operation that may either take an extended period of time
 *  to execute (and could block the UI thread) or that may
 *  interact with PJSIP in some way.  
 *
 *  After being created, they should be handed to the TCCommandHandler
 *  singleton's [TCCommandHandler postCommand:(TCCommand*)command] to be performed
 *  in an appropriate thread.  The TCCommandHandler will take care of any
 *  thread management, including registering the worker thread(s) with PJSIP properly.
 *
 *  Subclasses must implement a -(void)run method to perform their
 *  work and must not spawn any new threads that may cause any
 *  PJSIP interactions.
 */
@interface TCCommand : NSObject // TODO: maybe a protocol instead?  might not always have/need a connection.  shrug.
{
@private
    TCConnectionInternal* _connection;
}

@property (nonatomic, retain) TCConnectionInternal* connection;

-(id)initWithConnection:(TCConnectionInternal*)connection;
-(void)run; // abstract method, must be overridden or will throw an NSInternalInconsistencyException

@end
	
@interface TCMakeCallCommand : TCCommand
{

    TCDeviceInternal*            _device;
    NSDictionary*               _connectionParameters;
    id<TCConnectionDelegate>    _connectionDelegate;
    NSString*                   _capabilityToken;
}

// dependencies passed in for testing
-(id)initWithConnection:(TCConnectionInternal*)connection
             parameters:(NSDictionary*)params
                 device:(TCDeviceInternal*)device
        capabilityToken:(NSString*)token
     connectionDelegate:(id<TCConnectionDelegate>)delegate;

+(TCMakeCallCommand*)makeCallCommandWithConnection:(TCConnectionInternal*)connection
                                 parameters:(NSDictionary*)params
                                     device:(TCDeviceInternal*)device
                            capabilityToken:(NSString*)token
                         connectionDelegate:(id<TCConnectionDelegate>)delegate;
-(void)run;

@end


@interface TCHangupCallCommand : TCCommand

+(TCHangupCallCommand*)hangupCallCommandWithConnection:(TCConnectionInternal*)connection;

@end

@interface TCSendReinviteCommand : TCCommand

+(TCSendReinviteCommand*)sendReinviteCommandWithConnection:(TCConnectionInternal*)connection;

@end

@interface TCMuteCallCommand : TCCommand
{
    BOOL _muted;
}

-(id)initWithConnection:(TCConnectionInternal*)connection
                  muted:(BOOL)muted;
+(TCMuteCallCommand*)muteCallCommandWithConnection:(TCConnectionInternal*)connection
                                             muted:(BOOL)muted;

-(void)run;

@end


@class TCEventStream;

@interface TCRejectCallCommand : TCCommand
{
    TCEventStream* _eventStream;
}

-(id)initWithConnection:(TCConnectionInternal*)connection
            eventStream:(TCEventStream *)eventStream;
+(TCRejectCallCommand*)rejectCallCommandWithConnection:(TCConnectionInternal*)connection
                                           eventStream:(TCEventStream*)eventStream;

-(void)run;

@end


@interface TCSendDigitsCommand : TCCommand
{
    NSString* _digits;
}
-(id)initWithConnection:(TCConnectionInternal*)connection
           digitsString:(NSString*)digits;

+(TCSendDigitsCommand*)sendDigitsCommandWithConnection:(TCConnectionInternal*)connection
                                          digitsString:(NSString*)digits;

-(void)run;

@end


@interface TCSetPresenceCommand : TCCommand
{
    TCEventStream* _eventStream;
    NSString* _status;
    NSString* _statusText;
}

- (id)initWithEventStream:(TCEventStream*)eventStream
                   status:(NSString*)status
               statusText:(NSString*)statusText;

+ (id)setPresenceCommandWithEventStream:(TCEventStream*)eventStream
                                 status:(NSString*)status
                             statusText:(NSString*)statusText;

@end