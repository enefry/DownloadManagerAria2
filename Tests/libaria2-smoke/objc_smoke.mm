#import <DMAria2.h>

#import <Foundation/Foundation.h>

int main() {
  @autoreleasepool {
    if (![DMAria2Version() isEqualToString:@"1.37.0"]) {
      NSLog(@"unexpected version: %@", DMAria2Version());
      return 1;
    }

    NSError *error = nil;
    DMAria2Session *session =
        [[DMAria2Session alloc] initWithOptions:@{
          @"dir" : @".",
          @"quiet" : @"true",
          @"enable-rpc" : @"false",
        }
                                           error:&error];
    if (!session) {
      NSLog(@"session failed: %@", error);
      return 2;
    }

    if ([session run:DMAria2RunModeOnce error:&error] < 0) {
      NSLog(@"run failed: %@", error);
      return 3;
    }

    if (![session shutdown:YES error:&error]) {
      NSLog(@"shutdown failed: %@", error);
      return 4;
    }

    [session finish:&error];
    if (error) {
      NSLog(@"finish failed: %@", error);
      return 5;
    }

    NSLog(@"DMAria2 ObjC smoke ok");
  }
  return 0;
}

