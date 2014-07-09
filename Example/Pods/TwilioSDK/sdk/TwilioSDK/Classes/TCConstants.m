//
//  TCConstants.m
//  TwilioSDK
//
//  Created by Brian Tarricone on 1/5/12.
//  Copyright (c) 2012 Twilio, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "TCConstants.h"
#import "NSObject+JSON.h"
#include <sys/types.h>
#include <sys/sysctl.h>
#include <mach/machine.h>
#include "TCVersion.h"


#define TWILIO_DEFAULT_MATRIX_HOST   @"matrix.twilio.com"

NSString * const TwilioMatrixApiString = @"2012-02-09";
NSString * const TwilioDefaultSipUsername = @"twilio";
NSString * const TwilioDefaultSipPassword = @"none";
const NSUInteger TwilioSessionExpiration = 4 * 60 * 60;  // the maximum time supported by Asterisk inside of Twilio


NSString* const METRICS_TWILIO_LIB_VERSION_KEY = @"v";
NSString* const METRICS_TWILIO_LIB_VERSION_VALUE = @TWILIO_CLIENT_VERSION;
NSString* const METRICS_TWILIO_LIB_PLATFORM_KEY = @"p";
NSString* const METRICS_TWILIO_LIB_PLATFORM_VALUE = @"ios";
NSString* const METRICS_MOBILE_KEY = @"mobile";
NSString* const METRICS_MOBILE_NAME_KEY = @"name";
NSString* const METRICS_MOBILE_PRODUCT_KEY = @"product"; // e.g. "iPad" -- device.model
NSString* const METRICS_MOBILE_VERSION_KEY = @"v"; // e.g. "4.2.10" -- device.systemVersion
NSString* const METRICS_MOBILE_ARCHITECTURE_KEY = @"arch"; // e.g. "arm", x86, etc.


static NSMutableDictionary *params = nil;
static NSString* sTwilioClientString = nil;

@implementation TCConstants

+ (NSString *)callControlHost
{
    NSString *value = [params objectForKey:TC_PARAM_CHUNDER_HOST];
    return value ? value : TWILIO_DEFAULT_CHUNDER_HOST;
}

+ (unsigned short)callControlPort
{
    NSNumber *value = [params objectForKey:TC_PARAM_CHUNDER_PORT];
    return value ? [value unsignedShortValue] : 0;
}

+ (unsigned short)callControlPortUsingTLS:(BOOL)usingTLS
{
    NSNumber *value = [params objectForKey:TC_PARAM_CHUNDER_PORT];
    return value ? [value unsignedShortValue] : ( usingTLS ? TWILIO_DEFAULT_CHUNDER_PORT_TLS : TWILIO_DEFAULT_CHUNDER_PORT_TCP );
}

+ (NSString *)registerHost
{
    NSString *value = [params objectForKey:TC_PARAM_MATRIX_HOST];
    return value ? value : TWILIO_DEFAULT_MATRIX_HOST;
}

+ (NSURL *)matrixUrlForClientName:(NSString *)clientName
                       accountSid:(NSString *)accountSid
                  capabilityToken:(NSString *)capabilityToken
                         features:(NSSet *)features
{
    // URL looks like this:
    // https://$HOST/$API_STRING/$ACCOUNT_SID/$CLIENT_NAME?AccessToken=$CAPABILITY_TOKEN
    NSMutableString *urlStr = [[NSMutableString alloc] initWithFormat:@"https://%@/%@/%@/%@?AccessToken=%@",
            [self registerHost],
            TwilioMatrixApiString,
            accountSid,
            clientName,
            capabilityToken];

    if (features)
    {
        // ... with &feature=$FEATURE appended to the query string for each
        // feature we want to enable
        for (NSString *feature in features)
            [urlStr appendFormat:@"&feature=%@", feature];
    }

    NSURL *url = [NSURL URLWithString:urlStr];
    [urlStr release];
    return url;
}

+ (NSString *)matrixSSLPeerName
{
    NSString *registerHost = [self registerHost];
    if ([registerHost hasSuffix:@".dev.twilio.com"])
        return @"*.dev.twilio.com";
    else if ([registerHost hasSuffix:@".stage.twilio.com"])
        return @"*.stage.twilio.com";
    else
        return @"*.twilio.com";
}

