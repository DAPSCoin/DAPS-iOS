//
//  BRTransaction.m
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

#import "BRTransaction.h"
#import "BRKey.h"
#import "NSString+Dash.h"
#import "NSData+Dash.h"
#import "NSString+Bitcoin.h"
#import "NSMutableData+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import "BRAddressEntity.h"
#import "NSManagedObject+Sugar.h"

#define TX_VERSION    0x00000001u
#define TX_LOCKTIME   0x00000000u
#define TXIN_SEQUENCE UINT32_MAX
#define SIGHASH_ALL   0x00000001u

@interface BRTransaction ()

//vin
@property (nonatomic, strong) NSMutableArray *hashes, *indexes, *inScripts, *signatures, *sequences;    //hashes,indexes->prevout, signatures->scriptSig
@property (nonatomic, strong) NSMutableArray *in_encryptionKey, *in_keyImage, *in_decoys, *in_masternodeStealthAddress, *in_s, *in_R;
//vout
@property (nonatomic, strong) NSMutableArray *amounts, *addresses, *outScripts;     //outScripts->scriptPubKey, address->converted string from scriptPubKey
@property (nonatomic, strong) NSMutableArray *out_txPriv, *out_txPub, *out_maskValue, *out_masternodeStealthAddress, *out_commitment, *out_InMemoryRawBind;

@end

void initTxOut(BRTxOut *txout) {
    txout->nValue = 0;
    txout->scriptPubKey = [NSMutableData data];
    txout->nRounds = 0;
    txout->txPriv = [NSMutableData data];
    txout->txPub = [NSMutableData data];
    memset(&txout->mask_amount, 0, sizeof(UInt256));
    memset(&txout->mask_mask, 0, sizeof(UInt256));
    memset(&txout->mask_hashOfKey, 0, sizeof(UInt256));
    txout->mask_inMemoryRawBind = [BRKey keyWithRandSecret:YES];
    txout->masternodeStealthAddress = [NSMutableData data];
    txout->commitment = [NSMutableData data];
}

int getSerializeSize(BRTxOut *txout) {
    int size = 0;
    size += sizeof(txout->nValue);
    size += txout->scriptPubKey.length;
    size += txout->txPriv.length;
    size += txout->txPub.length;
    size += sizeof(UInt256);
    size += sizeof(UInt256);
    size += sizeof(UInt256);
    size += txout->masternodeStealthAddress.length;
    size += txout->commitment.length;
    
    return size;
}

@implementation BRTransaction

+ (instancetype)transactionWithMessage:(NSData *)message
{
    return [[self alloc] initWithMessage:message];
}

- (instancetype)init
{
    if (! (self = [super init])) return nil;
    
    _version = TX_VERSION;
    
    //vin
    self.hashes = [NSMutableArray array];
    self.indexes = [NSMutableArray array];
    self.inScripts = [NSMutableArray array];
    self.signatures = [NSMutableArray array];
    self.sequences = [NSMutableArray array];
    self.in_encryptionKey = [NSMutableArray array];
    self.in_keyImage = [NSMutableArray array];
    self.in_decoys = [NSMutableArray array];
    self.in_masternodeStealthAddress = [NSMutableArray array];
    self.in_s = [NSMutableArray array];
    self.in_R = [NSMutableArray array];
    
    //vout
    self.amounts = [NSMutableArray array];
    self.addresses = [NSMutableArray array];
    self.outScripts = [NSMutableArray array];
    self.out_txPriv = [NSMutableArray array];
    self.out_txPub = [NSMutableArray array];
    self.out_maskValue = [NSMutableArray array];
    self.out_masternodeStealthAddress = [NSMutableArray array];
    self.out_commitment = [NSMutableArray array];
    self.out_InMemoryRawBind = [NSMutableArray array];
    
    self.S = [NSMutableArray array];
    _lockTime = TX_LOCKTIME;
    _blockHeight = TX_UNCONFIRMED;
    return self;
}

