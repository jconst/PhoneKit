//
//  TCEventStream.h
//  TwilioSDK
//
//  Created by Brian Tarricone on 1/4/12.
//  Copyright (c) 2012 Twilio, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TCHttpJsonLongPollConnection.h"

@class TCEventStream;

extern NSString * const TCEventStreamErrorWillRetryKey;

extern NSString *const TCEventStreamFeatureIncomingCalls;
extern NSString *const TCEventStreamFeaturePresenceEvents;
extern NSString *const TCEventStreamFeaturePublishPresence;

@protocol TCEventStreamDelegate <NSObject>

- (void)eventStreamDidConnect:(TCEventStream *)eventStream;
- (void)eventStreamDidDisconnect:(TCEventStream *)eventStream;
- (void)eventStream:(TCEventStream *)eventStream didFailWithError:(NSError *)error willRetry:(BOOL)willRetry;
- (BOOL)eventStream:(TCEventStream *)eventStream didReceiveMessage:(NSDictionary *)messageParams;
- (void)eventStreamFeaturesUpdated:(TCEventStream *)eventStream;

@end

@interface TCEventStream : NSObject <TCHttpJsonLongPollConnectionDelegate>
{
    id<TCEventStreamDelegate> delegate_;

    NSString *capabilityToken_;
    NSString *accountSid_;
    NSSet *features_;
    BOOL hasIncoming_;
    BOOL incomingEnabled_;
    NSString *clientName_;
	
    TCHttpJsonLongPollConnection *matrixConn_;
}

+ (id)eventStreamWithCapabilityToken:(NSString *)capabilityToken
                        capabilities:(NSDictionary *)capabilities
                            features:(NSSet *)features
                            delegate:(id<TCEventStreamDelegate>)delegate;

- (void)addFeature:(NSString *)feature;
- (void)removeFeature:(NSString *)feature;
- (BOOL)hasFeature:(NSString *)feature;

// never call this from the main thread
- (BOOL)postMessage:(NSString *)message
       toSubchannel:(NSString *)subchannel
        contentType:(NSString *)contentType;

- (void)disconnect;

@property (nonatomic, assign)   id<TCEventStreamDelegate> delegate;
@property (nonatomic, readonly) NSSet *features;
@property (nonatomic, retain) TCHttpJsonLongPollConnection *matrixConn;

@end
