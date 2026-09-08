#ifndef EVE_LOCAL_CORE_H
#define EVE_LOCAL_CORE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Synchronous JSON UTF-8 request. Caller owns input; els_free owns response. */
char *els_call(const char *request);
void els_free(char *response);
/* Input buffer includes a final NUL, max 1 MiB + 1. */
uint8_t *els_alloc(size_t size);
void els_dealloc(uint8_t *pointer, size_t original_size);
#ifdef __cplusplus
}
#endif
#endif
