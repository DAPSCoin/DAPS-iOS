//
//  BRWallet.m
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

#import "BRWallet.h"
#import "BRKey.h"
#import "BRAddressEntity.h"
#import "BRTransaction.h"
#import "BRTransactionEntity.h"
#import "BRTxInputEntity.h"
#import "BRTxOutputEntity.h"
#import "BRTxMetadataEntity.h"
#import "BRPeerManager.h"
#import "BRKeySequence.h"
#import "BRMerkleBlock.h"
#import "NSData+Bitcoin.h"
#import "NSMutableData+Bitcoin.h"
#import "NSManagedObject+Sugar.h"
#include "secp256k1_bulletproofs.h"
#include "secp256k1_commitment.h"
#include "secp256k1_generator.h"
// chain position of first tx output address that appears in chain
static NSUInteger txAddressIndex(BRTransaction *tx, NSArray *chain) {
    for (NSString *addr in tx.outputAddresses) {
        NSUInteger i = [chain indexOfObject:addr];
        
        if (i != NSNotFound) return i;
    }
    
    return NSNotFound;
}

@interface BRWallet ()

@property (nonatomic, strong) id<BRKeySequence> sequence;
@property (nonatomic, strong) NSData *masterPublicKey,*masterBIP32PublicKey;
@property (nonatomic, strong) NSMutableArray *internalBIP44Addresses,*internalBIP32Addresses, *externalBIP44Addresses,*externalBIP32Addresses, *allKeys;
@property (nonatomic, strong) NSMutableSet *allAddresses, *usedAddresses;
@property (nonatomic, strong) NSSet *spentOutputs, *invalidTx, *pendingTx;
@property (nonatomic, strong) NSMutableOrderedSet *transactions;
@property (nonatomic, strong) NSOrderedSet *utxos;
@property (nonatomic, strong) NSMutableDictionary *allTx;
@property (nonatomic, strong) NSArray *balanceHistory;
@property (nonatomic, assign) uint32_t bestBlockHeight;
@property (nonatomic, strong) SeedRequestBlock seed;
@property (nonatomic, strong) NSManagedObjectContext *moc;
@property (nonatomic, strong) NSMutableDictionary *amountMaps;
@property (nonatomic, strong) NSMutableDictionary *blindMaps;
@property (nonatomic, strong) NSMutableArray *coinbaseDecoysPool;
@property (nonatomic, strong) NSMutableArray *userDecoysPool;
@property (nonatomic, strong) NSMutableArray *inSpendQueueOutpointsPerSession;

@property (nonatomic, strong) BRKey *viewKey, *spendKey;

@end

@implementation BRWallet

- (instancetype)initWithContext:(NSManagedObjectContext *)context sequence:(id<BRKeySequence>)sequence
                masterBIP44PublicKey:(NSData *)masterPublicKey masterBIP32PublicKey:(NSData *)masterBIP32PublicKey requestSeedBlock:(SeedRequestBlock)seed
{
    if (! (self = [super init])) return nil;
    
    NSMutableSet *updateTx = [NSMutableSet set];
    
    self.moc = context;
    self.sequence = sequence;
    self.masterPublicKey = masterPublicKey;
    self.masterBIP32PublicKey = masterBIP32PublicKey;
    self.seed = seed;
    self.allTx = [NSMutableDictionary dictionary];
    self.transactions = [NSMutableOrderedSet orderedSet];
    self.internalBIP32Addresses = [NSMutableArray array];
    self.internalBIP44Addresses = [NSMutableArray array];
    self.externalBIP32Addresses = [NSMutableArray array];
    self.externalBIP44Addresses = [NSMutableArray array];
    self.allAddresses = [NSMutableSet set];
    self.allKeys = [NSMutableArray array];
    self.usedAddresses = [NSMutableSet set];
    self.amountMaps = [NSMutableDictionary dictionary];
    self.blindMaps = [NSMutableDictionary dictionary];
    self.viewKey = nil;
    self.spendKey = nil;
    self.coinbaseDecoysPool = [NSMutableArray array];
    self.userDecoysPool = [NSMutableArray array];
    self.inSpendQueueOutpointsPerSession = [NSMutableArray array];
    
    [self.moc performBlockAndWait:^{
        [BRAddressEntity setContext:self.moc];
        [BRTransactionEntity setContext:self.moc];
        [BRTxMetadataEntity setContext:self.moc];
        
        for (BRAddressEntity *e in [BRAddressEntity allObjects]) {
            @autoreleasepool {
                if (e.purpose == 1) { //viewkey
                    self.viewKey = [BRKey keyWithPrivateKey:e.address];
                    continue;
                }
                
                if (e.purpose == 2) { //spendkey
                    self.spendKey = [BRKey keyWithPrivateKey:e.address];
                    continue;
                }
                
                if (e.purpose == 3) { //spendable key
                    [self.allKeys addObject:[BRKey keyWithPrivateKey:e.address]];
                    continue;
                }
                
                NSMutableArray *a = (e.purpose == 44)?((e.internal) ? self.internalBIP44Addresses : self.externalBIP44Addresses) : ((e.internal) ? self.internalBIP32Addresses : self.externalBIP32Addresses);
                
                while (e.index >= a.count) [a addObject:[NSNull null]];
                a[e.index] = e.address;
                [self.allAddresses addObject:e.address];
            }
        }
        
        if (self.viewKey == nil) {
            self.viewKey = [BRKey keyWithRandSecret:YES];
            
            BRAddressEntity *e = [BRAddressEntity managedObject];
            e.purpose = 1;
            e.account = 0;
            e.address = self.viewKey.privateKey;
            e.index = 0;
            e.internal = NO;
        }
        
        if (self.spendKey == nil) {
            self.spendKey = [BRKey keyWithRandSecret:YES];
            
            BRAddressEntity *e = [BRAddressEntity managedObject];
            e.purpose = 2;
            e.account = 0;
            e.address = self.spendKey.privateKey;
            e.index = 0;
            e.internal = NO;
        }
        
        for (BRTxMetadataEntity *e in [BRTxMetadataEntity allObjects]) {
            @autoreleasepool {
                if (e.type != TX_MDTYPE_MSG) continue;
                
                BRTransaction *tx = e.transaction;
                NSValue *hash = (tx) ? uint256_obj(tx.txHash) : nil;
                
                if (! tx) continue;
                self.allTx[hash] = tx;
                [self.transactions addObject:tx];
                [self.usedAddresses addObjectsFromArray:tx.inputAddresses];
                [self.usedAddresses addObjectsFromArray:tx.outputAddresses];
            }
        }
        
        if ([BRTransactionEntity countAllObjects] > self.allTx.count) {
            // pre-fetch transaction inputs and outputs
            [BRTxInputEntity allObjects];
            [BRTxOutputEntity allObjects];
            
            for (BRTransactionEntity *e in [BRTransactionEntity allObjects]) {
                @autoreleasepool {
                    BRTransaction *tx = e.transaction;
                    NSValue *hash = (tx) ? uint256_obj(tx.txHash) : nil;
                    
                    if (! tx || self.allTx[hash] != nil) continue;
                    
                    [updateTx addObject:tx];
                    self.allTx[hash] = tx;
                    [self.transactions addObject:tx];
                    [self.usedAddresses addObjectsFromArray:tx.inputAddresses];
                    [self.usedAddresses addObjectsFromArray:tx.outputAddresses];
                }
            }
        }
    }];
    
    if (updateTx.count > 0) {
        [self.moc performBlock:^{
            for (BRTransaction *tx in updateTx) {
                [[BRTxMetadataEntity managedObject] setAttributesFromTx:tx];
            }
            
            [BRTxMetadataEntity saveContext];
        }];
    }
    
    [self sortTransactions];
    _balance = UINT64_MAX; // trigger balance changed notification even if balance is zero
    [self updateBalance];
    
    return self;
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

-(NSArray*)internalAddresses {
    return [self.internalBIP32Addresses arrayByAddingObjectsFromArray:self.internalBIP44Addresses];
}

-(NSArray*)externalAddresses {
    return [self.externalBIP32Addresses arrayByAddingObjectsFromArray:self.externalBIP44Addresses];
}

// Wallets are composed of chains of addresses. Each chain is traversed until a gap of a certain number of addresses is
// found that haven't been used in any transactions. This method returns an array of <gapLimit> unused addresses
// following the last used address in the chain. The internal chain is used for change addresses and the external chain
// for receive addresses.
- (NSArray *)addressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal
{
    NSMutableArray *a = [NSMutableArray arrayWithArray:(internal) ? self.internalBIP44Addresses : self.externalBIP44Addresses];
    NSUInteger i = a.count;
    
    // keep only the trailing contiguous block of addresses with no transactions
    while (i > 0 && ! [self.usedAddresses containsObject:a[i - 1]]) {
        i--;
    }
    
    if (i > 0) [a removeObjectsInRange:NSMakeRange(0, i)];
    if (a.count >= gapLimit) return [a subarrayWithRange:NSMakeRange(0, gapLimit)];
    
    if (gapLimit > 1) { // get receiveAddress and changeAddress first to avoid blocking
        [self receiveAddress];
        [self changeAddress];
    }
    
    @synchronized(self) {
        [a setArray:(internal) ? self.internalBIP44Addresses : self.externalBIP44Addresses];
        i = a.count;
        
        unsigned n = (unsigned)i;
        
        // keep only the trailing contiguous block of addresses with no transactions
        while (i > 0 && ! [self.usedAddresses containsObject:a[i - 1]]) {
            i--;
        }
        
        if (i > 0) [a removeObjectsInRange:NSMakeRange(0, i)];
        if (a.count >= gapLimit) return [a subarrayWithRange:NSMakeRange(0, gapLimit)];
        
        while (a.count < gapLimit) { // generate new addresses up to gapLimit
            NSData *pubKey = [self.sequence publicKey:n internal:internal masterPublicKey:self.masterPublicKey];
            NSString *addr = [BRKey keyWithPublicKey:pubKey].address;
            
            if (! addr) {
                NSLog(@"error generating keys");
                return nil;
            }
            
            [self.moc performBlock:^{ // store new address in core data
                BRAddressEntity *e = [BRAddressEntity managedObject];
                e.purpose = 44;
                e.account = 0;
                e.address = addr;
                e.index = n;
                e.internal = internal;
            }];
            
            [self.allAddresses addObject:addr];
            [(internal) ? self.internalBIP44Addresses : self.externalBIP44Addresses addObject:addr];
            [a addObject:addr];
            n++;
        }
        
        return a;
    }
}

- (NSArray *)addressesBIP32NoPurposeWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal
{
    @synchronized(self) {
        NSMutableArray *a = [NSMutableArray arrayWithArray:(internal) ? self.internalBIP32Addresses : self.externalBIP32Addresses];
        NSUInteger i = a.count;
        
        unsigned n = (unsigned)i;
        
        // keep only the trailing contiguous block of addresses with no transactions
        while (i > 0 && ! [self.usedAddresses containsObject:a[i - 1]]) {
            i--;
        }
        
        if (i > 0) [a removeObjectsInRange:NSMakeRange(0, i)];
        if (a.count >= gapLimit) return [a subarrayWithRange:NSMakeRange(0, gapLimit)];
        
        while (a.count < gapLimit) { // generate new addresses up to gapLimit
            NSData *pubKey = [self.sequence publicKey:n internal:internal masterPublicKey:self.masterBIP32PublicKey];
            NSString *addr = [BRKey keyWithPublicKey:pubKey].address;
            
            if (! addr) {
                NSLog(@"error generating keys");
                return nil;
            }
            
            [self.moc performBlock:^{ // store new address in core data
                BRAddressEntity *e = [BRAddressEntity managedObject];
                e.purpose = 0;
                e.account = 0;
                e.address = addr;
                e.index = n;
                e.internal = internal;
            }];
            
            [self.allAddresses addObject:addr];
            [(internal) ? self.internalBIP32Addresses : self.externalBIP32Addresses addObject:addr];
            [a addObject:addr];
            n++;
        }
        
        return a;
    }
}

// this sorts transactions by block height in descending order, and makes a best attempt at ordering transactions within
// each block, however correct transaction ordering cannot be relied upon for determining wallet balance or UTXO set
- (void)sortTransactions
{
    BOOL (^isAscending)(id, id);
    __block __weak BOOL (^_isAscending)(id, id) = isAscending = ^BOOL(BRTransaction *tx1, BRTransaction *tx2) {
        if (! tx1 || ! tx2) return NO;
        if (tx1.blockHeight > tx2.blockHeight) return YES;
        if (tx1.blockHeight < tx2.blockHeight) return NO;
        
        NSValue *hash1 = uint256_obj(tx1.txHash), *hash2 = uint256_obj(tx2.txHash);
        
        if ([tx1.inputHashes containsObject:hash2]) return YES;
        if ([tx2.inputHashes containsObject:hash1]) return NO;
        if ([self.invalidTx containsObject:hash1] && ! [self.invalidTx containsObject:hash2]) return YES;
        if ([self.pendingTx containsObject:hash1] && ! [self.pendingTx containsObject:hash2]) return YES;
        
        for (NSValue *hash in tx1.inputHashes) {
            if (_isAscending(self.allTx[hash], tx2)) return YES;
        }
        
        return NO;
    };
    
    [self.transactions sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(id tx1, id tx2) {
        if (isAscending(tx1, tx2)) return NSOrderedAscending;
        if (isAscending(tx2, tx1)) return NSOrderedDescending;
        
        NSUInteger i = txAddressIndex(tx1, self.internalAddresses),
        j = txAddressIndex(tx2, (i == NSNotFound) ? self.externalAddresses : self.internalAddresses);
        
        if (i == NSNotFound && j != NSNotFound) i = txAddressIndex(tx1, self.externalAddresses);
        if (i == NSNotFound || j == NSNotFound || i == j) return NSOrderedSame;
        return (i > j) ? NSOrderedAscending : NSOrderedDescending;
    }];
}

- (void)updateBalance
{
    uint64_t balance = 0, prevBalance = 0, totalSent = 0, totalReceived = 0;
    NSMutableOrderedSet *utxos = [NSMutableOrderedSet orderedSet];
    NSMutableSet *spentOutputs = [NSMutableSet set], *invalidTx = [NSMutableSet set], *pendingTx = [NSMutableSet set];
    NSMutableArray *balanceHistory = [NSMutableArray array];
    uint32_t now = [NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970;
    
    for (BRTransaction *tx in [self.transactions reverseObjectEnumerator]) {
        @autoreleasepool {
            NSMutableSet *spent = [NSMutableSet set];
            NSSet *inputs;
            uint32_t i = 0, n = 0;
            BOOL pending = NO;
            UInt256 h;
            
            for (NSValue *hash in tx.inputHashes) {
                n = [tx.inputIndexes[i++] unsignedIntValue];
                [hash getValue:&h];
                [spent addObject:brutxo_obj(((BRUTXO) { h, n }))];
            }
            
            inputs = [NSSet setWithArray:tx.inputHashes];
            
            // check if any inputs are invalid or already spent
            if (tx.blockHeight == TX_UNCONFIRMED &&
                ([spent intersectsSet:spentOutputs] || [inputs intersectsSet:invalidTx])) {
                [invalidTx addObject:uint256_obj(tx.txHash)];
                [balanceHistory insertObject:@(balance) atIndex:0];
                continue;
            }
            
            [spentOutputs unionSet:spent]; // add inputs to spent output set
            n = 0;
            
            // check if any inputs are pending
            if (tx.blockHeight == TX_UNCONFIRMED) {
                if (tx.size > TX_MAX_SIZE) pending = YES; // check transaction size is under TX_MAX_SIZE
                
                for (NSNumber *sequence in tx.inputSequences) {
                    if (sequence.unsignedIntValue < UINT32_MAX - 1) pending = YES; // check for replace-by-fee
                    if (sequence.unsignedIntValue < UINT32_MAX && tx.lockTime < TX_MAX_LOCK_HEIGHT &&
                        tx.lockTime > self.bestBlockHeight + 1) pending = YES; // future lockTime
                    if (sequence.unsignedIntValue < UINT32_MAX && tx.lockTime >= TX_MAX_LOCK_HEIGHT &&
                        tx.lockTime > now) pending = YES; // future locktime
                }
                
                for (NSNumber *amount in tx.outputAmounts) { // check that no outputs are dust
                    if (amount.unsignedLongLongValue < TX_MIN_OUTPUT_AMOUNT) pending = YES;
                }
                
                if (pending || [inputs intersectsSet:pendingTx]) {
                    [pendingTx addObject:uint256_obj(tx.txHash)];
                    [balanceHistory insertObject:@(balance) atIndex:0];
                    continue;
                }
            }
            
            //TODO: don't add outputs below TX_MIN_OUTPUT_AMOUNT
            //TODO: don't add coin generation outputs < 100 blocks deep
            //NOTE: balance/UTXOs will then need to be recalculated when last block changes
            for (NSString *address in tx.outputAddresses) { // add outputs to UTXO set
                if ([self containsAddress:address]) {
                    [utxos addObject:brutxo_obj(((BRUTXO) { tx.txHash, n }))];
                    balance += [tx.outputAmounts[n] unsignedLongLongValue];
                }
                
                n++;
            }
            
            // transaction ordering is not guaranteed, so check the entire UTXO set against the entire spent output set
            [spent setSet:utxos.set];
            [spent intersectSet:spentOutputs];
            
            for (NSValue *output in spent) { // remove any spent outputs from UTXO set
                BRTransaction *transaction;
                BRUTXO o;
                
                [output getValue:&o];
                transaction = self.allTx[uint256_obj(o.hash)];
                [utxos removeObject:output];
                balance -= [transaction.outputAmounts[o.n] unsignedLongLongValue];
            }
            
            if (prevBalance < balance) totalReceived += balance - prevBalance;
            if (balance < prevBalance) totalSent += prevBalance - balance;
            [balanceHistory insertObject:@(balance) atIndex:0];
            prevBalance = balance;
        }
    }
    
    self.invalidTx = invalidTx;
    self.pendingTx = pendingTx;
    self.spentOutputs = spentOutputs;
    self.utxos = utxos;
    self.balanceHistory = balanceHistory;
    _totalSent = totalSent;
    _totalReceived = totalReceived;
    
    if (balance != _balance) {
        _balance = balance;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(balanceNotification) object:nil];
            [self performSelector:@selector(balanceNotification) withObject:nil afterDelay:0.1];
        });
    }
}