- (instancetype)initWithMessage:(NSData *)message
{
    if (! (self = [self init])) return nil;
 
    NSString *address = nil;
    NSNumber * l = 0;
    NSUInteger off = 0, count = 0;
    NSData *d = nil;

    @autoreleasepool {
        _version = [message UInt32AtOffset:off]; // tx version
        off += sizeof(uint32_t);
        count = (NSUInteger)[message varIntAtOffset:off length:&l]; // input count
        if (count == 0) return nil; // at least one input is required
        off += l.unsignedIntegerValue;

        for (NSUInteger i = 0; i < count; i++) { // inputs
            [self.hashes addObject:uint256_obj([message hashAtOffset:off])];
            off += sizeof(UInt256);
            [self.indexes addObject:@([message UInt32AtOffset:off])]; // input index
            off += sizeof(uint32_t);
            [self.inScripts addObject:[NSNull null]]; // placeholder for input script (comes from input transaction)
            d = [message dataAtOffset:off length:&l];
            [self.signatures addObject:(d.length > 0) ? d : [NSNull null]]; // input signature
            off += l.unsignedIntegerValue;
            [self.sequences addObject:@([message UInt32AtOffset:off])]; // input sequence number (for replacement tx)
            off += sizeof(uint32_t);
            d = [message dataAtOffset:off length:&l];
            [self.in_encryptionKey addObject:(d.length > 0) ? d : [NSNull null]]; // input encryptionKey
            off += l.unsignedIntegerValue;
            d = [message dataAtOffset:off length:&l];
            [self.in_keyImage addObject:(d.length > 0) ? d : [NSNull null]]; // input keyImage
            off += l.unsignedIntegerValue;
            NSUInteger decoy_count = (NSUInteger)[message varIntAtOffset:off length:&l]; // decoys count
            off += l.unsignedIntegerValue;
            NSMutableArray *decoy = [NSMutableArray array];
            for (NSUInteger j = 0; j < decoy_count; j++) {  //decoys
                BRUTXO o;
                o.hash = [message hashAtOffset:off];
                off += sizeof(UInt256);
                o.n = [message UInt32AtOffset:off];
                off += sizeof(uint32_t);
                [decoy addObject:brutxo_obj(o)];
            }
            [self.in_decoys addObject:decoy];
            d = [message dataAtOffset:off length:&l];
            [self.in_masternodeStealthAddress addObject:(d.length > 0) ? d : [NSNull null]]; // input masternodestealthAddress
            off += l.unsignedIntegerValue;
            d = [message dataAtOffset:off length:&l];
            [self.in_s addObject:(d.length > 0) ? d : [NSNull null]]; // input s
            off += l.unsignedIntegerValue;
            d = [message dataAtOffset:off length:&l];
            [self.in_R addObject:(d.length > 0) ? d : [NSNull null]]; // input R
            off += l.unsignedIntegerValue;
        }

        count = (NSUInteger)[message varIntAtOffset:off length:&l]; // output count
        off += l.unsignedIntegerValue;

        for (NSUInteger i = 0; i < count; i++) { // outputs
            [self.amounts addObject:@([message UInt64AtOffset:off])]; // output amount
            off += sizeof(uint64_t);
            d = [message dataAtOffset:off length:&l];
            [self.outScripts addObject:(d) ? d : [NSNull null]]; // output script
            off += l.unsignedIntegerValue;
            address = [NSString addressWithScriptPubKey:d]; // address from output script if applicable
            [self.addresses addObject:(address) ? address : [NSNull null]];
            d = [message dataAtOffset:off length:&l];
            [self.out_txPriv addObject:(d) ? d : [NSNull null]]; // output txPriv
            off += l.unsignedIntegerValue;
            d = [message dataAtOffset:off length:&l];
            [self.out_txPub addObject:(d) ? d : [NSNull null]]; // output txPub
            off += l.unsignedIntegerValue;
            
            NSMutableArray *mask = [NSMutableArray array];      //output maskValue
            [mask addObject:uint256_obj([message hashAtOffset:off])];   //maskValue->amount
            off += sizeof(UInt256);
            [mask addObject:uint256_obj([message hashAtOffset:off])];   //maskValue->mask
            off += sizeof(UInt256);
            [mask addObject:uint256_obj([message hashAtOffset:off])];   //maskValue->hashOfKey
            off += sizeof(UInt256);
            [self.out_maskValue addObject:mask];
            d = [message dataAtOffset:off length:&l];
            [self.out_masternodeStealthAddress addObject:(d.length > 0) ? d : [NSNull null]]; // output masternodestealthAddress
            off += l.unsignedIntegerValue;
            d = [message dataAtOffset:off length:&l];
            [self.out_commitment addObject:(d.length > 0) ? d : [NSNull null]]; // output commitment
            off += l.unsignedIntegerValue;
        }

        _lockTime = [message UInt32AtOffset:off]; // tx locktime
        off += sizeof(uint32_t);
        _hasPaymentID = [message UInt8AtOffset:off]; // tx haspaymentid
        off += sizeof(uint8_t);
        if (_hasPaymentID != 0) {
            _paymentID = [message UInt64AtOffset:off]; // tx paymentid
            off += sizeof(uint64_t);
        }
        _txType = [message UInt32AtOffset:off]; // tx txType
        off += sizeof(uint32_t);
        _bulletProofs = [message dataAtOffset:off length:&l];   //tx bulletproofs
        off += l.unsignedIntegerValue;
        _nTxFee = [message UInt64AtOffset:off]; // tx nTxFee
        off += sizeof(uint64_t);
        _c = [message hashAtOffset:off];  //tx c
        off += sizeof(UInt256);
        
        count = (NSUInteger)[message varIntAtOffset:off length:&l]; // tx S count
        off += l.unsignedIntegerValue;
        for (NSUInteger i = 0; i < count; i++) { // tx S item
            NSMutableArray *subItem = [NSMutableArray array];
            NSUInteger subCount = (NSUInteger)[message varIntAtOffset:off length:&l];   //tx S subCount
            off += l.unsignedIntegerValue;
            for (NSUInteger j = 0; j < subCount; j++) { // tx S subitem
                [subItem addObject:uint256_obj([message hashAtOffset:off])];
                off += sizeof(UInt256);
            }
            [_S addObject:subItem];
        }
        _ntxFeeKeyImage = [message dataAtOffset:off length:&l];     // tx ntxFeeKeyImage
        off += l.unsignedIntegerValue;
        
        _txHash = self.data.SHA256_2;
    }
    
    NSString * outboundShapeshiftAddress = [self shapeshiftOutboundAddress];
    if (outboundShapeshiftAddress) {
        self.associatedShapeshift = [DSShapeshiftEntity shapeshiftHavingWithdrawalAddress:outboundShapeshiftAddress];
        if (self.associatedShapeshift && [self.associatedShapeshift.shapeshiftStatus integerValue] == eShapeshiftAddressStatus_Unused) {
            self.associatedShapeshift.shapeshiftStatus = @(eShapeshiftAddressStatus_NoDeposits);
        }
        if (!self.associatedShapeshift) {
            NSString * possibleOutboundShapeshiftAddress = [self shapeshiftOutboundAddressForceScript];
            self.associatedShapeshift = [DSShapeshiftEntity shapeshiftHavingWithdrawalAddress:possibleOutboundShapeshiftAddress];
            if (self.associatedShapeshift && [self.associatedShapeshift.shapeshiftStatus integerValue] == eShapeshiftAddressStatus_Unused) {
                self.associatedShapeshift.shapeshiftStatus = @(eShapeshiftAddressStatus_NoDeposits);
            }
        }
        if (!self.associatedShapeshift && [self.outputAddresses count]) {
            NSString * mainOutputAddress = nil;
            NSMutableArray * allAddresses = [NSMutableArray array];
            for (BRAddressEntity *e in [BRAddressEntity allObjects]) {
                [allAddresses addObject:e.address];
            }
            for (NSString * outputAddress in self.outputAddresses) {
                if (outputAddress && [allAddresses containsObject:address]) continue;
                if ([outputAddress isEqual:[NSNull null]]) continue;
                mainOutputAddress = outputAddress;
            }
            //NSAssert(mainOutputAddress, @"there should always be an output address");
            if (mainOutputAddress){
                self.associatedShapeshift = [DSShapeshiftEntity registerShapeshiftWithInputAddress:mainOutputAddress andWithdrawalAddress:outboundShapeshiftAddress withStatus:eShapeshiftAddressStatus_NoDeposits];
            }
        }
    }

    return self;
}

