//
//  BRTransaction.h
//  BreadWallet
//
//  Created by Aaron Voisine on 5/16/13.
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
#import "DSShapeshiftEntity+CoreDataClass.h"
#import "IntTypes.h"

#define TX_FEE_PER_KB        10000ULL    // standard tx fee per kb of tx size, rounded up to nearest kb
#define TX_FEE_PER_INPUT     10000ULL    // standard ix fee per input
#define TX_OUTPUT_SIZE       34          // estimated size for a typical transaction output
#define TX_INPUT_SIZE        148         // estimated size for a typical compact pubkey transaction input
#define TX_MIN_OUTPUT_AMOUNT (TX_FEE_PER_KB*3*(TX_OUTPUT_SIZE + TX_INPUT_SIZE)/1000) //no txout can be below this amount
#define TX_MAX_SIZE          100000      // no tx can be larger than this size in bytes
#define TX_FREE_MAX_SIZE     1000        // tx must not be larger than this size in bytes without a fee
#define TX_FREE_MIN_PRIORITY 57600000ULL // tx must not have a priority below this value without a fee
#define TX_UNCONFIRMED       INT32_MAX   // block height indicating transaction is unconfirmed
#define TX_MAX_LOCK_HEIGHT   500000000   // a lockTime below this value is a block height, otherwise a timestamp

#define IX_PREVIOUS_CONFIRMATIONS_NEEDED       6   // number of previous confirmations needed in ix inputs

@class BRKey;

typedef struct _BRUTXO {
    UInt256 hash;
    unsigned long n; // use unsigned long instead of uint32_t to avoid trailing struct padding (for NSValue comparisons)
} BRUTXO;

typedef struct _BRTxOut {
    uint64_t nValue; //should always be 0
    NSMutableData *scriptPubKey;
    int nRounds;
    //txPriv is optional and will be used for PoS blocks to incentivize masternodes
    //and fullnodes will use it to verify whether the reward is really sent to the registered address of masternodes
    NSMutableData *txPriv;
    NSMutableData *txPub;
    //ECDH encoded value for the amount: the idea is the use the shared secret and a key derivation function to
    //encode the value and the mask so that only the sender and the receiver of the tx output can decode the encoded amount
    UInt256 mask_amount;
    UInt256 mask_mask;   //blinding factor, this is encoded throug ECDH before sending to the receiver
    UInt256 mask_hashOfKey;
    BRKey *mask_inMemoryRawBind;
    NSMutableData *masternodeStealthAddress;  //will be clone from the tx having 1000000 daps output
    NSMutableData *commitment;  //Commitment C = mask * G + amount * H, H = Hp(G), Hp = toHashPoint
} BRTxOut;

void initTxOut(BRTxOut *txout);
int getSerializeSize(BRTxOut *txout);

#define brutxo_obj(o) [NSValue value:&(o) withObjCType:@encode(BRUTXO)]
#define brutxo_data(o) [NSData dataWithBytes:&((struct { uint32_t u[256/32 + 1]; }) {\
o.hash.u32[0], o.hash.u32[1], o.hash.u32[2], o.hash.u32[3],\
o.hash.u32[4], o.hash.u32[5], o.hash.u32[6], o.hash.u32[7],\
CFSwapInt32HostToLittle((uint32_t)o.n) }) length:sizeof(UInt256) + sizeof(uint32_t)]


enum {
    TX_TYPE_FULL  =  0, //used for any normal transaction
                        //transaction with no hidden amount (used for collateral transaction, rewarding transaction
                        // (for masternode and staking node), and PoA mining rew)
    TX_TYPE_REVEAL_AMOUNT,
    TX_TYPE_REVEAL_SENDER,    //transaction with no ring signature (used for decollateral transaction + reward transaction
    TX_TYPE_REVEAL_BOTH         //this is a staking transaction that consumes a staking coin and rewards the staking node and masternode
};

@interface BRTransaction : NSObject

@property (nonatomic, readonly) NSArray *inputAddresses;
@property (nonatomic, readonly) NSMutableArray *inputHashes;
@property (nonatomic, readonly) NSMutableArray *inputIndexes;
@property (nonatomic, readonly) NSArray *inputScripts;
@property (nonatomic, readonly) NSMutableArray *inputSignatures;
@property (nonatomic, readonly) NSMutableArray *inputSequences;
@property (nonatomic, readonly) NSArray *inputEncryptionKey;
@property (nonatomic, readonly) NSMutableArray *inputKeyImage;
@property (nonatomic, readonly) NSMutableArray *inputDecoys;
@property (nonatomic, readonly) NSArray *inputMasternodeStealthAddress;
@property (nonatomic, readonly) NSArray *inputS;
@property (nonatomic, readonly) NSArray *inputR;

