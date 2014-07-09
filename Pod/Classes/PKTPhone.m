#import "PKTPhone.h"
#import <AudioToolbox/AudioServices.h>
#import "RACEXTScope.h"
#import "PKTCallViewController.h"
#import "PKTCallRecord.h"
#import "NSString+PKTHelpers.h"

@interface PKTPhone ()

@property (strong, nonatomic) PKTCallViewController *callingViewController;
@property (strong, nonatomic) TCDevice                 *phoneDevice;
@property (strong, nonatomic) TCConnection             *activeConnection;
@property (strong, nonatomic) TCConnection             *pendingIncomingConnection;
@property (strong, nonatomic) AVAudioPlayer            *audioPlayer;
@property (strong, nonatomic) NSDate                   *callStart;

@end


@implementation PKTPhone

+ (instancetype)phoneWithCapabilityToken:(NSString *)token
{
    PKTPhone *phone = [[self alloc] init];
    phone.capabilityToken = token;
    return phone;
}

- (id)init
{
	if (self = [super init])
	{
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
            else
                self.phoneDevice = [[TCDevice alloc] initWithCapabilityToken:token delegate:self];
        }];
        
        [self setupRinger];

		_speakerEnabled = NO;
		_presenceContactsExceptMe = @[];
    }

	return self;
}

- (void)setupRinger
{
    NSString* ringPath = [[NSBundle mainBundle] pathForResource:@"ring" ofType:@"wav"];
    if ( ringPath )
    {
        NSURL *ringURL = [NSURL fileURLWithPath:ringPath];
        
        self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:ringURL error:nil];
        self.audioPlayer.numberOfLoops = -1;
        [self.audioPlayer prepareToPlay];
    }
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

        if (conn && (conn.state == TCConnectionStateConnecting ||
                     conn.state == TCConnectionStateConnected)) {
            
            return @([[self audioOutputPorts] containsObject:AVAudioSessionPortBuiltInReceiver]);
        } else {
            return @NO;
        }
    }];
    //disconnect connections when phone will dealloc:
    [self.rac_willDeallocSignal subscribeNext:^(id x) {
        [self.activeConnection disconnect];
        [self.pendingIncomingConnection reject];
    }];
}

#pragma mark - Calls

-(void)call:(NSString*)number
{
    self.callingViewController = [PKTCallViewController presentCallViewWithNumber:number unanswered:NO phone:self];

    NSMutableDictionary* params = [NSMutableDictionary dictionary];
    params[@"type"] = [number isClientNumber] ? @"client" : @"phone";
    
    if (number) {
        NSString* sanitizedNumber = [number sanitizeNumber];
        params[@"to"] = sanitizedNumber;
    }
    
    if (self.callerID)
        params[@"callerid"] = self.callerID;
    
    if (self.phoneDevice)
        self.activeConnection = [self.phoneDevice connect:params delegate:self];
}

-(void)sendDigits:(NSString*)digits
{
	if (self.activeConnection && self.activeConnection.state == TCConnectionStateConnected) {
		[self.activeConnection sendDigits:digits];
	}
}

- (void)hangup
{
    [self.activeConnection disconnect]; // will be nilled out in connectionDidDisconnect
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.callingViewController dismissViewControllerAnimated:YES completion:nil];
    });
}

- (BOOL)inCall
{
    return self.activeConnection && self.activeConnection.state == TCConnectionStateConnected;
}

- (PKTCallRecord *)callRecordForConnection:(TCConnection*)connection
{
    PKTCallRecord *record = [PKTCallRecord new];
    record.incoming    = connection.incoming;
    record.dateTime    = [NSDate date];

    if (record.incoming) {
        record.number = (connection.parameters)[@"From"];
        record.city   = (connection.parameters)[@"FromState"];
        record.state  = (connection.parameters)[@"FromCountry"];

        // Call record starts as missed if it's incoming.
        // Once the connection is answered, we'll update the record.
        record.missed = YES;
    } else {
        NSDictionary *params    = connection.parameters;
        record.number           = params[@"to"];
        record.city             = nil;
    }
    
    if ([record.number isClientNumber]) {
        record.number = [record.number sanitizeNumber];
    }

    return record;
}

#pragma mark Incoming Calls

