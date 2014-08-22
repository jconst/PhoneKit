//
//  PKTViewController.m
//  PhoneKit
//
//  Created by Joseph Constantakis on 07/08/2014.
//  Copyright (c) 2014 Joseph Constantakis. All rights reserved.
//

#import "PKTViewController.h"
#import "UIView+FrameAccessor.h"
#import "AFNetworking.h"
#import "PKTPhone.h"
#import "PKTCallViewController.h"

#warning replace with the URL of your server
#define kBasicPhoneBaseURL @"https://tcs.ngrok.com"
#define kLoginEndpoint @"auth.php"

@interface PKTViewController ()

@property (strong, nonatomic) PKTCallViewController *callViewController;

@end

@implementation PKTViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.

    NSURL *baseURL = [NSURL URLWithString:kBasicPhoneBaseURL];
    AFHTTPRequestOperationManager *manager = [[AFHTTPRequestOperationManager alloc] initWithBaseURL:baseURL];
    
    [manager GET:kLoginEndpoint parameters:@{@"clientName": @"demo"}
    success:^(AFHTTPRequestOperation *operation, id responseObject) {
        [self setupPhoneKitWithToken:responseObject[@"token"]];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"error: %@", error);
    }];
}

- (void)setupPhoneKitWithToken:(NSString *)token
{
    [PKTPhone sharedPhone].capabilityToken = token;
    self.callViewController = [PKTCallViewController new];
    self.callViewController.mainText = @"Support";
    [PKTPhone sharedPhone].delegate = self.callViewController;
}

- (void)didTapCall:(id)sender
{
#warning replace with a verified phone number, or another client name
    [[PKTPhone sharedPhone] call:@""];
}

@end