- (void)balanceNotification
{
    [[NSNotificationCenter defaultCenter] postNotificationName:BRWalletBalanceChangedNotification object:nil];
}

// MARK: - wallet info

// returns the first unused external address
- (NSString *)receiveAddress
{
    //TODO: limit to 10,000 total addresses and utxos for practical usability with bloom filters
#if ADDRESS_DEFAULT == BIP32_PURPOSE
    NSString *addr = [self addressesBIP32NoPurposeWithGapLimit:1 internal:NO].lastObject;
    return (addr) ? addr : self.externalBIP32Addresses.lastObject;
#else
    NSString *addr = [self addressesWithGapLimit:1 internal:NO].lastObject;
    return (addr) ? addr : self.externalBIP44Addresses.lastObject;
#endif
}

- (NSString *)receiveStealthAddress
{
    int size = 71;      //71bytes stealth address
    NSMutableData *d = [NSMutableData secureDataWithCapacity:size];
    
    [d appendUInt8:18];
    [d appendBytes:self.spendKey.publicKey.bytes length:33];
    [d appendBytes:self.viewKey.publicKey.bytes length:33];
    UInt256 h = d.SHA256_2;
    
    [d appendBytes:h.u8 length:4];
    
    NSString *result = @"";
    NSMutableData *inputData = nil;
    NSString *base58;
    for (int i = 1; i < 9; i++) {
        UInt64 input8;
        [d getBytes:&input8 range:NSMakeRange(8 * (i - 1), 8)];
        
        inputData = [NSMutableData dataWithBytes:&input8 length:8];
        base58 = inputData.base58String;
        if (base58.length < 11) {
            int diff = 11 - base58.length;
            for (int j = 0; j < diff; j++)
                base58 = [@"1" stringByAppendingString:base58];
        }
            
        result = [result stringByAppendingString:base58];
    }
    
    UInt8 input7[7];
    [d getBytes:input7 range:NSMakeRange(64, 7)];
    inputData = [NSMutableData dataWithBytes:input7 length:7];
    base58 = inputData.base58String;
    if (base58.length < 11) {
        int diff = 11 - base58.length;
        for (int j = 0; j < diff; j++)
            base58 = [@"1" stringByAppendingString:base58];
    }
    result = [result stringByAppendingString:base58];
    
    return result;
}

// returns the first unused internal address
- (NSString *)changeAddress
{
    //TODO: limit to 10,000 total addresses and utxos for practical usability with bloom filters
#if ADDRESS_DEFAULT == BIP32_PURPOSE
    return [self addressesBIP32NoPurposeWithGapLimit:1 internal:YES].lastObject;
#else
    return [self addressesWithGapLimit:1 internal:YES].lastObject;
#endif
}

// all previously generated external addresses
- (NSSet *)allReceiveAddresses
{
    return [NSSet setWithArray:[self.externalBIP32Addresses arrayByAddingObjectsFromArray:self.externalBIP44Addresses]];
}

// all previously generated external addresses
- (NSSet *)allChangeAddresses
{
    return [NSSet setWithArray:[self.internalBIP32Addresses arrayByAddingObjectsFromArray:self.internalBIP44Addresses]];
}

// NSData objects containing serialized UTXOs
- (NSArray *)unspentOutputs
{
    return self.utxos.array;
}

- (NSDictionary *)amountMap {
    return self.amountMaps;
}

- (NSDictionary *)blindMap {
    return self.blindMaps;
}

// last 100 transactions sorted by date, most recent first
- (NSArray *)recentTransactions
{
    //TODO: don't include receive transactions that don't have at least one wallet output >= TX_MIN_OUTPUT_AMOUNT
    return [self.transactions.array subarrayWithRange:NSMakeRange(0, (self.transactions.count > 100) ? 100 :
                                                                  self.transactions.count)];
}

// all wallet transactions sorted by date, most recent first
- (NSArray *)allTransactions
{
    return self.transactions.array;
}

// true if the address is controlled by the wallet
- (BOOL)containsAddress:(NSString *)address
{
    return (address && [self.allAddresses containsObject:address]) ? YES : NO;
}

// gives the purpose of the address (either 0 or 44 for now)
-(NSUInteger)addressPurpose:(NSString *)address
{
    if ([self.internalBIP44Addresses containsObject:address] || [self.externalBIP44Addresses containsObject:address]) return BIP44_PURPOSE;
    if ([self.internalBIP32Addresses containsObject:address] || [self.externalBIP32Addresses containsObject:address]) return BIP32_PURPOSE;
    return NSIntegerMax;
}

// true if the address was previously used as an input or output in any wallet transaction
- (BOOL)addressIsUsed:(NSString *)address
{
    return (address && [self.usedAddresses containsObject:address]) ? YES : NO;
}