- (instancetype)initWithInputHashes:(NSArray *)hashes inputIndexes:(NSArray *)indexes inputScripts:(NSArray *)scripts
outputAddresses:(NSArray *)addresses outputAmounts:(NSArray *)amounts
{
    if (hashes.count == 0 || hashes.count != indexes.count) return nil;
    if (scripts.count > 0 && hashes.count != scripts.count) return nil;
    if (addresses.count != amounts.count) return nil;

    if (! (self = [super init])) return nil;

    _version = TX_VERSION;
    self.hashes = [NSMutableArray arrayWithArray:hashes];
    self.indexes = [NSMutableArray arrayWithArray:indexes];

    if (scripts.count > 0) {
        self.inScripts = [NSMutableArray arrayWithArray:scripts];
    }
    else self.inScripts = [NSMutableArray arrayWithCapacity:hashes.count];

    while (self.inScripts.count < hashes.count) {
        [self.inScripts addObject:[NSNull null]];
    }

    self.amounts = [NSMutableArray arrayWithArray:amounts];
    self.addresses = [NSMutableArray arrayWithArray:addresses];
    self.outScripts = [NSMutableArray arrayWithCapacity:addresses.count];

    for (int i = 0; i < addresses.count; i++) {
        [self.outScripts addObject:[NSMutableData data]];
        [self.outScripts.lastObject appendScriptPubKeyForAddress:self.addresses[i]];
    }

    self.signatures = [NSMutableArray arrayWithCapacity:hashes.count];
    self.sequences = [NSMutableArray arrayWithCapacity:hashes.count];

    for (int i = 0; i < hashes.count; i++) {
        [self.signatures addObject:[NSNull null]];
        [self.sequences addObject:@(TXIN_SEQUENCE)];
    }

    _lockTime = TX_LOCKTIME;
    _blockHeight = TX_UNCONFIRMED;
    return self;
}

- (void)inputInit {
    //vin
    [self.hashes removeAllObjects];
    [self.indexes removeAllObjects];
    [self.inScripts removeAllObjects];
    [self.signatures removeAllObjects];
    [self.sequences removeAllObjects];
    [self.in_encryptionKey removeAllObjects];
    [self.in_keyImage removeAllObjects];
    [self.in_decoys removeAllObjects];
    [self.in_masternodeStealthAddress removeAllObjects];
    [self.in_s removeAllObjects];
    [self.in_R removeAllObjects];
}

- (void)outputInit {
    //vout
    [self.amounts removeAllObjects];
    [self.addresses removeAllObjects];
    [self.outScripts removeAllObjects];
    [self.out_txPriv removeAllObjects];
    [self.out_txPub removeAllObjects];
    [self.out_maskValue removeAllObjects];
    [self.out_masternodeStealthAddress removeAllObjects];
    [self.out_commitment removeAllObjects];
    [self.out_InMemoryRawBind removeAllObjects];
}

