
#import "JCDialPad.h"
#import "JCPadButton.h"
#import "UIView+FrameAccessor.h"
#import "NBAsYouTypeFormatter.h"

#define DIV_ROUND_UP(N,D) ((N+D-1)/D)
#define animationLength 0.3
#define IS_IPHONE5 ([UIScreen mainScreen].bounds.size.height==568)
#define IS_IOS6_OR_LOWER (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_6_1)
#define IS_IPAD UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad

@interface JCDialPad()

@property (nonatomic, strong) UIView* contentView;
@property (nonatomic, strong) UIView* backgroundBlurringView;
@property (nonatomic, strong) NBAsYouTypeFormatter *numFormatter;

@end


@implementation JCDialPad

- (id)initWithFrame:(CGRect)frame buttons:(NSArray *)buttons
{
    if (self = [self initWithFrame:frame])
    {
        self.buttons = buttons;
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self initializeProperties];
        self.frame = frame;
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder]) {
        [self initializeProperties];
    }
    return self;
}

- (void)initializeProperties
{
    [self setDefaultStyles];
    
    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, MIN(self.height, 568.0f))];
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.contentView.center = self.center;
    [self addSubview:self.contentView];
    
    self.deleteButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.deleteButton addTarget:self action:@selector(didTapDeleteButton:) forControlEvents:UIControlEventTouchUpInside];
    self.deleteButton.titleLabel.font = [UIFont systemFontOfSize:24.0];
    [self.deleteButton setTitle:@"◀︎" forState:UIControlStateNormal];
    [self.deleteButton setTitleColor:[self.mainColor colorWithAlphaComponent:0.500] forState:UIControlStateHighlighted];
    self.deleteButton.hidden = YES;
    self.deleteButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    UIGestureRecognizer *holdRec = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(didHoldDeleteButton:)];
    [self.deleteButton addGestureRecognizer:holdRec];
    
    self.digitsTextField = [UITextField new];
    self.digitsTextField.font = IS_IOS6_OR_LOWER
                                ? [UIFont fontWithName:@"HelveticaNeue" size:38.0]
                                : [UIFont fontWithName:@"HelveticaNeue-Thin" size:38.0];
    self.digitsTextField.adjustsFontSizeToFitWidth = YES;
    self.digitsTextField.enabled = NO;
    self.digitsTextField.textAlignment = NSTextAlignmentCenter;
    self.digitsTextField.contentVerticalAlignment = UIViewContentModeCenter;
    self.digitsTextField.borderStyle = UITextBorderStyleNone;
    self.digitsTextField.textColor = [self.mainColor colorWithAlphaComponent:0.9];
    
    self.formatTextToPhoneNumber = YES;
    self.rawText = @"";
}

#pragma mark -
#pragma mark - Lifecycle Methods

- (void)setDefaultStyles
{
    self.frame = [[UIScreen mainScreen] bounds];
    if (IS_IOS6_OR_LOWER) {
        self.y += 20;
        self.height -= 64;
    }
    self.mainColor = [UIColor whiteColor];
    self.showDeleteButton = YES;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    for (UIView *subview in [self.contentView subviews]) {
        [subview removeFromSuperview];
    }
    [self performLayout];
}

#pragma mark -
#pragma mark - Public Methods
+ (NSArray *)defaultButtons
{
    NSArray *mains = @[@"1", @"2",   @"3",   @"4",   @"5",   @"6",   @"7",    @"8",   @"9",    @"✳︎", @"0", @"＃"];
    NSArray *subs  = @[@"",  @"ABC", @"DEF", @"GHI", @"JKL", @"MNO", @"PQRS", @"TUV", @"WXYZ", @"",  @"+", @""];
    NSMutableArray *ret = [NSMutableArray array];
    
    [mains enumerateObjectsUsingBlock:^(NSString *main, NSUInteger idx, BOOL *stop) {
        JCPadButton *button = [[JCPadButton alloc] initWithMainLabel:main subLabel:subs[idx]];
        if ([main isEqualToString:@"✳︎"]) {
            button.input = @"*";
        } else if ([main isEqualToString:@"＃"]) {
            button.input = @"#";
        }
        [ret addObject:button];
    }];
    
    return ret;
}

