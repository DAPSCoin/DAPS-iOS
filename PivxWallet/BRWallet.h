//
//  BRWallet.h
//  BreadWallet
//
//  Created by Aaron Voisine on 5/12/13.
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

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "BRTransaction.h"
#import "BRKeySequence.h"
#import "NSData+Bitcoin.h"

typedef struct _BRCoinControl {
    UInt160 destChange;
    NSData *receiver;
    BRKey *txPriv;  //for change UTXO
} BRCoinControl;

typedef enum _AvailableCoinsType {
    ALL_COINS = 1,
    ONLY_DENOMINATED = 2,
    ONLY_NOT1000000IFMN = 3,
    ONLY_NONDENOMINATED_NOT1000000IFMN = 4, // ONLY_NONDENOMINATED and not 1000000 DAPS at the same time
    ONLY_1000000 = 5,                        // find masternode outputs including locked ones (use with caution)
    STAKABLE_COINS = 6                          // UTXO's that are valid for staking
} AvailableCoinsType;

FOUNDATION_EXPORT NSString* _Nonnull const BRWalletBalanceChangedNotification;

#define DUFFS           100000000LL
#define COIN DUFFS
#define CENT 1000000LL
#define MAX_MONEY          (21000000LL*DUFFS) // TODO: Infinite in PIVX.. check this.
#define DEFAULT_FEE_PER_KB (0.1 * COIN)
//#define MIN_FEE_PER_KB     ((TX_FEE_PER_KB*1000 + 190)/191) // minimum relay fee on a 191byte tx
#define MAX_FEE_PER_KB     (1 * COIN)

#define MAX_DECOYS_POOL 300
#define MAX_BLOCK_COUNT 500
#define PROBABILITY_NEW_COIN_SELECTED 70
#define COINBASE_MATURITY 100

typedef void (^TransactionValidityCompletionBlock)(BOOL signedTransaction);
typedef void (^SeedCompletionBlock)(NSData * _Nullable seed);
typedef void (^SeedRequestBlock)(NSString * _Nullable authprompt, uint64_t amount, _Nullable SeedCompletionBlock seedCompletion);

@class BRTransaction;
@class BRKey;
@class BRMerkleBlock;
@protocol BRKeySequence;

@interface BRWallet : NSObject

// current wallet balance excluding transactions known to be invalid
@property (nonatomic, readonly) uint64_t balance;

// returns the first unused external address
@property (nonatomic, readonly) NSString * _Nullable receiveAddress;

// returns stealth address
@property (nonatomic, readonly) NSString * _Nullable receiveStealthAddress;

// returns the first unused internal address
@property (nonatomic, readonly) NSString * _Nullable changeAddress;

// all previously generated external addresses
@property (nonatomic, readonly) NSSet * _Nonnull allReceiveAddresses;

// all previously generated internal addresses
@property (nonatomic, readonly) NSSet * _Nonnull allChangeAddresses;

// NSValue objects containing UTXO structs
@property (nonatomic, readonly) NSArray * _Nonnull unspentOutputs;

@property (nonatomic, strong) NSMutableDictionary * _Nonnull spentOutputKeyImage;
@property (nonatomic, strong) NSMutableDictionary * _Nonnull spentBalance;
@property (nonatomic, strong) NSMutableDictionary * _Nonnull inSpendOutput;

// amount reveal value
@property (nonatomic, readonly) NSDictionary * _Nonnull amountMap;

// key value
@property (nonatomic, readonly) NSDictionary * _Nonnull blindMap;

// latest 100 transactions sorted by date, most recent first
@property (nonatomic, readonly) NSArray * _Nonnull recentTransactions;

// all wallet transactions sorted by date, most recent first
@property (nonatomic, readonly) NSArray * _Nonnull allTransactions;

// the total amount spent from the wallet (excluding change)
@property (nonatomic, readonly) uint64_t totalSent;

// the total amount received by the wallet (excluding change)
@property (nonatomic, readonly) uint64_t totalReceived;

// fee per kb of transaction size to use when including tx fee
@property (nonatomic, assign) uint64_t feePerKb;