// MARK: - transactions

// returns an unsigned transaction that sends the specified amount from the wallet to the given address
- (BRTransaction *)transactionFor:(uint64_t)amount to:(NSString *)address withFee:(BOOL)fee
{
    NSMutableData *script = [NSMutableData data];
    
    [script appendScriptPubKeyForAddress:address];
    
    return [self transactionForAmounts:@[@(amount)] toOutputScripts:@[script] withFee:fee];
}

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (BRTransaction *)transactionForAmounts:(NSArray *)amounts toOutputScripts:(NSArray *)scripts withFee:(BOOL)fee {
    return [self transactionForAmounts:amounts toOutputScripts:scripts withFee:fee isInstant:FALSE toShapeshiftAddress:nil];
}

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (BRTransaction *)transactionForAmounts:(NSArray *)amounts toOutputScripts:(NSArray *)scripts withFee:(BOOL)fee  isInstant:(BOOL)isInstant {
    return [self transactionForAmounts:amounts toOutputScripts:scripts withFee:fee isInstant:isInstant toShapeshiftAddress:nil];
}

// returns an unsigned transaction that sends the specified amounts from the wallet to the specified output scripts
- (BRTransaction *)transactionForAmounts:(NSArray *)amounts toOutputScripts:(NSArray *)scripts withFee:(BOOL)fee isInstant:(BOOL)isInstant toShapeshiftAddress:(NSString*)shapeshiftAddress
{
    
    uint64_t amount = 0, balance = 0, feeAmount = 0;
    BRTransaction *transaction = [BRTransaction new], *tx;
    NSUInteger i = 0, cpfpSize = 0;
    BRUTXO o;
    
    if (amounts.count != scripts.count || amounts.count < 1) return nil; // sanity check
    
    for (NSData *script in scripts) {
        if (script.length == 0) return nil;
        [transaction addOutputScript:script amount:[amounts[i] unsignedLongLongValue]];
        amount += [amounts[i++] unsignedLongLongValue];
    }
    
    //TODO: use up all UTXOs for all used addresses to avoid leaving funds in addresses whose public key is revealed
    //TODO: avoid combining addresses in a single transaction when possible to reduce information leakage
    //TODO: use up UTXOs received from any of the output scripts that this transaction sends funds to, to mitigate an
    //      attacker double spending and requesting a refund
    for (NSValue *output in self.utxos) {
        [output getValue:&o];
        tx = self.allTx[uint256_obj(o.hash)];
        if (! tx) continue;
        //for example the tx block height is 25, can only send after the chain block height is 31 for previous confirmations needed of 6
        if (isInstant && (tx.blockHeight >= (self.blockHeight - IX_PREVIOUS_CONFIRMATIONS_NEEDED))) continue;
        [transaction addInputHash:tx.txHash index:o.n script:tx.outputScripts[o.n]];
        
        if (transaction.size + 34 > TX_MAX_SIZE) { // transaction size-in-bytes too large
            NSUInteger txSize = 10 + self.utxos.count*148 + (scripts.count + 1)*34;
            
            // check for sufficient total funds before building a smaller transaction
            if (self.balance < amount + [self feeForTxSize:txSize + cpfpSize isInstant:isInstant inputCount:transaction.inputHashes.count]) {
                NSLog(@"Insufficient funds. %llu is less than transaction amount:%llu", self.balance,
                      amount + [self feeForTxSize:txSize + cpfpSize isInstant:isInstant inputCount:transaction.inputHashes.count]);
                return nil;
            }
            
            uint64_t lastAmount = [amounts.lastObject unsignedLongLongValue];
            NSArray *newAmounts = [amounts subarrayWithRange:NSMakeRange(0, amounts.count - 1)],
            *newScripts = [scripts subarrayWithRange:NSMakeRange(0, scripts.count - 1)];
            
            if (lastAmount > amount + feeAmount + self.minOutputAmount - balance) { // reduce final output amount
                newAmounts = [newAmounts arrayByAddingObject:@(lastAmount - (amount + feeAmount - balance))];
                newScripts = [newScripts arrayByAddingObject:scripts.lastObject];
            }
            
            return [self transactionForAmounts:newAmounts toOutputScripts:newScripts withFee:fee];
        }
        
        balance += [tx.outputAmounts[o.n] unsignedLongLongValue];
        
        // add up size of unconfirmed, non-change inputs for child-pays-for-parent fee calculation
        // don't include parent tx with more than 10 inputs or 10 outputs
        if (tx.blockHeight == TX_UNCONFIRMED && tx.inputHashes.count <= 10 && tx.outputAmounts.count <= 10 &&
            [self amountSentByTransaction:tx] == 0) cpfpSize += tx.size;
        
        if (fee) {
            feeAmount = [self feeForTxSize:transaction.size + 34 + cpfpSize isInstant:isInstant inputCount:transaction.inputHashes.count]; // assume we will add a change output
            if (self.balance > amount) feeAmount += (self.balance - amount) % 100; // round off balance to 100 satoshi
        }
        
        if (balance == amount + feeAmount || balance >= amount + feeAmount + self.minOutputAmount) break;
    }
    
    transaction.isInstant = isInstant;
    
    if (balance < amount + feeAmount) { // insufficient funds
        NSLog(@"Insufficient funds. %llu is less than transaction amount:%llu", balance, amount + feeAmount);
        return nil;
    }
    
    if (shapeshiftAddress) {
        [transaction addOutputShapeshiftAddress:shapeshiftAddress];
    }
    
    if (balance - (amount + feeAmount) >= self.minOutputAmount) {
        [transaction addOutputAddress:self.changeAddress amount:balance - (amount + feeAmount)];
        [transaction shuffleOutputOrder];
    }
    
    return transaction;
    
    
}

// sign any inputs in the given transaction that can be signed using private keys from the wallet
- (void)signTransaction:(BRTransaction *)transaction withPrompt:(NSString *)authprompt completion:(TransactionValidityCompletionBlock)completion;
{
    int64_t amount = [self amountSentByTransaction:transaction] - [self amountReceivedFromTransaction:transaction];
    NSMutableOrderedSet *externalIndexesPurpose44 = [NSMutableOrderedSet orderedSet],
    *internalIndexesPurpose44 = [NSMutableOrderedSet orderedSet],
    *externalIndexesNoPurpose = [NSMutableOrderedSet orderedSet],
    *internalIndexesNoPurpose = [NSMutableOrderedSet orderedSet];
    
    for (NSString *addr in transaction.inputAddresses) {
        NSInteger index = [self.internalBIP44Addresses indexOfObject:addr];
        if (index != NSNotFound) {
            [internalIndexesPurpose44 addObject:@(index)];
            continue;
        }
        index = [self.externalBIP44Addresses indexOfObject:addr];
        if (index != NSNotFound) {
            [externalIndexesPurpose44 addObject:@(index)];
            continue;
        }
        index = [self.internalBIP32Addresses indexOfObject:addr];
        if (index != NSNotFound) {
            [internalIndexesNoPurpose addObject:@(index)];
            continue;
        }
        index = [self.externalBIP32Addresses indexOfObject:addr];
        if (index != NSNotFound) {
            [externalIndexesNoPurpose addObject:@(index)];
            continue;
        }
    }
    
    @autoreleasepool { // @autoreleasepool ensures sensitive data will be dealocated immediately
        self.seed(authprompt, (amount > 0) ? amount : 0,^void (NSData * _Nullable seed) {
            if (! seed) {
                if (completion) completion(YES);
            } else {
                NSMutableArray *privkeys = [NSMutableArray array];
                [privkeys addObjectsFromArray:[self.sequence privateKeys:externalIndexesPurpose44.array purpose:BIP44_PURPOSE internal:NO fromSeed:seed]];
                [privkeys addObjectsFromArray:[self.sequence privateKeys:internalIndexesPurpose44.array purpose:BIP44_PURPOSE internal:YES fromSeed:seed]];
                [privkeys addObjectsFromArray:[self.sequence privateKeys:externalIndexesNoPurpose.array purpose:BIP32_PURPOSE internal:NO fromSeed:seed]];
                [privkeys addObjectsFromArray:[self.sequence privateKeys:internalIndexesNoPurpose.array purpose:BIP32_PURPOSE internal:YES fromSeed:seed]];
                
                BOOL signedSuccessfully = [transaction signWithPrivateKeys:privkeys];
                if (completion) completion(signedSuccessfully);
            }
        });
    }
}

// sign any inputs in the given transaction that can be signed using private keys from the wallet
- (void)signBIP32Transaction:(BRTransaction *)transaction withPrompt:(NSString *)authprompt completion:(TransactionValidityCompletionBlock)completion;
{
    int64_t amount = [self amountSentByTransaction:transaction] - [self amountReceivedFromTransaction:transaction];
    NSMutableOrderedSet *externalIndexes = [NSMutableOrderedSet orderedSet],
    *internalIndexes = [NSMutableOrderedSet orderedSet];
    
    for (NSString *addr in transaction.inputAddresses) {
        [internalIndexes addObject:@([self.internalBIP32Addresses indexOfObject:addr])];
        [externalIndexes addObject:@([self.externalBIP32Addresses indexOfObject:addr])];
    }
    
    [internalIndexes removeObject:@(NSNotFound)];
    [externalIndexes removeObject:@(NSNotFound)];
    
    @autoreleasepool { // @autoreleasepool ensures sensitive data will be dealocated immediately
        self.seed(authprompt, (amount > 0) ? amount : 0,^void (NSData * _Nullable seed) {
            if (! seed) {
                completion(YES);
            } else {
                NSMutableArray *privkeys = [NSMutableArray array];
                [privkeys addObjectsFromArray:[self.sequence privateKeys:externalIndexes.array purpose:BIP32_PURPOSE internal:NO fromSeed:seed]];
                [privkeys addObjectsFromArray:[self.sequence privateKeys:internalIndexes.array purpose:BIP32_PURPOSE internal:YES fromSeed:seed]];
                
                BOOL signedSuccessfully = [transaction signWithPrivateKeys:privkeys];
                completion(signedSuccessfully);
            }
        });
    }
}

// true if the given transaction is associated with the wallet (even if it hasn't been registered), false otherwise
- (BOOL)containsTransaction:(BRTransaction *)transaction
{
    NSValue *hash = [NSValue valueWithUInt256:transaction.txHash];
    if (self.allTx[hash])
        return YES;
    
    if ([[NSSet setWithArray:transaction.outputAddresses] intersectsSet:self.allAddresses]) return YES;
    if ([self IsTransactionForMe:transaction])
        return YES;
    
    NSInteger i = 0;
    
    for (NSValue *txHash in transaction.inputHashes) {
        BRTransaction *tx = self.allTx[txHash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];
        
        if (n < tx.outputAddresses.count && [self containsAddress:tx.outputAddresses[n]]) return YES;
        if ([self IsTransactionForMe:tx])
            return YES;
    }
    
    return NO;
}