- (void)setBackgroundView:(UIView *)backgroundView
{
	[_backgroundView removeFromSuperview];
	_backgroundView = backgroundView;

	if(_backgroundView == nil) {
		[self.backgroundBlurringView setHidden:YES];
	} else {
		if(self.backgroundBlurringView == nil) {
			if (IS_IOS6_OR_LOWER) {
                self.backgroundBlurringView = [[UIView alloc] initWithFrame:self.bounds];
				self.backgroundBlurringView.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.75f];
			} else {
				self.backgroundBlurringView = [[UINavigationBar alloc] initWithFrame:self.bounds];
				[(UINavigationBar*)self.backgroundBlurringView setBarStyle: UIBarStyleBlack];
			}
			self.backgroundBlurringView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
			[self insertSubview:self.backgroundBlurringView belowSubview:self.contentView];
		}
		
		[self.backgroundBlurringView setHidden:NO];

		[_backgroundView setFrame:self.bounds];
		[_backgroundView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
		[self insertSubview:_backgroundView belowSubview:self.backgroundBlurringView];
	}
}

#pragma mark - Helper Methods
- (void)didTapButton:(UIButton *)sender
{
    if ([sender isKindOfClass:[JCPadButton class]]) {
        JCPadButton *button = (JCPadButton *)sender;
        
        if (![self.delegate respondsToSelector:@selector(dialPad:shouldInsertText:forButtonPress:)] ||
            [self.delegate dialPad:self shouldInsertText:button.input forButtonPress:button]) {
            [self appendText:button.input];
        }
    }
}

- (void)setRawText:(NSString *)rawText
{
    self.numFormatter = [[NBAsYouTypeFormatter alloc] initWithRegionCode:@"US"];
    _rawText = @"";
    self.digitsTextField.text = @"";
    for (int i = 0; i < rawText.length; ++i) {
        NSString *c = [rawText substringWithRange:NSMakeRange(i, 1)];
        [self appendText:c];
    }
    if (!self.rawText.length) {
        [self toggleDeleteButtonVisible:NO animated:YES];
    }
}

- (void)setShowDeleteButton:(BOOL)showDeleteButton
{
    _showDeleteButton = showDeleteButton;
    if (!showDeleteButton) {
        [self toggleDeleteButtonVisible:NO animated:YES];
    }
}

- (void)appendText:(NSString *)text
{
    if (text.length) {
        _rawText = [self.rawText stringByAppendingString:text];
        NSString *formatted = self.rawText;
        if (self.formatTextToPhoneNumber) {
            [self.numFormatter inputDigit:text];
            formatted = [self.numFormatter description];
        }
        self.digitsTextField.text = formatted;
        
        [self toggleDeleteButtonVisible:YES animated:YES];
    }
}

- (void)didTapDeleteButton:(UIButton *)sender
{
    if (!self.rawText.length)
        return;
    
    _rawText = [self.rawText substringToIndex:self.rawText.length - 1];
    NSString *formatted = self.rawText;
    if (self.formatTextToPhoneNumber) {
        [self.numFormatter removeLastDigit];
        formatted = [self.numFormatter description];
    }
    self.digitsTextField.text = formatted;
    if (!self.rawText.length) {
        [self toggleDeleteButtonVisible:NO animated:YES];
    }
}

- (void)didHoldDeleteButton:(UIGestureRecognizer *)holdRec
{
    self.rawText = @"";
}

#pragma mark - Layout Methods
- (void)performLayout
{
    [self layoutTitleArea];
    [self layoutButtons];
}

- (void)layoutTitleArea
{
    CGFloat top = 22;
	
	if(IS_IPHONE5) {
		top = 35;
	} else if (IS_IPAD) {
        top = 60;
    }
    if (IS_IOS6_OR_LOWER) {
        top -= 20;
    }
	
    CGFloat textFieldWidth = 250;
    self.digitsTextField.frame = CGRectMake((self.correctWidth / 2.0) - (textFieldWidth / 2.0), top, textFieldWidth, 40);
    [self.contentView addSubview:self.digitsTextField];
    
    self.deleteButton.frame = CGRectMake(self.digitsTextField.right + 2, self.digitsTextField.center.y - 10, top + 28, 20);
    [self.contentView addSubview:self.deleteButton];
}

