#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "ReactiveCocoa.h"
#import "TwilioClient.h"
#import "PKTCallRecord.h"

@protocol PKTPhoneDelegate <NSObject>
- (void)callEndedWithRecord:(PKTCallRecord *)record error:(NSError *)error;
@end

typedef NS_ENUM(NSUInteger, IncomingCallResponse) {
    PKTCallResponseAccept,
    PKTCallResponseIgnore,
    PKTCallResponseReject
};

@class PKTCallViewController;

@interface PKTPhone : NSObject<TCDeviceDelegate, TCConnectionDelegate>

@property (weak, nonatomic            ) id             delegate;

@property (nonatomic, strong          ) NSString       *capabilityToken;
@property (nonatomic, strong          ) NSString       *callerID;
@property (nonatomic, assign          ) BOOL           muted;
@property (nonatomic, assign          ) BOOL           speakerEnabled;
@property (nonatomic, strong, readonly) NSArray        *presenceContactsExceptMe;
@property (nonatomic, assign, readonly) TCDeviceState  state;
@property (nonatomic, assign, readonly) NSTimeInterval callDuration;
@property (nonatomic, assign, readonly) BOOL           inCall;
@property (nonatomic, assign, readonly) BOOL           hasActiveOrPendingCall;

+ (instancetype)phoneWithCapabilityToken:(NSString *)token;

- (void)call:(NSString *)number;
- (void)sendDigits:(NSString *)digitsString;
- (void)hangup;

- (void)showIncomingCall:(NSDictionary *)callInfo;
- (void)respondToIncomingCall:(IncomingCallResponse)response;

- (void)toggleRinger:(BOOL)on;

@end
