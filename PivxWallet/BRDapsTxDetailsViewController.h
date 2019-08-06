//
//  BRDapsTxDetailsViewController.h

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface BRDapsTxDetailsViewController : UIViewController
@property (strong, nonatomic) NSString *strDestAddress;
@property (strong, nonatomic) NSString *strAmount;
@property (strong, nonatomic) NSString *strFee;
@property (strong, nonatomic) NSString *strBalance;
@property (strong, nonatomic) NSString *strStealthAddress;
@property (strong, nonatomic) NSString *strTransactionID;
@property (strong, nonatomic) NSString *strDate;
@property (strong, nonatomic) NSString *strTime;
@end