+ (NSString *)callControlPeerName
{
    NSString *callControlHost = [self callControlHost];
    if ([callControlHost hasSuffix:@".dev.twilio.com"])
        return @"*.dev.twilio.com";
    else if ([callControlHost hasSuffix:@".stage.twilio.com"])
        return @"*.stage.twilio.com";
    else
        return @"*.twilio.com";
}

static dispatch_once_t sSetValueDispatchOnceToken = NULL;

+ (void)setValue:(id)value forKey:(NSString *)key
{
    dispatch_once(&sSetValueDispatchOnceToken, ^(void)
    {
        params = [[NSMutableDictionary alloc] init];
    });
    
    [params setValue:value forKey:key];
}

+(NSString*)machineInfo
{
	// thanks Erica Sudan from Ars Technica for letting me be really lazy.
	size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char* machinePtr = malloc(size);
	sysctlbyname("hw.machine", machinePtr, &size, NULL, 0);
	NSString* machineInfo = [NSString stringWithCString:machinePtr encoding:NSUTF8StringEncoding];
	free(machinePtr);
	
	return machineInfo;
}

+(NSString*)archInfo
{
	size_t size = sizeof(uint32_t);
	uint32_t type;
	sysctlbyname("hw.cputype", &type, &size, NULL, 0);
	
	uint32_t subtype;
	sysctlbyname("hw.cpusubtype", &subtype, &size, NULL, 0);
	
	switch (type)
	{
		case CPU_TYPE_X86: // simulator
			return @"x86";
		case CPU_TYPE_X86_64: // simulator
			return @"x86_64";
		case CPU_TYPE_ARM:
		{
			switch ( subtype )
			{
				case CPU_SUBTYPE_ARM_V6:
					return @"armv6";
				case CPU_SUBTYPE_ARM_V7:
					return @"armv7";
				default:
					return [NSString stringWithFormat:@"arm subtype %d", subtype];
			}
		}
		default:
			return [NSString stringWithFormat:@"unknown type %d subtype %d", type, subtype];	
	}
}

static dispatch_once_t sClientStringDispatchOnceToken = NULL;

+(NSString*)clientString
{
    dispatch_once(&sClientStringDispatchOnceToken, ^(void)
    {
        // build up the JSON string that we'll send along with each
        // connection for metrics.
        // The specification for what goes into the string is in
        // the Chunder Functional Specification under the browser/mobile breakdown
        // section.
        // https://docs.google.com/a/twilio.com/document/d/1J2Dje6TiHBKNj4rX52Msj7qxG0xitr3X-hc9962ud4U/edit?hl=en_US
        UIDevice* device = [UIDevice currentDevice];
        
        NSDictionary* mobileDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                    device.model,				METRICS_MOBILE_PRODUCT_KEY,
                                    [TCConstants machineInfo],	METRICS_MOBILE_NAME_KEY, // e.g. iPhone3,1
                                    device.systemVersion,		METRICS_MOBILE_VERSION_KEY,
                                    [TCConstants archInfo],		METRICS_MOBILE_ARCHITECTURE_KEY,
                                    nil];
        
        NSDictionary* mainDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                  METRICS_TWILIO_LIB_PLATFORM_VALUE,	METRICS_TWILIO_LIB_PLATFORM_KEY, // platform
                                  METRICS_TWILIO_LIB_VERSION_VALUE,		METRICS_TWILIO_LIB_VERSION_KEY, // library version
                                  mobileDict,							METRICS_MOBILE_KEY, 
                                  nil ];
        NSString* jsonRepresentation = [mainDict TCJSONRepresentation];
#if DEBUG
        NSLog(@"X-Twilio-Client string: %@", jsonRepresentation);
#endif			
        NSString* encodedRepresentation = [jsonRepresentation stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        sTwilioClientString = [encodedRepresentation retain];
    });
    
	return sTwilioClientString;
}

+(void)shutdown
{
	[params removeAllObjects];
	[params release];
	params = nil;
	sSetValueDispatchOnceToken = NULL; // reset to NULL so the dispatch_once can execute again.
	
	[sTwilioClientString release];
	sTwilioClientString = nil;
	sClientStringDispatchOnceToken = NULL; // reset to NULL so the dispatch_once can execute again.
	
}

@end
