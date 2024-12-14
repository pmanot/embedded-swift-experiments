#ifndef UTILS_H
#define UTILS_H

#include <stdio.h>

// Buffer size for float conversion
#define FLOAT_STR_BUFFER_SIZE 32

// Convert float to string with specified decimal places
static inline void float_to_str(char* buffer, float value, int decimal_places) {
    snprintf(buffer, FLOAT_STR_BUFFER_SIZE, "%.*f", decimal_places, value);
}

#endif /* UTILS_H */