- (void)layoutButtons
{
    NSInteger count                       = self.buttons.count;
    NSInteger numRows                     = DIV_ROUND_UP(count, 3);

    const CGFloat bottomSpace             = IS_IOS6_OR_LOWER ? 36 : 60; //Leave room for tab bar if necessary
    CGFloat highestTopAllowed             = self.digitsTextField.bottom + 4;
    CGFloat maxButtonAreaHeight           = self.height - highestTopAllowed - bottomSpace;

    const CGFloat horizontalButtonPadding = 20;
    CGFloat totalButtonHeight             = numRows * JCPadButtonHeight;
    CGFloat maxTotalPaddingHeight         = maxButtonAreaHeight - totalButtonHeight;
    CGFloat verticalButtonPadding         = MIN(16, maxTotalPaddingHeight / (numRows-1));
    CGFloat totalPaddingHeight            = verticalButtonPadding * (numRows-1);
    
    CGFloat buttonAreaHeight              = totalPaddingHeight + totalButtonHeight;
    CGFloat buttonAreaVertCenter          = highestTopAllowed + (maxButtonAreaHeight/2);
    CGFloat topRowTop                     = buttonAreaVertCenter - (buttonAreaHeight/2);
    
    CGFloat cellWidth                     = JCPadButtonWidth + horizontalButtonPadding;
    CGFloat center                        = [self correctWidth]/2.0;
    
    if (IS_IPAD) {
        topRowTop = highestTopAllowed + 24;
    }
    
    [self.buttons enumerateObjectsUsingBlock:^(JCPadButton *btn, NSUInteger idx, BOOL *stop) {
        NSInteger row = idx / 3;
        NSInteger btnsInRow = MIN(3, count - (row * 3));
        NSInteger col = idx % 3;
        
        CGFloat top = topRowTop + (row * (btn.height+verticalButtonPadding));
        CGFloat rowWidth = (btn.width * btnsInRow) + (horizontalButtonPadding * (btnsInRow-1));
        
        CGFloat left = center - (rowWidth/2) + (cellWidth*col);
        [self setUpButton:btn left:left top:top];
    }];
}

- (void)setUpButton:(UIButton *)button left:(CGFloat)left top:(CGFloat)top
{
    button.frame = CGRectMake(left, top, JCPadButtonWidth, JCPadButtonHeight);
    [button addTarget:self action:@selector(didTapButton:) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:button];
    [self setRoundedView:button toDiameter:JCPadButtonHeight];
}

- (void)toggleDeleteButtonVisible:(BOOL)visible animated:(BOOL)animated
{
    if (!self.showDeleteButton && visible)
        return;
    
    if (self.deleteButton.hidden) {
        self.deleteButton.alpha = 0;
        self.deleteButton.hidden = NO;
    } else {
        self.deleteButton.alpha = 1;
    }
    
    __weak JCDialPad *weakSelf = self;
    [self performAnimations:^{
        weakSelf.deleteButton.alpha = visible;
    } animated:animated completion:^(BOOL finished) {
        weakSelf.deleteButton.hidden = !visible;
    }];
}

- (void)performAnimations:(void (^)(void))animations animated:(BOOL)animated completion:(void (^)(BOOL finished))completion
{
    CGFloat length = (animated) ? animationLength : 0.0f;
    
    [UIView animateWithDuration:length delay:0.0f options:UIViewAnimationOptionCurveEaseIn
                     animations:animations
                     completion:completion];
}

#pragma mark -
#pragma mark - Orientation height helpers
- (CGFloat)correctWidth
{
	return self.contentView.bounds.size.width;
}

- (CGFloat)correctHeight
{
    return self.contentView.bounds.size.height;
}

#pragma mark -
#pragma mark -  View Methods

- (void)setRoundedView:(UIView *)roundedView toDiameter:(CGFloat)newSize;
{
    CGRect newFrame = CGRectMake(roundedView.frame.origin.x, roundedView.frame.origin.y, newSize, newSize);
    roundedView.frame = newFrame;
    roundedView.clipsToBounds = YES;
    roundedView.layer.cornerRadius = newSize / 2.0;
}

@end