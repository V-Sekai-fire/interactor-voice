/* Opus 1.6.1 as the classic float codec: no DNN extensions (OSCE, DRED, deep PLC), no
   platform intrinsics. The same file builds the riscv64 guest and the native test library. */
#ifndef VOICE_OPUS_CONFIG_H
#define VOICE_OPUS_CONFIG_H

#define OPUS_BUILD
#define PACKAGE_VERSION "1.6.1"
#define HAVE_LRINT 1
#define HAVE_LRINTF 1
#define HAVE_STDINT_H 1
#define HAVE_STRING_H 1
#define VAR_ARRAYS 1
#define FLOAT_APPROX 1
#define restrict __restrict

#endif
