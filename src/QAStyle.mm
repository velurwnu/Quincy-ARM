//
//  QAStyle.mm — AStyle 2.06 linked in as a library.
//
//  The original shelled out to astyle.exe; here AStyleMain is called
//  directly, so beautifying is synchronous and leaves no temporary files.
//

#import "Quincy.h"
#include <string>

extern "C" char *AStyleMain(const char *sourceIn, const char *optionsIn,
                            void (*fpError)(int, const char *),
                            char *(*fpAlloc)(unsigned long));
extern "C" const char *AStyleGetVersion(void);

static std::string gAStyleError;

static void ASError(int errorNumber, const char *message) {
    gAStyleError = message ? message : "";
}

static char *ASAlloc(unsigned long size) {
    return new (std::nothrow) char[size];
}

extern "C" NSString *QAStyleFormat(NSString *source, NSString *options,
                                   NSString **error) {
    gAStyleError.clear();
    char *out = AStyleMain(source.UTF8String, (options ?: @"").UTF8String,
                           ASError, ASAlloc);
    if (!out) {
        if (error)
            *error = gAStyleError.empty()
                ? @"AStyle could not format the source"
                : @(gAStyleError.c_str());
        return nil;
    }
    NSString *result = @(out);
    delete[] out;
    if (error) *error = nil;
    return result;
}

extern "C" NSString *QAStyleVersion(void) {
    const char *v = AStyleGetVersion();
    return v ? @(v) : @"";
}
