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

#define kBasicPhoneBaseURL @"http://localhost"
#define kLoginEndpoint @"token"

@interface PKTViewController ()

@property (nonatomic, weak)   UIButton *callButton;
@property (nonatomic, strong) PKTCallViewController *callViewController;

@end

@implementation PKTViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    self.callButton.enabled = NO;
    
    NSURL *baseURL = [NSURL URLWithString:kBasicPhoneBaseURL];
    AFHTTPRequestOperationManager *manager = [[AFHTTPRequestOperationManager alloc] initWithBaseURL:baseURL];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    manager.responseSerializer.acceptableContentTypes =
        [manager.responseSerializer.acceptableContentTypes setByAddingObject:@"text/html"];
    
//    [manager setCredential:[NSURLCredential credentialWithUser:@"" password:@"" persistence:NSURLCredentialPersistenceForSession]];
    
    [manager GET:kLoginEndpoint parameters:@{}
    success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSString *token = [[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
        [self setupPhoneKitWithToken:token];
        self.callButton.enabled = YES;
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

- (IBAction)didTapCall:(id)sender
{
    [[PKTPhone sharedPhone] call];
}

@end
