//
//  DataStore.m
//  Macnews Notify
//
//  Created by mtjddnr on 2015. 3. 19..
//  Copyright (c) 2015년 mtjddnr. All rights reserved.
//

#import "DataStore.h"
@interface DataStore ()

@property (strong, nonatomic) NSMutableArray *hosts;
@property (strong, readonly, nonatomic) NSDictionary *hostsMap;

@end

@implementation DataStore
static DataStore *__sharedData = nil;
+ (DataStore *)sharedData {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"[[DataStore alloc] init]");
        __sharedData = [[DataStore alloc] init];
    });
    return __sharedData;
}

- (NSURL *)managedObjectModelURL {
    return [[NSBundle mainBundle] URLForResource:@"Macnews_Notify" withExtension:@"momd"];
}
- (NSURL *)storeURL {
    NSURL *directory = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:@"group.kr.smoon.ios.macnews"];
    return [directory URLByAppendingPathComponent:@"Macnews_Notify.sqlite"];
}

@synthesize userDefaults=_userDefaults;
- (NSUserDefaults *)userDefaults {
    if (_userDefaults) return _userDefaults;
    return (_userDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.kr.smoon.ios.macnews"]);
}

- (NSInteger)idx {
    return [self.userDefaults integerForKey:@"idx"];
}
- (void)setIdx:(NSInteger)idx {
    [self.userDefaults setInteger:idx forKey:@"idx"];
}
- (void)resetIdx {
    [self.userDefaults removeObjectForKey:@"idx"];
}

- (NSString *)token {
    return [self.userDefaults stringForKey:@"deviceToken"];
}

- (void)resetContext {
    
}

#pragma mark - Hosts
- (NSMutableArray *)hosts {
    if (_hosts == nil) {
        _hosts = [NSMutableArray array];
        
        NSArray *hosts = [self.userDefaults objectForKey:@"hosts"];
        [hosts enumerateObjectsUsingBlock:^(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
            [_hosts addObject:[NSMutableDictionary dictionaryWithDictionary:obj]];
        }];
        
        if ([_hosts count] == 0) {
            [_hosts addObject:[NSMutableDictionary dictionaryWithDictionary:@{
                                                                              @"webId": @"web.com.tistory.macnews",
                                                                              @"title": @"Back to the Mac",
                                                                              @"url": @"http://macnews.tistory.com/m/%@",
                                                                              @"enabled": @(self.token != nil)
                                                                              }]];
            [self.userDefaults setObject:_hosts forKey:@"hosts"];
        }
    }
    return _hosts;
}
- (NSDictionary *)hostsMap {
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    [self.hosts enumerateObjectsUsingBlock:^(NSMutableDictionary *obj, NSUInteger idx, BOOL *stop) { map[obj[@"webId"]] = obj; }];
    return [NSDictionary dictionaryWithDictionary:map];
}
- (NSInteger)numberOfHosts {
    return [self.hosts count];
}
- (NSMutableDictionary *)hostAtIndex:(NSInteger)row {
    return self.hosts[row];
}
- (NSMutableDictionary *)hostWithWebId:(NSString *)webId {
    return self.hostsMap[webId];
}
- (void)saveHosts {
    [self.userDefaults setObject:self.hosts forKey:@"hosts"];
    [self.userDefaults synchronize];
}

- (void)setMultiHostEnabled:(BOOL)multiHostEnabled {
    [self.userDefaults setBool:multiHostEnabled forKey:@"multiHostEnabled"];
}
- (BOOL)multiHostEnabled {
    return [self.userDefaults boolForKey:@"multiHostEnabled"];
}

- (void)updateHostSettings {
    assert([NSThread isMainThread] == NO);
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://push.smoon.kr/v1/hosts"]];
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
    
    if (data == nil) return;
    
    NSArray *list = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
    
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    [list enumerateObjectsUsingBlock:^(NSMutableDictionary *obj, NSUInteger idx, BOOL *stop) { map[obj[@"webId"]] = obj; }];
    
    if (self.multiHostEnabled == NO) {
        NSDictionary *item = map[@"web.com.tistory.macnews"];
        [self.hostsMap[@"web.com.tistory.macnews"] addEntriesFromDictionary:item];
    } else {
        [list enumerateObjectsUsingBlock:^(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
            if (self.hostsMap[obj[@"webId"]] == nil) {
                [self.hosts addObject:[NSMutableDictionary dictionaryWithDictionary:obj]];
            } else {
                [self.hostsMap[obj[@"webId"]] addEntriesFromDictionary:obj];
            }
        }];
    }
    [self saveHosts];
}
- (BOOL)setHost:(NSString *)webId enabled:(BOOL)enabled {
    if (self.token == nil) return NO;
    assert([NSThread isMainThread] == NO);
    
    NSString *pwebId = [NSString stringWithFormat:@"ios%@", [webId substringFromIndex:3]];
    
    NSMutableString *url = [NSMutableString stringWithFormat:@"https://push.smoon.kr/v1/devices/%@/registrations/%@", self.token, pwebId];
    if (enabled == NO) [url appendString:@"/delete"];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [[NSString stringWithFormat:@"version=%@", [[UIDevice currentDevice] systemVersion]] dataUsingEncoding:NSUTF8StringEncoding];
    
    NSHTTPURLResponse *response = nil;
    [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil];
    
    if (response.statusCode == 200) {
        self.hostsMap[webId][@"enabled"] = @(enabled);
        [self saveHosts];
        return YES;
    }
    return NO;
}

#pragma mark - Data
- (void)updateData:(void (^)(NSInteger statusCode, NSUInteger count))onComplete {
    NSManagedObjectContext *context = [self newManagedObjectContext];
    
    NSString *url = self.token != nil ? [NSString stringWithFormat:@"https://push.smoon.kr/v1/notification/%@/%li", self.token, (long)self.idx] :
    [NSString stringWithFormat:@"https://push.smoon.kr/v1/notification/%li", (long)self.idx];
    
    NSURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    NSURLResponse *response = nil;
    NSError *error = nil, *errorJson = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    if ([(NSHTTPURLResponse *)response statusCode] != 200) {
        onComplete([(NSHTTPURLResponse *)response statusCode], 0);
        return;
    }
    
    NSString *entityName = @"Notification";
    
    NSArray *json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&errorJson];
    NSManagedObject *newManagedObject = nil;
    for (NSDictionary *obj in json) {
        NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:obj];
        item[@"reg"] = [NSDate dateWithTimeIntervalSince1970:[item[@"reg"] intValue]];
        NSDictionary *apn = [NSJSONSerialization JSONObjectWithData:[item[@"contents"] dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:nil];
        apn = apn[@"apn"];
        item[@"title"] = apn[@"title"];
        if (apn[@"image"]) item[@"image"] = apn[@"image"];
        if ([apn[@"url-args"] count] > 0) item[@"arg"] = apn[@"url-args"][0];
        newManagedObject = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:context];
        [newManagedObject setValuesForKeysWithDictionary:item];
        [newManagedObject setValue:@NO forKey:@"archived"];
        
        self.idx = MAX(self.idx, [item[@"idx"] integerValue]);
        [self.userDefaults synchronize];
    }
    
    if ([newManagedObject valueForKey:@"image"] != nil) {
        NSData *imageData = [NSData dataWithContentsOfURL:[NSURL URLWithString:[newManagedObject valueForKey:@"image"]]];
        if (imageData != nil) [newManagedObject setValue:imageData forKey:@"imageData"];
    }
    
    NSError *dbError = nil;
    [context save:&dbError];
    
    onComplete([(NSHTTPURLResponse *)response statusCode], [json count]);
}
@end
