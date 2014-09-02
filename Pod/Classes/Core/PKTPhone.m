#import "PKTPhone.h"
#import <AudioToolbox/AudioServices.h>
#import <AVFoundation/AVFoundation.h>
#import "RACEXTScope.h"
#import "PKTCallRecord.h"
#import "NSString+PKTHelpers.h"

@interface PKTPhone ()

@property (strong, nonatomic) NSDate *callStart;

@end


@implementation PKTPhone

+ (instancetype)sharedPhone;
{
    static PKTPhone *phone = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        phone = [[self alloc] init];
    });
    return phone;
}

- (id)init
{
	if (self = [super init]) {
        [self setupBindingsForActiveConnection];
        
        //bind self.state to phoneDevice.state:  
        RAC(self, state) = RACObserve(self.phoneDevice, state);
        //update the audio route whenever self.speakerEnabled changes:
        [RACObserve(self, speakerEnabled) subscribeNext:^(NSNumber *enabled) {
            [self changeRouteToSpeaker:[enabled boolValue]];
        }];
        //update the phoneDevice whenever the capability token changes:
        [[RACObserve(self, capabilityToken) ignore:nil] subscribeNext:^(NSString *token) {
            if (self.phoneDevice)
                [self.phoneDevice updateCapabilityToken:token];
            else {
                self.phoneDevice = [[TCDevice alloc] initWithCapabilityToken:token delegate:self];
            }
        }];
        
        RACSignal *didBecomeActive = [[NSNotificationCenter defaultCenter]
                                      rac_addObserverForName:UIApplicationDidBecomeActiveNotification  object:nil];
        [didBecomeActive subscribeNext:^(id _) {
            [self informOfPendingCall];
        }];
        
		_presenceContactsExceptMe = @[];
    }

	return self;
}

- (void)setupBindingsForActiveConnection
{
    [RACObserve(self, activeConnection) subscribeNext:^(TCConnection *conn) {
        if (conn) {
            RAC(conn, muted) = RACObserve(self, muted);
        } else {
            self.muted = NO;
        }
    }];
    
    // set proximity sensor = on if using the iphone's built-in receiver:
    RACSignal *audioRouteChanged = [[NSNotificationCenter defaultCenter]
                                    rac_addObserverForName:AVAudioSessionRouteChangeNotification
                                                    object:[AVAudioSession sharedInstance]];
    
    RAC([UIDevice currentDevice], proximityMonitoringEnabled) = [RACSignal
    combineLatest:@[RACObserve(self, activeConnection), audioRouteChanged]
    reduce:^NSNumber *(TCConnection *conn, NSNotification *notif){

        return (conn && (conn.state == TCConnectionStateConnecting || conn.state == TCConnectionStateConnected))
               ? @([[self audioOutputPorts] containsObject:AVAudioSessionPortBuiltInReceiver])
               : @NO;
    }];
    //disconnect connections when phone will dealloc:
    [self.rac_willDeallocSignal subscribeNext:^(id _) {
        [self.phoneDevice disconnectAll];
    }];
}

#pragma mark - Calls

-(void)call:(NSString *)callee
{
    [self call:callee withParams:nil];
}

- (void)call:(NSString *)callee withParams:(NSDictionary *)params
{
    if (!(self.phoneDevice && self.capabilityToken)) {
        NSLog(@"Error: You must set PKTPhone's capability token before you make a call");
        return;
    }
    
    NSMutableDictionary *connectParams = [NSMutableDictionary dictionaryWithDictionary:params];
    if (callee.length)
        connectParams[@"callee"] = callee;
    if (self.callerId.length)
        connectParams[@"callerId"] = self.callerId;
    self.activeConnection = [self.phoneDevice connect:connectParams delegate:self];
    
    if ([self.delegate respondsToSelector:@selector(callStartedWithParams:incoming:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate callStartedWithParams:connectParams incoming:NO];
        });
    }
}

-(void)sendDigits:(NSString*)digits
{
	if (self.activeConnection && self.activeConnection.state == TCConnectionStateConnected) {
		[self.activeConnection sendDigits:digits];
	}
}

- (void)hangup
{
    [self.activeConnection disconnect];
}

- (BOOL)hasActiveCall
{
    return self.activeConnection && self.activeConnection.state == TCConnectionStateConnected;
}

- (BOOL)hasPendingCall
{
    return self.pendingIncomingConnection != nil;
}

- (PKTCallRecord *)callRecordForConnection:(TCConnection*)connection
{
    PKTCallRecord *record = [PKTCallRecord new];
    record.incoming   = connection.incoming;
    record.startTime  = [NSDate dateWithTimeIntervalSinceNow:-self.callDuration];
    record.duration   = self.callDuration;
    if (record.incoming) {
        record.number = connection.parameters[@"From"];
        record.city   = connection.parameters[@"FromState"];
        record.state  = connection.parameters[@"FromCountry"];
        record.missed = connection != self.activeConnection;
    } else {
        record.number = connection.parameters[@"callee"];
        record.city   = nil;
        record.state  = nil;
    }
    if ([record.number isClientNumber]) {
        record.number = [record.number sanitizeNumber];
    }
    return record;
}

#pragma mark Incoming Calls

