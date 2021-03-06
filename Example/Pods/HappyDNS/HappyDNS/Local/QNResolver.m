//
//  QNResolver.m
//  HappyDNS
//
//  Created by bailong on 15/6/23.
//  Copyright (c) 2015年 Qiniu Cloud Storage. All rights reserved.
//

#include <arpa/inet.h>
#include <resolv.h>
#include <string.h>

#import "QNDomain.h"
#import "QNRecord.h"
#import "QNResolver.h"

@interface QNResolver ()
@property (nonatomic) NSString *address;
@end

static NSArray *query_ip_v4(res_state res, const char *host) {
    u_char answer[1500];
    int len = res_nquery(res, host, ns_c_in, ns_t_a, answer, sizeof(answer));

    ns_msg handle;
    ns_initparse(answer, len, &handle);

    int count = ns_msg_count(handle, ns_s_an);
    if (count <= 0) {
        res_ndestroy(res);
        return nil;
    }
    NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:count];
    char buf[32];
    char cnameBuf[NS_MAXDNAME];
    memset(cnameBuf, 0, sizeof(cnameBuf));
    for (int i = 0; i < count; i++) {
        ns_rr rr;
        if (ns_parserr(&handle, ns_s_an, i, &rr) != 0) {
            res_ndestroy(res);
            return nil;
        }
        int t = ns_rr_type(rr);
        int ttl = ns_rr_ttl(rr);
        NSString *val;
        if (t == ns_t_a) {
            const char *p = inet_ntop(AF_INET, ns_rr_rdata(rr), buf, 32);
            val = [NSString stringWithUTF8String:p];
        } else if (t == ns_t_cname) {
            int x = ns_name_uncompress(answer, &(answer[len]), ns_rr_rdata(rr), cnameBuf, sizeof(cnameBuf));
            if (x <= 0) {
                continue;
            }
            val = [NSString stringWithUTF8String:cnameBuf];
            memset(cnameBuf, 0, sizeof(cnameBuf));
        } else {
            continue;
        }

        QNRecord *record = [[QNRecord alloc] init:val ttl:ttl type:t];
        [array addObject:record];
    }
    res_ndestroy(res);
    return array;
}

static NSArray *query_ip_v6(res_state res, const char *host) {
    u_char answer[1500];
    int len = res_nquery(res, host, ns_c_in, ns_t_aaaa, answer, sizeof(answer));

    ns_msg handle;
    ns_initparse(answer, len, &handle);

    int count = ns_msg_count(handle, ns_s_an);
    if (count <= 0) {
        res_ndestroy(res);
        return nil;
    }
    NSMutableArray *array = [[NSMutableArray alloc] initWithCapacity:count];
    char buf[64];
    char cnameBuf[NS_MAXDNAME];
    memset(cnameBuf, 0, sizeof(cnameBuf));
    for (int i = 0; i < count; i++) {
        ns_rr rr;
        if (ns_parserr(&handle, ns_s_an, i, &rr) != 0) {
            res_ndestroy(res);
            return nil;
        }
        int t = ns_rr_type(rr);
        int ttl = ns_rr_ttl(rr);
        NSString *val;
        if (t == ns_t_aaaa) {
            const char *p = inet_ntop(AF_INET6, ns_rr_rdata(rr), buf, 64);
            val = [NSString stringWithUTF8String:p];
        } else if (t == ns_t_cname) {
            int x = ns_name_uncompress(answer, &(answer[len]), ns_rr_rdata(rr), cnameBuf, sizeof(cnameBuf));
            if (x <= 0) {
                continue;
            }
            val = [NSString stringWithUTF8String:cnameBuf];
            memset(cnameBuf, 0, sizeof(cnameBuf));
        } else {
            continue;
        }

        QNRecord *record = [[QNRecord alloc] init:val ttl:ttl type:t];
        [array addObject:record];
    }
    res_ndestroy(res);
    return array;
}

static int setup_dns_server_v4(res_state res, const char *dns_server) {
    struct in_addr addr;
    int r = inet_pton(AF_INET, dns_server, &addr);
    if (r == 0) {
        return -1;
    }

    res->nsaddr_list[0].sin_addr = addr;
    res->nsaddr_list[0].sin_family = AF_INET;
    res->nsaddr_list[0].sin_port = htons(NS_DEFAULTPORT);
    res->nscount = 1;
    return 0;
}

// does not support ipv6 nameserver now
static int setup_dns_server_v6(res_state res, const char *dns_server) {
    return -1;
}

static int setup_dns_server(res_state res, const char *dns_server) {
    int r = res_ninit(res);
    if (r != 0) {
        return r;
    }
    if (dns_server == NULL) {
        return 0;
    }

    if (strchr(dns_server, ':') == NULL) {
        return setup_dns_server_v4(res, dns_server);
    }

    return setup_dns_server_v6(res, dns_server);
}

@implementation QNResolver
- (instancetype)initWithAddres:(NSString *)address {
    if (self = [super init]) {
        _address = address;
    }
    return self;
}

- (NSArray *)query:(QNDomain *)domain networkInfo:(QNNetworkInfo *)netInfo error:(NSError *__autoreleasing *)error {
    struct __res_state res;

    int r;
    if (_address == nil) {
        r = setup_dns_server(&res, NULL);
    } else {
        r = setup_dns_server(&res, [_address cStringUsingEncoding:NSASCIIStringEncoding]);
    }
    if (r != 0) {
        return nil;
    }

    NSArray *ret = query_ip_v4(&res, [domain.domain cStringUsingEncoding:NSUTF8StringEncoding]);
    if (ret != NULL) {
        return ret;
    }
    return query_ip_v6(&res, [domain.domain cStringUsingEncoding:NSUTF8StringEncoding]);
}

+ (instancetype)systemResolver {
    return [[QNResolver alloc] initWithAddres:nil];
}

@end
