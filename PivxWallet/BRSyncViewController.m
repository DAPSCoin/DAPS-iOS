//
//  BRHomeViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 5/8/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "BRSyncViewController.h"
#import "BRPeerManager.h"
#import "BRWalletManager.h"

@interface BRSyncViewController ()
@property (weak, nonatomic) IBOutlet UILabel *lblAvailBalance;
@property (weak, nonatomic) IBOutlet UILabel *lblPendingBalance;
@property (weak, nonatomic) IBOutlet UILabel *lblBlockRemaining;

@property (nonatomic, strong) id syncFinishedObserver;
@property (nonatomic, strong) id syncFailedObserver;
@end

@implementation BRSyncViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (self.syncFinishedObserver == nil){
        self.syncFinishedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncFinishedNotification object:nil
                                                           queue:nil usingBlock:^(NSNotification *note) {
                                                               [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateData) object:nil];
                                                           }];
    }
    if (self.syncFailedObserver == nil){
        self.syncFailedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncFailedNotification object:nil
                                                           queue:nil usingBlock:^(NSNotification *note) {
                                                               [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateData) object:nil];
                                                           }];
    }
    
    [self updateData];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (self.syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];
    self.syncFailedObserver = nil;
    if (self.syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
    self.syncFinishedObserver = nil;
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateData) object:nil];
    
    [super viewWillDisappear:animated];
}

- (void)dealloc
{
    if (self.syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
    if (self.syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateData) object:nil];
}


- (void)updateData {
//    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateData) object:nil];
    
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSMutableAttributedString * attributedBalanceString = [[manager attributedStringForDashAmount:manager.wallet.balance withTintColor:[UIColor whiteColor]] mutableCopy];
    [self.lblAvailBalance setText:attributedBalanceString.string];
    [self.lblPendingBalance setText:attributedBalanceString.string];
    
    NSString *remainingString = [NSString stringWithFormat:@"%d of %d", [BRPeerManager sharedInstance].lastBlockHeight, [BRPeerManager sharedInstance].estimatedBlockHeight];
    [self.lblBlockRemaining setText:remainingString];
    
    [self performSelector:@selector(updateData) withObject:nil afterDelay:2.0f];
}

@end
