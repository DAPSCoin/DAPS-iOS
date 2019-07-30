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

#import "BRHomeViewController.h"
#import "BRPeerManager.h"
#import "BRWalletManager.h"
#import "BRRootViewController.h"
#import "pivxwallet-Swift.h"

@interface BRHomeViewController ()
@property (weak, nonatomic) IBOutlet UILabel *lblAvailBalance;
@property (weak, nonatomic) IBOutlet UILabel *lblLastKnownBlock;
@property (weak, nonatomic) IBOutlet UILabel *lblCurrentBlockHeight;

@property (nonatomic, strong) id txStatusObserver;

@end

@implementation BRHomeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self updateData];
    
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (! self.txStatusObserver) {
        self.txStatusObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerTxStatusNotification object:nil
                                                           queue:nil usingBlock:^(NSNotification *note) {
                                                               [self updateData];
                                                           }];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
    self.txStatusObserver = nil;
    
    [super viewWillDisappear:animated];
}

- (void)dealloc
{
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
}

- (IBAction)onSyncAgain:(id)sender {
    [self showAlertOption];
}

-(void)showAlertOption {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rescan blockchain"
                                                                   message:@"The blockchain is going to be reseted.\nThe synchronization could take a while.\nAre you sure?"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *firstAction = [UIAlertAction actionWithTitle:@"cancel"
                                                          style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
                                                              
                                                          }]; // 2
    UIAlertAction *secondAction = [UIAlertAction actionWithTitle:@"ok"
                                                           style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
                                                               [[BRWalletManager sharedInstance].wallet initChain];
                                                               [[BRPeerManager sharedInstance] rescan];
                                                               [((UIPageViewController*)self.parentViewController) setViewControllers:@[SyncController.shared] direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
                                                           }]; // 3
    
    [alert addAction:firstAction]; // 4
    [alert addAction:secondAction]; // 5
    
    [self presentViewController:alert animated:YES completion:nil]; // 6
}

- (void)updateData {
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSMutableAttributedString * attributedBalanceString = [[manager attributedStringForDashAmount:manager.wallet.balance withTintColor:[UIColor whiteColor]] mutableCopy];
    [self.lblAvailBalance setText:attributedBalanceString.string];
    
    NSNumberFormatter *blockNumber = [[NSNumberFormatter alloc] init];
    blockNumber.numberStyle = NSNumberFormatterDecimalStyle;
    blockNumber.groupingSeparator = @" ";
    blockNumber.usesGroupingSeparator = TRUE;

    NSString *blockNumberString = [blockNumber stringFromNumber:(id)[NSDecimalNumber numberWithUnsignedInt:[BRPeerManager sharedInstance].lastBlockHeight]];
    [self.lblLastKnownBlock setText:blockNumberString];
    [self.lblCurrentBlockHeight setText:blockNumberString];
}

@end
