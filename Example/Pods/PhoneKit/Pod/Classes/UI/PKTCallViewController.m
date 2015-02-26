#import "PKTCallViewController.h"

#import "PKTPhone.h"
#import "JCPadButton.h"
#import "FontasticIcons.h"
#import "UIView+FrameAccessor.h"

#define kCallingViewMuteInput @"M"
#define kCallingViewKeypadInput @"K"
#define kCallingViewSpeakerInput @"S"
#define kCallingViewAcceptInput @"A"
#define kCallingViewIgnoreInput @"I"
#define kCallingViewHangupInput @"H"
#define kKeyboardViewBackInput @"B"
#define DEG_TO_RAD(deg) deg*M_PI/180

@interface PKTCallViewController ()

@property (strong, nonatomic) JCDialPad *mainPad;
@property (strong, nonatomic) JCDialPad *keyPad;
@property (strong, nonatomic) JCDialPad *incomingPad;
@property (strong, nonatomic) UIImage   *backgroundImage;

@end

@implementation PKTCallViewController

#pragma mark - View Lifecycle

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder]) {
        [self initializeProperties];
    }
    return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        [self initializeProperties];
    }
    return self;
}

- (void)initializeProperties
{
    self.mainPad     = [JCDialPad new];
    self.keyPad      = [JCDialPad new];
    self.incomingPad = [JCDialPad new];
    self.mainText    = @"";
    
    RAC(self.mainPad, rawText)     = RACObserve(self, mainText);
    RAC(self.incomingPad, rawText) = RACObserve(self, mainText);
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	
    self.incomingPad.buttons = [self incomingPadButtons];
    self.keyPad.buttons      = [self keyPadButtons];
    [self setupDialPads];
    [self setupCallStatusLabel];
}

- (void)present
{
    UIApplication *app                   = [UIApplication sharedApplication];
    UIViewController *rootViewController = (UITabBarController *)app.keyWindow.rootViewController;
    if (rootViewController.presentedViewController == self) {
        return;
    } else if (rootViewController.presentedViewController) {
        [rootViewController dismissViewControllerAnimated:YES completion:^{
            [self present];
        }];
    }
    
    //take snapshot of root view and set as background:
    UIGraphicsBeginImageContext(rootViewController.view.size);
    [rootViewController.view drawViewHierarchyInRect:rootViewController.view.bounds afterScreenUpdates:YES];
    self.backgroundImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    [rootViewController presentViewController:self animated:YES completion:nil];
}

#pragma mark - PKTPhoneDelegate

- (void)callStartedWithParams:(NSDictionary *)params incoming:(BOOL)incoming
{
    [self present];
    if (incoming && !self.mainText.length) {
        self.mainText = params[@"From"] ?: @"unknown";
    }
 	self.callStatusLabel.text = incoming ? @"incoming call" : @"connecting...";
    [self switchToPad:incoming ? self.incomingPad : self.mainPad
             animated:NO];
    
    if ([self.phoneDelegate respondsToSelector:_cmd])
        [self.phoneDelegate callStartedWithParams:params incoming:incoming];
}

- (void)callConnected
{
    [self switchToPad:self.mainPad
             animated:NO];
    
    if ([self.phoneDelegate respondsToSelector:_cmd])
        [self.phoneDelegate callConnected];
}

-(void)callEndedWithRecord:(PKTCallRecord *)record error:(NSError *)error
{
    self.callStatusLabel.text = @"call ended";
    self.keyPad.rawText       = @"";
    [[[RACSignal empty] delay:0.5] subscribeCompleted:^{
        [self dismissViewControllerAnimated:YES completion:nil];
    }];
    
    if ([self.phoneDelegate respondsToSelector:_cmd])
        [self.phoneDelegate callEndedWithRecord:record error:error];
}

#pragma mark - Dial Pads

- (NSArray *)dialPads
{
    return @[self.mainPad, self.keyPad, self.incomingPad];
}

