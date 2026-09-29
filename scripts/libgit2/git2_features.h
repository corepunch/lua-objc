#ifndef INCLUDE_features_h__
#define INCLUDE_features_h__

#define GIT_THREADS 1

#if defined(__LP64__) || defined(_LP64)
#define GIT_ARCH_64 1
#else
#define GIT_ARCH_32 1
#endif

#ifdef GIT2_USE_ICONV
#define GIT_USE_ICONV 1
#endif

#define GIT_USE_NSEC 1
#define GIT_USE_STAT_MTIMESPEC 1
#define GIT_USE_FUTIMENS 1

#define GIT_REGEX_BUILTIN 1
#define GIT_QSORT_BSD

#define GIT_HTTPS 1
#define GIT_SECURE_TRANSPORT 1
#define GIT_HTTPPARSER_BUILTIN 1

#define GIT_SHA1_COLLISIONDETECT 1
#define GIT_SHA256_COMMON_CRYPTO 1
#define GIT_COMPRESSION_ZLIB 1

#define GIT_RAND_GETLOADAVG 1
#define GIT_IO_POLL 1
#define GIT_IO_SELECT 1

#endif
