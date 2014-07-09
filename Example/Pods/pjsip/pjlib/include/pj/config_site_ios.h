#ifndef _CONFIG_SITE_IOS_H_

//#define BRIAN_SAYS_NO_ASSERTS

#if !defined(DEBUG) || DEBUG==0 || defined(BRIAN_SAYS_NO_ASSERTS)
#define pj_assert(expr) do { (void)(expr); } while(0)
#endif

#define PJ_LOG_MAX_LEVEL 6
#define PJ_LOG_ENABLE_INDENT 1

//#define PJ_OS_NAME "arm-apple-darwin9"
#define PJ_DARWINOS 1
//#define PJ_M_NAME "arm"
#define PJ_IS_LITTLE_ENDIAN 1
#define PJ_IS_BIG_ENDIAN 0
#define PJ_HAS_FLOATING_POINT 0
#define PJ_HAS_ARPA_INET_H 1
#define PJ_HAS_ASSERT_H 1
#define PJ_HAS_CTYPE_H 1
#define PJ_HAS_ERRNO_H 1
#define PJ_HAS_FCNTL_H 1
#define PJ_HAS_LIMITS_H 1
#define PJ_HAS_NETDB_H 1
#define PJ_HAS_NETINET_IN_SYSTM_H 1
#define PJ_HAS_NETINET_IN_H 1
#define PJ_HAS_NETINET_IP_H 1
#define PJ_HAS_NETINET_TCP_H 1
#define PJ_HAS_NET_IF_H 1
#define PJ_HAS_IFADDRS_H 1
#define PJ_HAS_SEMAPHORE_H 1
#define PJ_HAS_SETJMP_H 1
#define PJ_HAS_STDARG_H 1
#define PJ_HAS_STDDEF_H 1
#define PJ_HAS_STDIO_H 1
#define PJ_HAS_STDINT_H 1
#define PJ_HAS_STDLIB_H 1
#define PJ_HAS_STRING_H 1
#define PJ_HAS_SYS_IOCTL_H 1
#define PJ_HAS_SYS_SELECT_H 1
#define PJ_HAS_SYS_SOCKET_H 1
#define PJ_HAS_SYS_TIME_H 1
#define PJ_HAS_SYS_TIMEB_H 1
#define PJ_HAS_SYS_TYPES_H 1
#define PJ_HAS_SYS_FILIO_H 1
#define PJ_HAS_SYS_SOCKIO_H 1
#define PJ_HAS_SYS_UTSNAME_H 1
#define PJ_HAS_TIME_H 1
#define PJ_HAS_UNISTD_H 1
#define PJ_SOCK_HAS_INET_ATON 1
#define PJ_SOCK_HAS_INET_PTON 1
#define PJ_SOCK_HAS_INET_NTOP 1
#define PJ_SOCK_HAS_GETADDRINFO 1
#define PJ_HAS_SEMAPHORE	1
#define PJ_HAS_PTHREAD_MUTEXATTR_SETTYPE 1
#define PJ_SOCKADDR_HAS_LEN 1
#define PJ_HAS_SOCKLEN_T 1
#define PJ_SELECT_NEEDS_NFDS 0
#define PJ_HAS_ERRNO_VAR 1
#define PJ_HAS_SO_ERROR 1
//#define PJ_BLOCKING_ERROR_VAL EAGAIN
#define PJ_BLOCKING_CONNECT_ERROR_VAL EINPROGRESS
#ifndef PJ_HAS_THREADS
#  define PJ_HAS_THREADS (1)
#endif
#define PJ_HAS_HIGH_RES_TIMER 1
#define PJ_HAS_MALLOC 1
#ifndef PJ_OS_HAS_CHECK_STACK
#  define PJ_OS_HAS_CHECK_STACK 0
#endif
#define PJ_NATIVE_STRING_IS_UNICODE 0
#define PJ_POOL_ALIGNMENT 4
#define PJ_ATOMIC_VALUE_TYPE long

#include "TargetConditionals.h"
#if TARGET_OS_IPHONE
#  include "Availability.h"
   /* Use CFHost API for pj_getaddrinfo() (see ticket #1246) */
#  define PJ_GETADDRINFO_USE_CFHOST 1
   /* Disable local host resolution in pj_gethostip() (see ticket #1342) */
#  define PJ_GETHOSTIP_DISABLE_LOCAL_RESOLUTION 1
#  ifdef __IPHONE_4_0
     /* Is multitasking support available?  (see ticket #1107) */
#    define PJ_IPHONE_OS_HAS_MULTITASKING_SUPPORT 1
     /* Enable activesock TCP background mode support */
#    define PJ_ACTIVESOCK_TCP_IPHONE_OS_BG 1
#  endif
#endif

#define PJ_EMULATE_RWMUTEX 0
#define PJ_THREAD_SET_STACK_SIZE 0
#define PJ_THREAD_ALLOCATE_STACK 0
#define PJ_HAS_SSL_SOCK 1
#define PJSIP_HAS_TLS_TRANSPORT 1

#define PJMEDIA_HAS_G711_CODEC 1
#define PJMEDIA_HAS_L16_CODEC 0
#define PJMEDIA_HAS_GSM_CODEC 0
#define PJMEDIA_HAS_SPEEX_CODEC 1
#define PJMEDIA_HAS_ILBC_CODEC 0
#define PJMEDIA_HAS_G722_CODEC 0
#define PJMEDIA_HAS_G7221_CODEC 0
#define PJMEDIA_HAS_OPENCORE_AMRNB_CODEC 0

#define PJMEDIA_HAS_VIDEO 0


#define PJMEDIA_AUDIO_DEV_HAS_PORTAUDIO	0
#define PJMEDIA_AUDIO_DEV_HAS_WMME 0
#define PJMEDIA_AUDIO_DEV_HAS_COREAUDIO 1
#define PJMEDIA_CODEC_SPEEX_DEFAULT_QUALITY	5
#define PJSUA_DEFAULT_CODEC_QUALITY 4
#define PJSUA_MAX_ACC 4
#define PJSUA_MAX_PLAYERS 4
#define PJSUA_MAX_RECORDERS 4
#define PJSUA_MAX_CONF_PORTS (PJSUA_MAX_CALLS+2*PJSUA_MAX_PLAYERS)
#define PJSUA_MAX_BUDDIES 32

/* Small and Large Filter defines */

#define RESAMPLE_HAS_SMALL_FILTER 1
#define RESAMPLE_HAS_LARGE_FILTER 1

#endif  /* !_CONFIG_SITE_IOS_H_ */