- (void)setupDialPads
{
    for (JCDialPad *dialPad in [self dialPads]) {
        dialPad.showDeleteButton = NO;
        dialPad.frame            = self.view.bounds;
        dialPad.delegate         = self;
        
        [[RACObserve(self, backgroundImage)
         ignore:nil]
         subscribeNext:^(UIImage *bg) {
            UIImageView* backgroundView = [[UIImageView alloc] initWithImage:bg];
            backgroundView.contentMode  = UIViewContentModeScaleAspectFill;
            [dialPad setBackgroundView:backgroundView];
        }];
        
        [self.view addSubview:dialPad];
    }
    
    self.incomingPad.hidden             = YES;
    self.keyPad.hidden                  = YES;
    self.keyPad.formatTextToPhoneNumber = NO;
    
    //reload mainPad buttons whenever muted or speakerEnabled changes,
    //or if viewWillAppear fires
    [[[RACSignal
    combineLatest:@[RACObserve([PKTPhone sharedPhone], muted),
                    RACObserve([PKTPhone sharedPhone], speakerEnabled)]]
            merge:[self rac_signalForSelector:@selector(viewWillAppear:)]]
    subscribeNext:^(RACTuple *next) {
        //reload buttons
        self.mainPad.buttons = [self mainPadButtons];
        [self.mainPad layoutSubviews];
    }];
}

- (NSArray *)mainPadButtons
{
    NSArray *inputs = @[kCallingViewMuteInput,
                        kCallingViewKeypadInput,
                        kCallingViewSpeakerInput,
                        kCallingViewHangupInput];
    NSArray *icons = @[[PKTPhone sharedPhone].muted ? [FIFontAwesomeIcon microphoneIcon] : [FIFontAwesomeIcon microphoneOffIcon],
                       [FIFontAwesomeIcon thIcon],
                       [PKTPhone sharedPhone].speakerEnabled ? [FIFontAwesomeIcon volumeDownIcon] : [FIFontAwesomeIcon volumeUpIcon],
                       [FIFontAwesomeIcon phoneIcon]];
    
    NSMutableArray *buttons = [NSMutableArray array];
    
    [inputs enumerateObjectsUsingBlock:^(NSString *input, NSUInteger i, BOOL *stop) {
        FIIconView *iconView     = [[FIIconView alloc] initWithFrame:CGRectMake(0, 0, 65, 65)];
        iconView.backgroundColor = [UIColor clearColor];
        iconView.icon            = icons[i];
        iconView.padding         = 15;
        iconView.iconColor       = [UIColor whiteColor];
        JCPadButton *button      = [[JCPadButton alloc] initWithInput:input iconView:iconView subLabel:@""];
        
        if ([input isEqual:kCallingViewHangupInput] ||
            [input isEqual:kCallingViewKeypadInput]) {
            iconView.transform     = CGAffineTransformMakeRotation(DEG_TO_RAD(90));
        } if ([input isEqual:kCallingViewHangupInput]) {
            UIColor *buttonColor   = [UIColor colorWithRed:0.987 green:0.133 blue:0.146 alpha:1.000];
            button.backgroundColor = buttonColor;
            button.borderColor     = buttonColor;
        }
        [buttons addObject:button];
    }];
    return buttons;
}

- (NSArray *)keyPadButtons
{
    FIIconView *iconView     = [[FIIconView alloc] initWithFrame:CGRectMake(0, 0, 65, 65)];
    iconView.backgroundColor = [UIColor clearColor];
    iconView.icon            = [FIFontAwesomeIcon replyIcon];
    iconView.padding         = 15;
    iconView.iconColor       = [UIColor whiteColor];

    JCPadButton *backButton  = [[JCPadButton alloc] initWithInput:kKeyboardViewBackInput iconView:iconView subLabel:@""];
    
    return [[JCDialPad defaultButtons] arrayByAddingObject:backButton];
}