//called after self.pendingIncomingConnection is already set to the call
- (void)showIncomingCall:(NSDictionary *)callInfo
{
    if (![callInfo[@"callSID"] isEqualToString:self.pendingIncomingConnection.parameters[TCConnectionIncomingParameterCallSIDKey]]) {
        NSLog(@"acceptNotification(): Call is already terminated");
        return;
    }
    [self toggleRinger:YES];
    
    self.callingViewController = [PKTCallViewController presentCallViewWithNumber:callInfo[@"from"] unanswered:YES phone:self];
}

- (void)respondToIncomingCall:(IncomingCallResponse)response
{
    [self toggleRinger:NO];
    NSArray* oldNotifications = [[UIApplication sharedApplication] scheduledLocalNotifications];
    // Clear out the old notification before scheduling a new one.
    if ([oldNotifications count] > 0) {
        [[UIApplication sharedApplication] cancelAllLocalNotifications];
    }
    
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

-(void)toggleRinger:(BOOL)on
{
	if (on) {
		AudioServicesPlaySystemSound(kSystemSoundID_Vibrate); // won't vibrate if user has them disabled
		if ([self shouldRingThroughSpeaker]) {
			[self changeRouteToSpeaker:YES];
		}
		self.audioPlayer.currentTime = 0;
		[self.audioPlayer play];
	}
	else if ( self.audioPlayer.playing ) // don't change the route unless the ringer is actually going.
	{
		// be a good citizen and set the audio route to off once the ringer is done.
		[self changeRouteToSpeaker:NO];
		[self.audioPlayer stop];
	}
}

#pragma mark - TCDeviceDelegate

- (void)deviceDidStartListeningForIncomingConnections:(TCDevice *)device
{
}

-(void)device:(TCDevice*)theDevice didStopListeningForIncomingConnections:(NSError*)error
{
	if (error)
		NSLog(@"Did stop listening for connections due to error %@", [error localizedDescription]);
	else
		NSLog(@"Stopped listening for connections");
}

- (void)device:(TCDevice*)theDevice didReceiveIncomingConnection:(TCConnection*)connection
{
	if (![self hasActiveOrPendingCall]) { // only the first incoming connection is handled,
                                                // and once an active connection is established we auto-reject
		connection.delegate = self;
		self.pendingIncomingConnection = connection;
		
        NSString *from = connection.parameters[@"From"] ?: @"unknown";
        
        NSDictionary *callInfo = @{@"callSID": self.pendingIncomingConnection.parameters[TCConnectionIncomingParameterCallSIDKey],
                                      @"from": from};
        
		if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
            UILocalNotification* alarm = [UILocalNotification new];
            
            if (alarm) {
                from                   = [from sanitizeNumber];
                alarm.alertAction      = @"View";
                alarm.fireDate         = [NSDate date];
                alarm.timeZone         = [NSTimeZone defaultTimeZone];
                alarm.repeatInterval   = 0;
                alarm.soundName        = @"default";
                alarm.alertBody        = [NSString stringWithFormat:@"Incoming Twilio Call From %@", from];

                [alarm setUserInfo:callInfo];
                
                [[UIApplication sharedApplication] scheduleLocalNotification:alarm];
            }
        } else {
            [self showIncomingCall:callInfo];
        }
	} else {
		[connection reject];
	}
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
    [self.callingViewController callConnected];
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
-(void)connectionDisconnected:(TCConnection*)theConnection error:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.callingViewController callEnded];
        [self.callingViewController dismissViewControllerAnimated:YES completion:nil];
    });
    
    PKTCallRecord *record = [self callRecordForConnection:theConnection];

	if (theConnection == self.pendingIncomingConnection) {
		self.pendingIncomingConnection = nil;
		[self toggleRinger:NO];
	}
	if (theConnection == self.activeConnection) {
		self.activeConnection = nil;
		self.speakerEnabled = NO;
        record.missed = NO;
	}

    if ([self.delegate respondsToSelector:@selector(callEndedWithRecord:error:)])
        [self.delegate callEndedWithRecord:record error:error];
}

#pragma mark - Helpers

- (void)changeRouteToSpeaker:(BOOL)speaker
{
    AVAudioSessionPortOverride override = speaker
    ? AVAudioSessionPortOverrideSpeaker
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

-(BOOL)hasActiveOrPendingCall
{
    return  (self.activeConnection.state == TCConnectionStateConnected ||
             self.pendingIncomingConnection.state == TCConnectionStateConnected);
}

#pragma mark - Teardown

-(void)dealloc
{
    [self.phoneDevice disconnectAll];
    self.phoneDevice = nil;
}

@end