// outputs below this amount are uneconomical due to fees
@property (nonatomic, readonly) uint64_t minOutputAmount;

@property (nonatomic, strong) NSMutableArray *txPrivKeys;

// largest amount that can be sent from the wallet after fees
- (uint64_t)maxOutputAmountUsingInstantSend:(BOOL)instantSend;

- (uint64_t)maxOutputAmountWithConfirmationCount:(uint64_t)confirmationCount usingInstantSend:(BOOL)instantSend;

- (instancetype _Nullable)initWithContext:(NSManagedObjectContext * _Nullable)context
                                 sequence:(id<BRKeySequence> _Nonnull)sequence
                          masterBIP44PublicKey:(NSData * _Nonnull)masterPublicKey
                            masterBIP32PublicKey:(NSData * _Nonnull)masterBIP32PublicKey
                            requestSeedBlock:(_Nullable SeedRequestBlock)seed;

-(NSUInteger)addressPurpose:(NSString * _Nonnull)address;

// true if the address is controlled by the wallet
- (BOOL)containsAddress:(NSString * _Nonnull)address;

// true if the address was previously used as an input or output in any wallet transaction
- (BOOL)addressIsUsed:(NSString * _Nonnull)address;

- (uint32_t)blockHeight;

// Wallets are composed of chains of addresses. Each chain is traversed until a gap of a certain number of addresses is
// found that haven't been used in any transactions. This method returns an array of <gapLimit> unused addresses
// following the last used address in the chain. The internal chain is used for change addresses and the external chain
// for receive addresses.  These have a hardened purpose scheme of 44 as compliant with BIP 43 and 44
- (NSArray * _Nullable)addressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal;

// For the sake of backwards compatibility we need to register addresses that aren't compliant with BIP 43 and 44.
- (NSArray * _Nullable)addressesBIP32NoPurposeWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal;

// returns an unsigned transaction that sends the specified amount from the wallet to the given address
- (BRTransaction * _Nullable)transactionFor:(uint64_t)amount to:(NSString * _Nonnull)address withFee:(BOOL)fee;

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (BRTransaction * _Nullable)transactionForAmounts:(NSArray * _Nonnull)amounts
                                   toOutputScripts:(NSArray * _Nonnull)scripts withFee:(BOOL)fee;

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (BRTransaction * _Nullable)transactionForAmounts:(NSArray * _Nonnull)amounts toOutputScripts:(NSArray * _Nonnull)scripts withFee:(BOOL)fee  isInstant:(BOOL)isInstant;

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (BRTransaction * _Nullable)transactionForAmounts:(NSArray * _Nonnull)amounts toOutputScripts:(NSArray * _Nonnull)scripts withFee:(BOOL)fee isInstant:(BOOL)isInstant toShapeshiftAddress:(NSString* _Nullable)shapeshiftAddress;

// sign any inputs in the given transaction that can be signed using private keys from the wallet
- (void)signTransaction:(BRTransaction * _Nonnull)transaction withPrompt:(NSString * _Nonnull)authprompt completion:(_Nonnull TransactionValidityCompletionBlock)completion;
- (void)signBIP32Transaction:(BRTransaction * _Nonnull)transaction withPrompt:(NSString * _Nonnull)authprompt completion:(_Nonnull TransactionValidityCompletionBlock)completion;

// true if the given transaction is associated with the wallet (even if it hasn't been registered), false otherwise
- (BOOL)containsTransaction:(BRTransaction * _Nonnull)transaction;

// adds a transaction to the wallet, or returns false if it isn't associated with the wallet
- (BOOL)registerTransaction:(BRTransaction * _Nonnull)transaction;

- (void)initChain;

// removes a transaction from the wallet along with any transactions that depend on its outputs
- (void)removeTransaction:(UInt256)txHash;

// returns the transaction with the given hash if it's been registered in the wallet (might also return non-registered)
- (BRTransaction * _Nullable)transactionForHash:(UInt256)txHash;

// true if no previous wallet transaction spends any of the given transaction's inputs, and no inputs are invalid
- (BOOL)transactionIsValid:(BRTransaction * _Nonnull)transaction;