// records the transaction in the wallet, or returns false if it isn't associated with the wallet
- (BOOL)registerTransaction:(BRTransaction *)transaction
{
    UInt256 txHash = transaction.txHash;
    NSValue *hash = uint256_obj(txHash);
    
    if (uint256_is_zero(txHash)) return NO;
    
    if (! [self containsTransaction:transaction]) {
        if (transaction.blockHeight == TX_UNCONFIRMED) self.allTx[hash] = transaction;
        return NO;
    }
    
    if (self.allTx[hash] != nil) return YES;
    
    //TODO: handle tx replacement with input sequence numbers (now replacements appear invalid until confirmation)
    NSLog(@"[BRWallet] received unseen transaction %@", transaction);
    
    self.allTx[hash] = transaction;
    [self.transactions insertObject:transaction atIndex:0];
    [self.usedAddresses addObjectsFromArray:transaction.inputAddresses];
    [self.usedAddresses addObjectsFromArray:transaction.outputAddresses];
    [self updateBalance];
    
    // when a wallet address is used in a transaction, generate a new address to replace it
    [self addressesWithGapLimit:SEQUENCE_GAP_LIMIT_EXTERNAL internal:NO];
    [self addressesWithGapLimit:SEQUENCE_GAP_LIMIT_INTERNAL internal:YES];
    
    [self.moc performBlock:^{ // add the transaction to core data
        if ([BRTransactionEntity countObjectsMatching:@"txHash == %@",
             [NSData dataWithBytes:&txHash length:sizeof(txHash)]] == 0) {
            [[BRTransactionEntity managedObject] setAttributesFromTx:transaction];
        }
        
        if ([BRTxMetadataEntity countObjectsMatching:@"txHash == %@ && type == %d",
             [NSData dataWithBytes:&txHash length:sizeof(txHash)], TX_MDTYPE_MSG] == 0) {
            [[BRTxMetadataEntity managedObject] setAttributesFromTx:transaction];
        }
    }];
    
    return YES;
}

// removes a transaction from the wallet along with any transactions that depend on its outputs
- (void)removeTransaction:(UInt256)txHash
{
    BRTransaction *transaction = self.allTx[uint256_obj(txHash)];
    NSMutableSet *hashes = [NSMutableSet set];
    
    for (BRTransaction *tx in self.transactions) { // remove dependent transactions
        if (tx.blockHeight < transaction.blockHeight) break;
        
        if (! uint256_eq(txHash, tx.txHash) && [tx.inputHashes containsObject:uint256_obj(txHash)]) {
            [hashes addObject:uint256_obj(tx.txHash)];
        }
    }
    
    for (NSValue *hash in hashes) {
        UInt256 h;
        
        [hash getValue:&h];
        [self removeTransaction:h];
    }
    
    [self.allTx removeObjectForKey:uint256_obj(txHash)];
    if (transaction) [self.transactions removeObject:transaction];
    [self updateBalance];
    
    [self.moc performBlock:^{ // remove transaction from core data
        [BRTransactionEntity deleteObjects:[BRTransactionEntity objectsMatching:@"txHash == %@",
                                            [NSData dataWithBytes:&txHash length:sizeof(txHash)]]];
        [BRTxMetadataEntity deleteObjects:[BRTxMetadataEntity objectsMatching:@"txHash == %@",
                                           [NSData dataWithBytes:&txHash length:sizeof(txHash)]]];
    }];
}

// returns the transaction with the given hash if it's been registered in the wallet (might also return non-registered)
- (BRTransaction *)transactionForHash:(UInt256)txHash
{
    return self.allTx[uint256_obj(txHash)];
}

// true if no previous wallet transactions spend any of the given transaction's inputs, and no input tx is invalid
- (BOOL)transactionIsValid:(BRTransaction *)transaction
{
    //TODO: XXX attempted double spends should cause conflicted tx to remain unverified until they're confirmed
    //TODO: XXX verify signatures for spends
    if (transaction.blockHeight != TX_UNCONFIRMED) return YES;
    
    if (self.allTx[uint256_obj(transaction.txHash)] != nil) {
        return ([self.invalidTx containsObject:uint256_obj(transaction.txHash)]) ? NO : YES;
    }
    
    uint32_t i = 0;
    
    for (NSValue *hash in transaction.inputHashes) {
        BRTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];
        UInt256 h;
        
        [hash getValue:&h];
        if ((tx && ! [self transactionIsValid:tx]) ||
            [self.spentOutputs containsObject:brutxo_obj(((BRUTXO) { h, n }))]) return NO;
    }
    
    return YES;
}

- (void)ecdhDecode:(unsigned char *)masked :(unsigned char *)amount :(NSData *)sharedSec {
    UInt256 sharedSec1 = sharedSec.SHA256_2;
    NSMutableData *sharedSec1_Data = [NSMutableData dataWithBytes:&sharedSec1 length:32];
    UInt256 sharedSec2 = sharedSec1_Data.SHA256_2;
    
    for (int i = 0;i < 32; i++) {
        masked[i] ^= *(sharedSec1.u8 + i);
    }

    unsigned char temp[32];
    memcpy(temp, amount, 32);
    memset(amount, 0, 8);
    for (int i = 0; i < 32; i++) {
        amount[i] = temp[i % 8] ^ *(sharedSec2.u8 + i);
    }
}

- (void)ECDHInfo_Decode:(unsigned char*)encodedMask :(unsigned char*)encodedAmount :(NSData *)sharedSec :(UInt256 *)decodedMask :(UInt64 *)decodedAmount {
    unsigned char tempAmount[32], tempDecoded[32];
    memcpy(tempDecoded, encodedMask, 32);
    memcpy(tempAmount, encodedAmount, 32);
    [self ecdhDecode:tempDecoded :tempAmount :sharedSec];
    memcpy(decodedAmount, tempAmount, 8);
    memcpy(decodedMask, tempDecoded, 32);
}

- (void)ECDHInfo_ComputeSharedSec:(const UInt256*)priv :(NSData*)pubKey :(NSMutableData**)sharedSec {
    NSMutableData *temp = [NSMutableData secureDataWithCapacity:65];
    [temp appendBytes:pubKey.bytes length:33];
    
    if (!BRSecp256k1PointMul((BRECPoint*)temp.bytes, priv)) {
        NSLog(@"Cannot compute EC multiplication: secp256k1_ec_pubkey_tweak_mul");
        return;
    }
    
    *sharedSec = [NSMutableData secureDataWithCapacity:33];
    [*sharedSec appendBytes:temp.bytes length:33];
}

- (BOOL)ComputeSharedSec:(BRTransaction *)transaction :(NSUInteger)outIndex :(NSMutableData **)sharedSec {
    if (transaction.txType == TX_TYPE_REVEAL_AMOUNT || transaction.txType == TX_TYPE_REVEAL_BOTH) {
        *sharedSec = [NSMutableData secureDataWithCapacity:33];
        [*sharedSec appendBytes:[transaction.outputTxPub[outIndex] bytes] length:33];
    } else {
        const UInt256 *view = self.viewKey.secretKey;
        [self ECDHInfo_ComputeSharedSec:view :transaction.outputTxPub[outIndex] :sharedSec];
    }
    
    return YES;
}

- (BOOL)HaveKey:(NSData *)pubkey {
    for (int i = 0; i < self.allKeys.count; i++) {
        BRKey *item = (BRKey *)self.allKeys[i];
        if ([item.publicKey isEqualToData:pubkey])
            return YES;
    }
    return NO;
}

- (BOOL)RevealTxOutAmount:(BRTransaction *)transaction :(NSUInteger)outIndex :(UInt64 *)amount :(BRKey *)blind {
    if ([transaction isCoinBase]) {
        *amount = [transaction.outputAmounts[outIndex] unsignedLongLongValue];
        return YES;
    }
    
    if ([transaction isCoinStake]) {
        if ([transaction.outputAmounts[outIndex] unsignedLongLongValue] > 0) {
            *amount = [transaction.outputAmounts[outIndex] unsignedLongLongValue];
            return YES;
        }
    }
    
    NSData *scriptPubKey = transaction.outputScripts[outIndex];
    if ([self.amountMaps valueForKey:scriptPubKey.hexString] != nil) {
        *amount = [[self.amountMaps valueForKey:scriptPubKey.hexString] unsignedLongLongValue];
        
        UInt256 value;
        [[self.blindMaps valueForKey:scriptPubKey.hexString] getValue:&value];
        blind = [BRKey keyWithSecret:value compressed:YES];
        return YES;
    }
    
    NSMutableData *pubKey = [NSMutableData secureDataWithCapacity:33];
    [pubKey appendPubKey:scriptPubKey];
    if (![self HaveKey:pubKey]) {
        *amount = 0;
        return YES;
    }
    
//    if (IsLocked()) {
//        return true;
//    }
    
    NSMutableData *sharedSec;
    [self ComputeSharedSec:transaction :outIndex :&sharedSec];
    
    UInt256 val, mask;
    NSArray *maskvalue = (NSArray*)transaction.outputMaskValue[outIndex];
    [maskvalue[0] getValue:&val];
    [maskvalue[1] getValue:&mask];
    
    UInt256 decodedMask;
    [self ECDHInfo_Decode:(unsigned char*)&mask :(unsigned char*)&val :sharedSec :&decodedMask :amount];
    [self.amountMaps setValue:[NSNumber numberWithUnsignedLongLong:*amount] forKey:scriptPubKey.hexString];
    [self.blindMaps setValue:[NSValue valueWithUInt256:decodedMask] forKey:scriptPubKey.hexString];
    blind = [BRKey keyWithSecret:decodedMask compressed:YES];
    return YES;
}

- (BOOL)IsTransactionForMe:(BRTransaction * _Nonnull)transaction {
    BOOL ret = NO;
    for (NSUInteger i = 0; i < transaction.outputAmounts.count; i++) {
        if ([transaction.outputAmounts[i] unsignedLongLongValue] == 0 &&
            [transaction.outputScripts[i] length] == 0)
            continue;
        
        NSData *txPub = [NSData dataWithData:transaction.outputTxPub[i]];
        const UInt256 *spend = self.spendKey.secretKey;
        const UInt256 *view = self.viewKey.secretKey;
        NSData *pubSpendKey = self.spendKey.publicKey;
        
        //compute the tx destination
        //P' = Hs(aR)G+B, a = view private, B = spend pub, R = tx public key
        NSMutableData *aR = [NSMutableData secureDataWithCapacity:65];
        //copy R into a
        [aR appendBytes:txPub.bytes length:txPub.length];
        if (!BRSecp256k1PointMul((BRECPoint*)aR.bytes, view)) {
            return false;
        }
        aR.length = txPub.length;
        UInt256 HS = aR.SHA256_2;
        NSMutableData *expectedDestination = [NSMutableData secureDataWithCapacity:65];
        [expectedDestination appendBytes:pubSpendKey.bytes length:pubSpendKey.length];
        if (!BRSecp256k1PointAdd((BRECPoint*)expectedDestination.bytes, &HS)) {
            continue;
        }
        NSData *expectedDes = [NSData dataWithBytes:expectedDestination.bytes length:33];
        NSMutableData *scriptPubKey = [NSMutableData data];
        [scriptPubKey appendScriptPubKey:expectedDes];
        if ([scriptPubKey isEqualToData:transaction.outputScripts[i]]) {
            ret = ret || YES;
            
            UInt256 txHash = transaction.txHash;
            
            //Compute private key to spend
            //x = Hs(aR) + b, b = spend private key
            NSMutableData *HStemp = [NSMutableData secureDataWithCapacity:32];
            NSMutableData *spendTemp = [NSMutableData secureDataWithCapacity:32];
            [HStemp appendBytes:&HS length:32];
            [spendTemp appendBytes:spend length:32];
            if (!BRSecp256k1ModAdd((UInt256 *)HStemp.bytes, (UInt256 *)spendTemp.bytes)) {
                NSLog(@"Failed to do secp256k1_ec_privkey_tweak_add");
                return NO;
            }
            NSMutableData *privKeyData = [NSMutableData secureDataWithCapacity:32];
            [privKeyData appendData:HStemp];
            BRKey *privKey = [BRKey keyWithSecret:*(UInt256 *)privKeyData.bytes compressed:YES];
            
            if (![self HaveKey:privKey.publicKey]) {
                [self.moc performBlock:^{ // store new address in core data
                    BRAddressEntity *e = [BRAddressEntity managedObject];
                    e.purpose = 3;
                    e.account = 0;
                    e.address = privKey.privateKey;
                    e.index = 0;
                    e.internal = NO;
                }];
                [self.allKeys addObject:privKey];
            }
            
            NSData *computed = privKey.publicKey;
            
            //put in map from address to txHash used for qt wallet
            UInt160 tempKeyID = computed.hash160;
//            UInt64 c;
//            BRKey *blind;
//            [self RevealTxOutAmount:transaction :i :&c :blind];
        }
    }
    
    return ret;
}

