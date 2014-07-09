//
//  TCConstants.h
//  TwilioSDK
//
//  Created by Brian Tarricone on 1/5/12.
//  Copyright (c) 2012 Twilio, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#define TC_PARAM_CHUNDER_HOST  @"chunder"
#define TC_PARAM_CHUNDER_PORT  @"chunder-port"
#define TC_PARAM_MATRIX_HOST   @"matrix"
#define TC_PARAM_STREAM_HOST   @"stream"

#define TWILIO_DEFAULT_CHUNDER_HOST  @"chunderm.twilio.com"
#define TWILIO_DEFAULT_CHUNDER_PORT_TLS  10194
#define TWILIO_DEFAULT_CHUNDER_PORT_TCP  10193

extern NSString * const TwilioMatrixApiString;
extern NSString * const TwilioDefaultSipUsername;
extern NSString * const TwilioDefaultSipPassword;
extern const NSUInteger TwilioSessionExpiration;

@interface TCConstants : NSObject

+(NSString*)clientString;

+ (NSString *)callControlHost;
+ (unsigned short)callControlPort;
+ (unsigned short)callControlPortUsingTLS:(BOOL)usingTLS;
+ (NSString *)registerHost;

+ (NSURL *)matrixUrlForClientName:(NSString *)clientName
                       accountSid:(NSString *)accountSid
                  capabilityToken:(NSString *)capabilityToken
                         features:(NSSet *)features;

+ (NSString *)matrixSSLPeerName;
+ (NSString *)callControlPeerName; // SIP

// this is super private!
+ (void)setValue:(id)value forKey:(NSString *)key;

+ (void)shutdown; // 
@end