- (void)addOutput:(BRTxOut *)txout
{
    [self.amounts addObject:@(txout->nValue)];
    [self.outScripts addObject:txout->scriptPubKey];
    [self.out_txPriv addObject:txout->txPriv];
    [self.out_txPub addObject:txout->txPub];
    NSMutableArray *mask = [NSMutableArray array];
    [mask addObject:uint256_obj(txout->mask_amount)];
    [mask addObject:uint256_obj(txout->mask_mask)];
    [mask addObject:uint256_obj(txout->mask_hashOfKey)];
    [self.out_maskValue addObject:mask];
    [self.out_masternodeStealthAddress addObject:txout->masternodeStealthAddress];
    [self.out_commitment addObject:txout->commitment];
    [self.out_InMemoryRawBind addObject:txout->mask_inMemoryRawBind];
}

- (NSMutableArray *)inputHashes
{
    return self.hashes;
}

- (NSMutableArray *)inputIndexes
{
    return self.indexes;
}

- (NSArray *)inputScripts
{
    return self.inScripts;
}

- (NSArray *)inputSignatures
{
    return self.signatures;
}

- (NSArray *)inputSequences
{
    return self.sequences;
}

- (NSArray *)inputEncryptionKey
{
    return self.in_encryptionKey;
}

- (NSMutableArray *)inputKeyImage
{
    return self.in_keyImage;
}

- (NSMutableArray *)inputDecoys
{
    return self.in_decoys;
}

- (NSArray *)inputMasternodeStealthAddress
{
    return self.in_masternodeStealthAddress;
}

- (NSArray *)inputS
{
    return self.in_s;
}

- (NSArray *)inputR
{
    return self.in_R;
}

- (NSArray *)outputAmounts
{
    return self.amounts;
}

- (NSArray *)outputAddresses
{
    return self.addresses;
}

- (NSArray *)outputScripts
{
    return self.outScripts;
}

- (NSArray *)outputTxPriv
{
    return self.out_txPriv;
}

- (NSArray *)outputTxPub
{
    return self.out_txPub;
}

- (NSArray *)outputMaskValue
{
    return self.out_maskValue;
}

- (NSMutableArray *)outputInMemoryRawBind
{
    return self.out_InMemoryRawBind;
}

- (NSArray *)outputMasternodeStealthAddress
{
    return self.out_masternodeStealthAddress;
}

- (NSMutableArray *)outputCommitment
{
    return self.out_commitment;
}

- (NSString *)description
{
    NSString *txid = [NSString hexWithData:[NSData dataWithBytes:self.txHash.u8 length:sizeof(UInt256)].reverse];
    return [NSString stringWithFormat:@"%@(id=%@)", [self class], txid];
}

- (NSString *)longDescription
{
    NSString *txid = [NSString hexWithData:[NSData dataWithBytes:self.txHash.u8 length:sizeof(UInt256)].reverse];
    return [NSString stringWithFormat:
            @"%@(id=%@, inputHashes=%@, inputIndexes=%@, inputScripts=%@, inputSignatures=%@, inputSequences=%@, "
                           "outputAmounts=%@, outputAddresses=%@, outputScripts=%@)",
            [[self class] description], txid,
            self.inputHashes, self.inputIndexes, self.inputScripts, self.inputSignatures, self.inputSequences,
            self.outputAmounts, self.outputAddresses, self.outputScripts];
}

// size in bytes if signed, or estimated size assuming compact pubkey sigs
- (size_t)size
{
    if (! uint256_is_zero(_txHash)) return self.data.length;
    return 8 + [NSMutableData sizeOfVarInt:self.hashes.count] + [NSMutableData sizeOfVarInt:self.addresses.count] +
           TX_INPUT_SIZE*self.hashes.count + TX_OUTPUT_SIZE*self.addresses.count;
}

- (uint64_t)standardFee
{
    return ((self.size + 999)/1000)*TX_FEE_PER_KB;
}

- (uint64_t)standardInstantFee
{
    return TX_FEE_PER_INPUT*[self.inputHashes count];
}

// checks if all signatures exist, but does not verify them
- (BOOL)isSigned
{
    return (self.signatures.count > 0 && self.signatures.count == self.hashes.count &&
            ! [self.signatures containsObject:[NSNull null]]) ? YES : NO;
}

- (NSData *)toData
{
    return [self toDataWithSubscriptIndex:NSNotFound];
}

