#import <UIKit/UIKit.h>
#import "JCDialPad.h"
#import "PKTPhone.h"

@interface PKTCallViewController : UIViewController <JCDialPadDelegate, PKTPhoneDelegate>

@property (nonatomic, weak  ) id<PKTPhoneDelegate> phoneDelegate;
@property (nonatomic, strong) NSString             *mainText;
@property (nonatomic, strong) UILabel              *callStatusLabel;

@end
