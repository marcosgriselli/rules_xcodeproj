#import "Foo.h"

@implementation Foo

- (NSString *)greeting {
    return @"Hello, world?";
}

- (NSInteger)answer {
    return [Answers new].answer;
}

- (void)handleFileManager:(id<FileManagerProtocol>)fileManager {}

@end