- (UInt256)txSignatureHash
{
    UInt256 hash;
    NSMutableData *d = [NSMutableData data];
    [d appendUInt32:self.version];
    [d appendVarInt:self.hashes.count];
    for (NSUInteger i = 0; i < self.hashes.count; i++) {
        [self.hashes[i] getValue:&hash];
        [d appendBytes:&hash length:sizeof(hash)];
        [d appendUInt32:[self.indexes[i] unsignedIntValue]];
        
        if (self.signatures[i] != [NSNull null]) {
            [d appendVarInt:[self.signatures[i] length]];
            [d appendData:self.signatures[i]];
        }
        else [d appendVarInt:0];
        
        [d appendUInt32:[self.sequences[i] unsignedIntValue]];
        
        if (self.in_encryptionKey[i] != [NSNull null]) {
            [d appendVarInt:[self.in_encryptionKey[i] length]];
            [d appendData:self.in_encryptionKey[i]];
        } else [d appendVarInt:0];
        
        if (self.in_keyImage[i] != [NSNull null]) {
            [d appendVarInt:[self.in_keyImage[i] length]];
            [d appendData:self.in_keyImage[i]];
        } else [d appendVarInt:0];
        
        if (self.in_decoys[i] != [NSNull null] && self.in_decoys[i] != nil) {
            NSMutableArray *decoy = (NSMutableArray *)self.in_decoys[i];
            [d appendVarInt:decoy.count];
            for (NSUInteger j = 0; j < decoy.count; j++) {
                BRUTXO o;
                [decoy[j] getValue:&o];
                [d appendBytes:&o.hash length:sizeof(o.hash)];
                [d appendUInt32:o.n];
            }
        } else [d appendVarInt:0];
        
        if (self.in_masternodeStealthAddress[i] != [NSNull null]) {
            [d appendVarInt:[self.in_masternodeStealthAddress[i] length]];
            [d appendData:self.in_masternodeStealthAddress[i]];
        } else [d appendVarInt:0];
        
        if (self.in_s[i] != [NSNull null]) {
            [d appendVarInt:[self.in_s[i] length]];
            [d appendData:self.in_s[i]];
        } else [d appendVarInt:0];
        
        if (self.in_R[i] != [NSNull null]) {
            [d appendVarInt:[self.in_R[i] length]];
            [d appendData:self.in_R[i]];
        } else [d appendVarInt:0];
    }
    
    [d appendVarInt:self.amounts.count];
    for (NSUInteger i = 0; i < self.amounts.count; i++) {
        [d appendUInt64:[self.amounts[i] unsignedLongLongValue]];
        
        if (self.outScripts[i] != [NSNull null]) {
            [d appendVarInt:[self.outScripts[i] length]];
            [d appendData:self.outScripts[i]];
        } else [d appendVarInt:0];
        
        if (self.out_txPriv[i] != [NSNull null]) {
            [d appendVarInt:[self.out_txPriv[i] length]];
            [d appendData:self.out_txPriv[i]];
        } else [d appendVarInt:0];
        
        if (self.out_txPub[i] != [NSNull null]) {
            [d appendVarInt:[self.out_txPub[i] length]];
            [d appendData:self.out_txPub[i]];
        } else [d appendVarInt:0];
        
        if (self.out_maskValue[i] != [NSNull null]) {
            NSMutableArray *mask = (NSMutableArray *)self.out_maskValue[i];
            [mask[0] getValue:&hash];
            [d appendBytes:&hash length:sizeof(hash)];
            [mask[1] getValue:&hash];
            [d appendBytes:&hash length:sizeof(hash)];
            [mask[2] getValue:&hash];
            [d appendBytes:&hash length:sizeof(hash)];
        }
        
        if (self.out_masternodeStealthAddress[i] != [NSNull null]) {
            [d appendVarInt:[self.out_masternodeStealthAddress[i] length]];
            [d appendData:self.out_masternodeStealthAddress[i]];
        } else [d appendVarInt:0];
        
        if (self.out_commitment[i] != [NSNull null]) {
            [d appendVarInt:[self.out_commitment[i] length]];
            [d appendData:self.out_commitment[i]];
        } else [d appendVarInt:0];
    }
    
    [d appendUInt32:self.lockTime];
    [d appendUInt8:self.hasPaymentID];
    if (self.hasPaymentID != 0)
        [d appendUInt64:self.paymentID];
    [d appendUInt32:self.txType];
    
    [d appendUInt64:self.nTxFee];
    
    return d.SHA256_2;
}

- (void)addInputHash:(UInt256)hash index:(NSUInteger)index script:(NSData *)script
{
    [self addInputHash:hash index:index script:script signature:nil sequence:TXIN_SEQUENCE];
}

- (void)addInputHash:(UInt256)hash index:(NSUInteger)index script:(NSData *)script signature:(NSData *)signature
sequence:(uint32_t)sequence
{
    [self.hashes addObject:uint256_obj(hash)];
    [self.indexes addObject:@(index)];
    [self.inScripts addObject:(script) ? script : [NSNull null]];
    [self.signatures addObject:(signature) ? signature : [NSNull null]];
    [self.sequences addObject:@(sequence)];
}

- (void)addOutputAddress:(NSString *)address amount:(uint64_t)amount
{
    [self.amounts addObject:@(amount)];
    [self.addresses addObject:address];
    [self.outScripts addObject:[NSMutableData data]];
    [self.outScripts.lastObject appendScriptPubKeyForAddress:address];
}

- (void)addOutputShapeshiftAddress:(NSString *)address
{
    [self.amounts addObject:@(0)];
    [self.addresses addObject:[NSNull null]];
    [self.outScripts addObject:[NSMutableData data]];
    [self.outScripts.lastObject appendShapeshiftMemoForAddress:address];
}

