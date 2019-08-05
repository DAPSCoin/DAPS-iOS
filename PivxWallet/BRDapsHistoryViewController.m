//
//  BRDapsHistoryViewController.m
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

#import "BRDapsHistoryViewController.h"
#import "BRPeerManager.h"
#import "BRWalletManager.h"
#import "BRTransaction.h"
#import "pivxwallet-Swift.h"

@interface BRDapsHistoryViewController ()

@end

@implementation BRDapsHistoryViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    self.navigationItem.title = @"Transaction History";
    
    [self addMenuButton];
    [[self.navigationController navigationBar] setTranslucent:FALSE];
    [[self.navigationController navigationBar] setShadowImage:[UIImage imageNamed:@""]];
    [[self.navigationController navigationBar] setBackgroundImage:[UIImage imageNamed:@""] forBarMetrics: UIBarMetricsDefault];
    
    UIImageView *tempImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"background"]];
    [tempImageView setFrame:self.tableView.frame];
    self.tableView.backgroundView = tempImageView;
    
//    UIView *v = [[[NSBundle mainBundle] loadNibNamed:@"SearchDialog" owner:self options:nil] lastObject];
//    [v setFrame:CGRectMake(0, 0, self.tableView.frame.size.width, self.tableView.frame.size.height)];
//    [self.navigationController.view addSubview:v];
}

- (void)viewLayoutMarginsDidChange {
    [super viewLayoutMarginsDidChange];
    
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
}

- (void)dealloc
{
    
}

-(void)addMenuButton {
    UIImage *image = [UIImage imageNamed:@"burger"];
    self.navigationItem.hidesBackButton = TRUE;
    UIBarButtonItem *menuButton = [[UIBarButtonItem alloc] initWithImage:image
                                                                   style:UIBarButtonItemStylePlain target:self action:@selector(tappedMenuButton)];
    [menuButton setTintColor: UIColor.whiteColor];
    self.navigationItem.leftBarButtonItem = menuButton;
}

-(void)tappedMenuButton{
    [Utils openLeftMenu];
}

- (NSString *)dateForTx:(BRTransaction *)tx
{
    NSDateFormatter *yearMonthDay = [NSDateFormatter new];
    yearMonthDay.dateFormat = @"dd/MM/yyyy";
    
    NSTimeInterval now = [[BRPeerManager sharedInstance] timestampForBlockHeight:TX_UNCONFIRMED];
    
    NSTimeInterval txTime = (tx.timestamp > 1) ? tx.timestamp : now;
    
    return [yearMonthDay stringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:txTime]];
}

- (NSString *)timeForTx:(BRTransaction *)tx
{
    NSDateFormatter *timeFormat = [NSDateFormatter new];
    timeFormat.dateFormat = @"hh:mm:ss";
    
    NSTimeInterval now = [[BRPeerManager sharedInstance] timestampForBlockHeight:TX_UNCONFIRMED];
    NSTimeInterval txTime = (tx.timestamp > 1) ? tx.timestamp : now;
    
    return [timeFormat stringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:txTime]];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    return manager.wallet.allTransactions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UILabel *descritionLable, *balanceLabel, *dateLabel, *timeLabel;
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HistoryCell" forIndexPath:indexPath];
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    
    descritionLable = (UILabel*)[cell viewWithTag:1];
    balanceLabel = (UILabel*)[cell viewWithTag:2];
    dateLabel = (UILabel*)[cell viewWithTag:3];
    timeLabel = (UILabel*)[cell viewWithTag:4];
    
    BRTransaction *tx = manager.wallet.allTransactions[indexPath.row];
    uint64_t received = [manager.wallet amountReceivedFromTransaction:tx],
    sent = [manager.wallet amountSentByTransaction:tx],
    balance = [manager.wallet balanceAfterTransaction:tx];
    
    NSString *balanceString = @"";
    int64_t diff = received - sent;
    if (diff > 0) {
        balanceString = [balanceString stringByAppendingString:@"+ "];
        balanceLabel.textColor = [UIColor rgb:150 green:255 blue:131 alpha:255];
    }
    else {
        balanceString = [balanceString stringByAppendingString:@"- "];
        balanceLabel.textColor = [UIColor rgb:147 green:103 blue:144 alpha:255];
        diff *= -1;
    }
    
    balanceLabel.text = [balanceString stringByAppendingString:[manager attributedStringForDashAmount:diff withTintColor:[UIColor whiteColor]].string];
    dateLabel.text = [self dateForTx:tx];
    timeLabel.text = [self timeForTx:tx];
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 20.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width,
                                                         [self tableView:tableView heightForHeaderInSection:section])];
    v.backgroundColor = [UIColor clearColor];
    
    return v;
}

@end
