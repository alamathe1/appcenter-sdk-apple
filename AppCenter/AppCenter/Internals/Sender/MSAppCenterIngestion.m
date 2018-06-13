#import "MSAppCenterErrors.h"
#import "MSAppCenterIngestion.h"
#import "MSAppCenterInternal.h"
#import "MSCompression.h"
#import "MSConstants+Internal.h"
#import "MSHttpSenderPrivate.h"
#import "MSLoggerInternal.h"
#import "MSLogContainer.h"

@implementation MSAppCenterIngestion

static NSString *const kMSAPIVersion = @"1.0.0";
static NSString *const kMSAPIVersionKey = @"api-version";
static NSString *const kMSApiPath = @"/logs";

- (id)initWithBaseUrl:(NSString *)baseUrl appSecret:(NSString *)appSecret installId:(NSString *)installId {
  self = [super initWithBaseUrl:baseUrl
      apiPath:kMSApiPath
      headers:@{
        kMSHeaderContentTypeKey : kMSAppCenterContentType,
        kMSHeaderAppSecretKey : appSecret,
        kMSHeaderInstallIDKey : installId
      }
      queryStrings:@{
        kMSAPIVersionKey : kMSAPIVersion
      }
      reachability:[MS_Reachability reachabilityForInternetConnection]
      retryIntervals:@[ @(10), @(5 * 60), @(20 * 60) ]];
  return self;
}

- (void)sendAsync:(NSObject *)data completionHandler:(MSSendAsyncCompletionHandler)handler {
  MSLogContainer *container = (MSLogContainer *)data;
  NSString *batchId = container.batchId;

  /*
   * FIXME: All logs are already validated at the time the logs are enqueued to Channel. It is not necessary but it can
   * still protect against invalid logs being sent to server that are messed up somehow in Storage. If we see
   * performance issues due to this validation, we will remove `[container isValid]` call below.
   */
  // Verify container.
  if (!container || ![container isValid]) {
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey : kMSACLogInvalidContainerErrorDesc};
    NSError *error =
        [NSError errorWithDomain:kMSACErrorDomain code:kMSACLogInvalidContainerErrorCode userInfo:userInfo];
    MSLogError([MSAppCenter logTag], @"%@", [error localizedDescription]);
    handler(batchId, nil, nil, error);
    return;
  }

  [super sendAsync:container callId:container.batchId completionHandler:handler];
}

- (NSURLRequest *)createRequest:(NSObject *)data {
  MSLogContainer *container = (MSLogContainer *)data;
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.sendURL];

  // Set method.
  request.HTTPMethod = @"POST";

  // Set Header params.
  request.allHTTPHeaderFields = self.httpHeaders;

  // Set body.
  NSString *jsonString = [container serializeLog];
  NSData *httpBody = [jsonString dataUsingEncoding:NSUTF8StringEncoding];

  // Zip HTTP body if length worth it.
  if (httpBody.length >= kMSHTTPMinGZipLength) {
    NSData *compressedHttpBody = [MSCompression compressData:httpBody];
    if (compressedHttpBody) {
      [request setValue:kMSHeaderContentEncoding forHTTPHeaderField:kMSHeaderContentEncodingKey];
      httpBody = compressedHttpBody;
    }
  }
  request.HTTPBody = httpBody;

  // Always disable cookies.
  [request setHTTPShouldHandleCookies:NO];

  // Don't loose time pretty printing headers if not going to be printed.
  if ([MSLogger currentLogLevel] <= MSLogLevelVerbose) {
    MSLogVerbose([MSAppCenter logTag], @"URL: %@", request.URL);
    MSLogVerbose([MSAppCenter logTag], @"Headers: %@", [super prettyPrintHeaders:request.allHTTPHeaderFields]);
  }
  return request;
}

- (NSString *)obfuscateHeaderValue:(NSString *)key value:(NSString *)value {
  return [key isEqualToString:kMSHeaderAppSecretKey] ? [MSSenderUtil hideSecret:value] : value;
}

@end