- (bool)findCoinbaseDecoy:(BRUTXO) outpoint {
    NSValue *outpointValue = brutxo_obj(outpoint);
    for (NSValue *output in self.coinbaseDecoysPool) {
        if ([output isEqualToValue:outpointValue])
            return YES;
    }
    
    return NO;
}

- (bool)generateKeyImage:(NSMutableData* _Nonnull)scriptPubKey :(NSMutableData* _Nonnull)img {
    unsigned char pubData[65];
    for (int i = 0; i < self.allKeys.count; i++) {
        BRKey *item = (BRKey *)self.allKeys[i];
        
        NSMutableData *script = [NSMutableData data];
        NSData *pub = item.publicKey;
        
        [script appendScriptPubKey:pub];
        if ([script isEqualToData:scriptPubKey]) {
            UInt256 hash = pub.SHA256_2;
            pubData[0] = *(unsigned char*)pub.bytes;
            memcpy(pubData + 1, &hash, 32);
            
            NSMutableData *newPubKey = [NSMutableData secureDataWithCapacity:65];
            [newPubKey appendBytes:pubData length:33];
            //P' = Hs(aR)G+B, a = view private, B = spend pub, R = tx public key
            unsigned char ki[65];
            //copy newPubKey into ki
            memcpy(ki, newPubKey.bytes, newPubKey.length);
            while (!BRSecp256k1PointMul((BRECPoint*)ki, item.secretKey)) {
                hash = newPubKey.SHA256_2;
                pubData[0] = *(unsigned char*)newPubKey.bytes;
                memcpy(pubData + 1, &hash, 32);
                [newPubKey replaceBytesInRange:NSMakeRange(0, 33) withBytes:pubData length:33];
                memcpy(ki, newPubKey.bytes, newPubKey.length);
            }
            
            [img appendBytes:ki length:33];
            return YES;
        }
    }

    return NO;
}

- (bool)selectDecoysAndRealIndex: (BRTransaction *_Nonnull)tx :(int *_Nonnull)myIndex :(int)ringSize {
    if (self.coinbaseDecoysPool.count <= 14) {
        for (int i = [self blockHeight] - COINBASE_MATURITY; i > 0; i--) {
            if (self.coinbaseDecoysPool.count > 14) break;
            BRMerkleBlock *b = [[BRPeerManager sharedInstance] getBlockWithHeight:i];
            if (b) {
                int coinbaseIdx = 0;
                if ([self IsProofOfStake:b])
                    coinbaseIdx = 1;
                
                UInt256 txHash;
                [[b.txHashes objectAtIndex:coinbaseIdx] getValue:&txHash];
                BRTransaction *coinbase = [self transactionForHash:txHash];
                
                for (size_t i = 0; i < coinbase.outputAmounts.count; i++) {
                    if ([coinbase.outputAmounts[i] unsignedLongLongValue] == 0 &&
                        [coinbase.outputScripts[i] length] == 0)
                        continue;
                    if ([coinbase.outputAmounts[i] unsignedLongLongValue] == -1)
                        continue;
                    
                    if ((rand() % 100) <= PROBABILITY_NEW_COIN_SELECTED) {
                        BRUTXO newOutPoint;
                        newOutPoint.hash = coinbase.txHash;
                        newOutPoint.n = i;
                        if ([self findCoinbaseDecoy:newOutPoint])
                            continue;
                        if (self.coinbaseDecoysPool.count >= MAX_DECOYS_POOL) {
                            int selected = rand() % MAX_DECOYS_POOL;
                            self.coinbaseDecoysPool[selected] = brutxo_obj(newOutPoint);
                        } else {
                            [self.coinbaseDecoysPool addObject:brutxo_obj(newOutPoint)];
                        }
                    }
                }
            }
        }
    }
    
    //Choose decoys
    
    *myIndex = -1;
    NSMutableArray *decoys;
    for(size_t i = 0; i < tx.inputHashes.count; i++) {
        //generate key images and choose decoys
        BRTransaction *txPrev;
        UInt256 hashBlock;
        decoys = (NSMutableArray*)tx.inputDecoys[i];
        
        txPrev = [BRPeerManager sharedInstance].publishedTx[tx.inputHashes[i]];
        if (!txPrev)
            txPrev = self.allTx[tx.inputHashes[i]];
        if (!txPrev)
            return NO;
        
        NSMutableData *ki = [NSMutableData secureDataWithCapacity:65];
        if (![self generateKeyImage:txPrev.outputScripts[[tx.inputIndexes[i] unsignedIntValue]] :ki]) {
            NSLog(@"Cannot generate key image");
            return NO;
        } else {
            tx.inputKeyImage[i] = ki;
        }
        
        int numDecoys = 0;
        if ([txPrev isCoinAudit] || [txPrev isCoinBase] || [txPrev isCoinStake]) {
            if ((int)self.coinbaseDecoysPool.count >= ringSize * 5) {
                while (numDecoys < ringSize) {
                    bool duplicated = NO;
                    NSValue *outpoint = self.coinbaseDecoysPool[rand() % self.coinbaseDecoysPool.count];
                    for (size_t d = 0; d < decoys.count; d++) {
                        if ([decoys[d] isEqualToValue:outpoint]) {
                            duplicated = YES;
                            break;
                        }
                    }
                    
                    if (duplicated) {
                        continue;
                    }
                    
                    [decoys addObject:outpoint];
                    numDecoys++;
                }
            } else if ((int)self.coinbaseDecoysPool.count >= ringSize) {
                for (size_t j = 0; j < self.coinbaseDecoysPool.count; j++) {
                    [decoys addObject:self.coinbaseDecoysPool[j]];
                    numDecoys++;
                    if (numDecoys == ringSize) break;
                }
            } else {
                NSLog(@"Don't have enough decoys, please wait for around 10 minutes and re-try");
                return NO;
            }
        } else {
            NSMutableArray *decoySet = [NSMutableArray arrayWithArray:self.userDecoysPool];
            [decoySet addObjectsFromArray:self.coinbaseDecoysPool];
            if ((int)decoySet.count >= ringSize * 5) {
                while(numDecoys < ringSize) {
                    bool duplicated = NO;
                    NSValue *outpoint = decoySet[rand() % decoySet.count];
                    for (size_t d = 0; d < decoys.count; d++) {
                        if ([decoys[d] isEqualToValue:outpoint]) {
                            duplicated = true;
                            break;
                        }
                    }
                    if (duplicated) {
                        continue;
                    }
                    [decoys addObject:outpoint];
                    numDecoys++;
                }
            } else if ((int)decoySet.count >= ringSize) {
                for (size_t j = 0; j < decoySet.count; j++) {
                    [decoys addObject:decoySet[j]];
                    numDecoys++;
                    if (numDecoys == ringSize) break;
                }
            } else {
                NSLog(@"Don't have enough decoys, please wait for around 10 minutes and re-try");
                return NO;
            }
        }
    }
    
    decoys = (NSMutableArray*)tx.inputDecoys[0];
    *myIndex = rand() % (decoys.count + 1) - 1;
    
    for (size_t i = 0; i < tx.inputHashes.count; i++) {
        BRUTXO o;
        [tx.inputHashes[i] getValue:&o.hash];
        o.n = [tx.inputIndexes[i] unsignedIntValue];
        [self.inSpendQueueOutpointsPerSession addObject:brutxo_obj(o)];
    }

    if (*myIndex != -1) {
        for(size_t i = 0; i < tx.inputHashes.count; i++) {
            decoys = (NSMutableArray*)tx.inputDecoys[i];
            BRUTXO o;
            [tx.inputHashes[i] getValue:&o.hash];
            o.n = [tx.inputIndexes[i] unsignedIntValue];
            
            BRUTXO temp;
            [decoys[*myIndex] getValue:&temp];
            tx.inputHashes[i] = uint256_obj(temp.hash);
            tx.inputIndexes[i] = @(temp.n);
            
            decoys[*myIndex] = brutxo_obj(o);
        }
    }
    
    return YES;
}

- (bool)findCorrespondingPrivateKey:(BRTransaction *)tx :(int)outIndex :(BRKey**)key
{
    for (int i = 0; i < self.allKeys.count; i++) {
        *key = (BRKey *)self.allKeys[i];
        NSMutableData *script = [NSMutableData data];
        [script appendScriptPubKey:(*key).publicKey];
        if ([script isEqualToData:tx.outputScripts[outIndex]])
            return YES;
    }
    
    return NO;
}

- (bool)CreateCommitment:(unsigned char*)blind :(uint64_t)val :(NSMutableData *)commitment
{
    secp256k1_context2 *both = BRSecp256k1_Context();
    secp256k1_pedersen_commitment commitmentD;
    if (!secp256k1_pedersen_commit(both, &commitmentD, blind, val, &secp256k1_generator_const_h, &secp256k1_generator_const_g)) {
        return false;
    }
    unsigned char output[33];
    if (!secp256k1_pedersen_commitment_serialize(both, output, &commitmentD)) {
        return false;
    }
    
    [commitment appendBytes:output length:33];
    return YES;
}

- (bool)PointHashingSuccessively:(NSData *)pk :(unsigned char*)tweak :(unsigned char*)out {
    unsigned char pubData[65];
    UInt256 hash = pk.SHA256_2;
    pubData[0] = *(unsigned char*)pk.bytes;
    memcpy(pubData + 1, &hash, 32);
    NSMutableData *newPubKey = [NSMutableData dataWithBytes:pubData length:33];
    memcpy(out, newPubKey.bytes, newPubKey.length);
    while (!BRSecp256k1PointMul((BRECPoint*)out, (UInt256*)tweak)) {
        hash = newPubKey.SHA256_2;
        pubData[0] = *(unsigned char*)newPubKey.bytes;
        memcpy(pubData + 1, &hash, 32);
        [newPubKey replaceBytesInRange:NSMakeRange(0, 33) withBytes:pubData length:33];
        memcpy(out, newPubKey.bytes, newPubKey.length);
    }
    
    return YES;
}

