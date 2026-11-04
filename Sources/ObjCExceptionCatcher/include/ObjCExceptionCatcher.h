#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and turns an Objective-C exception into an NSError.
/// Swift cannot catch NSException, and AVFAudio raises them when the audio
/// hardware disappears (e.g. during a dark wake), which would abort the app.
BOOL SCTryObjC(NS_NOESCAPE void (^block)(void), NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