- (void)device:(TCDevice*)theDevice didReceiveIncomingConnection:(TCConnection*)connection
{
	if (!([self hasActiveCall] || [self hasPendingCall])) { // only the first incoming connection is handled,
        // and once an active connection is established we auto-reject
		connection.delegate = self;
		self.pendingIncomingConnection = connection;
        
		if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
            [self informOfPendingCall];
        } else {
            // Clear out the old notification before scheduling a new one.
            [[UIApplication sharedApplication] cancelAllLocalNotifications];

            UILocalNotification *alarm = [UILocalNotification new];
            NSString *from             = [connection.parameters[@"From"] sanitizeNumber] ?: @"unknown";
            NSDictionary *callInfo     = @{@"callSID": connection.parameters[TCConnectionIncomingParameterCallSIDKey],
                                          @"from": from};
            alarm.soundName            = @"incoming.wav";
            alarm.alertBody            = [NSString stringWithFormat:@"Incoming Twilio Call From %@", from];
            alarm.userInfo             = callInfo;
            
            [[UIApplication sharedApplication] scheduleLocalNotification:alarm];
        }
	} else {
		[connection reject];
	}
}

- (void)informOfPendingCall
{
    if ([self hasPendingCall] && ![self hasActiveCall]) {
        if ([self.delegate respondsToSelector:@selector(callEndedWithRecord:error:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate callStartedWithParams:self.pendingIncomingConnection.parameters incoming:YES];
            });
        }
    }
}

- (void)respondToIncomingCall:(IncomingCallResponse)response
{
    if (response == PKTCallResponseAccept) {
        [self.pendingIncomingConnection accept];
        self.activeConnection = self.pendingIncomingConnection;
    } else {
        response == PKTCallResponseReject ? [self.pendingIncomingConnection reject]
                                          : [self.pendingIncomingConnection ignore];
    }
    self.pendingIncomingConnection = nil; // pending becomes active.
}

- (BOOL)shouldRingThroughSpeaker
{
	return [[self audioOutputPorts] containsObject:AVAudioSessionPortBuiltInReceiver] ||
           [[self audioOutputPorts] containsObject:AVAudioSessionPortBuiltInSpeaker];
}

#pragma mark - TCDeviceDelegate

-(void)device:(TCDevice*)theDevice didStopListeningForIncomingConnections:(NSError*)error
{
	if (error)
		NSLog(@"Did stop listening for connections due to error %@", [error localizedDescription]);
	else
		NSLog(@"Stopped listening for connections");
}

-(void)device:(TCDevice*)device didReceivePresenceUpdate:(TCPresenceEvent*)presenceEvent
{
	// skip any update if it's about the logged in client.
    NSString *clientName = self.phoneDevice.capabilities[TCDeviceCapabilityClientNameKey];
	if ([presenceEvent.name isEqualToString:clientName])
		return;
    
	NSString *contact = [self.presenceContactsExceptMe.rac_sequence objectPassingTest:^BOOL(NSString *c) {
        return [c isEqualToString:presenceEvent.name];
    }];
    
    NSMutableArray *newPresence = [self.presenceContactsExceptMe mutableCopy];
	
    BOOL changed = NO;
    if (!contact && presenceEvent.available) {
        [newPresence addObject:presenceEvent.name];
		changed = YES;
    }
	else if (contact && !presenceEvent.available) {
        [newPresence removeObject:contact];
		changed = YES;
    }
	
	if (changed) {
		[newPresence sortUsingComparator:^(NSString *name1, NSString *name2) {
            return [name1 localizedCaseInsensitiveCompare:name2];
        }];
		
		_presenceContactsExceptMe = newPresence;
	}
}

#pragma mark - TCConnectionDelegate

-(void)connectionDidConnect:(TCConnection*)theConnection
{
    self.callStart = [NSDate date];
    
    //signal that sends next when activeConnection dies
    RACSignal *endSignal = [RACObserve(self, activeConnection) filter:^BOOL(TCConnection *conn) {
        return conn == nil;
    }];
    
    //Every 1 second, until activeConnection is nil,
    //set self.callDuration to the number of seconds since callStart
    RAC(self, callDuration) = [[[RACSignal
    interval:1.0 onScheduler:[RACScheduler mainThreadScheduler]]
    takeUntil:endSignal]
    map:^NSNumber *(NSDate *current) {
        return @([current timeIntervalSinceDate:self.callStart]);
    }];

	[self changeRouteToSpeaker:self.speakerEnabled];
    
    if ([self.delegate respondsToSelector:@selector(callConnected)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate callConnected];
        });
    }
}

-(void)connectionDidDisconnect:(TCConnection*)theConnection
{
	[self connectionDisconnected:theConnection error:nil];
}

-(void)connection:(TCConnection*)theConnection didFailWithError:(NSError*)error
{
	[self connectionDisconnected:theConnection error:error];
}

// common behaviors whether the call disconnects normally or due to an error
-(void)connectionDisconnected:(TCConnection*)connection error:(NSError *)error
{
    PKTCallRecord *record = [self callRecordForConnection:connection];
	
    if (connection == self.activeConnection) {
		self.activeConnection = nil;
		self.speakerEnabled = NO;
	}
    if (connection == self.pendingIncomingConnection) {
		self.pendingIncomingConnection = nil;
	}
    
    if ([self.delegate respondsToSelector:@selector(callEndedWithRecord:error:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate callEndedWithRecord:record error:error];
        });
    }
}

#pragma mark - Helpers

- (void)changeRouteToSpeaker:(BOOL)speaker
{
    AVAudioSessionPortOverride override = speaker ? AVAudioSessionPortOverrideSpeaker
                                                  : kAudioSessionOverrideAudioRoute_None;
    
    [[AVAudioSession sharedInstance] overrideOutputAudioPort:override error:nil];
}

- (NSArray *)audioOutputPorts
{
    return [[[[AVAudioSession sharedInstance] currentRoute].outputs.rac_sequence
    map:^NSString *(AVAudioSessionPortDescription *desc) {
        return desc.portType;
    }] array];
}

@end