- (NSArray *)incomingPadButtons
{
    NSArray *inputs = @[kCallingViewAcceptInput,
                        kCallingViewIgnoreInput,
                        kCallingViewHangupInput];
    NSArray *icons = @[[FIFontAwesomeIcon phoneIcon],
                       [FIEntypoIcon muteIcon],
                       [FIFontAwesomeIcon phoneIcon]];
    
    NSMutableArray *buttons = [NSMutableArray array];
    
    [inputs enumerateObjectsUsingBlock:^(NSString *input, NSUInteger i, BOOL *stop) {
        FIIconView *iconView     = [[FIIconView alloc] initWithFrame:CGRectMake(0, 0, 65, 65)];
        iconView.backgroundColor = [UIColor clearColor];
        iconView.icon            = icons[i];
        iconView.padding         = 15;
        iconView.iconColor       = [UIColor whiteColor];
        JCPadButton *button      = [[JCPadButton alloc] initWithInput:input iconView:iconView subLabel:@""];

        UIColor *buttonColor     = [UIColor colorWithRed:0.488 green:0.478 blue:0.504 alpha:1.000];
        
        if ([input isEqual:kCallingViewAcceptInput]) {
            buttonColor        = [UIColor colorWithRed:0.261 green:0.837 blue:0.319 alpha:1.000];
        } if ([input isEqual:kCallingViewHangupInput]) {
            buttonColor        = [UIColor colorWithRed:0.987 green:0.133 blue:0.146 alpha:1.000];
            iconView.transform = CGAffineTransformMakeRotation(DEG_TO_RAD(90));
        }
        button.backgroundColor = buttonColor;
        button.borderColor     = buttonColor;
        [buttons addObject:button];
    }];
    return buttons;
}

- (BOOL)dialPad:(JCDialPad *)dialPad shouldInsertText:(NSString *)text forButtonPress:(JCPadButton *)button
{
    if (dialPad == self.mainPad) {
        if ([text isEqual:kCallingViewMuteInput]) {
            [PKTPhone sharedPhone].muted = ![PKTPhone sharedPhone].muted;
        }
        else if ([text isEqual:kCallingViewSpeakerInput]) {
            [PKTPhone sharedPhone].speakerEnabled = ![PKTPhone sharedPhone].speakerEnabled;
        }
        else if ([text isEqualToString:kCallingViewKeypadInput]) {
            [self switchToPad:self.keyPad animated:YES];
        }
        else {
            [[PKTPhone sharedPhone] hangup];
        }
        return NO;
    }
    else if (dialPad == self.keyPad) {
        if ([text isEqual:kKeyboardViewBackInput]) {
            [self switchToPad:self.mainPad animated:YES];
            return NO;
        }
        [[PKTPhone sharedPhone] sendDigits:text];
        return YES;
    } else {
        NSDictionary *responses = @{kCallingViewAcceptInput: @(PKTCallResponseAccept),
                                    kCallingViewIgnoreInput: @(PKTCallResponseIgnore),
                                    kCallingViewHangupInput: @(PKTCallResponseReject)};
        [[PKTPhone sharedPhone] respondToIncomingCall:[responses[text] unsignedIntegerValue]];
        return NO;
    }
}

-(void)switchToPad:(JCDialPad *)pad animated:(BOOL)animated
{
    if (pad.hidden) {
        pad.alpha = 0;
    }
    pad.hidden = NO;
    [self.view bringSubviewToFront:pad];
    [self.view bringSubviewToFront:self.callStatusLabel];
    
    [UIView animateWithDuration:0.3*animated animations:^{
        self.callStatusLabel.alpha = !(pad == self.keyPad);
        pad.alpha = 1.0;
    } completion:^(BOOL finished) {
        for (JCDialPad *otherPad in [self dialPads]) {
            if (otherPad != pad)
                otherPad.hidden = YES;
        }
    }];
}

#pragma mark - Call Status Label

- (void)setupCallStatusLabel
{
    CGRect frame                                = CGRectMake(0, self.mainPad.digitsTextField.bottom, self.view.width, 24);
    self.callStatusLabel                        = [[UILabel alloc] initWithFrame:frame];
    self.callStatusLabel.textColor              = [UIColor colorWithWhite:1.000 alpha:0.800];
    self.callStatusLabel.font                   = [UIFont fontWithName:@"HelveticaNeue-Light" size:16];
    self.callStatusLabel.textAlignment          = NSTextAlignmentCenter;
    self.callStatusLabel.userInteractionEnabled = NO;
    [self.view addSubview:self.callStatusLabel];
    
    RACSignal *statusText =
    [RACObserve([PKTPhone sharedPhone], callDuration)
    map:^NSString *(NSNumber *duration){
        long dur      = [duration longValue];
        BOOL hasHours = dur / 3600 > 0;
        if (hasHours) {
            return [NSString stringWithFormat:@"%lu:%02lu:%02lu", dur/3600, (dur % 3600)/60, dur % 60];
        } else {
            return [NSString stringWithFormat:@"%02lu:%02lu", dur/60, dur % 60];
        }
    }];
    RAC(self.callStatusLabel, text) = statusText;
}

#pragma mark - Preferences

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

@end
