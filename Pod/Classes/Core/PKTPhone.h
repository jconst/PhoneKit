#import <Foundation/Foundation.h>
#import "ReactiveCocoa.h"
#import "TwilioClient.h"
#import "PKTCallRecord.h"

@protocol PKTPhoneDelegate <NSObject>
@optional
- (void)callStartedWithParams:(NSDictionary *)params incoming:(BOOL)incoming;
- (void)callConnected;
- (void)callEndedWithRecord:(PKTCallRecord *)record error:(NSError *)error;
@end

typedef NS_ENUM(NSUInteger, IncomingCallResponse) {
    PKTCallResponseAccept,
    PKTCallResponseIgnore,
    PKTCallResponseReject
};

@interface PKTPhone : NSObject<TCDeviceDelegate, TCConnectionDelegate>

@property (nonatomic, weak            ) id             delegate;

@property (nonatomic, strong          ) NSString       *capabilityToken;
@property (nonatomic, strong          ) NSString       *callerId;
@property (nonatomic, assign          ) BOOL           muted;
@property (nonatomic, assign          ) BOOL           speakerEnabled;
@property (nonatomic, strong, readonly) NSArray        *presenceContactsExceptMe;
@property (nonatomic, assign, readonly) TCDeviceState  state;
@property (nonatomic, assign, readonly) NSTimeInterval callDuration;
@property (nonatomic, assign, readonly) BOOL           hasActiveCall;
@property (nonatomic, assign, readonly) BOOL           hasPendingCall;

@property (nonatomic, strong          ) TCDevice       *phoneDevice;
@property (nonatomic, strong          ) TCConnection   *activeConnection;
@property (nonatomic, strong          ) TCConnection   *pendingIncomingConnection;

+ (instancetype)sharedPhone;

- (void)call:(NSString *)callee;
- (void)call:(NSString *)callee withParams:(NSDictionary *)params;
- (void)sendDigits:(NSString *)digitsString;
- (void)hangup;

- (void)respondToIncomingCall:(IncomingCallResponse)response;

@end