- (void)addOutputScript:(NSData *)script amount:(uint64_t)amount;
{
    NSString *address = [NSString addressWithScriptPubKey:script];

    [self.amounts addObject:@(amount)];
    [self.outScripts addObject:script];
    [self.addresses addObject:(address) ? address : [NSNull null]];
}

- (void)setInputAddress:(NSString *)address atIndex:(NSUInteger)index;
{
    NSMutableData *d = [NSMutableData data];

    [d appendScriptPubKeyForAddress:address];
    self.inScripts[index] = d;
}

- (NSArray *)inputAddresses
{
    NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:self.inScripts.count];
    NSInteger i = 0;

    for (NSData *script in self.inScripts) {
        NSString *addr = [NSString addressWithScriptPubKey:script];

        if (! addr) addr = [NSString addressWithScriptSig:self.signatures[i]];
        [addresses addObject:(addr) ? addr : [NSNull null]];
        i++;
    }

    return addresses;
}

- (void)shuffleOutputOrder
{    
    for (NSUInteger i = 0; i + 1 < self.amounts.count; i++) { // fischer-yates shuffle
        NSUInteger j = i + arc4random_uniform((uint32_t)(self.amounts.count - i));
        
        if (j == i) continue;
        [self.amounts exchangeObjectAtIndex:i withObjectAtIndex:j];
        [self.outScripts exchangeObjectAtIndex:i withObjectAtIndex:j];
        [self.addresses exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
}

// Returns the binary transaction data that needs to be hashed and signed with the private key for the tx input at
// subscriptIndex. A subscriptIndex of NSNotFound will return the entire signed transaction.
- (NSData *)toDataWithSubscriptIndex:(NSUInteger)subscriptIndex
{
    UInt256 hash;
//    NSMutableData *d = [NSMutableData dataWithCapacity:10 + TX_INPUT_SIZE*self.hashes.count +
//                        TX_OUTPUT_SIZE*self.addresses.count];
    NSMutableData *d = [NSMutableData data];

    [d appendUInt32:self.version];
    [d appendVarInt:self.hashes.count];

    for (NSUInteger i = 0; i < self.hashes.count; i++) {
        [self.hashes[i] getValue:&hash];
        [d appendBytes:&hash length:sizeof(hash)];
        [d appendUInt32:[self.indexes[i] unsignedIntValue]];

        if (subscriptIndex == NSNotFound && self.signatures[i] != [NSNull null]) {
            [d appendVarInt:[self.signatures[i] length]];
            [d appendData:self.signatures[i]];
        }
        else if (subscriptIndex == i && self.inScripts[i] != [NSNull null]) {
            //TODO: to fully match the reference implementation, OP_CODESEPARATOR related checksig logic should go here
            [d appendVarInt:[self.inScripts[i] length]];
            [d appendData:self.inScripts[i]];
        }
        else [d appendVarInt:0];
        
        [d appendUInt32:[self.sequences[i] unsignedIntValue]];
        
        if (self.in_encryptionKey[i] != [NSNull null]) {
            [d appendVarInt:[self.in_encryptionKey[i] length]];
            [d appendData:self.in_encryptionKey[i]];
        } else [d appendVarInt:0];
        
        if (self.in_keyImage[i] != [NSNull null]) {
            [d appendVarInt:[self.in_keyImage[i] length]];
            [d appendData:self.in_keyImage[i]];
        } else [d appendVarInt:0];
        
        if (self.in_decoys[i] != [NSNull null] && self.in_decoys[i] != nil) {
            NSMutableArray *decoy = (NSMutableArray *)self.in_decoys[i];
            [d appendVarInt:decoy.count];
            for (NSUInteger j = 0; j < decoy.count; j++) {
                BRUTXO o;
                [decoy[j] getValue:&o];
                [d appendBytes:&o.hash length:sizeof(o.hash)];
                [d appendUInt32:o.n];
            }
        } else [d appendVarInt:0];
        
        if (self.in_masternodeStealthAddress[i] != [NSNull null]) {
            [d appendVarInt:[self.in_masternodeStealthAddress[i] length]];
            [d appendData:self.in_masternodeStealthAddress[i]];
        } else [d appendVarInt:0];
        
        if (self.in_s[i] != [NSNull null]) {
            [d appendVarInt:[self.in_s[i] length]];
            [d appendData:self.in_s[i]];
        } else [d appendVarInt:0];
        
        if (self.in_R[i] != [NSNull null]) {
            [d appendVarInt:[self.in_R[i] length]];
            [d appendData:self.in_R[i]];
        } else [d appendVarInt:0];
    }
    
    [d appendVarInt:self.amounts.count];
    
    for (NSUInteger i = 0; i < self.amounts.count; i++) {
        [d appendUInt64:[self.amounts[i] unsignedLongLongValue]];
        
        if (self.outScripts[i] != [NSNull null]) {
            [d appendVarInt:[self.outScripts[i] length]];
            [d appendData:self.outScripts[i]];
        } else [d appendVarInt:0];
        
        if (self.out_txPriv[i] != [NSNull null]) {
            [d appendVarInt:[self.out_txPriv[i] length]];
            [d appendData:self.out_txPriv[i]];
        } else [d appendVarInt:0];
        
        if (self.out_txPub[i] != [NSNull null]) {
            [d appendVarInt:[self.out_txPub[i] length]];
            [d appendData:self.out_txPub[i]];
        } else [d appendVarInt:0];
        
        if (self.out_maskValue[i] != [NSNull null]) {
            NSMutableArray *mask = (NSMutableArray *)self.out_maskValue[i];
            [mask[0] getValue:&hash];
            [d appendBytes:&hash length:sizeof(hash)];
            [mask[1] getValue:&hash];
            [d appendBytes:&hash length:sizeof(hash)];
            [mask[2] getValue:&hash];
            [d appendBytes:&hash length:sizeof(hash)];
        }
        
        if (self.out_masternodeStealthAddress[i] != [NSNull null]) {
            [d appendVarInt:[self.out_masternodeStealthAddress[i] length]];
            [d appendData:self.out_masternodeStealthAddress[i]];
        } else [d appendVarInt:0];
        
        if (self.out_commitment[i] != [NSNull null]) {
            [d appendVarInt:[self.out_commitment[i] length]];
            [d appendData:self.out_commitment[i]];
        } else [d appendVarInt:0];
    }
    
    [d appendUInt32:self.lockTime];
    [d appendUInt8:self.hasPaymentID];
    if (self.hasPaymentID != 0)
        [d appendUInt64:self.paymentID];
    [d appendUInt32:self.txType];
    
    [d appendVarInt:[self.bulletProofs length]];
    [d appendData:self.bulletProofs];
    
    [d appendUInt64:self.nTxFee];
    [d appendBytes:&_c length:sizeof(_c)];
    
    [d appendVarInt:self.S.count];
    for (NSUInteger i = 0; i < self.S.count; i++) {
        if (self.S[i] != [NSNull null]) {
            NSMutableArray *subItem = (NSMutableArray *)self.S[i];
            [d appendVarInt:subItem.count];
            for (NSUInteger j = 0; j < subItem.count; j++) {
                [subItem[j] getValue:&hash];
                [d appendBytes:&hash length:sizeof(hash)];
            }
        } else [d appendVarInt:0];
    }
    
    [d appendVarInt:[self.ntxFeeKeyImage length]];
    [d appendData:self.ntxFeeKeyImage];
    
    if (subscriptIndex != NSNotFound) [d appendUInt32:SIGHASH_ALL];
    return d;
}

- (BOOL)signWithPrivateKeys:(NSArray *)privateKeys
{
    NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:privateKeys.count],
                   *keys = [NSMutableArray arrayWithCapacity:privateKeys.count];
    
    for (NSString *pk in privateKeys) {
        BRKey *key = [BRKey keyWithPrivateKey:pk];
        
        if (! key) continue;
        [keys addObject:key];
        [addresses addObject:key.address];
    }
    
    for (NSUInteger i = 0; i < self.hashes.count; i++) {
        NSString *addr = [NSString addressWithScriptPubKey:self.inScripts[i]];
        NSUInteger keyIdx = (addr) ? [addresses indexOfObject:addr] : NSNotFound;
        
        if (keyIdx == NSNotFound) continue;
        
        NSMutableData *sig = [NSMutableData data];
        UInt256 hash = [self toDataWithSubscriptIndex:i].SHA256_2;
        NSMutableData *s = [NSMutableData dataWithData:[keys[keyIdx] sign:hash]];
        NSArray *elem = [self.inScripts[i] scriptElements];
        
        [s appendUInt8:SIGHASH_ALL];
        [sig appendScriptPushData:s];
        
        if (elem.count >= 2 && [elem[elem.count - 2] intValue] == OP_EQUALVERIFY) { // pay-to-pubkey-hash scriptSig
            [sig appendScriptPushData:[keys[keyIdx] publicKey]];
        }
        
        self.signatures[i] = sig;
    }
    
    if (! self.isSigned) return NO;
    _txHash = self.data.SHA256_2;
    return YES;
}

// priority = sum(input_amount_in_satoshis*input_age_in_blocks)/size_in_bytes
- (uint64_t)priorityForAmounts:(NSArray *)amounts withAges:(NSArray *)ages
{
    uint64_t p = 0;
    
    if (amounts.count != self.hashes.count || ages.count != self.hashes.count || [ages containsObject:@(0)]) return 0;
    
    for (NSUInteger i = 0; i < amounts.count; i++) {    
        p += [amounts[i] unsignedLongLongValue]*[ages[i] unsignedLongLongValue];
    }
    
    return p/self.size;
}

// the block height after which the transaction can be confirmed without a fee, or TX_UNCONFIRMRED for never
- (uint32_t)blockHeightUntilFreeForAmounts:(NSArray *)amounts withBlockHeights:(NSArray *)heights
{
    if (amounts.count != self.hashes.count || heights.count != self.hashes.count ||
        self.size > TX_FREE_MAX_SIZE || [heights containsObject:@(TX_UNCONFIRMED)]) {
        return TX_UNCONFIRMED;
    }

    for (NSNumber *amount in self.amounts) {
        if (amount.unsignedLongLongValue < TX_MIN_OUTPUT_AMOUNT) return TX_UNCONFIRMED;
    }

    uint64_t amountTotal = 0, amountsByHeights = 0;
    
    for (NSUInteger i = 0; i < amounts.count; i++) {
        amountTotal += [amounts[i] unsignedLongLongValue];
        amountsByHeights += [amounts[i] unsignedLongLongValue]*[heights[i] unsignedLongLongValue];
    }
    
    if (amountTotal == 0) return TX_UNCONFIRMED;
    
    // this could possibly overflow a uint64 for very large input amounts and far in the future block heights,
    // however we should be okay up to the largest current bitcoin balance in existence for the next 40 years or so,
    // and the worst case is paying a transaction fee when it's not needed
    return (uint32_t)((TX_FREE_MIN_PRIORITY*(uint64_t)self.size + amountsByHeights + amountTotal - 1ULL)/amountTotal);
}

- (NSUInteger)hash
{
    if (uint256_is_zero(_txHash)) return super.hash;
    return *(const NSUInteger *)&_txHash;
}

- (BOOL)isEqual:(id)object
{
    return self == object || ([object isKindOfClass:[BRTransaction class]] && uint256_eq(_txHash, [object txHash]));
}

#pragma mark - Extra shapeshift methods

- (NSString*)shapeshiftOutboundAddress {
    for (NSData * script in self.outputScripts) {
        NSString * outboundAddress = [BRTransaction shapeshiftOutboundAddressForScript:script];
        if (outboundAddress) return outboundAddress;
    }
    return nil;
}

- (NSString*)shapeshiftOutboundAddressForceScript {
    for (NSData * script in self.outputScripts) {
        NSString * outboundAddress = [BRTransaction shapeshiftOutboundAddressForceScript:script];
        if (outboundAddress) return outboundAddress;
    }
    return nil;
}

+ (NSString*)shapeshiftOutboundAddressForceScript:(NSData*)script {
    if ([script UInt8AtOffset:0] == OP_RETURN) {
        UInt8 length = [script UInt8AtOffset:1];
        if ([script UInt8AtOffset:2] == OP_SHAPESHIFT) {
            NSMutableData * data = [NSMutableData data];
            uint8_t v = BITCOIN_SCRIPT_ADDRESS;
            [data appendBytes:&v length:1];
            NSData * addressData = [script subdataWithRange:NSMakeRange(3, length - 1)];
            
            [data appendData:addressData];
            return [NSString base58checkWithData:data];
        }
    }
    return nil;
}

+ (NSString*)shapeshiftOutboundAddressForScript:(NSData*)script {
    if ([script UInt8AtOffset:0] == OP_RETURN) {
        UInt8 length = [script UInt8AtOffset:1];
        if ([script UInt8AtOffset:2] == OP_SHAPESHIFT) {
            NSMutableData * data = [NSMutableData data];
            uint8_t v = BITCOIN_PUBKEY_ADDRESS;
            [data appendBytes:&v length:1];
            NSData * addressData = [script subdataWithRange:NSMakeRange(3, length - 1)];
            
            [data appendData:addressData];
            return [NSString base58checkWithData:data];
        } else if ([script UInt8AtOffset:2] == OP_SHAPESHIFT_SCRIPT) {
            NSMutableData * data = [NSMutableData data];
            uint8_t v = BITCOIN_SCRIPT_ADDRESS;
            [data appendBytes:&v length:1];
            NSData * addressData = [script subdataWithRange:NSMakeRange(3, length - 1)];
            
            [data appendData:addressData];
            return [NSString base58checkWithData:data];
        }
    }
    return nil;
}

- (BOOL)isCoinBase {
    if (self.hashes.count != 1)
        return NO;

    UInt256 hash;
    [self.hashes[0] getValue:&hash];
    
    for (int i = 0; i < 32; i++) {
        if (hash.u8[i] != 0)
            return NO;
    }
    
    return YES;
}

- (BOOL)isCoinStake {
    if (self.hashes.count == 0)
        return NO;
    
    UInt256 hash;
    [self.hashes[0] getValue:&hash];
    
    BOOL ret = NO;
    for (int i = 0; i < 32; i++) {
        if (hash.u8[i] != 0) {
            ret = YES;
            break;
        }
    }
    if (!ret)
        return NO;
    
    if (self.in_decoys.count != 0)
        return NO;
    
    if (self.amounts.count < 2)
        return NO;
    
    if ([self.amounts[0] unsignedLongLongValue] != 0)
        return NO;
    
    if (self.outScripts[0] != [NSNull null] && [self.outScripts[0] length] > 0)
        return NO;
    
    return YES;
}

- (BOOL)isCoinAudit
{
    if (self.hashes.count != 1)
        return NO;
    
    if (self.hashes[0] == [NSNull null])
        return NO;
    
    return YES;
}

@end