- (bool)makeRingCT:(BRTransaction *_Nonnull)wtxNew :(int)ringSize :(NSString * _Nonnull)strFailReason {
    int myIndex;
    if (![self selectDecoysAndRealIndex:wtxNew :&myIndex :ringSize]) {
        return NO;
    }
    
    secp256k1_context2 *both = BRSecp256k1_Context();
    for (int i = 0; i < wtxNew.outputAmounts.count; i++) {
        if ([wtxNew.outputAmounts[i] unsignedLongLongValue] == 0 && wtxNew.outputScripts[i] == [NSNull null])
            continue;
        
        secp256k1_pedersen_commitment commitment;
        NSData *secret = (NSData *)wtxNew.outputInMemoryRawBind[i];
        BRKey *blind = [BRKey keyWithSecret:*(UInt256 *)secret.bytes compressed:YES];
        if (!secp256k1_pedersen_commit(both, &commitment, (unsigned char*)blind.secretKey,
                                       [wtxNew.outputAmounts[i] unsignedLongLongValue],
                                       &secp256k1_generator_const_h, &secp256k1_generator_const_g)) {
            NSLog(@"Cannot commit commitment");
            return NO;
        }
        unsigned char output[33];
        if (!secp256k1_pedersen_commitment_serialize(both, output, &commitment)) {
            NSLog(@"Cannot serialize commitment");
            return NO;
        }
        [wtxNew.outputCommitment removeAllObjects];
        NSMutableData *commitmentData = [NSMutableData dataWithBytes:output length:33];
        [wtxNew.outputCommitment addObject:commitmentData];
    }
    
    if (wtxNew.inputHashes.count >= 30) {
        NSLog(@"Failed due to transaction size too large");
        return NO;
    }

    const size_t MAX_VIN = 32;
    const size_t MAX_DECOYS = 13;    //padding 1 for safety reasons
    const size_t MAX_VOUT = 5;

    NSMutableArray *myInputCommiments = [NSMutableArray array];
    int totalCommits = wtxNew.inputHashes.count + wtxNew.outputAmounts.count;
    int npositive = wtxNew.inputHashes.count;
    unsigned char myBlinds[MAX_VIN + MAX_VIN + MAX_VOUT + 1][32];    //myBlinds is used for compuitng additional private key in the ring =
    memset(myBlinds, 0, (MAX_VIN + MAX_VIN + MAX_VOUT + 1) * 32);
    const unsigned char *bptr[MAX_VIN + MAX_VIN + MAX_VOUT + 1];
    //all in pubkeys + an additional public generated from commitments
    unsigned char allInPubKeys[MAX_VIN + 1][MAX_DECOYS + 1][33];
    unsigned char allKeyImages[MAX_VIN + 1][33];
    unsigned char allInCommitments[MAX_VIN][MAX_DECOYS + 1][33];
    unsigned char allOutCommitments[MAX_VOUT][33];

    int myBlindsIdx = 0;
    //additional member in the ring = Sum of All input public keys + sum of all input commitments - sum of all output commitments
    for (size_t j = 0; j < wtxNew.inputHashes.count; j++) {
        BRUTXO myOutpoint;
        NSMutableArray *decoys = (NSMutableArray*)wtxNew.inputDecoys[j];
        if (myIndex == -1) {
            [wtxNew.inputHashes[j] getValue:&myOutpoint.hash];
            myOutpoint.n = [wtxNew.inputIndexes[j] unsignedIntValue];
        } else {
            [decoys[myIndex] getValue:&myOutpoint];
        }
        
        BRTransaction *inTx = [self transactionForHash:myOutpoint.hash];
        BRKey *tmp;
        if (![self findCorrespondingPrivateKey:inTx :myOutpoint.n :&tmp]) {
            NSLog(@"Cannot find private key corresponding to the input");
            return NO;
        }
        memcpy(&myBlinds[myBlindsIdx][0], tmp.secretKey, 32);
        bptr[myBlindsIdx] = &myBlinds[myBlindsIdx][0];
        myBlindsIdx++;
    }

    //Collecting input commitments blinding factors
    for (int i = 0; i < wtxNew.inputHashes.count; i++) {
        BRUTXO myOutpoint;
        NSMutableArray *decoys = (NSMutableArray*)wtxNew.inputDecoys[i];
        if (myIndex == -1) {
            [wtxNew.inputHashes[i] getValue:&myOutpoint.hash];
            myOutpoint.n = [wtxNew.inputIndexes[i] unsignedIntValue];
        } else {
            [decoys[myIndex] getValue:&myOutpoint];
        }
        
        BRTransaction *inTx = [self transactionForHash:myOutpoint.hash];
        secp256k1_pedersen_commitment inCommitment;
        if (!secp256k1_pedersen_commitment_parse(both, &inCommitment, [inTx.outputCommitment[myOutpoint.n] bytes])) {
            NSLog(@"Cannot parse the commitment for inputs");
            return NO;
        }
        
        [myInputCommiments addObject:[NSValue value:&inCommitment withObjCType:@encode(secp256k1_pedersen_commitment)]];
        uint64_t tempAmount;
        BRKey *tmp = nil;
        [self RevealTxOutAmount:inTx :myOutpoint.n :&tempAmount :tmp];
        memcpy(&myBlinds[myBlindsIdx][0], tmp.secretKey, 32);
        
        //verify input commitments
        NSMutableData *recomputedCommitment = [NSMutableData data];
        if (![self CreateCommitment:&myBlinds[myBlindsIdx][0] :tempAmount :recomputedCommitment]) {
            NSLog(@"Cannot create pedersen commitment");
            return NO;
        }
        
        if (![recomputedCommitment isEqualToData:inTx.outputCommitment[myOutpoint.n]]) {
            NSLog(@"Input commitments are not correct");
            return NO;
        }
        
        bptr[myBlindsIdx] = myBlinds[myBlindsIdx];
        myBlindsIdx++;
    }

    //collecting output commitment blinding factors
    for (int i = 0; i < wtxNew.outputAmounts.count; i++) {
        if ([wtxNew.outputAmounts[i] unsignedLongLongValue] == 0 &&
            [wtxNew.outputScripts[i] length] == 0)
            continue;
        
        NSData *secret = (NSData *)wtxNew.outputInMemoryRawBind[i];
        if (secret.length != 0)
            memcpy(&myBlinds[myBlindsIdx][0], secret.bytes, 32);
        bptr[myBlindsIdx] = &myBlinds[myBlindsIdx][0];
        myBlindsIdx++;
    }
    
    BRKey *newBlind = [BRKey keyWithRandSecret:YES];
    memcpy(&myBlinds[myBlindsIdx][0], newBlind.secretKey, 32);
    bptr[myBlindsIdx] = &myBlinds[myBlindsIdx][0];

    int myRealIndex = 0;
    if (myIndex != -1) {
        myRealIndex = myIndex + 1;
    }

    int PI = myRealIndex;
    unsigned char SIJ[MAX_VIN + 1][MAX_DECOYS + 1][32];
    unsigned char LIJ[MAX_VIN + 1][MAX_DECOYS + 1][33];
    unsigned char RIJ[MAX_VIN + 1][MAX_DECOYS + 1][33];
    unsigned char ALPHA[MAX_VIN + 1][32];
    unsigned char AllPrivKeys[MAX_VIN + 1][32];

    //generating LIJ and RIJ at PI: LIJ[j][PI], RIJ[j][PI], j=0..wtxNew.vin.size()
    for (size_t j = 0; j < wtxNew.inputHashes.count; j++) {
        BRUTXO myOutpoint;
        NSMutableArray *decoys = (NSMutableArray*)wtxNew.inputDecoys[j];
        if (myIndex == -1) {
            [wtxNew.inputHashes[j] getValue:&myOutpoint.hash];
            myOutpoint.n = [wtxNew.inputIndexes[j] unsignedIntValue];
        } else {
            [decoys[myIndex] getValue:&myOutpoint];
        }

        BRTransaction *inTx = [self transactionForHash:myOutpoint.hash];
        BRKey *tempPk;

        //looking for private keys corresponding to my real inputs
        if (![self findCorrespondingPrivateKey:inTx :myOutpoint.n :&tempPk]) {
            NSLog(@"Cannot find corresponding private key");
            return NO;
        }
        memcpy(AllPrivKeys[j], tempPk.secretKey, 32);
        //copying corresponding key images
        memcpy(allKeyImages[j], [wtxNew.inputKeyImage[j] bytes], 33);
        //copying corresponding in public keys
        NSData *tempPubKey = tempPk.publicKey;
        memcpy(allInPubKeys[j][PI], tempPubKey.bytes, 33);

        memcpy(allInCommitments[j][PI], [inTx.outputCommitment[myOutpoint.n] bytes], 33);
        BRKey *alpha = [BRKey keyWithRandSecret:YES];
        memcpy(ALPHA[j], alpha.secretKey, 32);
        NSData *LIJ_PI = alpha.publicKey;
        memcpy(LIJ[j][PI], LIJ_PI.bytes, 33);
        [self PointHashingSuccessively:tempPubKey :(unsigned char*)alpha.secretKey :RIJ[j][PI]];
    }

    //computing additional input pubkey and key images
    //additional private key = sum of all existing private keys + sum of all blinds in - sum of all blind outs
    unsigned char outSum[32];
    if (!secp256k1_pedersen_blind_sum(both, outSum, (const unsigned char * const *)bptr, npositive + totalCommits, 2 * npositive)) {
        NSLog(@"Cannot compute pedersen blind sum");
        return NO;
    }
    memcpy(myBlinds[myBlindsIdx], outSum, 32);
    memcpy(AllPrivKeys[wtxNew.inputHashes.count], outSum, 32);
    UInt256 keyData;
    memcpy(&keyData, myBlinds[myBlindsIdx], 32);
    BRKey *additionalPkKey = [BRKey keyWithSecret:keyData compressed:YES];
    
    NSData *additionalPubKey = additionalPkKey.publicKey;
    memcpy(allInPubKeys[wtxNew.inputHashes.count][PI], additionalPubKey.bytes, 33);
    [self PointHashingSuccessively:additionalPubKey :myBlinds[myBlindsIdx] :allKeyImages[wtxNew.inputHashes.count]];

    //verify that additional public key = sum of wtx.vin.size() real public keys + sum of wtx.vin.size() commitments - sum of wtx.vout.size() commitments - commitment to zero of transction fee

    //filling LIJ & RIJ at [j][PI]
    BRKey *alpha_additional = [BRKey keyWithRandSecret:YES];
    memcpy(ALPHA[wtxNew.inputHashes.count], alpha_additional.secretKey, 32);
    NSData *LIJ_PI_additional = alpha_additional.publicKey;
    memcpy(LIJ[wtxNew.inputHashes.count][PI], LIJ_PI_additional.bytes, 33);
    [self PointHashingSuccessively:additionalPubKey :(unsigned char*)alpha_additional.secretKey :RIJ[wtxNew.inputHashes.count][PI]];

    //Initialize SIJ except S[..][PI]
    for (int i = 0; i < wtxNew.inputHashes.count + 1; i++) {
        for (int j = 0; j < [wtxNew.inputDecoys[0] count] + 1; j++) {
            if (j != PI) {
                BRKey *randGen = [BRKey keyWithRandSecret:YES];
                memcpy(SIJ[i][j], randGen.secretKey, 32);
            }
        }
    }

    //extract all public keys
    for (int i = 0; i < wtxNew.inputHashes.count; i++) {
        NSMutableArray *decoysForIn = [NSMutableArray array];
        BRUTXO o;
        [wtxNew.inputHashes[i] getValue:&o.hash];
        o.n = [wtxNew.inputIndexes[i] unsignedIntValue];
        [decoysForIn addObject:brutxo_obj(o)];

        NSMutableArray *decoys = (NSMutableArray*)wtxNew.inputDecoys[i];
        for(int j = 0; j < [wtxNew.inputDecoys[i] length]; j++) {
            [decoys[j] getValue:&o];
            [decoysForIn addObject:brutxo_obj(o)];
        }
        for (int j = 0; j < [wtxNew.inputDecoys[0] length] + 1; j++) {
            if (j != PI) {
                BRTransaction *txPrev;
                [decoysForIn[j] getValue:&o];
                txPrev = [self transactionForHash:o.hash];
                if (!txPrev)
                    return NO;
                
                NSMutableData *extractedPub = [NSMutableData data];
                [extractedPub appendPubKey:txPrev.outputScripts[o.n]];
                if (extractedPub.length == 0) {
                    NSLog(@"Cannot extract public key from script pubkey");
                    return NO;
                }

                memcpy(allInPubKeys[i][j], extractedPub.bytes, 33);
                memcpy(allInCommitments[i][j], [txPrev.outputCommitment[o.n] bytes], 33);
            }
        }
    }

    secp256k1_pedersen_commitment allInCommitmentsPacked[MAX_VIN][MAX_DECOYS + 1];
    secp256k1_pedersen_commitment allOutCommitmentsPacked[MAX_VOUT + 1]; //+1 for tx fee

    for (size_t i = 0; i < wtxNew.outputAmounts.count; i++) {
        memcpy(&(allOutCommitments[i][0]), [wtxNew.outputCommitment[i] bytes], 33);
        if (!secp256k1_pedersen_commitment_parse(both, &allOutCommitmentsPacked[i], allOutCommitments[i])) {
            NSLog(@"Cannot parse the commitment for inputs");
            return NO;
        }
    }

    //commitment to tx fee, blind = 0
    unsigned char txFeeBlind[32];
    memset(txFeeBlind, 0, 32);
    if (!secp256k1_pedersen_commit(both, &allOutCommitmentsPacked[wtxNew.outputAmounts.count], txFeeBlind, wtxNew.nTxFee, &secp256k1_generator_const_h, &secp256k1_generator_const_g)) {
        NSLog(@"Cannot parse the commitment for transaction fee");
        return NO;
    }

    //filling the additional pubkey elements for decoys: allInPubKeys[wtxNew.vin.size()][..]
    //allInPubKeys[wtxNew.vin.size()][j] = sum of allInPubKeys[..][j] + sum of allInCommitments[..][j] - sum of allOutCommitments
    const secp256k1_pedersen_commitment *outCptr[MAX_VOUT + 1];
    for(size_t i = 0; i < wtxNew.outputAmounts.count + 1; i++) {
        outCptr[i] = &allOutCommitmentsPacked[i];
    }
    secp256k1_pedersen_commitment inPubKeysToCommitments[MAX_VIN][MAX_DECOYS + 1];
    for(int i = 0; i < wtxNew.inputHashes.count; i++) {
        for (int j = 0; j < [wtxNew.inputDecoys[0] count] + 1; j++) {
            secp256k1_pedersen_serialized_pubkey_to_commitment(allInPubKeys[i][j], 33, &inPubKeysToCommitments[i][j]);
        }
    }

    for (int j = 0; j < [wtxNew.inputDecoys[0] count] + 1; j++) {
        if (j != PI) {
            const secp256k1_pedersen_commitment *inCptr[MAX_VIN * 2];
            for (int k = 0; k < wtxNew.inputHashes.count; k++) {
                if (!secp256k1_pedersen_commitment_parse(both, &allInCommitmentsPacked[k][j], allInCommitments[k][j])) {
                    NSLog(@"Cannot parse the commitment for inputs");
                    return NO;
                }
                inCptr[k] = &allInCommitmentsPacked[k][j];
            }
            for (size_t k = wtxNew.inputHashes.count; k < 2*wtxNew.inputHashes.count; k++) {
                inCptr[k] = &inPubKeysToCommitments[k - wtxNew.inputHashes.count][j];
            }
            secp256k1_pedersen_commitment out;
            size_t length;
            //convert allInPubKeys to pederson commitment to compute sum of all in public keys
            if (!secp256k1_pedersen_commitment_sum(both, inCptr, wtxNew.inputHashes.count*2, outCptr, wtxNew.outputAmounts.count + 1, &out))
                NSLog(@"Cannot compute sum of commitment");
            if (!secp256k1_pedersen_commitment_to_serialized_pubkey(&out, allInPubKeys[wtxNew.inputHashes.count][j], &length))
                NSLog(@"Cannot covert from commitment to public key");
        }
    }

    //Computing C
    int PI_interator = PI + 1; //PI_interator: PI + 1 .. wtxNew.vin[0].decoys.size() + 1 .. PI
    //unsigned char SIJ[wtxNew.vin.size() + 1][wtxNew.vin[0].decoys.size() + 1][32];
    //unsigned char LIJ[wtxNew.vin.size() + 1][wtxNew.vin[0].decoys.size() + 1][33];
    //unsigned char RIJ[wtxNew.vin.size() + 1][wtxNew.vin[0].decoys.size() + 1][33];
    unsigned char CI[MAX_DECOYS + 1][32];
    unsigned char tempForHash[2 * (MAX_VIN + 1) * 33 + 32];
    unsigned char* tempForHashPtr = tempForHash;
    for (size_t i = 0; i < wtxNew.inputHashes.count + 1; i++) {
        memcpy(tempForHashPtr, &LIJ[i][PI][0], 33);
        tempForHashPtr += 33;
        memcpy(tempForHashPtr, &RIJ[i][PI][0], 33);
        tempForHashPtr += 33;
    }
    UInt256 ctsHash = wtxNew.txSignatureHash;
    memcpy(tempForHashPtr, &ctsHash, 32);

    if (PI_interator == [wtxNew.inputDecoys[0] count] + 1) PI_interator = 0;
    NSMutableData *hashData = [NSMutableData dataWithBytes:tempForHash length:2 * (wtxNew.inputHashes.count + 1) * 33 + 32];
    UInt256 temppi1 = hashData.SHA256_2;
    if (PI_interator == 0) {
        memcpy(CI[0], &temppi1, 32);
    } else {
        memcpy(CI[PI_interator], &temppi1, 32);
    }

    while (PI_interator != PI) {
        for (int j = 0; j < wtxNew.inputHashes.count + 1; j++) {
            //compute LIJ
            unsigned char CP[33];
            memcpy(CP, allInPubKeys[j][PI_interator], 33);
            if (!BRSecp256k1PointMul((BRECPoint*)CP, (UInt256*)CI[PI_interator])) {
                NSLog(@"Cannot compute LIJ for ring signature in secp256k1_ec_pubkey_tweak_mul");
                return NO;
            }
            if (!BRSecp256k1PointAdd((BRECPoint*)CP, (UInt256*)SIJ[j][PI_interator])) {
                NSLog(@"Cannot compute LIJ for ring signature in secp256k1_ec_pubkey_tweak_add");
                return NO;
            }
            memcpy(LIJ[j][PI_interator], CP, 33);

            //compute RIJ
            //first compute CI * I
            memcpy(RIJ[j][PI_interator], allKeyImages[j], 33);
            if (!BRSecp256k1PointMul((BRECPoint*)RIJ[j][PI_interator], (UInt256*)CI[PI_interator])) {
                NSLog(@"Cannot compute RIJ for ring signature in secp256k1_ec_pubkey_tweak_mul");
                return NO;
            }

            //compute S*H(P)
            unsigned char SHP[33];
            NSMutableData *tempP = [NSMutableData dataWithBytes:allInPubKeys[j][PI_interator] length:33];
            [self PointHashingSuccessively:tempP :SIJ[j][PI_interator] :SHP];
            //convert shp into commitment
            secp256k1_pedersen_commitment SHP_commitment;
            secp256k1_pedersen_serialized_pubkey_to_commitment(SHP, 33, &SHP_commitment);

            //convert CI*I into commitment
            secp256k1_pedersen_commitment cii_commitment;
            secp256k1_pedersen_serialized_pubkey_to_commitment(RIJ[j][PI_interator], 33, &cii_commitment);

            const secp256k1_pedersen_commitment *twoElements[2];
            twoElements[0] = &SHP_commitment;
            twoElements[1] = &cii_commitment;

            secp256k1_pedersen_commitment sum;
            if (!secp256k1_pedersen_commitment_sum_pos(both, twoElements, 2, &sum)) {
                NSLog(@"Cannot compute sum of commitments");
                return NO;
            }
            
            size_t tempLength;
            if (!secp256k1_pedersen_commitment_to_serialized_pubkey(&sum, RIJ[j][PI_interator], &tempLength)) {
                NSLog(@"Cannot compute two elements and serialize it to pubkey");
            }
        }

        PI_interator++;
        if (PI_interator == [wtxNew.inputDecoys[0] count] + 1) PI_interator = 0;

        int prev, ciIdx;
        if (PI_interator == 0) {
            prev = [wtxNew.inputDecoys[0] count];
            ciIdx = 0;
        } else {
            prev = PI_interator - 1;
            ciIdx = PI_interator;
        }

        tempForHashPtr = tempForHash;
        for (int i = 0; i < wtxNew.inputHashes.count + 1; i++) {
            memcpy(tempForHashPtr, LIJ[i][prev], 33);
            tempForHashPtr += 33;
            memcpy(tempForHashPtr, RIJ[i][prev], 33);
            tempForHashPtr += 33;
        }
        memcpy(tempForHashPtr, &ctsHash, 32);
        NSMutableData *ciHashTmpData = [NSMutableData dataWithBytes:tempForHash length:2 * (wtxNew.inputHashes.count + 1) * 33 + 32];
        UInt256 ciHashTmp = ciHashTmpData.SHA256_2;
        memcpy(CI[ciIdx], &ciHashTmp, 32);
    }

    //compute S[j][PI] = alpha_j - c_pi * x_j, x_j = private key corresponding to key image I
    for (size_t j = 0; j < wtxNew.inputHashes.count + 1; j++) {
        unsigned char cx[32];
        memcpy(cx, CI[PI], 32);
        if (!BRSecp256k1ModMul((UInt256*)cx, (UInt256*)AllPrivKeys[j])) {
            NSLog(@"Cannot compute EC mul");
            return NO;
        }
        
        const unsigned char *sumArray[2];
        sumArray[0] = ALPHA[j];
        sumArray[1] = cx;
        if (!secp256k1_pedersen_blind_sum(both, SIJ[j][PI], sumArray, 2, 1)) {
            NSLog(@"Cannot compute pedersen blind sum");
            return NO;
        }
    }
    UInt256 c_temp = wtxNew.c;
    memcpy(&c_temp, CI[0], 32);
    wtxNew.c = c_temp;
    
    //i for decoy index => PI
    for (int i = 0; i < [wtxNew.inputDecoys[0] count] + 1; i++) {
        NSMutableArray *S_column = [NSMutableArray array];
        for (int j = 0; j < wtxNew.inputHashes.count + 1; j++) {
            UInt256 t;
            memcpy(&t, SIJ[j][i], 32);
            [S_column addObject:uint256_obj(t)];
        }
        [wtxNew.S addObject:S_column];
    }

    wtxNew.ntxFeeKeyImage = [NSMutableData dataWithBytes:allKeyImages[wtxNew.inputHashes.count] length:33];
    
    return YES;
}

