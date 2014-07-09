//
//  TCHttpJsonLongPollConnection.h
//  TwilioSDK
//
//  Created by Brian Tarricone on 1/4/12.
//  Copyright (c) 2012 Twilio, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TCAsyncSocket.h"

extern NSString * const TCHttpErrorDomain;
extern NSString * const TCHttpStatusCodeKey;

typedef enum
{
    kTCHttpErrorBadResponseHeders = 0,
    kTCHttpErrorBadChunkSize,
    kTCHttpErrorBadUrlScheme,
    kTCHttpErrorConnectFailed,
    kTCHttpErrorStatus,
} TCHttpErrorCode;

@class TCHttpJsonLongPollConnection;
@class TwilioReachability;

@protocol TCHttpJsonLongPollConnectionDelegate <NSObject>

- (void)longPollConnectionDidConnect:(TCHttpJsonLongPollConnection *)connection;

- (void)longPollConnection:(TCHttpJsonLongPollConnection *)connection
         didReceiveHeaders:(NSDictionary *)headers
                statusCode:(NSUInteger)statusCode
             statusMessage:(NSString *)statusMessage;

- (void)longPollConnection:(TCHttpJsonLongPollConnection *)connection
         didReceiveMessage:(NSDictionary *)messageParams;

- (void)longPollConnectionDidDisconnect:(TCHttpJsonLongPollConnection *)connection;

- (void)longPollConnection:(TCHttpJsonLongPollConnection *)connection
          didFailWithError:(NSError *)error
                 willRetry:(BOOL)willRetry;

@end

typedef enum
{
    kTCTransferEncodingNone = 0,
    kTCTransferEncodingChunked,
} TCTransferEncoding;

@interface TCHttpJsonLongPollConnection : NSObject <TCAsyncSocketDelegate>
{
    id<TCHttpJsonLongPollConnectionDelegate> delegate_;
    NSURL *url_;
    NSURL *finalUrl_;
    NSDictionary *headers_;
    TCAsyncSocket *sock_;
    TCTransferEncoding transferEncoding_;
    BOOL connected_;
    BOOL isHTTPS_;
    int curReconnectWait_;
    NSTimer *reconnectTimer_;
	BOOL doCertVerification_;
	NSString *sslPeerName_;
    CFStringRef networkServiceType_;
}

- (id)initWithURL:(NSURL *)url
          headers:(NSDictionary *)headers
         delegate:(id<TCHttpJsonLongPollConnectionDelegate>)delegate;

- (void)connect;
- (void)disconnect;
- (void)reconnect;

@property (nonatomic, assign) id<TCHttpJsonLongPollConnectionDelegate> delegate;
@property (nonatomic, assign) CFStringRef networkServiceType;
@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly, getter=isConnected) BOOL connected;
@property (nonatomic, assign) BOOL doCertVerification; // perform verification of the SSL server certificate against the SSL peer name.
@property (nonatomic, retain) NSString* sslPeerName; // must be non-nil if doCertVerification is YES.

@end