- (bool)updateDecoys:(uint32_t)height;
- (bool)verifyRingCT:(BRTransaction *)wtxNew;

// true if the transaction is to me
- (NSString *)getTransactionDestAddress:(BRTransaction *)transaction;
- (uint64_t)spentAmountByTransaction:(BRTransaction *)tx;
- (BOOL)IsTransactionForMe:(BRTransaction * _Nonnull)transaction;
- (BOOL)RevealTxOutAmount:(BRTransaction * _Nonnull)transaction :(NSUInteger)outIndex :(UInt64 *_Nullable)amount :(BRKey ** _Nonnull)blind;
- (BOOL)ComputeSharedSec:(BRTransaction * _Nonnull)transaction :(NSMutableData*)outTxPub :(NSMutableData ** _Nonnull)sharedSec;
- (void)ECDHInfo_Decode:(unsigned char* _Nonnull)encodedMask :(unsigned char* _Nonnull)encodedAmount :(NSData * _Nonnull)sharedSec :(UInt256 * _Nonnull)decodedMask :(UInt64 * _Nonnull)decodedAmount;
- (void)ECDHInfo_ComputeSharedSec:(const UInt256* _Nonnull)priv :(NSData* _Nonnull)pubKey :(NSMutableData** _Nonnull)sharedSec;
- (void)ecdhDecode:(unsigned char * _Nonnull)masked :(unsigned char * _Nonnull)amount :(NSData * _Nonnull)sharedSec;

- (bool)makeRingCT:(BRTransaction *_Nonnull)wtxNew :(int)ringSize;
- (bool)selectDecoysAndRealIndex: (BRTransaction *_Nonnull)tx :(int *_Nonnull)myIndex :(int)ringSize;
- (bool)SendToStealthAddress:(NSString*)stealthAddr :(uint64_t)nValue :(BRTransaction*)wtxNew :(bool)fUseIX :(int)ringSize;

- (bool)IsProofOfStake:(BRMerkleBlock *_Nonnull)block;
- (bool)IsProofOfWork:(BRMerkleBlock *_Nonnull)block;
- (bool)IsProofOfAudit:(BRMerkleBlock *_Nonnull)block;

// true if transaction cannot be immediately spent (i.e. if it or an input tx can be replaced-by-fee, via BIP125)
- (BOOL)transactionIsPending:(BRTransaction * _Nonnull)transaction;

// true if tx is considered 0-conf safe (valid and not pending, timestamp is greater than 0, and no unverified inputs)
- (BOOL)transactionIsVerified:(BRTransaction * _Nonnull)transaction;

// sets the block heights and timestamps for the given transactions, and returns an array of hashes of the updated tx
// use a height of TX_UNCONFIRMED and timestamp of 0 to indicate a transaction and it's dependents should remain marked
// as unverified (not 0-conf safe)
- (NSArray * _Nonnull)setBlockHeight:(int32_t)height andTimestamp:(NSTimeInterval)timestamp
                         forTxHashes:(NSArray * _Nonnull)txHashes;

// returns the amount received by the wallet from the transaction (total outputs to change and/or receive addresses)
- (uint64_t)amountReceivedFromTransaction:(BRTransaction * _Nonnull)transaction;

// retuns the amount sent from the wallet by the trasaction (total wallet outputs consumed, change and fee included)
- (uint64_t)amountSentByTransaction:(BRTransaction * _Nonnull)transaction;

// returns the fee for the given transaction if all its inputs are from wallet transactions, UINT64_MAX otherwise
- (uint64_t)feeForTransaction:(BRTransaction * _Nonnull)transaction;

// historical wallet balance after the given transaction, or current balance if transaction is not registered in wallet
- (uint64_t)balanceAfterTransaction:(BRTransaction * _Nonnull)transaction;

// returns the block height after which the transaction is likely to be processed without including a fee
- (uint32_t)blockHeightUntilFree:(BRTransaction * _Nonnull)transaction;

// fee that will be added for a transaction of the given size in bytes
- (uint64_t)feeForTxSize:(NSUInteger)size isInstant:(BOOL)isInstant inputCount:(NSInteger)inputCount;

@end