- (bool)IsProofOfStake:(BRMerkleBlock *_Nonnull)block {
    if (block.txHashes.count <= 1)
        return NO;
    
    UInt256 txHash;
    [[block.txHashes objectAtIndex:1] getValue:&txHash];
    BRTransaction *tx = [self transactionForHash:txHash];
    if (!tx)
        return NO;
    
    if (![tx isCoinStake])
        return NO;
    
    if ([self IsProofOfAudit:block])
        return NO;
    
    return YES;
}

- (bool)IsProofOfWork:(BRMerkleBlock *_Nonnull)block {
    if ([self IsProofOfStake:block])
        return NO;
    
    if ([self IsProofOfAudit:block])
        return NO;
    
    return YES;
}

- (bool)IsProofOfAudit:(BRMerkleBlock *_Nonnull)block {
    return block.version >= 100;
}

// true if transaction cannot be immediately spent (i.e. if it or an input tx can be replaced-by-fee)
- (BOOL)transactionIsPending:(BRTransaction *)transaction
{
    if (transaction.blockHeight != TX_UNCONFIRMED) return NO; // confirmed transactions are not pending
    if (transaction.size > TX_MAX_SIZE) return YES; // check transaction size is under TX_MAX_SIZE
    
    // check for future lockTime or replace-by-fee: https://github.com/bitcoin/bips/blob/master/bip-0125.mediawiki
    for (NSNumber *sequence in transaction.inputSequences) {
        if (sequence.unsignedIntValue < UINT32_MAX - 1) return YES;
        if (sequence.unsignedIntValue < UINT32_MAX && transaction.lockTime < TX_MAX_LOCK_HEIGHT &&
            transaction.lockTime > self.bestBlockHeight + 1) return YES;
        if (sequence.unsignedIntValue < UINT32_MAX && transaction.lockTime >= TX_MAX_LOCK_HEIGHT &&
            transaction.lockTime > [NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970) return YES;
    }
    
    for (NSNumber *amount in transaction.outputAmounts) { // check that no outputs are dust
        if (amount.unsignedLongLongValue < TX_MIN_OUTPUT_AMOUNT) return YES;
    }
    
    for (NSValue *txHash in transaction.inputHashes) { // check if any inputs are known to be pending
        if ([self transactionIsPending:self.allTx[txHash]]) return YES;
    }
    
    return NO;
}

// true if tx is considered 0-conf safe (valid and not pending, timestamp is greater than 0, and no unverified inputs)
- (BOOL)transactionIsVerified:(BRTransaction *)transaction
{
    if (transaction.blockHeight != TX_UNCONFIRMED) return YES; // confirmed transactions are always verified
    if (transaction.timestamp == 0) return NO; // a timestamp of 0 indicates transaction is to remain unverified
    if (! [self transactionIsValid:transaction] || [self transactionIsPending:transaction]) return NO;
    
    for (NSValue *txHash in transaction.inputHashes) { // check if any inputs are known to be unverfied
        if (! self.allTx[txHash]) continue;
        if (! [self transactionIsVerified:self.allTx[txHash]]) return NO;
    }
    
    return YES;
}

// set the block heights and timestamps for the given transactions, use a height of TX_UNCONFIRMED and timestamp of 0 to
// indicate a transaction and it's dependents should remain marked as unverified (not 0-conf safe)
- (NSArray *)setBlockHeight:(int32_t)height andTimestamp:(NSTimeInterval)timestamp forTxHashes:(NSArray *)txHashes
{
    NSMutableArray *hashes = [NSMutableArray array], *updated = [NSMutableArray array];
    BOOL needsUpdate = NO;
    
    if (height != TX_UNCONFIRMED && height > self.bestBlockHeight) self.bestBlockHeight = height;
    
    for (NSValue *hash in txHashes) {
        BRTransaction *tx = self.allTx[hash];
        UInt256 h;
        
        if (! tx || (tx.blockHeight == height && tx.timestamp == timestamp)) continue;
        tx.blockHeight = height;
        tx.timestamp = timestamp;
        
        if ([self containsTransaction:tx]) {
            [hash getValue:&h];
            [hashes addObject:[NSData dataWithBytes:&h length:sizeof(h)]];
            [updated addObject:hash];
            if ([self.pendingTx containsObject:hash] || [self.invalidTx containsObject:hash]) needsUpdate = YES;
        }
        else if (height != TX_UNCONFIRMED) [self.allTx removeObjectForKey:hash]; // remove confirmed non-wallet tx
    }
    
    if (hashes.count > 0) {
        if (needsUpdate) {
            [self sortTransactions];
            [self updateBalance];
        }
        
        [self.moc performBlockAndWait:^{
            @autoreleasepool {
                NSMutableSet *entities = [NSMutableSet set];
                
                for (BRTransactionEntity *e in [BRTransactionEntity objectsMatching:@"txHash in %@", hashes]) {
                    e.blockHeight = height;
                    e.timestamp = timestamp;
                    [entities addObject:e];
                }
                
                for (BRTxMetadataEntity *e in [BRTxMetadataEntity objectsMatching:@"txHash in %@ && type == %d", hashes,
                                               TX_MDTYPE_MSG]) {
                    @autoreleasepool {
                        BRTransaction *tx = e.transaction;
                        
                        tx.blockHeight = height;
                        tx.timestamp = timestamp;
                        [e setAttributesFromTx:tx];
                        [entities addObject:e];
                    }
                }
                
                if (height != TX_UNCONFIRMED) {
                    // BUG: XXX saving the tx.blockHeight and the block it's contained in both need to happen together
                    // as an atomic db operation. If the tx.blockHeight is saved but the block isn't when the app exits,
                    // then a re-org that happens afterward can potentially result in an invalid tx showing as confirmed
                    [BRTxMetadataEntity saveContext];
                    
                    for (NSManagedObject *e in entities) {
                        [self.moc refreshObject:e mergeChanges:NO];
                    }
                }
            }
        }];
    }
    
    return updated;
}

// returns the amount received by the wallet from the transaction (total outputs to change and/or receive addresses)
- (uint64_t)amountReceivedFromTransaction:(BRTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger n = 0;
    
    //TODO: don't include outputs below TX_MIN_OUTPUT_AMOUNT
    for (int i = 0; i < transaction.outputAmounts.count; i++) {
        UInt64 c = 0;
        BRKey *blind;
        [self RevealTxOutAmount:transaction :i :&c :blind];
        
        amount += c;
    }
    
    return amount;
}

- (NSString *)getTransactionDestAddress:(BRTransaction *)transaction
{
    for (int i = 0; i < transaction.outputAmounts.count; i++) {
        NSData *scriptPubKey = transaction.outputScripts[i];
        NSMutableData *pubKey = [NSMutableData secureDataWithCapacity:33];
        [pubKey appendPubKey:scriptPubKey];
        if (![self HaveKey:pubKey])
            continue;
        
        BRKey *destPubKey = [BRKey keyWithPublicKey:pubKey];
        return destPubKey.address;
    }
    
    return nil;
}

// retuns the amount sent from the wallet by the trasaction (total wallet outputs consumed, change and fee included)
- (uint64_t)amountSentByTransaction:(BRTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger i = 0;
    
    for (NSValue *hash in transaction.inputHashes) {
        BRTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];
        
        if (n < tx.outputAddresses.count && [self containsAddress:tx.outputAddresses[n]]) {
            amount += [tx.outputAmounts[n] unsignedLongLongValue];
        }
    }
    
    return amount;
}

