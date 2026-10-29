//
//  QProject.m — the .prj file.
//
//  The original's project file was binary MFC serialisation; this one is a
//  readable `Key=Value` list so it can live in version control:
//
//      Target=hello
//      Type=Console
//      File=main.cpp
//      File=util.cpp
//

#import "Quincy.h"

static NSArray<NSString *> *TypeNames(void) {
    return @[@"Console", @"Library", @"Dylib", @"Win32GUI", @"WinBGIm",
             @"Koolplot", @"FLTK"];
}

@implementation QProject

- (instancetype)initNewAtURL:(NSURL *)url {
    if (!(self = [super init])) return nil;
    _url = url;
    _target = url.lastPathComponent.stringByDeletingPathExtension;
    _type = QProjectConsole;
    _outputDirectory = @"";
    _includes = _defines = _libraries = @"";
    _files = [NSMutableArray array];
    return self;
}

+ (instancetype)projectWithURL:(NSURL *)url error:(NSError **)error {
    NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding
                                                 error:error];
    if (!text) return nil;
    QProject *p = [[QProject alloc] initNewAtURL:url];
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:
                           NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:
                          NSCharacterSet.whitespaceCharacterSet];
        if (!line.length || [line hasPrefix:@"#"]) continue;
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *key = [line substringToIndex:eq.location].lowercaseString;
        NSString *value = [line substringFromIndex:eq.location + 1];
        if ([key isEqual:@"file"]) [p.files addObject:value];
        else if ([key isEqual:@"target"]) p.target = value;
        else if ([key isEqual:@"output"]) p.outputDirectory = value;
        else if ([key isEqual:@"includes"]) p.includes = value;
        else if ([key isEqual:@"defines"]) p.defines = value;
        else if ([key isEqual:@"libraries"]) p.libraries = value;
        else if ([key isEqual:@"type"]) {
            NSUInteger i = [TypeNames() indexOfObject:value];
            p.type = i == NSNotFound ? QProjectConsole : (QProjectType)i;
        }
    }
    return p;
}

- (BOOL)save:(NSError **)error {
    NSMutableString *s = [NSMutableString stringWithString:@"# Quincy 2005 project\n"];
    [s appendFormat:@"Target=%@\nType=%@\n", _target, TypeNames()[_type]];
    if (_outputDirectory.length) [s appendFormat:@"Output=%@\n", _outputDirectory];
    if (_includes.length)  [s appendFormat:@"Includes=%@\n", _includes];
    if (_defines.length)   [s appendFormat:@"Defines=%@\n", _defines];
    if (_libraries.length) [s appendFormat:@"Libraries=%@\n", _libraries];
    for (NSString *f in _files) [s appendFormat:@"File=%@\n", f];
    return [s writeToURL:_url atomically:YES encoding:NSUTF8StringEncoding error:error];
}

- (NSString *)folder { return _url.URLByDeletingLastPathComponent.path; }

- (NSString *)absolutePath:(NSString *)relative {
    if (relative.isAbsolutePath) return relative;
    return [[self.folder stringByAppendingPathComponent:relative]
            stringByStandardizingPath];
}

- (NSString *)relativePath:(NSString *)absolute {
    NSString *folder = [self.folder stringByAppendingString:@"/"];
    if ([absolute hasPrefix:folder]) return [absolute substringFromIndex:folder.length];
    return absolute;
}

- (NSArray<NSString *> *)pathsWithExtensions:(NSArray *)exts {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *f in _files)
        if ([exts containsObject:f.pathExtension.lowercaseString])
            [out addObject:[self absolutePath:f]];
    return out;
}

- (NSArray<NSString *> *)sourcePaths {
    return [self pathsWithExtensions:@[@"c", @"cpp", @"cc", @"cxx"]];
}

- (NSArray<NSString *> *)headerPaths {
    return [self pathsWithExtensions:@[@"h", @"hpp"]];
}

- (NSArray<NSString *> *)archivePaths {
    return [self pathsWithExtensions:@[@"a", @"o", @"dylib"]];
}

- (NSString *)targetPath {
    NSString *dir = _outputDirectory.length ? [self absolutePath:_outputDirectory]
                                            : self.folder;
    NSString *name = _target.length ? _target
                                    : _url.lastPathComponent.stringByDeletingPathExtension;
    switch (_type) {
        case QProjectLibrary:
            if (![name hasPrefix:@"lib"]) name = [@"lib" stringByAppendingString:name];
            return [dir stringByAppendingPathComponent:[name stringByAppendingString:@".a"]];
        case QProjectDylib:
            if (![name hasPrefix:@"lib"]) name = [@"lib" stringByAppendingString:name];
            return [dir stringByAppendingPathComponent:[name stringByAppendingString:@".dylib"]];
        default:
            return [dir stringByAppendingPathComponent:name];
    }
}

@end