@property (nonatomic, readonly) NSMutableArray *outputAmounts;
@property (nonatomic, readonly) NSArray *outputAddresses;
@property (nonatomic, readonly) NSArray *outputScripts;
@property (nonatomic, readonly) NSArray *outputTxPriv;
@property (nonatomic, readonly) NSArray *outputTxPub;
@property (nonatomic, readonly) NSArray *outputMaskValue;
@property (nonatomic, readonly) NSMutableArray *outputInMemoryRawBind;
@property (nonatomic, readonly) NSArray *outputMasternodeStealthAddress;
@property (nonatomic, readonly) NSMutableArray *outputCommitment;

@property (nonatomic, assign) BOOL isInstant;
@property (nonatomic, assign) BOOL fFromMe;
@property (nonatomic, assign) BOOL isForMe;

@property (nonatomic, assign) UInt256 txHash;
@property (nonatomic, assign) uint32_t version;

@property (nonatomic, assign) uint8_t hasPaymentID;
@property (nonatomic, assign) uint64_t paymentID;
@property (nonatomic, assign) uint32_t txType;
@property (nonatomic, strong) NSMutableData *bulletProofs;
@property (nonatomic, assign) uint64_t nTxFee;
@property (nonatomic, assign) UInt256 c;
@property (nonatomic, strong) NSMutableArray *S;
@property (nonatomic, strong) NSMutableData *ntxFeeKeyImage;
@property (nonatomic, strong) BRKey *txPrivM;

@property (nonatomic, assign) BOOL fTimeReceivedIsTxTime;

@property (nonatomic, assign) uint32_t lockTime;
@property (nonatomic, assign) uint32_t blockHeight;
@property (nonatomic, assign) UInt256 txSignatureHash;
@property (nonatomic, assign) NSTimeInterval timestamp; // time interval since refrence date, 00:00:00 01/01/01 GMT
@property (nonatomic, readonly) size_t size; // size in bytes if signed, or estimated size assuming compact pubkey sigs
@property (nonatomic, readonly) uint64_t standardFee;
@property (nonatomic, readonly) BOOL isSigned; // checks if all signatures exist, but does not verify them
@property (nonatomic, readonly, getter = toData) NSData *data;

@property (nonatomic, readonly) NSString *longDescription;


@property (nonatomic, strong) DSShapeshiftEntity * associatedShapeshift;

+ (instancetype)transactionWithMessage:(NSData *)message;

- (instancetype)initWithMessage:(NSData *)message;
- (instancetype)initWithInputHashes:(NSArray *)hashes inputIndexes:(NSArray *)indexes inputScripts:(NSArray *)scripts
outputAddresses:(NSArray *)addresses outputAmounts:(NSArray *)amounts;

- (void)addInputHash:(UInt256)hash index:(NSUInteger)index script:(NSData *)script;
- (void)addInputHash:(UInt256)hash index:(NSUInteger)index script:(NSData *)script signature:(NSData *)signature
sequence:(uint32_t)sequence;
- (void)addOutputAddress:(NSString *)address amount:(uint64_t)amount;
- (void)addOutputShapeshiftAddress:(NSString *)address;
- (void)addOutputScript:(NSData *)script amount:(uint64_t)amount;
- (void)setInputAddress:(NSString *)address atIndex:(NSUInteger)index;
- (void)shuffleOutputOrder;
- (BOOL)signWithPrivateKeys:(NSArray *)privateKeys;
- (BOOL)isCoinBase;
- (BOOL)isCoinStake;
- (BOOL)isCoinAudit;
- (void)inputInit;
- (void)outputInit;
- (void)addOutput:(BRTxOut *)txout;

- (NSString*)shapeshiftOutboundAddress;
- (NSString*)shapeshiftOutboundAddressForceScript;
+ (NSString*)shapeshiftOutboundAddressForScript:(NSData*)script;

// priority = sum(input_amount_in_satoshis*input_age_in_blocks)/tx_size_in_bytes
- (uint64_t)priorityForAmounts:(NSArray *)amounts withAges:(NSArray *)ages;

// the block height after which the transaction can be confirmed without a fee, or TX_UNCONFIRMED for never
- (uint32_t)blockHeightUntilFreeForAmounts:(NSArray *)amounts withBlockHeights:(NSArray *)heights;

@end