// returns the fee for the given transaction if all its inputs are from wallet transactions, UINT64_MAX otherwise
- (uint64_t)feeForTransaction:(BRTransaction *)transaction
{
    uint64_t amount = 0;
    NSUInteger i = 0;
    
    for (NSValue *hash in transaction.inputHashes) {
        BRTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];
        
        if (n >= tx.outputAmounts.count) return UINT64_MAX;
        amount += [tx.outputAmounts[n] unsignedLongLongValue];
    }
    
    for (NSNumber *amt in transaction.outputAmounts) {
        amount -= amt.unsignedLongLongValue;
    }
    
    return amount;
}

// historical wallet balance after the given transaction, or current balance if transaction is not registered in wallet
- (uint64_t)balanceAfterTransaction:(BRTransaction *)transaction
{
    NSUInteger i = [self.transactions indexOfObject:transaction];
    
    return (i < self.balanceHistory.count) ? [self.balanceHistory[i] unsignedLongLongValue] : self.balance;
}

// Returns the block height after which the transaction is likely to be processed without including a fee. This is based
// on the default satoshi client settings, but on the real network it's way off. In testing, a 0.01btc transaction that
// was expected to take an additional 90 days worth of blocks to confirm was confirmed in under an hour by Eligius pool.
- (uint32_t)blockHeightUntilFree:(BRTransaction *)transaction
{
    // TODO: calculate estimated time based on the median priority of free transactions in last 144 blocks (24hrs)
    NSMutableArray *amounts = [NSMutableArray array], *heights = [NSMutableArray array];
    NSUInteger i = 0;
    
    for (NSValue *hash in transaction.inputHashes) { // get the amounts and block heights of all the transaction inputs
        BRTransaction *tx = self.allTx[hash];
        uint32_t n = [transaction.inputIndexes[i++] unsignedIntValue];
        
        if (n >= tx.outputAmounts.count) break;
        [amounts addObject:tx.outputAmounts[n]];
        [heights addObject:@(tx.blockHeight)];
    };
    
    return [transaction blockHeightUntilFreeForAmounts:amounts withBlockHeights:heights];
}

// fee that will be added for a transaction of the given size in bytes
- (uint64_t)feeForTxSize:(NSUInteger)size isInstant:(BOOL)isInstant inputCount:(NSInteger)inputCount
{
    if (isInstant) {
        return TX_FEE_PER_INPUT*inputCount;
    } else {
        uint64_t standardFee = ((size + 999)/1000)*TX_FEE_PER_KB; // standard fee based on tx size rounded up to nearest kb
#if (!!FEE_PER_KB_URL)
        uint64_t fee = (((size*self.feePerKb/1000) + 99)/100)*100; // fee using feePerKb, rounded up to nearest 100 satoshi
        return (fee > standardFee) ? fee : standardFee;
#else
        return standardFee;
#endif
        
    }
}

// outputs below this amount are uneconomical due to fees
- (uint64_t)minOutputAmount
{
    uint64_t amount = (TX_MIN_OUTPUT_AMOUNT*self.feePerKb + MIN_FEE_PER_KB - 1)/MIN_FEE_PER_KB;
    
    return (amount > TX_MIN_OUTPUT_AMOUNT) ? amount : TX_MIN_OUTPUT_AMOUNT;
}

- (uint64_t)maxOutputAmountUsingInstantSend:(BOOL)instantSend
{
    return [self maxOutputAmountWithConfirmationCount:0 usingInstantSend:instantSend];
}

- (uint32_t)blockHeight
{
    static uint32_t height = 0;
    uint32_t h = [BRPeerManager sharedInstance].lastBlockHeight;
    
    if (h > height) height = h;
    return height;
}

- (uint64_t)maxOutputAmountWithConfirmationCount:(uint64_t)confirmationCount usingInstantSend:(BOOL)instantSend
{
    BRUTXO o;
    BRTransaction *tx;
    NSUInteger inputCount = 0;
    uint64_t amount = 0, fee;
    size_t cpfpSize = 0, txSize;
    
    for (NSValue *output in self.utxos) {
        [output getValue:&o];
        tx = self.allTx[uint256_obj(o.hash)];
        if (o.n >= tx.outputAmounts.count) continue;
        if (confirmationCount && (tx.blockHeight >= (self.blockHeight - confirmationCount))) continue;
        inputCount++;
        amount += [tx.outputAmounts[o.n] unsignedLongLongValue];
        
        // size of unconfirmed, non-change inputs for child-pays-for-parent fee
        // don't include parent tx with more than 10 inputs or 10 outputs
        if (tx.blockHeight == TX_UNCONFIRMED && tx.inputHashes.count <= 10 && tx.outputAmounts.count <= 10 &&
            [self amountSentByTransaction:tx] == 0) cpfpSize += tx.size;
    }
    
    
    txSize = 8 + [NSMutableData sizeOfVarInt:inputCount] + TX_INPUT_SIZE*inputCount +
    [NSMutableData sizeOfVarInt:2] + TX_OUTPUT_SIZE*2;
    fee = [self feeForTxSize:txSize + cpfpSize isInstant:instantSend inputCount:inputCount];
    return (amount > fee) ? amount - fee : 0;
}

@end
